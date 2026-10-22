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
