package org.octave.android;

/** JNI bridge to the cross-compiled numerical stack (liboctdemo.so). */
public final class NativeDemo {
    static { System.loadLibrary("octdemo"); }
    private NativeDemo() {}
    /** Runs LAPACK dgesv + FFTW r2c + ARPACK dsaupd and returns a report. */
    public static native String runAll();
}
