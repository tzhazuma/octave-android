package org.octave.gui;

import android.os.Bundle;
import android.util.Log;
import android.view.View;

import org.qtproject.qt.android.bindings.QtActivity;

/**
 * GNU Octave's GUI as a Qt for Android application.
 *
 * <p>Qt does the heavy lifting: it reads {@code android.app.lib_name} from the manifest, builds
 * the library name {@code <value>_<abi>}, loads it and calls the {@code main} symbol it exports
 * once the JNI environment exists. That is why octave-gui is linked as a shared object
 * (libOctaveGui_arm64-v8a.so): Android refuses execve on app_data_file, and Qt wants to own the
 * process anyway.
 */
public class MainActivity extends QtActivity {
    private static final String TAG = "OctaveGui";

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        disableQtAccessibilityBridge();
    }

    /**
     * Give the GUI a way out.
     *
     * <p>Octave's desktop UI has File &gt; Exit, but on a phone the menu bar is not reachable and
     * Android gives the app no quit affordance at all -- Back does nothing, and Ctrl+Q needs a
     * keyboard. Without this the only way to stop Octave is to swipe it out of recents, which
     * kills the process without letting it shut down.
     *
     * <p>Back now asks first, then finishes the task. The confirmation matters: Back is also how
     * people dismiss the on-screen keyboard.
     */
    /**
     * QtActivity consumes the Back key before onBackPressed() is ever reached -- Qt turns it into
     * a key event for the Qt app -- so the dialog has to be triggered one level lower, before the
     * activity gets a chance to swallow it.
     */
    @Override
    public boolean dispatchKeyEvent(android.view.KeyEvent event) {
        if (event.getKeyCode() == android.view.KeyEvent.KEYCODE_BACK
                && event.getAction() == android.view.KeyEvent.ACTION_UP) {
            askToQuit();
            return true;
        }
        return super.dispatchKeyEvent(event);
    }

    private void askToQuit() {
        new android.app.AlertDialog.Builder(this)
                .setTitle("退出 Octave？")
                .setMessage("未保存的脚本会丢失。")
                .setNegativeButton("取消", null)
                .setPositiveButton("退出", (d, w) -> {
                    Log.i(TAG, "exit requested from the back button");
                    finishAffinity();
                })
                .show();
    }

    /**
     * Stop Android's accessibility framework from calling into Qt's virtual view tree.
     *
     * <p>Qt's {@code AccessibilityDelegate} does a synchronous {@code QMetaObject::invokeMethod}
     * into the Qt thread on every {@code getNodeForVirtualViewId()}. When an accessibility
     * service asks for a node while that thread is busy, the Android UI thread blocks in the JNI
     * call, Android declares input dispatch timed out and kills the app. The console-style plot
     * tree has no meaningful accessibility structure anyway, and system dialogs are separate
     * windows, so hiding the descendants costs nothing.
     */
    private void disableQtAccessibilityBridge() {
        try {
            View decor = getWindow().getDecorView();
            decor.setImportantForAccessibility(
                    View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
            decor.setAccessibilityDelegate(null);
            Log.i(TAG, "disabled the Qt accessibility bridge");
        } catch (Throwable t) {
            Log.w(TAG, "could not disable the Qt accessibility bridge", t);
        }
    }
}
