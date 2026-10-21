package org.octave.gui;

import org.qtproject.qt.android.bindings.QtActivity;

/**
 * GNU Octave's GUI as a Qt for Android application.
 *
 * <p>All the work is done by Qt's own activity: it reads {@code android.app.lib_name} from the
 * manifest, builds the library name {@code <value>_<abi>}, loads it and calls the {@code main}
 * symbol it exports once the JNI/Android environment Qt needs is in place. That is why
 * octave-gui is linked as a shared object (libOctaveGui_arm64-v8a.so) instead of being an
 * executable: Android refuses execve on app_data_file, and Qt wants to own the process anyway.
 */
public class MainActivity extends QtActivity {
}
