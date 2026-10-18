/* JNI entry point for the Octave-on-Android numerical-core APK.
 *
 * This exercises the cross-compiled native stack that was built and verified
 * for route B (STATUS.md 3.5-3.7):
 *   - OpenBLAS  : LAPACK dgesv  (linear solve)
 *   - FFTW 3    : real-to-complex FFT
 *   - ARPACK-ng : dsaupd/dseupd symmetric eigensolver (via the Fortran wrapper)
 *   - qrupdate  : linked in as a dependency of the stack
 *
 * Everything here is the SAME code that was verified on-device by pushing
 * adb binaries; the point of this APK is to prove it also works from inside a
 * real Android application (jniLibs packaging + 16 KB page alignment).
 */
#include <jni.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

extern void dgesv_(const int *n, const int *nrhs, double *a, const int *lda,
                   int *ipiv, double *b, const int *ldb, int *info);
extern void demo_eigs_(const int *n, const double *d, const int *nev,
                       double *out, int *info);
extern void *fftw_plan_dft_r2c_1d(int n, double *in, double *out,
                                  unsigned flags);
extern void fftw_execute(const void *plan);
extern void fftw_destroy_plan(void *plan);

#define BUF 4096

/* ---- 1. LAPACK: solve A x = b ---------------------------------------- */
static void do_lapack(char *s, size_t cap)
{
    int n = 2, nrhs = 1, lda = 2, ldb = 2, info = 0, ipiv[2];
    double A[4] = {3.0, 1.0, 1.0, 2.0};   /* column-major [[3,1],[1,2]] */
    double b[2] = {9.0, 8.0};             /* 3x+y=9, x+2y=8 -> x=(2,3) */
    dgesv_(&n, &nrhs, A, &lda, ipiv, b, &ldb, &info);
    snprintf(s, cap, "LAPACK dgesv  info=%d  x = (%.6f, %.6f)   [expect (2, 3)]",
             info, b[0], b[1]);
}

/* ---- 2. FFTW: real-to-complex FFT of a pure cosine -------------------- */
static void do_fftw(char *s, size_t cap)
{
    const int n = 16;
    double in[16];
    double out[2 * (16 / 2 + 1)];
    int i, k = 3;                          /* 3 full cycles across 16 samples */
    double peak = 0.0;
    int peakbin = -1;

    for (i = 0; i < n; i++)
        in[i] = cos(2.0 * M_PI * k * i / n);
    memset(out, 0, sizeof(out));

    {
        void *plan = fftw_plan_dft_r2c_1d(n, in, out, 0 /*FFTW_ESTIMATE*/);
        fftw_execute(plan);
        fftw_destroy_plan(plan);
    }
    /* out is interleaved (re,im); magnitude of bin j */
    for (i = 0; i <= n / 2; i++) {
        double mag = sqrt(out[2 * i] * out[2 * i] + out[2 * i + 1] * out[2 * i + 1]);
        if (mag > peak) { peak = mag; peakbin = i; }
    }
    snprintf(s, cap, "FFTW   r2c(16)  peak bin = %d  magnitude = %.3f   [expect bin 3, 8.000]",
             peakbin, peak);
}

/* ---- 3. ARPACK: 4 smallest eigenvalues of diag(1..100) ---------------- */
static void do_arpack(char *s, size_t cap)
{
    const int n = 100, nev = 4;
    double d[100], out[4];
    int info = 0, i;
    char tmp[256];
    size_t used;

    for (i = 0; i < n; i++)
        d[i] = (double)(i + 1);            /* eigenvalues are exactly 1..100 */

    demo_eigs_(&n, d, &nev, out, &info);

    used = (size_t)snprintf(s, cap, "ARPACK dsaupd/dseupd  info=%d  nev=%d\n", info, nev);
    for (i = 0; i < nev && used < cap; i++) {
        int m = snprintf(tmp, sizeof(tmp),
                         "          lambda(%d) = %.6f   [expect %d]\n",
                         i + 1, out[i], i + 1);
        if (m > 0 && used + (size_t)m < cap) {
            memcpy(s + used, tmp, (size_t)m);
            used += (size_t)m;
            s[used] = '\0';
        }
    }
    if (used < cap)
        snprintf(s + used, cap - used,
                 "          (diag(1..100), WHICH='SM' -> smallest magnitude)");
}

JNIEXPORT jstring JNICALL
Java_org_octave_android_NativeDemo_runAll(JNIEnv *env, jclass clazz)
{
    char lapack[BUF], fftw[BUF], arpack[BUF], all[3 * BUF];
    (void)clazz;

    do_lapack(lapack, sizeof(lapack));
    do_fftw(fftw, sizeof(fftw));
    do_arpack(arpack, sizeof(arpack));

    snprintf(all, sizeof(all),
             "Octave-on-Android :: native numerical core\n"
             "(cross-compiled for aarch64-linux-android with the NDK)\n"
             "-----------------------------------------------------------\n"
             "%s\n\n%s\n\n%s\n",
             lapack, fftw, arpack);
    return (*env)->NewStringUTF(env, all);
}
