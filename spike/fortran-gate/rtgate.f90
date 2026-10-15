! Harder gate: mimics real LAPACK/BLAS-style Fortran -> forces flang RUNTIME linkage
! (matmul, sqrt/sin intrinsics, formatted WRITE for xerbla-style error paths,
!  COMPLEX arithmetic for zgemm-style kernels)
      subroutine rtgate(n, a, b, c, s)
      implicit none
      integer n, i, j
      double precision a(n,n), b(n,n), c(n,n), s
      complex*16 z, w
      double precision t
      c = matmul(a, b)
      s = 0.0d0
      do j = 1, n
         do i = 1, n
            s = s + sqrt(abs(c(i,j))) + sin(c(i,j)) + dble(cos(dble(c(i,j))))
         end do
      end do
      z = dcmplx(1.0d0, 2.0d0)
      w = dcmplx(3.0d0, -1.0d0)
      z = z * w + z / w
      s = s + dble(z) + dimag(z)
      if (n .lt. 0) then
         write(*,*) 'RTGATE: invalid n =', n
         write(6,'(A,I8)') 'RTGATE: n=', n
      end if
      return
      end
