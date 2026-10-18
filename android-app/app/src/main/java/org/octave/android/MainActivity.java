package org.octave.android;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebView;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Octave on Android: a real octave-cli session, a script editor, and Android's file picker.
 *
 * <p>Three things this activity has to get right, because each one is a way the port can look
 * finished while being useless:
 *
 * <ul>
 *   <li>The console is a <em>session</em>, not a sequence of one-shot runs. See
 *       {@link OctaveRuntime} for why figures force that shape.</li>
 *   <li>Plots are rendered by the bundled gnuplot to SVG and shown in a WebView. Octave's
 *       Qt/FLTK toolkits are not built here, so gnuplot is the only path from
 *       {@code plot(...)} to pixels; SVG needs no image libraries on either side.</li>
 *   <li>Open and Save go through the Storage Access Framework. Octave itself only
 *       understands POSIX paths, so the app reads the chosen document into the editor (or
 *       writes the editor back to the same document) -- the URI never reaches Octave.</li>
 * </ul>
 */
public class MainActivity extends Activity {
    private static final int REQ_OPEN = 41;
    private static final int REQ_SAVE_AS = 42;

    private TextView console;
    private ScrollView consoleScroll;
    private WebView plotView;
    private EditText editor;
    private EditText input;
    private OctaveRuntime runtime;
    private Uri openUri;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        runtime = new OctaveRuntime(this);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(6);
        root.setPadding(pad, pad, pad, pad);

        root.addView(buttonRow());
        root.addView(buildConsole(), weight(1.2f));
        root.addView(buildPlot(), weight(1.1f));
        root.addView(buildEditor(), weight(0.8f));
        root.addView(buildInputRow());

        setContentView(root);
        boot();
    }

    private LinearLayout buttonRow() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.addView(button("Open .m", v -> pickOpen()));
        row.addView(button("Save", v -> save()));
        row.addView(button("Save as", v -> pickSaveAs()));
        row.addView(button("Run script", v -> runScript()));
        row.addView(button("Self-test", v -> selfTest()));
        return row;
    }

    private ScrollView buildConsole() {
        consoleScroll = new ScrollView(this);
        console = new TextView(this);
        console.setTypeface(Typeface.MONOSPACE);
        console.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        console.setTextIsSelectable(true);
        console.setTextColor(0xFFE8E8E8);
        console.setBackgroundColor(0xFF101014);
        console.setPadding(dp(6), dp(6), dp(6), dp(6));
        consoleScroll.addView(console);
        return consoleScroll;
    }

    private WebView buildPlot() {
        plotView = new WebView(this);
        plotView.setBackgroundColor(0xFFFFFFFF);
        return plotView;
    }

    private EditText buildEditor() {
        editor = new EditText(this);
        editor.setTypeface(Typeface.MONOSPACE);
        editor.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        editor.setGravity(Gravity.TOP | Gravity.START);
        editor.setHint(".m script (Open loads one here, Save writes it back)");
        editor.setMinLines(3);
        editor.setBackgroundColor(0xFF1B1B22);
        editor.setTextColor(0xFFEDEDED);
        editor.setPadding(dp(6), dp(6), dp(6), dp(6));
        return editor;
    }

    private LinearLayout buildInputRow() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        input = new EditText(this);
        input.setTypeface(Typeface.MONOSPACE);
        input.setHint("octave expression, e.g. plot(sin(0:0.1:6.3))");
        input.setSingleLine(true);
        input.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_SEND);
        input.setOnEditorActionListener((v, actionId, event) -> {
            sendInput();
            return true;
        });
        row.addView(input, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        row.addView(button("Send", v -> sendInput()));
        return row;
    }

    private Button button(String label, View.OnClickListener listener) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        b.setOnClickListener(listener);
        return b;
    }

    private LinearLayout.LayoutParams weight(float w) {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, w);
    }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                getResources().getDisplayMetrics());
    }

    private void boot() {
        append("Installing Octave… (first launch unpacks ~90 MB)\n");
        new Thread(() -> {
            try {
                runtime.install();
                runOnUiThread(() -> append("Starting octave-cli…\n"));
                runtime.start(new OctaveRuntime.Sink() {
                    @Override public void onText(String text) {
                        runOnUiThread(() -> append(text));
                    }
                    @Override public void onPlot(File svg) {
                        runOnUiThread(() -> showPlot(svg));
                    }
                    @Override public void onExit(int status) {
                        runOnUiThread(() -> append("\n[octave-cli exited: " + status + "]\n"));
                    }
                });
                // gnuplot is the only graphics toolkit the build carries; with no display the
                // figures must stay invisible so print() is the way they reach the screen.
                // Order matters: graphics_toolkit('gnuplot') validates the binary
                // immediately and errors out before gnuplot_binary() could point at it.
                runtime.submit("gnuplot_binary('" + runtime.gnuplotBin().getAbsolutePath() + "'); "
                        + "graphics_toolkit('gnuplot'); "
                        + "more off; set(0,'defaultfigurevisible','off');");
            }
            catch (Throwable t) {
                runOnUiThread(() -> append("\nBOOT FAILED: " + t + "\n"));
            }
        }, "octave-boot").start();
    }

    private void sendInput() {
        String code = input.getText().toString();
        if (code.trim().isEmpty()) {
            return;
        }
        input.setText("");
        append("\n" + code + "\n");
        try {
            runtime.submit(code);
        }
        catch (Throwable t) {
            append("cannot send: " + t + "\n");
        }
    }

    private void runScript() {
        String code = editor.getText().toString();
        if (code.trim().isEmpty()) {
            toast("editor is empty — Open a .m file or type one");
            return;
        }
        try {
            File scratch = new File(getFilesDir(), "scratch");
            scratch.mkdirs();
            File script = new File(scratch, "script.m");
            try (OutputStream out = new FileOutputStream(script)) {
                out.write(code.getBytes(StandardCharsets.UTF_8));
            }
            append("\n>> run " + script.getAbsolutePath() + "\n");
            runtime.submit("run('" + script.getAbsolutePath() + "')");
        }
        catch (Throwable t) {
            append("cannot run script: " + t + "\n");
        }
    }

    /** The numerical gate: LAPACK / FFTW / ARPACK through the packaged native library. */
    private void selfTest() {
        append("\n=== native numerical self-test ===\n");
        try {
            append(NativeDemo.runAll());
        }
        catch (Throwable t) {
            append("self-test failed: " + t + "\n");
        }
        append("=== end self-test ===\n");
    }

    // ---------------------------------------------------------------- SAF

    /**
     * Pin the AOSP document picker when it is installed.
     *
     * <p>On this ROM vivo's file manager also advertises ACTION_OPEN_DOCUMENT and wins the
     * implicit resolution, but it opens a media selector (图片 / 时光轴 / 相册集) that never
     * lists a .m file -- the picker appears and is useless. Setting the package keeps the
     * standard documents UI, which is a real filesystem browser.
     */
    private Intent pinDocumentsUi(Intent i) {
        if (isPackageInstalled("com.android.documentsui")) {
            i.setPackage("com.android.documentsui");
        }
        return i;
    }

    private boolean isPackageInstalled(String pkg) {
        try {
            getPackageManager().getPackageInfo(pkg, 0);
            return true;
        }
        catch (android.content.pm.PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    private void pickOpen() {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("*/*");
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
                | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        startActivityForResult(pinDocumentsUi(i), REQ_OPEN);
    }

    private void pickSaveAs() {
        Intent i = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("text/plain");
        i.putExtra(Intent.EXTRA_TITLE, "script.m");
        startActivityForResult(pinDocumentsUi(i), REQ_SAVE_AS);
    }

    private void save() {
        if (openUri == null) {
            pickSaveAs();
            return;
        }
        try {
            writeTo(openUri, editor.getText().toString());
            append("\nsaved " + describe(openUri) + "\n");
        }
        catch (Throwable t) {
            append("save failed: " + t + "\n");
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode != RESULT_OK || data == null || data.getData() == null) {
            return;
        }
        Uri uri = data.getData();
        try {
            // Keep the grant across restarts; without it the same document cannot be saved
            // back after the activity is recreated.
            getContentResolver().takePersistableUriPermission(uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        }
        catch (SecurityException ignored) {
            // Some providers grant only read; saving then fails loudly rather than silently.
        }
        if (requestCode == REQ_OPEN) {
            try {
                String text = readAll(uri);
                openUri = uri;
                editor.setText(text);
                append("\nopened " + describe(uri) + " (" + text.length() + " chars)\n");
            }
            catch (Throwable t) {
                append("open failed: " + t + "\n");
            }
        }
        else if (requestCode == REQ_SAVE_AS) {
            try {
                writeTo(uri, editor.getText().toString());
                openUri = uri;
                append("\nsaved as " + describe(uri) + "\n");
            }
            catch (Throwable t) {
                append("save-as failed: " + t + "\n");
            }
        }
    }

    private String readAll(Uri uri) throws Exception {
        try (InputStream in = getContentResolver().openInputStream(uri)) {
            if (in == null) {
                throw new IllegalStateException("provider returned no stream");
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[64 * 1024];
            int n;
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
            return out.toString("UTF-8");
        }
    }

    /** {@code "wt"} truncates: the document may already hold a longer version. */
    private void writeTo(Uri uri, String text) throws Exception {
        try (OutputStream out = getContentResolver().openOutputStream(uri, "wt")) {
            if (out == null) {
                throw new IllegalStateException("provider returned no stream");
            }
            out.write(text.getBytes(StandardCharsets.UTF_8));
        }
    }

    private String describe(Uri uri) {
        try (android.database.Cursor c = getContentResolver()
                .query(uri, new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                String name = c.getString(0);
                if (name != null) {
                    return name + " <" + uri + ">";
                }
            }
        }
        catch (Throwable ignored) {
            // Fall through to the URI alone.
        }
        return String.valueOf(uri);
    }

    // ------------------------------------------------------------ plumbing

    private void append(String text) {
        console.append(text);
        consoleScroll.post(() -> consoleScroll.fullScroll(View.FOCUS_DOWN));
    }

    private void showPlot(File svg) {
        try {
            byte[] buf = new byte[(int) svg.length()];
            try (InputStream in = new java.io.FileInputStream(svg)) {
                int off = 0;
                while (off < buf.length) {
                    int n = in.read(buf, off, buf.length - off);
                    if (n < 0) {
                        break;
                    }
                    off += n;
                }
            }
            String svgText = new String(buf, StandardCharsets.UTF_8);
            plotView.loadDataWithBaseURL(null, svgText, "image/svg+xml", "UTF-8", null);
            append("[plot rendered: " + svg.getName() + "]\n");
        }
        catch (Throwable t) {
            append("[plot read failed: " + t + "]\n");
        }
    }

    private void toast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    @Override
    protected void onDestroy() {
        runtime.stop();
        super.onDestroy();
    }
}
