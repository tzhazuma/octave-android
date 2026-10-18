package org.octave.android;

import android.content.Context;
import android.content.res.AssetManager;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.Reader;
import java.io.Writer;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Installs the bundled Octave tree and drives one interactive {@code octave-cli} session.
 *
 * <p>Octave here is a real cross-compiled program, not a library: {@code octave-cli} is an
 * executable that links {@code liboctinterp.so} / {@code liboctave.so} from the installed
 * prefix. That rules out the JNI shape the other ports use -- there is no {@code libmain.so}
 * for the JVM to call into, and no place to hang a JNI bridge -- so the app runs it as a
 * child process and speaks to it over pipes. Everything below exists to make that safe and
 * observable: fixed environment, marker-delimited command boundaries, and a plot hand-off.
 *
 * <p>Why a live session instead of one {@code --eval} per command: Octave keeps figures in
 * the process. A fresh process per command would throw the figure away before {@code print}
 * could write it, so {@code plot(...)} would never produce an image. A single long-lived
 * session also gives us the real {@code octave:1>} prompt, which is what the UI shows.
 */
public final class OctaveRuntime {
    private static final String TAG = "Octave";

    /**
     * Bump whenever anything under assets/oct changes.
     *
     * <p>The extraction marker embeds this string, so an updated APK re-unpacks over the old
     * tree instead of silently keeping it. That failure mode is the reason the marker exists:
     * a stale tree looks exactly like a working one until a missing file is touched.
     */
    static final String ASSETS_VERSION = "oct-2026-10-19-a";

    /** No command may leave these in the stream; they are how we delimit work. */
    private static final String CMD_DONE = "__OCT_CMD_DONE__";
    private static final String PLOT_OK = "__OCT_PLOT_OK__";
    private static final String NO_PLOT = "__OCT_NO_PLOT__";

    public interface Sink {
        void onText(String text);
        void onPlot(File svg);
        void onExit(int status);
    }

    private final Context ctx;
    private final File root;
    private Process proc;
    private Writer stdin;
    private Sink sink;
    private volatile boolean probePending;

    public OctaveRuntime(Context ctx) {
        this.ctx = ctx.getApplicationContext();
        this.root = new File(this.ctx.getFilesDir(), "oct");
    }

    /**
     * The octave-cli executable, packaged as a native library.
     *
     * <p>It cannot live under filesDir and be executed from there: Android 10 and later
     * refuse {@code execve} on {@code app_data_file}, which shows up as a bare
     * {@code error=13, Permission denied} even though the file is mode 0755. Files in the
     * APK's native library directory are exempt, so the executable ships as
     * {@code lib/liboctavecli.so} and is run from there. Same trick for gnuplot.
     */
    public File octaveBin() {
        return new File(ctx.getApplicationInfo().nativeLibraryDir, "liboctavecli.so");
    }

    /** gnuplot, also packaged as a native library so Octave may exec it. */
    public File gnuplotBin() {
        return new File(ctx.getApplicationInfo().nativeLibraryDir, "libgnuplot.so");
    }

    public File depsDir() {
        return new File(root, "deps");
    }

    public File plotFile() {
        return new File(ctx.getFilesDir(), "plot.svg");
    }

    public boolean isInstalled() {
        return new File(root, ".installed-" + ASSETS_VERSION).exists()
                && octaveBin().isFile();
    }

    /**
     * Copy {@code assets/oct/**} into {@code filesDir/oct/**}, once.
     *
     * <p>The extraction is all-or-nothing: the marker is written last, so an interrupted
     * first launch repeats the copy instead of leaving a half-installed prefix that fails in
     * confusing ways (missing m-file, missing .oct module, missing .so).
     */
    public void install() throws IOException {
        File marker = new File(root, ".installed-" + ASSETS_VERSION);
        if (isInstalled()) {
            Log.i(TAG, "octave tree already installed at " + root);
            return;
        }
        long t0 = System.currentTimeMillis();
        deleteRecursively(root);
        if (!root.mkdirs() && !root.isDirectory()) {
            throw new IOException("cannot create " + root);
        }
        int files = copyAssetTree(ctx.getAssets(), "oct", root);

        new File(ctx.getFilesDir(), "home").mkdirs();
        new File(ctx.getFilesDir(), "tmp").mkdirs();
        if (!marker.createNewFile()) {
            Log.w(TAG, "could not create marker " + marker);
        }
        Log.i(TAG, "installed " + files + " files in "
                + (System.currentTimeMillis() - t0) + " ms");
    }

    /** Launch the session. Returns immediately; output arrives through {@code sink}. */
    public void start(Sink sink) throws IOException {
        this.sink = sink;
        File files = ctx.getFilesDir();
        List<String> cmd = new ArrayList<>();
        cmd.add(octaveBin().getAbsolutePath());
        cmd.add("--no-gui");
        cmd.add("--quiet");
        cmd.add("--interactive");
        cmd.add("--no-window-system");

        ProcessBuilder pb = new ProcessBuilder(cmd);
        pb.directory(root);
        pb.redirectErrorStream(true);   // warnings and errors belong in the console
        Map<String, String> env = pb.environment();
        File home = new File(files, "home");
        File tmp = new File(files, "tmp");
        home.mkdirs();
        tmp.mkdirs();
        // The binary's DT_RPATH points at the machine that built it, so the library search
        // path has to be supplied here. deps/ holds the libraries Octave links but does not
        // install (OpenBLAS, FFTW, libc++_shared) plus the gnuplot Octave shells out to.
        env.put("OCTAVE_HOME", new File(root, "octave").getAbsolutePath());
        // nativeLibraryDir first: libc++_shared.so lives there so that gnuplot (exec'd from
        // the same directory) and octave-cli resolve the same copy.
        env.put("LD_LIBRARY_PATH",
                ctx.getApplicationInfo().nativeLibraryDir
                        + ":" + new File(root, "octave/lib/octave/11.3.0")
                        + ":" + depsDir().getAbsolutePath());
        // nativeLibraryDir first: gnuplot is exec'd by name from Octave's shell-outs.
        env.put("PATH", ctx.getApplicationInfo().nativeLibraryDir
                + ":" + new File(root, "octave/bin") + ":" + depsDir().getAbsolutePath()
                + ":/system/bin:/system/xbin");
        env.put("HOME", home.getAbsolutePath());
        env.put("TMPDIR", tmp.getAbsolutePath());
        env.put("GNUTERM", "svg");
        env.put("TERM", "dumb");
        // Inherited from the app process would shadow the bundled libraries.
        env.remove("LD_PRELOAD");

        Log.i(TAG, "exec: " + String.join(" ", cmd));
        proc = pb.start();
        stdin = new OutputStreamWriter(proc.getOutputStream(), "UTF-8");
        Thread t = new Thread(this::pump, "octave-reader");
        t.setDaemon(true);
        t.start();
    }

    /** Send one line of Octave code and ask for the end-of-command marker. */
    public synchronized void submit(String code) throws IOException {
        if (stdin == null) {
            throw new IOException("octave session is not running");
        }
        stdin.write(code);
        stdin.write("\n");
        stdin.write("disp('" + CMD_DONE + "')\n");
        stdin.flush();
    }

    /**
     * Ask the session whether a figure exists, and if so render it to SVG.
     *
     * <p>This is sent only after a command completed, so the figure it prints is the one that
     * command produced. The alternative -- rendering after every keystroke -- would fight the
     * user for the session and print stale figures.
     */
    private synchronized void probeFigure() throws IOException {
        if (probePending) {
            return;
        }
        probePending = true;
        String path = plotFile().getAbsolutePath();
        stdin.write("if isempty(get(0,'children')), disp('" + NO_PLOT + "'); else "
                + "print(get(0,'currentfigure'),'-dsvg','" + path + "'); disp('" + PLOT_OK + "'); end\n");
        stdin.flush();
    }

    private void pump() {
        StringBuilder window = new StringBuilder();
        char[] buf = new char[8192];
        try (Reader in = new InputStreamReader(proc.getInputStream(), "UTF-8")) {
            int n;
            while ((n = in.read(buf)) > 0) {
                window.append(buf, 0, n);
                drain(window);
            }
        }
        catch (IOException e) {
            Log.w(TAG, "reader stopped: " + e);
        }
        int status = -1;
        try {
            status = proc.waitFor();
        }
        catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        }
        if (sink != null) {
            sink.onExit(status);
        }
    }

    /**
     * Emit everything before the next marker, then act on that marker.
     *
     * <p>Kept as a rolling window because markers can be split across reads, and because the
     * prompt has no trailing newline: a line-based reader would sit on "octave:1> " forever.
     */
    private void drain(StringBuilder window) {
        while (true) {
            int done = window.indexOf(CMD_DONE);
            int plot = window.indexOf(PLOT_OK);
            int none = window.indexOf(NO_PLOT);
            int idx = Integer.MAX_VALUE;
            int which = 0;
            if (done >= 0 && done < idx) { idx = done; which = 1; }
            if (plot >= 0 && plot < idx) { idx = plot; which = 2; }
            if (none >= 0 && none < idx) { idx = none; which = 3; }
            if (idx == Integer.MAX_VALUE) {
                // No marker: emit all but a tail long enough to hold a split marker.
                int keep = Math.max(CMD_DONE.length(), Math.max(PLOT_OK.length(), NO_PLOT.length())) + 2;
                if (window.length() > keep) {
                    int cut = window.length() - keep;
                    emit(window.substring(0, cut));
                    window.delete(0, cut);
                }
                return;
            }
            emit(window.substring(0, idx));
            window.delete(0, idx);
            String marker = which == 1 ? CMD_DONE : which == 2 ? PLOT_OK : NO_PLOT;
            window.delete(0, marker.length());
            if (which == 1) {
                // Strip the newline Octave printed after disp(...).
                trimLeading(window);
                try {
                    probeFigure();
                }
                catch (IOException e) {
                    Log.w(TAG, "cannot probe figure: " + e);
                }
            }
            else if (which == 2) {
                trimLeading(window);
                probePending = false;
                if (sink != null) {
                    sink.onPlot(plotFile());
                }
            }
            else {
                trimLeading(window);
                probePending = false;
            }
        }
    }

    private static void trimLeading(StringBuilder b) {
        while (b.length() > 0 && (b.charAt(0) == '\n' || b.charAt(0) == '\r')) {
            b.deleteCharAt(0);
        }
    }

    private void emit(String text) {
        if (text.isEmpty() || sink == null) {
            return;
        }
        sink.onText(text);
    }

    public void stop() {
        if (proc != null) {
            proc.destroy();
        }
    }

    private int copyAssetTree(AssetManager assets, String path, File dest) throws IOException {
        String[] children = assets.list(path);
        if (children == null || children.length == 0) {
            if (dest.getParentFile() != null && !dest.getParentFile().exists()
                    && !dest.getParentFile().mkdirs()) {
                throw new IOException("cannot create " + dest.getParentFile());
            }
            try (InputStream in = assets.open(path);
                 OutputStream out = new FileOutputStream(dest)) {
                byte[] buffer = new byte[128 * 1024];
                int n;
                while ((n = in.read(buffer)) > 0) {
                    out.write(buffer, 0, n);
                }
            }
            return 1;
        }
        if (!dest.exists() && !dest.mkdirs()) {
            throw new IOException("cannot create " + dest);
        }
        int count = 0;
        for (String child : children) {
            count += copyAssetTree(assets, path + "/" + child, new File(dest, child));
        }
        return count;
    }

    private static void deleteRecursively(File f) {
        if (f.isDirectory()) {
            File[] kids = f.listFiles();
            if (kids != null) {
                for (File k : kids) {
                    deleteRecursively(k);
                }
            }
        }
        //noinspection ResultOfMethodCallIgnored
        f.delete();
    }
}
