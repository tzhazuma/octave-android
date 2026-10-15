# GNU Octave → Android

Porting GNU Octave to Android as a **native deliverable** (standalone APK preferred).

**Read [`STATUS.md`](STATUS.md) first** — it is the single source of truth: current
status, the full command/error log, evidence index, and next steps.

---

## Status in one screen

| Track | State |
|---|---|
| **Route B — NDK native cross-build** | ✅ **GO.** The blocking uncertainty (Fortran) is resolved. |
| **Route A — Termux host** | ✅ Working, archived as the verified fallback. |

### Device-verified on real hardware (Android 16 / arm64-v8a), no Termux involved

| Component | Evidence |
|---|---|
| **FFTW 3.3.10** | `fftw-wisdom --version` → `FFTW version 3.3.10` |
| **OpenBLAS 0.3.34** (BLAS) | `dgemm` → `[19 22 ; 43 50]` |
| **OpenBLAS 0.3.34** (+ full LAPACK) | `dgesv` → `x = [0.090909, 0.636364]` = exactly `[1/11, 7/11]`; `dpotrf` Cholesky verified |
| **Fortran gate** | `FORTRAN_GATE_OK fscale -> 2.5 5.0 7.5 10.0  fdot=25.0` |

---

## The two findings that unblocked route B

**1. Fortran cross-compilation works — with zero LLVM builds.**

The NDK ships no Fortran compiler, and building LLVM+flang from source needs
~40 GiB (this box had ~15). Instead:

- `brew install flang` → host **flang 23.1.3** (a bottle; depends on the llvm already present)
- The aarch64 Fortran **runtime** is a **1.07 MB** prebuilt from Termux's
  [`ndk-toolchain-clang-with-flang` r30](https://github.com/termux/ndk-toolchain-clang-with-flang/releases/tag/r30)
  release → `libflang_rt.runtime.a` (117 members, all ELF64/AArch64, zero libc++
  dependencies, sha256 verified against Termux's own pinned value)

```sh
flang-new --target=aarch64-linux-android24 -O2 -fPIC -c fscale.f90 -o fscale.o
$NDK/.../aarch64-linux-android24-clang driver.c fscale.o -o gate \
  -L$FLANG_RT_DIR -lflang_rt.runtime -Wl,-z,max-page-size=16384 -lm
```

**2. LAPACK needs no Fortran compiler at all.**

OpenBLAS ships an **f2c-converted LAPACK in C** — `lapack-netlib/SRC/*.c`,
2067 files. Of 2046 `.f` files only `dbddsc` and `sbddsc` lack a C counterpart.
The switch is `C_LAPACK=1` (`lapack-netlib/SRC/Makefile:60`):

```sh
gmake OSNAME=Android ARCH=arm64 TARGET=ARMV8 CROSS=1 HOSTCC=/usr/bin/clang \
  NOFORTRAN=1 C_LAPACK=1 ...      # -> zero undefined _FortranA* symbols
```

The resulting library needs neither a Fortran compiler nor a Fortran runtime.

---

## Reproducing

```sh
scripts/fetch_flang_runtime.sh                 # 1 MB runtime, sha256-verified
scripts/build_fftw.sh                          # FFTW 3.3.10
OPENBLAS_MODE=clapack scripts/build_openblas.sh  # OpenBLAS + full LAPACK, pure C
ANDROID_SERIAL=<host>:<port> scripts/fortran_gate_test.sh   # Fortran gate, on device
```

`scripts/env.sh` holds the shared environment. It documents two traps that each
cost a failed build:

- `which clang` resolves to the **ATfE bare-metal toolchain**, which has no host
  sysroot (`stdio.h` not found). `HOSTCC` is pinned to `/usr/bin/clang`.
- `make install` needs `OSNAME=Android` too, or it emits `.dylib` symlinks
  instead of `.so`.

Every artifact is linked with `-Wl,-z,max-page-size=16384`, so LOAD segments are
**16 KiB aligned** as Android 15/16 requires, and depends only on bionic
(`libm` / `libdl` / `libc`).

---

## Layout

```
STATUS.md     full status, command/error log, evidence index, next steps
evidence/     device run transcripts, screenshots, ELF/symbol proofs
scripts/      reproducible build + device-test scripts
spike/        the gate experiments (Fortran, BLAS, LAPACK) with their sources
logs/         selected build logs
```
