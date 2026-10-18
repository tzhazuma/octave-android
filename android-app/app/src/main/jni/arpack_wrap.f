c     ARPACK wrapper for the Android JNI demo.
c     Calling ARPACK's dsaupd/dseupd directly from C is ABI-fragile because they
c     take `character` arguments (the Fortran ABI appends hidden length
c     arguments). So we wrap them here: Fortran-to-Fortran uses the correct ABI,
c     and C only sees plain integer/real arguments.
c
c     Solves the standard symmetric eigenproblem for a DIAGONAL matrix
c     (so the exact eigenvalues are known: d(1..n)), asking for the NEV
c     eigenvalues of smallest magnitude via WHICH='SM'.
      subroutine demo_eigs(n, d, nev, out, info)
      implicit none
      integer n, nev, info
      double precision d(*), out(*)
      integer maxn, maxncv
      parameter (maxn=1000, maxncv=60)
      integer ido, iparam(11), ipntr(11), ncv, lworkl, i, ierr
      character bmat*1, which*2
      character howmny*3
      logical rvec, select(maxncv)
      double precision tol, resid(maxn), v(maxn,maxncv)
      double precision workd(3*maxn), workl(3*maxncv*maxncv+6*maxncv)
      double precision dout(maxncv), sigma
      double precision dd(maxn)
      common /demodata/ dd

      if (n .gt. maxn) then
         info = -1
         return
      end if
      do i = 1, n
         dd(i) = d(i)
      end do

      ido    = 0
      bmat   = 'I'
      which  = 'SM'
      tol    = 0.0d0
      ncv    = min(maxncv, n)
      lworkl = ncv*(ncv+8)
      info   = 0
      iparam(1) = 1
      iparam(3) = 3000
      iparam(7) = 1
      do i = 1, n
         resid(i) = 1.0d0
      end do

      ierr = 0
      do while (ido .ne. 99)
         call dsaupd(ido, bmat, n, which, nev, tol, resid, ncv, v, maxn,
     &               iparam, ipntr, workd, workl, lworkl, ierr)
         if (ierr .ne. 0) then
            info = ierr
            return
         end if
         if (ido .eq. -1 .or. ido .eq. 1) then
            call av(n, workd(ipntr(1)), workd(ipntr(2)))
         end if
      end do

      rvec   = .true.
      howmny = 'All'
      do i = 1, ncv
         select(i) = .true.
      end do
      sigma = 0.0d0
      call dseupd(rvec, howmny, select, dout, v, maxn, sigma, bmat, n,
     &            which, nev, tol, resid, ncv, v, maxn, iparam, ipntr,
     &            workd, workl, lworkl, ierr)
      if (ierr .ne. 0) then
         info = ierr
         return
      end if
      do i = 1, nev
         out(i) = dout(i)
      end do
      info = 0
      return
      end

c     Matrix-vector product y = A*x for the diagonal matrix A = diag(dd).
      subroutine av(n, x, y)
      implicit none
      integer n, i
      double precision x(*), y(*)
      double precision dd(1000)
      common /demodata/ dd
      do i = 1, n
         y(i) = dd(i) * x(i)
      end do
      return
      end
