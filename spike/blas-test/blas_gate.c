#include <stdio.h>
/* Fortran-ABI BLAS entry points -- exactly how Octave calls OpenBLAS. */
extern void dgemm_(const char*, const char*, const int*, const int*, const int*,
                   const double*, const double*, const int*, const double*, const int*,
                   const double*, double*, const int*);
extern double ddot_(const int*, const double*, const int*, const double*, const int*);
int main(void) {
    /* A = [[1,2],[3,4]]  B = [[5,6],[7,8]]  C = A*B = [[19,22],[43,50]] */
    double A[4] = {1,3, 2,4};   /* column-major */
    double B[4] = {5,7, 6,8};
    double C[4] = {0,0,0,0};
    char N = 'N'; int m = 2, n = 2, k = 2;
    double one = 1.0, zero = 0.0;
    int lda = 2, ldb = 2, ldc = 2;
    dgemm_(&N, &N, &m, &n, &k, &one, A, &lda, B, &ldb, &zero, C, &ldc);
    printf("OPENBLAS_GATE_OK dgemm C = [%.1f %.1f ; %.1f %.1f]\n", C[0], C[2], C[1], C[3]);
    printf("OPENBLAS_GATE_OK ddot(A,B) = %.1f\n", ddot_(&k, A, &lda, B, &ldb));
    return 0;
}
