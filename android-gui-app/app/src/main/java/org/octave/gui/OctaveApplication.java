package org.octave.gui;

import android.app.Application;
import android.content.res.AssetManager;
import android.system.Os;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;

/**
 * Sets Octave's runtime environment before anything loads.
 *
 * <p>Octave's shared library runs static constructors as soon as it is dlopen'ed, and those
 * read OCTAVE_HOME / OCTAVE_EXEC_PREFIX to locate its own data files. Without them the
 * constructors can dereference a null path and take the process down inside dlopen, which
 * shows up as "Fatal signal 11 ... in liboctave.so (string_vector::string_vector)". An
 * Application runs before the activity, hence before QtLoader touches a single library.
 */
public class OctaveApplication extends Application {
    @Override public void onCreate() {
        super.onCreate();
        String files = getFilesDir().getAbsolutePath();
        set("OCTAVE_HOME", files + "/octave");
        set("OCTAVE_EXEC_PREFIX", files + "/octave");
        set("OCTAVE_ARCHLIBDIR", files + "/octave/lib/octave");
        set("OCTAVE_LOCALE_DIR", files + "/octave/share/locale");
        set("OCTAVE_IMAGE_DIR", files + "/octave/share/octave");
        set("HOME", files);
        set("TMPDIR", files);
        set("PATH", "/system/bin:/system/xbin");
        unpackOctaveData(files);
        /* No preload here on purpose. System.loadLibrary("octgui") would pull Qt6Core in before
         * QtLoader has established the JNI environment, and Qt then aborts with
         * "JNI DETECTED ERROR IN APPLICATION: java_class == null". QtLoader loads the whole set
         * in the right order; the environment above is all it needs from us. */
    }


    /** Copy assets/oct/** into files/octave once, so OCTAVE_HOME points at real files. */
    private void unpackOctaveData(String files) {
        File root = new File(files, "octave");
        File marker = new File(root, ".unpacked-v1");
        if (marker.isFile()) return;
        try {
            long t0 = System.currentTimeMillis();
            copyTree(getAssets(), "oct", root);
            //noinspection ResultOfMethodCallIgnored
            marker.createNewFile();
            android.util.Log.i("OctaveApp", "unpacked Octave data in "
                    + (System.currentTimeMillis() - t0) + " ms");
        } catch (IOException e) {
            android.util.Log.e("OctaveApp", "could not unpack Octave data", e);
        }
    }

    private static void copyTree(AssetManager assets, String path, File dest) throws IOException {
        String[] children = assets.list(path);
        if (children != null && children.length > 0) {
            //noinspection ResultOfMethodCallIgnored
            dest.mkdirs();
            for (String child : children) copyTree(assets, path + "/" + child, new File(dest, child));
        } else {
            //noinspection ResultOfMethodCallIgnored
            dest.getParentFile().mkdirs();
            try (InputStream in = assets.open(path);
                 FileOutputStream out = new FileOutputStream(dest)) {
                byte[] buf = new byte[65536];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            }
        }
    }

    private static void set(String key, String value) {
        try { Os.setenv(key, value, true); } catch (Throwable ignored) { }
    }
}
