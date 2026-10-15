#include <stdio.h>
#include <math.h>
extern void dgesv_(const int*, const int*, double*, const int*, int*, double*, const int*, int*);
extern void dpotrf_(const char*, const int*, double*, const int*, int*);
int main(void) {
    /* Solve A x = b,  A = [[4,1],[1,3]] (col-major),  b = [1,2] */
    double A[4] = {4,1, 1,3};
    double b[2] = {1,2};
    int n = 2, nrhs = 1, lda = 2, ldb = 2, info = 0, ipiv[2];
    dgesv_(&n, &nrhs, A, &lda, ipiv, b, &ldb, &info);
    printf("LAPACK_GATE dgesv info=%d  x = [%.6f %.6f]\n", info, b[0], b[1]);
    printf("LAPACK_GATE expected  x = [%.6f %.6f]  (1/11, 7/11)\n", 1.0/11.0, 7.0/11.0);

    /* Cholesky of the same SPD matrix: A = L L^T */
    double C[4] = {4,1, 1,3};
    char U = 'U'; int ic = 0;
    dpotrf_(&U, &n, C, &lda, &ic);
    printf("LAPACK_GATE dpotrf info=%d  L^T = [%.6f %.6f ; %.6f %.6f]\n", ic, C[0], C[1], C[2], C[3]);
    /* verify L*L^T reproduces A[0][0] = 4 */
    printf("LAPACK_GATE check L11^2 = %.6f (expect 4)\n", C[0]*C[0]);
    return 0;
}
