! Fortran kernel with classic f77-style ABI -- exactly the shape Octave/ARPACK/LAPACK use.
      subroutine fscale(n, a, x)
      implicit none
      integer n, i
      double precision a, x(*)
      do i = 1, n
         x(i) = x(i) * a
      end do
      end
      double precision function fdot(n, x, y)
      implicit none
      integer n, i
      double precision x(*), y(*), s
      s = 0.0d0
      do i = 1, n
         s = s + x(i)*y(i)
      end do
      fdot = s
      end
