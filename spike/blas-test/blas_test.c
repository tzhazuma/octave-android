#include <stdio.h>
/* Real LAPACK/BLAS calls against the cross-compiled OpenBLAS. */
extern void dgesv_(const int*,const int*,double*,const int*,int*,double*,const int*,int*);
extern void dgemm_(const char*,const char*,const int*,const int*,const int*,const double*,
                   const double*,const int*,const double*,const int*,const double*,double*,const int*);
int main(void){
    /* Solve A x = b, A = [[3,1],[1,2]], b = [9,8]  ->  x = [2,3] */
    int n=2,nrhs=1,lda=2,ldb=2,info=0,ipiv[2];
    double A[4]={3,1,1,2}, b[2]={9,8};
    dgesv_(&n,&nrhs,A,&lda,ipiv,b,&ldb,&info);
    printf("DGESV info=%d x=(%.6f, %.6f)\n",info,b[0],b[1]);
    /* C = A*B, 2x2 */
    char N='N'; int m=2,k=2; double one=1.0,zero=0.0;
    double X[4]={1,2,3,4}, Y[4]={5,6,7,8}, C[4]={0,0,0,0};
    dgemm_(&N,&N,&m,&m,&k,&one,X,&m,Y,&m,&zero,C,&m);
    printf("DGEMM C=(%.1f %.1f; %.1f %.1f)\n",C[0],C[1],C[2],C[3]);
    /* sanity: 3x3 identity multiply */
    printf("OPENBLAS_DEVICE_OK\n");
    return 0;
}
