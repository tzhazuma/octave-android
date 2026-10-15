#include <stdio.h>
extern void rtgate_(const int *n, const double *a, const double *b, double *c, double *s);
int main(void){
    int n=3,i,j; double a[9],b[9],c[9],s=0.0;
    for(i=0;i<9;i++){a[i]=(double)(i+1);b[i]=(i%3==0)?1.0:0.0;}
    rtgate_(&n,a,b,c,&s);
    printf("RT_GATE_OK s=%.6f c00=%.6f c11=%.6f c22=%.6f\n",s,c[0],c[4],c[8]);
    (void)j; return 0;
}
