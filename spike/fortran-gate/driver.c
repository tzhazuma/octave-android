#include <stdio.h>
extern void fscale_(const int *n, const double *a, double *x);
extern double fdot_(const int *n, const double *x, const double *y);
int main(void) {
    int n = 4, i;
    double a = 2.5;
    double x[4] = {1.0, 2.0, 3.0, 4.0};
    double y[4] = {1.0, 1.0, 1.0, 1.0};
    fscale_(&n, &a, x);
    printf("FORTRAN_GATE_OK fscale ->");
    for (i = 0; i < 4; i++) printf(" %.1f", x[i]);
    printf("  fdot=%.1f\n", fdot_(&n, x, y));
    return 0;
}
