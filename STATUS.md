# GNU Octave → Android：移植状态

**目标**：把 GNU Octave 作为 Android 交付物移植（独立原生 APK 优先）。
**工作目录约定**：产物全部放 `~/octave-android/`（不碰 `~/FreeCAD`、`~/freecad-android`）。
**路线 A 结论日期**：2026-10-15　**路线 B 闸门打通日期**：2026-10-16

---

## 0. TL;DR（结论）

**路线 B（NDK 原生交叉编译）从"高风险长线"升级为 GO —— 前任判定的最大壁垒（Fortran）
已被证伪，且完全不需要编译 LLVM 源码。**

四条数值栈已**交叉编译成功并在真机上跑出正确数值**，全程不经过 Termux：

| 组件 | 产物 | 真机验证结果 |
|---|---|---|
| **FFTW 3.3.10** | `libfftw3.so` 832K + `libfftw3_threads.so` | `fftw-wisdom --version` → `FFTW version 3.3.10`，RC=0 |
| **OpenBLAS 0.3.34（BLAS）** | `libopenblas_armv8p-r0.3.34.so` 3.2M | `dgemm` → `[19 22 ; 43 50]` 正确，RC=0 |
| **OpenBLAS 0.3.34（+ 完整 LAPACK）** | 同名 .so **12.3M，100% 纯 C** | `dgesv` → `x=[0.090909, 0.636364]` = 精确 `[1/11, 7/11]`；`dpotrf` Cholesky 校验通过，RC=0 |
| **Fortran 闸门**（决定性） | flang 编译的 `.o` + NDK 链接 | `FORTRAN_GATE_OK fscale -> 2.5 5.0 7.5 10.0  fdot=25.0`，RC=0 |
| **ARPACK-ng 3.9.1**（Fortran-only） | `libarpack.so` 848K，16 KiB 对齐 | `dsdrv1` 2D Laplacian：**4/4 Ritz 值收敛**，残差 ~1e-14，与独立计算 `19.60540/48.21935/48.21935/76.83329` **精确一致** |
| **qrupdate-ng 1.3.1**（Fortran-only） | `libqrupdate.so.1.3.1` 225K | **自带验证套件真机 `10/10 PASS`**（Cholesky/QR/LU 更新全覆盖） |

**关键突破两条**：

1. **flang 交叉编译可用，零 LLVM 构建**：
   - 主机 `brew install flang` → **flang 23.1.3**（bottle，依赖已有的 llvm）
   - `flang-new --target=aarch64-linux-android24 -c x.f90` 直接产出 **ELF64 AArch64** 目标文件，
     符号是标准 f77 ABI（`fscale_`、`fdot_`），正是 Octave/ARPACK/LAPACK 期望的调用约定
   - aarch64 的 Fortran **运行时**用 Termux 发布的预编译包（**仅 1.07 MB**）：
     `libflang_rt.runtime.a`，117 个成员全是 ELF64 AArch64，**libc++ 依赖数 = 0**，
     NDK clang 可直接链接；sha256 与 Termux 官方 pin 值一致
2. **LAPACK 根本不需要 Fortran**：OpenBLAS 自带 **f2c 转换好的 LAPACK C 源码**
   （`lapack-netlib/SRC/*.c`，2067 个；2046 个 `.f` 里**只有 `dbddsc`/`sbddsc` 2 个**没有 C 版本）。
   开关是 `C_LAPACK=1`（`lapack-netlib/SRC/Makefile:60`）。
   最终产物 `_FortranA*` 未定义符号数 = **0** → **既不需要 Fortran 编译器，也不需要 Fortran 运行时**。

**路线 A（Termux 宿主）已完整跑通，归档为保底方案**（§2），不再投入时间。

---

## 1. 两条路线的最终定位

| | 路线 A：Termux 宿主 | 路线 B：NDK 原生 |
|---|---|---|
| 状态 | ✅ 已跑通，归档保底 | ✅ **闸门已开，转为主线** |
| 真机证据 | `disp(2+2)`→`4`、`magic(3)`、`--version` | FFTW / BLAS / LAPACK / Fortran 四项均跑出正确数值 |
| 依赖 Fortran？ | Termux 用自建 flang 解决 | **不需要**（LAPACK 走 f2c C 源码；真需要时用 flang，已验证可用） |
| 体积 | bootstrap + 59 包 ≈ 1–2 GB | 数值栈目前 ≈ 16 MB，可控 |
| 上游同步成本 | 低（4 个补丁） | 中（bionic `ac_cv_*` 缓存） |

**结论**：按用户要求「优先原生 APK」，主线走 **路线 B**；路线 A 作为已验证的保底交付形态保留。

---

## 2. 路线 A 归档摘要（Termux 宿主，已跑通，勿重复验证）

真机 Android 16 / arm64（**具体 IP / 端口不入库**，见 §7 环境）：

- Termux 内 `pkg install -y octave` 成功，**octave `2:11.3.0-1`**，59 个包，`DONE_RC=0`
- `octave --eval "disp(2+2)"` → 屏幕输出 **`4`**（`evidence/octave_disp_2plus2.png`）
- `octave --version` → **`GNU Octave (aarch64-unknown-linux-android) version 11.3.0`**
- `disp(magic(3))` → 正确 3×3 幻方
- 无害警告：`linker: normalize_path - invalid input: "11.3.0"`（配方 rpath 里塞了带冒号的
  `2:11.3.0`，冒号是 rpath 分隔符 → 后半段被当相对路径；**自建包时应剥成 `11.3.0`**）

### 2.1 Termux 配方要点（金矿，仍适用于路线 B 的 Octave 本体阶段）

数据源：`termux/termux-packages:packages/octave/build.sh` + `x11-packages/octave-x/build.sh`。

| 参数 | 作用 |
|---|---|
| `--without-x`（GUI 用 `--with-x --with-qt=6`） | CLI 无 X |
| `--disable-java` | Android 无 JVM 集成 |
| `--enable-link-all-dependencies` | Octave 库习惯 |
| `--disable-openmp` | bionic 无 OpenMP 运行时 |
| `--with-blas=openblas` | BLAS 用 OpenBLAS |
| `--enable-fortran-calling-convention=f2c` | **关键**：Fortran 调用约定改 f2c，绕开 gfortran ABI |
| `ac_cv_func_getpw*=no` 等 20 余项 | bionic 缺失 libc 函数的强制回答 |
| `ac_cv_header_glob_h=no`、`gl_cv_cc_visibility=no` | 头文件/可见性差异 |

**三个补丁（都很小，全是 bionic/路径适配）**：

| 补丁 | 内容 |
|---|---|
| `0001-fix-hardcoded-paths.patch` | 4 处 `/tmp` → `$PREFIX/tmp`（`sysdep.cc`/`oct-env.cc`/`mkoctfile.in.cc`/`run-octave.in`） |
| `0002-append-rpath-flag-to-pkg-config-files.patch` | `octinterp.pc`/`octave.pc` 的 `Libs:` 追加 `-Wl,-rpath,@octlibdir@` |
| `0003-undefine-the-macro-in-pwd.h.patch` | `pwd-wrappers.c` 里 `#undef getpwnam/getpwuid/getpwuid_r` |

> **源码层无障碍**（重要）：Octave 在 bionic 上只需这 3 个小补丁 + 20 余个 `ac_cv_*`。
> **编译器层才是壁垒 —— 而该壁垒已在本轮解决（§3）。**

### 2.2 Termux 驱动机制（实测，用于真机自动化）

1. `com.termux/.app.RunCommandService` 是 **Service 不是 Receiver**，需 dangerous 权限
   `com.termux.permission.RUN_COMMAND`；**adb shell 无法驱动**（`pm grant` 对 shell 不生效）。
2. **可靠通道 = UI 注入**：`am start com.termux/.app.TermuxActivity` → 设备端
   `input text '...'` + `input keyevent 66`，输出重定向到 `/sdcard/Download` 读回。
3. **含特殊字符的 adb 命令必须写成设备端脚本 push 后执行**（本地 bash 单引号会被多层 shell 吃掉）。
4. 设备**无 root、无 su**。
5. 本轮新发现：Termux 的 `com.termux` 是 **debuggable**，因此 **`adb shell run-as com.termux` 可用**，
   可直接读取 Termux prefix（`files/usr/bin/` 等）——比 UI 注入快得多的探查通道。

---

## 3. 路线 B 进度与闸门分析

### 3.1 前任的 go/no-go 闸门 —— 已全部有结论

| 闸门 | 结论 |
|---|---|
| ① FFTW3（纯 C） | ✅ **已打通**，真机运行正确 |
| ② OpenBLAS（`NOFORTRAN=1`，先只出 BLAS） | ✅ **已打通**，真机 `dgemm` 正确 |
| ③ **真正的闸门：Fortran** | ✅ **已打通**，两条路都验证过（§3.3 / §3.4） |
| ④ 无先例可抄 | 仍然成立：GitHub 全网没有 NDK 版 Octave 先例（成熟做法全是宿主容器式） |

### 3.2 FFTW3 打通记录

源码 `fftw-3.3.10`，复现脚本 `scripts/build_fftw.sh`。**确切的 configure 调用**
（从成功构建的 `config.status` 里逐字取出，是真正的 replay 而非重构）：

```sh
./configure --host=aarch64-linux-android \
  --prefix=$HOME/octave-android/prefix/arm64-v8a/fftw \
  --enable-shared --disable-static --enable-threads --disable-fortran \
  host_alias=aarch64-linux-android \
  CC=$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android24-clang \
  CFLAGS="-O2 -fPIC" \
  LDFLAGS="-Wl,-z,max-page-size=16384"
```

产物校验：
- `libfftw3.so`（832K）、`libfftw3_threads.so`（32K）→ `ELF 64-bit LSB shared object, ARM aarch64`
- `fftw_make.log` / `fftw_install.log` 中 **error 数 = 0**
- **真机验证**：push 到 `/data/local/tmp` 后
  `LD_LIBRARY_PATH=/data/local/tmp ./fftw-wisdom --version`
  → `fftw-wisdom tool for FFTW version 3.3.10`，`RC=0`

### 3.3 Fortran 闸门打通记录（本轮核心突破之一）

#### 路线 (a)：LLVM flang-new —— **可行，且不需要自己编 LLVM**

**发现 1：主机侧有现成的 flang。**
```sh
brew install flang          # flang 23.1.3（bottle，1.2 GB，依赖已有的 llvm 23.1.3）
flang-new --version         # Homebrew flang version 23.1.3
```

**发现 2：aarch64 的 Fortran 运行时是预编译的 1 MB 包。**
Termux 发布了一整套「NDK toolchain clang with flang」：
`github.com/termux/ndk-toolchain-clang-with-flang/releases/tag/r30`

| 资产 | 大小 | 用途 |
|---|---|---|
| `package-flang-aarch64.tar.bz2` | **1.07 MB** | **解包得 `libflang_rt.runtime.a`（aarch64 运行时）** |
| `package-flang-host.tar.bz2` | 114 MB | 主机 flang 二进制（Linux，未用上） |
| `package-flang-x86_64` / `package-install` | 1.2 MB / 494 MB | x86_64 运行时 / 完整安装（未用上） |

`scripts/fetch_flang_runtime.sh` 会下载并**对照 Termux 自己 pin 的 sha256 校验**：
`47a57240cfe454d20d2b7181ed216e7c529e15c8e3002d890d02f8e64ab999c7` ✅

运行时包内容校验：
- 唯一文件 `libflang_rt.runtime.a`（15.4 MB）
- **117 个成员，全部 `ELF64 / AArch64 / REL`**
- undefined 符号只有 `fprintf`/`free`/`stderr`/`__stack_chk_fail` 等 bionic 符号，
  **`_ZNSt3__1`（libc++）计数 = 0** → NDK clang 可直接静态链接

**端到端三步（全部 RC=0，证据 `evidence/fortran_gate_run.txt`）**：
```sh
# 1) 用主机 flang 交叉编译 Fortran → aarch64 目标文件
flang-new --target=aarch64-linux-android24 -O2 -fPIC -c fscale.f90 -o fscale.o
#    → ELF64 / AArch64 / REL，符号 fscale_ fdot_（正确的 f77 调用约定）

# 2) 用 NDK clang 链接，Fortran 运行时来自 Termux 预编译包
$NDK/.../aarch64-linux-android24-clang -O2 -fPIC driver.c fscale.o -o gate \
  -L$FLANG_RT_DIR -lflang_rt.runtime -Wl,-z,max-page-size=16384 -lm
#    → LINK_RC=0

# 3) 真机运行（uid=shell，完全不经过 Termux）
adb shell /data/local/tmp/gate
#    → FORTRAN_GATE_OK fscale -> 2.5 5.0 7.5 10.0  fdot=25.0
#    → EXIT_RC=0
```

> **这直接回答了本轮任务指定的最大不确定点**：「LLVM flang-new 能否 target
> aarch64-linux-android 并产出可链接的 libFortranRuntime」→ **能，且零 LLVM 构建**。
> 于是前任计划里「最小切分 3. 交叉编 LLVM Flang」**整条可以删掉**。

#### 路线 (b)：f2c —— **比预期更强：OpenBLAS 的 LAPACK 直接有 f2c C 源码**

见 §3.4。结论：**LAPACK 完全不需要 Fortran**；flang 只需留给
ARPACK / qrupdate / Octave 本体那些没有 C 替代的源码。

#### 附带发现
Termux 设备上还有**原生 `gfortran-14`**（`aarch64-linux-android-gfortran-14` → `gfortran-14`，
1.97 MB），可作为第三条备用 Fortran 路径（需在设备上编译）。

### 3.4 OpenBLAS 打通记录（含完整 LAPACK）

源码 `OpenBLAS-0.3.34`（**与 Termux 真机上的 `libopenblas 0.3.34` 版本完全一致**）。
复现脚本 `scripts/build_openblas.sh`（三模式：`blas` / `clapack` / `fortran`）。

#### 模式 `blas`（`NOFORTRAN=1 NO_LAPACK=1`）—— 已打通
```sh
gmake -j12 OSNAME=Android ARCH=arm64 TARGET=ARMV8 \
  CROSS=1 HOSTCC=/usr/bin/clang \
  CC=$NDK/.../aarch64-linux-android24-clang AR=$NDK/.../llvm-ar RANLIB=$NDK/.../llvm-ranlib \
  NOFORTRAN=1 NO_LAPACK=1 NO_LAPACKE=1 \
  USE_OPENMP=0 BINARY=64 DYNAMIC_ARCH=0 \
  COMMON_OPT="-O2 -fPIC" LDFLAGS="-Wl,-z,max-page-size=16384" \
  PREFIX=$HOME/octave-android/prefix/arm64-v8a/openblas
```
产物校验：`ELF64/AArch64/DYN`；`DT_NEEDED` 只有 **`libm.so` / `libdl.so` / `libc.so`**（纯 bionic，
无 Termux 依赖）；`SONAME=libopenblas.so`；**LOAD 段对齐 = `0x4000` = 16 KiB**
（满足 Android 15/16 的 16 KB 页要求）；导出 2187 个 `T` 符号，
`dgemm_/dgemv_/daxpy_/ddot_/dscal_/dsyrk_/dtrsm_/zgemm_/sgemm_` 均在。
LAPACK 符号（`dpotrf_`/`dgesv_`…）按预期缺失。

**真机验证**（`spike/blas-test/blas_gate.c`，用 Fortran-ABI 直接调 `dgemm_`/`ddot_`）：
```
OPENBLAS_GATE_OK dgemm C = [19.0 22.0 ; 43.0 50.0]     # A*B 正确
OPENBLAS_GATE_OK ddot(A,B) = 17.0                       # 带步长的点积，正确
EXIT_RC=0
```

#### 模式 `clapack`（`NOFORTRAN=1 C_LAPACK=1`）—— **本轮第二个关键发现**

OpenBLAS **自带 f2c 转换好的 LAPACK C 源码**。开关在
`lapack-netlib/SRC/Makefile:60`：
```make
ifneq ($(C_LAPACK), 1)
    # 用 .f —— 需要真正的 Fortran 编译器
else
    .SUFFIXES: .c .o        # 用 f2c 转换后的 C 源码
endif
```
`lapack-netlib/SRC/dgetrf.c` 开头就是标准 f2c 产物特征（`#undef complex`、`BLASLONG`、
`LAPACK_ILP64` 那套样板）。

**覆盖率统计**：`SRC/` 下 2046 个 `.f` 对 2067 个 `.c`，
**只有 `dbddsc` 和 `sbddsc` 这 2 个 `.f` 没有 `.c` 对应**（且不在编译对象列表里）。

把 `NO_LAPACK`/`NO_LAPACKE` 去掉、换成 `C_LAPACK=1`，LAPACK + LAPACKE 全部纯 C 编译通过。
**隔离目录下的干净构建（`OPENBLAS_SRC=src/OpenBLAS-0.3.34-clapack`）：`OPENBLAS_MAKE_RC=0`，
日志 0 error，约 2 分钟。**

产物校验（`.so` 12.3 MB）：
- `ELF64/AArch64/DYN`；`DT_NEEDED` 只有 `libm/libdl/libc`；`SONAME=libopenblas.so`；对齐 `0x4000`
- 导出 **7115** 个 `T` 符号，`dgesv_/dpotrf_/dgetrf_/dsyev_/dgeqrf_/dlamch_/dstev_/dposv_/dgels_` 全在
- **纯度证明：`_FortranA*` 未定义符号数 = `0`**
  → **既不需要 Fortran 编译器，也不需要 Fortran 运行时**（`llvm-ar t` 中 flang 目标文件数 = 0）

**真机验证**（`spike/openblas-lapack/lapack_gate.c`，链接时**没有**任何 flang 运行时）：
```
LAPACK_GATE dgesv info=0  x = [0.090909 0.636364]
LAPACK_GATE expected  x = [0.090909 0.636364]  (1/11, 7/11)   # 精确一致
LAPACK_GATE dpotrf info=0  L^T = [2.000000 1.000000 ; 0.500000 1.658312]
LAPACK_GATE check L11^2 = 4.000000 (expect 4)                  # Cholesky 正确
EXIT_RC=0
```

> **意义**：Octave 需要的数值内核（BLAS + LAPACK + FFTW）**已经在 Android 上全部跑通**，
> 且**不需要 Fortran 编译器**。

#### 模式 `fortran`（`NOFORTRAN=0 FC=<flang 交叉驱动>`）—— **也已打通（并发 agent 补充，见 §3.5）**

> 本条原先记为「已定位障碍，非必需」。并发推进的另一路 agent **把它做通了**，
> 且这条路对 **ARPACK-ng / qrupdate-ng（无 f2c 版本）是必需的**。详见 §3.5。

### 3.5 全 Fortran 路线：把 flang 变成可用的交叉驱动（并发 agent 补充）

§3.3 证明了「flang 能编出 aarch64 目标文件」，但**目标文件能编 ≠ 整条链能编**。
本节把它推进到「**能替代 gfortran 跑完真实构建系统**」，这是 ARPACK-ng / qrupdate-ng /
Octave 本体（都没有 f2c C 替代）的前提。

#### 3.5.1 可复用的交叉驱动：`scripts/toolbin/aarch64-linux-android24-flang-new`

一个 Termux 风格的 wrapper，**编译走 flang、链接走 NDK clang**：

| 调用形态 | 行为 |
|---|---|
| `-v` / `--version` / `-dumpversion` / `-print-*` | → 主机 `flang-new`（**关键**：让 `f_check`/autoconf 正确识别为 LLVM Flang） |
| `-c` / `-S` / `-E` / `-fc1` … | → `flang-new --target=aarch64-linux-android24 --sysroot=<NDK>` |
| 其它（链接） | → **两阶段**：先把 `.f/.f90` 源用 flang 编成临时 `.o`，再用 NDK clang+lld 链接，并补上 flang 运行时 + compiler-rt builtins |

> **为什么链接不能用 flang 自己的驱动**（实测）：flang 驱动为
> `aarch64-unknown-linux-android24` 这个 triple 去找**只存在于宿主**的运行时：
> ```
> ld.lld: error: unable to find library -lflang_rt.runtime
> ld.lld: error: cannot open .../lib/clang/23/lib/aarch64-unknown-linux-android24/libclang_rt.builtins.a
> ld.lld: error: unable to find library -l:libunwind.a
> ```
> 而 NDK clang+lld 能正确链 bionic，我们再显式补 flang 运行时即可。

#### 3.5.2 四个链接错误与修法（全部实测）

| # | 错误 | 根因 | 修法 |
|---|---|---|---|
| a | `unable to find library -lflang_rt.runtime` / `libclang_rt.builtins.a` / `-l:libunwind.a` | flang 驱动按宿主 triple 找运行时 | 链接交给 NDK clang |
| b | `undefined symbol: stderr` / `__gnu_strerror_r` / `__write_chk` | bionic **API 21** 不导出这些 | 用 **API ≥ 24** + `-D_FORTIFY_SOURCE=2`（API 21 静态链接也能过） |
| c | `duplicate symbol: second_ / dsecnd_` | `-Wl,--whole-archive` 把 LAPACK `INSTALL/` 里多个**互斥**的 `second/dsecnd` 变体（`_NONE` / `_INT_ETIME` …）全拉进来 | `-Wl,--allow-multiple-definition` |
| d | `relocation R_AARCH64_ADR_PREL_PG_HI21 cannot be used against symbol 'Fortran::runtime::UTF8FirstByteTable'; recompile with -fPIC` | **Termux 的 aarch64 flang runtime 未用 `-fPIC` 编译**（`utf.cpp.o`、`numeric.cpp.o` 实测都是非 PIC） | **`-Wl,-Bsymbolic`**：把库内引用绑定为本地、不再可抢占，非 PIC 重定位即合法（`-Bsymbolic-functions` 不够，必须全量 `-Bsymbolic`） |

> ⚠️ **卡点 d 是路线 B 共享库阶段的关键发现**：Termux 的运行时**只能用于静态可执行文件**，
> 不能直接进 `.so`。`-Bsymbolic` 是可用绕过，但**长期正解是自建 `-fPIC` 的 `flang-rt`**——
> Octave 自身的 `.so`（liboctinterp 等）同样会撞上这个问题。
> 附带语义影响：`-Bsymbolic` 会关闭符号抢占（对数学库通常是好事，但需知晓）。

#### 3.5.3 规模验证：2197 个真实 Fortran 源文件，零失败

| 目标 | 文件数 | 结果 | 耗时 |
|---|---|---|---|
| `lapack-netlib/BLAS/SRC/*.f`（参考 BLAS） | **151** | ✅ **151/151** | 47 s |
| `lapack-netlib/SRC/*.f`（完整 LAPACK） | **2046** | ✅ **2046/2046** | 667 s |

全部产出 `ELF 64-bit LSB relocatable, ARM aarch64`。这比单个 gate 程序强得多：
它证明 flang 能吃下 LAPACK 的全部语法面（`COMPLEX*16`、`EQUIVALENCE`、`ENTRY`、
`COMMON`、`DATA`、老式定格式、`INTRINSIC`、格式化 I/O 等）。

#### 3.5.4 OpenBLAS 全 Fortran 构建（`NOFORTRAN=0`）

```sh
make TARGET=ARMV8 BINARY=64 DYNAMIC_ARCH=0 CROSS=1 F_COMPILER=FLANGNEW \
  CC=<NDK aarch64-linux-android24-clang> \
  FC=$HOME/octave-android/scripts/toolbin/aarch64-linux-android24-flang-new \
  HOSTCC=cc AR=<llvm-ar> RANLIB=<llvm-ranlib> \
  NOFORTRAN=0 USE_OPENMP=0 NUM_THREADS=64 PREFIX=$PREFIX/arm64-v8a/openblas shared
```

- `F_COMPILER=FLANGNEW` **必须显式给**：`f_check` 若解析版本失败会退回
  `FLANG`（那是**经典 PGI/NVIDIA flang**），进而注入 `-Mrecursive -Kieee`
  这两个 LLVM Flang 不认的编译选项。wrapper 已保证 `-v` 正确输出，显式指定更稳。
- 结果：`OPENBLAS_MAKE_RC=0`（shared）→ `libopenblas.a` **26 MB**、
  `libopenblas_armv8p-r0.3.34.so` **12.6 MB**（`ELF64/AArch64/DYN`）；
  `make install` 亦 `RC=0`。

**真机验证**（`spike/blas-test/blas_test.c`，vivo PA2573 / Android 16 / arm64-v8a）：
```
-- STATIC 归档 + 动态 bionic --
DGESV info=0 x=(2.000000, 3.000000)        # 3x+y=9, x+2y=8  -> (2,3) 正确
DGEMM C=(23.0 34.0; 31.0 46.0)             # 与手算一致
OPENBLAS_DEVICE_OK
-- 共享库 libopenblas.so --
DGESV info=0 x=(2.000000, 3.000000)
DGEMM C=(23.0 34.0; 31.0 46.0)
OPENBLAS_DEVICE_OK
```
- ✅ **共享库可用**（`-Bsymbolic` 绕过非 PIC 运行时后）
- ⚠️ **完全 `-static` 链接会 SIGSEGV（exit 139）**；但「归档 + 动态 bionic(PIE)」正常。
  Android 交付形态本就是 `.so`/PIE，**不阻塞**。

#### 3.5.5 与 `clapack` 模式的关系（两路互补，不是二选一）

| | `clapack`（`C_LAPACK=1`）| `fortran`（本节） |
|---|---|---|
| LAPACK 来源 | OpenBLAS 自带 f2c C 源码 | netlib `.f` 原版 |
| 需要 Fortran 编译器 | **否** | 是（flang） |
| 覆盖 ARPACK / qrupdate | **不能**（无 f2c 版） | **能** |
| 用途 | 交付 OpenBLAS 的更简路径 | **ARPACK-ng / qrupdate-ng / Octave 本体的唯一路径** |

> 结论：**两条都要保留**。OpenBLAS 走 `clapack` 更省事；但 §3.5 的 flang 驱动是
> 后续 ARPACK/qrupdate/Octave 的必经之路。

#### 3.5.6 并发构建冲突的澄清（重要）

§5 #30 记录「`second_NONE.o` 是另一个并发构建用 flang 编出来的」——
**那个「另一个并发构建」就是本节**。两个 agent 同时在 `src/OpenBLAS-0.3.34/` 里构建：
flang 侧产出 `second_NONE.o`，C 侧产出 `second_INT_ETIME.o`，`--whole-archive` 下撞名。
→ 与 §7.1 的结论一致：**必须用隔离源码树**。本节后续构建已改到隔离路径。

### 3.6 ARPACK-ng 打通记录（**Fortran-only 依赖的首次完整验证**）

ARPACK-ng 是第一个**没有 f2c/C 替代**的 Octave 依赖 —— 它只能靠 Fortran 编译器。
因此它是 §3.5 flang 路线的真正试金石。**已完整跑通并真机验证。**

源码 `arpack-ng 3.9.1`（与 Termux 真机上的 `arpack-ng 2:3.9.1` 版本一致）。

#### 3.6.1 autoconf 交叉编译下的 Fortran 检测 —— 通过（这是最大的未知点）

```sh
autoreconf -ivf                      # GitHub archive 不含 configure，需自生成
./configure --host=aarch64-linux-android \
  CC=<ndk aarch64-linux-android24-clang> \
  FC=<scripts/toolbin/aarch64-linux-android24-flang-new> F77=<同上> \
  ac_cv_f77_libs="-L$PREFIX/flang-runtime -lFortranRuntime -lFortranDecimal" \
  --enable-shared --disable-static \
  --with-blas="-L$PREFIX/openblas/lib -lopenblas" \
  --with-lapack="-L$PREFIX/openblas/lib -lopenblas"
```

configure 输出（`ARPACK_CONFIGURE_RC=0`，`Configuration OK`）：
```
checking for aarch64-linux-android-gfortran... .../aarch64-linux-android24-flang-new
checking whether we are cross compiling... yes
checking for Fortran 77 libraries of <wrapper>... (cached) -L.../flang-runtime -lFortranRuntime -lFortranDecimal
checking for Fortran 77 name-mangling scheme... lower case, underscore, no extra underscore
```

> **`lower case, underscore, no extra underscore` 是关键**：它正是 LAPACK / BLAS /
> Octave 全生态使用的 f77 调用约定（`fscale_`、`dsaupd_`）。说明 flang 产出的
> ABI 与既有 C 代码**天然兼容**，不需要 `--enable-fortran-calling-convention=f2c`
> 那类妥协（f2c 只是 Octave 用来**调用** Fortran 的另一种方式，非必需）。
> `ac_cv_f77_libs` 被 autoconf 采纳，无需再试链接探针。

#### 3.6.2 构建与产物

`make -j8` → **`ARPACK_MAKE_RC=0`，320 个 `.f` 全部编译，零 error**。

`SRC/.libs/libarpack.so`（**848 KB**）：
- `ELF64/AArch64/DYN`；`SONAME=libarpack.so`
- `DT_NEEDED` 只有 **`libopenblas.so` / `libm.so` / `libdl.so` / `libc.so`**（无 Termux 依赖）
- **LOAD 段对齐 `0x4000` = 16 KiB** ✓（Android 15/16 页大小要求）
- 导出 `dsaupd_` `dseupd_` `dnaupd_` `dneupd_` `ssaupd_` `znaupd_` ✓

> ⚠️ **构建陷阱（复现时必踩）**：`UTIL/.libs/libarpackutil.a` 是**空的（96 字节，0 个成员）**，
> 而 `libarpack.so` 并未把 UTIL 例程折进去 → 直接链 `-larpackutil` 无效，
> 运行时报 `cannot locate symbol "svout_"`。
> **修法**：显式把 `UTIL/.libs/*.o`（`dmout/ivout/dvout/svout/second_NONE` 等）加进链接；
> `arscnd_` 在 `second_NONE.o` 里。
> 另外链接可执行文件时需 `-Wl,--allow-shlib-undefined`（`libarpack.so` 对 UTIL 符号是未定义引用）。

#### 3.6.3 真机数值验证：**与独立计算精确一致**

用 ARPACK 自带的 `EXAMPLES/SYM/dsdrv1.f`（**2D Laplacian，10×10 网格，N=100，
按 1/h²=121 缩放**）跑 `dsaupd`/`dseupd` 求**最小幅值（SM）4 个特征值**：

```
  Size of the matrix is  100
  The number of Ritz values requested is  4
  The number of Arnoldi vectors generated (NCV) is  10
  What portion of the spectrum: SM
  The number of converged Ritz values is  4      <- 4/4 全部收敛
  The number of Implicit Arnoldi update iterations taken is  30
  The convergence criterion is  1.1102230246251565E-16
```

| Ritz 值（设备） | 相对残差 | 独立计算 `121*(4-2cos(jπ/11)-2cos(kπ/11))` |
|---|---|---|
| `1.96054D+01` | `2.3e-14` | **19.60540** |
| `4.82193D+01` | `7.9e-15` | **48.21935** |
| `4.82193D+01` | `5.1e-15` | **48.21935**（(1,2)/(2,1) 简并，符合预期） |
| `7.68333D+01` | `7.1e-15` | **76.83329** |

> **5 位有效数字精确吻合，残差 ~1e-14（机器精度）** → ARPACK + OpenBLAS 在 Android 上
> **数值正确**。这是「Fortran 闸门」从「能编译」到「能算出对的答案」的完整闭环。
> 证据：`evidence/arpack_device.log`。

### 3.7 qrupdate-ng 打通记录（**最后一个 Fortran-only 依赖，自带测试套件 10/10 通过**）

源码 `qrupdate-ng 1.3.1`，**sha256 `6013533…e6c55ea` 与 Termux 配方 pin 值完全一致** ✓。

#### 3.7.1 CMake 交叉配置（与 §3.6 的 autoconf 路线并列的第二条验证）

```sh
cmake <src> -DCMAKE_SYSTEM_NAME=Linux \      # 按 Termux 的做法：对 CMake 冒充 Linux，
  -DCMAKE_C_COMPILER=<ndk aarch64-linux-android28-clang> \   # 绕开 CMake 自带 NDK 集成
  -DCMAKE_Fortran_COMPILER=<scripts/toolbin/aarch64-linux-android24-flang-new> \
  -DCMAKE_AR=<llvm-ar> -DCMAKE_RANLIB=<llvm-ranlib> \
  -DCMAKE_EXE_LINKER_FLAGS="-L<flang-runtime> -lFortranRuntime -lFortranDecimal <builtins> -Wl,--allow-shlib-undefined -lm" \
  -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-Bsymbolic -Wl,--allow-multiple-definition -Wl,--allow-shlib-undefined" \
  -DLAPACK_LIBRARIES=<openblas.so> -DBLAS_LIBRARIES=<openblas.so> \
  -DCMAKE_INSTALL_PREFIX=<prefix>/qrupdate -DBUILD_SHARED_LIBS=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5
```
结果：`CMAKE_RC=0`；`-- The Fortran compiler identification is LLVMFlang 23.1.3`、
`Check for working Fortran compiler ... - works`、`Found BLAS` / `Found LAPACK`。

#### 3.7.2 两个新踩到的坑

| 现象 | 根因 | 修法 |
|---|---|---|
| `FortranCInterface_VERIFY` 链接失败：`undefined symbol: _FortranAioBeginExternalListOutput / _FortranAioOutputAscii / _FortranAioEndIoStatement` | CMake 的**混合 C/Fortran 测试用 C 驱动链接**，我们补的 flang 运行时只在 `FC` 那条线上 | 把 flang 运行时 + builtins 也加到 **`CMAKE_EXE_LINKER_FLAGS`** |
| 测试二进制链接失败：`undefined symbol: aligned_alloc` | **bionic 从 API 28 才提供 `aligned_alloc`**，而基线是 API 24 | wrapper 支持 `ANDROID_API_LEVEL` 覆盖（默认 24）→ 测试用 **28**。**库本身在 24 也能建** |

> wrapper 已改为 **API 等级可通过 `ANDROID_API_LEVEL` 环境变量覆盖**（默认 24，向后兼容）。

#### 3.7.3 构建与真机验证

- `make -j8` → **`MAKE_RC=0`，零 error**（451 个 Fortran 源，含 `lapack-missing/`）
- `libqrupdate.so.1.3.1`（225 KB），`SONAME=libqrupdate.so.1`；另有 `libqrupdate.a`（325 KB）
- **qrupdate 自带验证套件在真机上 `10/10 PASS`**：
  ```
  PASS tch1up  PASS tch1dn  PASS tchdex  PASS tchinx  PASS tchshx
  PASS tqr1up  PASS tqrinc  PASS tqrinr  PASS tqrshc  PASS tlu1up
  QRUPDATE_TESTS pass=10 fail=0
  ```
  覆盖 Cholesky 更新/降级（`ch1up`/`ch1dn`/`chdex`/`chinx`/`chshx`）、
  QR 更新/插入/删除/位移（`qr1up`/`qrinc`/`qrinr`/`qrshc`）、LU 更新（`lu1up`）。
- 证据：`evidence/qrupdate_device.log`

#### 3.7.4 外部佐证：Termux 用了**和我们一样**的 `-Bsymbolic`

Termux 自己的 `packages/qrupdate-ng/build.sh` 里有：
```sh
termux_setup_flang                                        # LLVM Flang，与我们一致
-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-Bsymbolic                # 与 §3.5.2 卡点 d 的修法完全一致
```
→ **独立佐证**：非 PIC 的 flang 运行时进 `.so` 确实需要 `-Bsymbolic`，这不是我们的误判，
而是这条技术路线的固有特征（也说明 Termux 并未自建 PIC 运行时，而是同样绕过）。

---

## 4. 已验证到哪一步（证据索引）

全部证据在 `~/octave-android/evidence/`：

| 文件 | 内容 |
|---|---|
| `octave_disp_2plus2.png` | **路线 A 主证据**：Termux 屏上 `disp(2+2)` → `4` |
| `oct_ver.txt` | `GNU Octave (aarch64-unknown-linux-android) version 11.3.0` |
| `oct_magic.txt` | `disp(magic(3))` → `8 1 6 / 3 5 7 / 4 9 2` |
| `octave_out.txt` / `oct_install.log` | `disp(2+2)` 完整输出 / 59 包装载日志（`DONE_RC=0`） |
| `termux_launch.png` / `inj1.png` / `oct_probe.png` | Termux 启动、UI 注入通道、环境探查截图 |
| **`fortran_gate_run.txt`** | **Fortran 闸门三步全记录**（flang 交叉编译 → NDK 链接 → 真机运行） |
| **`fortran_gate_binary`** | 真机跑通的 aarch64 可执行文件本体（6.6 KB） |
| **`openblas_lapack_gate_run.txt`** | **纯 C BLAS+LAPACK 记录**：纯度证明 + ELF/依赖/对齐 + 真机 `dgesv`/`dpotrf` |
| **`fortran_gate.log`** | **可复现 Fortran 闸门全记录**（§3.5）：工具链身份、纯计算目标文件、运行时 ABI 面、API21 失败 vs API24+fortify 成功、与宿主 gfortran 数值对照 |
| **`fortran_gate_device.log`** | **真机运行记录**：`FORTRAN_GATE_OK`（static+PIE）、`RT_GATE_OK`（matmul/内建/complex/write） |
| **`openblas_device.log`** | **全 Fortran OpenBLAS 真机数值验证**：`DGESV`/`DGEMM` 与手算一致（静态归档 + 共享库两种链接） |
| **`arpack_device.log`** | **ARPACK-ng 真机验证**（§3.6）：autoconf 交叉检测、320 个 `.f` 零错误、`.so` 属性、`dsdrv1` 特征值与独立计算精确一致 |
| **`qrupdate_device.log`** | **qrupdate-ng 真机验证**（§3.7）：CMake 交叉配置、451 个 Fortran 源零错误、**自带测试套件 10/10 PASS**、Termux `-Bsymbolic` 佐证 |

配套源码/测试在 `~/octave-android/spike/`：
- `spike/fortran-gate/`：`fscale.f90`、`driver.c`、`gate`（+ 产物 `fscale.o`）
- `spike/blas-test/`：`blas_gate.c`、`blas_gate`
- `spike/openblas-lapack/`：`lapack_gate.c`、`lapack_gate`、`lapack_gate_clean`

构建日志在 `~/octave-android/logs/`。

---

## 5. 已尝试命令与逐条错误（调试历程，按时间序）

### 路线 A（2026-10-15）

| # | 尝试 | 结果/错误 | 修法 |
|---|---|---|---|
| 1 | `adb devices` | `command not found` | 用 `~/Library/Android/sdk/platform-tools/adb` 全路径 |
| 2 | `curl api.github.com/search/...` | `API rate limit exceeded` | 改用已登录的 `gh api`；纯内容用 `raw.githubusercontent.com` |
| 3 | GitHub tree HTML 抓目录 | 抓到仓库根 payload | 改 `gh api repos/.../contents/<dir>` |
| 4 | `am broadcast -n com.termux/.RunCommandReceiver` | `/system/bin/sh: can't create &1` | 组件名不对 + 引号被吃掉 |
| 5 | 输出文件里是 am 自己的报错 | `>` 被**设备 shell**截获，把 am 报错写进了"输出文件" | 从此含特殊字符的命令一律写**设备端脚本** |
| 6 | 查源码 | 真实组件是 **`com.termux/.app.RunCommandService`**（Service） | 换 `am start-foreground-service` |
| 7 | 未授权时调 Service | `Error: Requires permission com.termux.permission.RUN_COMMAND` | 需 shell 持有该 dangerous 权限 |
| 8 | `pm grant com.android.shell ...` | rc=0 **但不生效**（shell 未在 manifest declare） | adb 路线不通 |
| 9 | 前台后重试 | `Failed transaction (2147483646)`，`mAllowStart_*=DENIED` | 放弃 adb 程序化通道 |
| 10 | `adb shell su` / `adb root` | `su: inaccessible or not found` / production build | 设备不可 root |
| 11 | **UI 注入** `input text ...` + `keyevent 66` | ✅ `inj.txt` = `INJ_TEST_OK` | 确立主力自动化通道 |
| 12 | `pkg install -y octave` | 自动测速选 mirror，59 包，**`DONE_RC=0`**（约 3 分钟） | 无需人工换源 |
| 13 | `octave --eval "disp(2+2)"` | `4` ✅（附带 rpath 冒号警告） | 警告不阻塞 |

### 路线 B（2026-10-16）

| # | 尝试 | 结果/错误 | 修法 |
|---|---|---|---|
| 14 | 检查 NDK r28 | **无 flang/gfortran**；`find *Fortran*` 空 | 需要外部 Fortran 方案 |
| 15 | 检查主机 LLVM | `brew llvm 23.1.3` / `ATfE-23.1.0` / `llvm@22/18/15` **全都没有 flang** | 找独立 flang |
| 16 | 想编 LLVM 源码 | 磁盘实测只剩 **15 GiB**（非 25），LLVM 全量构建需 ~40+ GiB | **此路不可行，必须绕开** |
| 17 | LLVM release 的 `.jsonl` | 是 sigstore 证明包，**不是文件清单**，查不到 flang | 换思路 |
| 18 | `brew search flang` | **有 `flang` formula**（23.1.3，bottled） | `brew install flang` → 成功 |
| 19 | Termux `clang` 包 | 里面**没有** flang（只有 clang-21） | flang 来自另一处 |
| 20 | 读 `termux_setup_flang.sh` | 发现预编译 release `termux/ndk-toolchain-clang-with-flang@r30` | **直接取 aarch64 运行时（1 MB）** |
| 21 | **`flang-new --target=aarch64-linux-android24 -c fscale.f90`** | ✅ **ELF64 AArch64 REL，符号 `fscale_`/`fdot_`** | **闸门开** |
| 22 | NDK clang 链接 flang 目标文件 | ✅ `LINK_RC=0`，真机 `FORTRAN_GATE_OK ... fdot=25.0` | 完成 |
| 23 | OpenBLAS 首次构建 | `getarch.c:80: fatal error: 'stdio.h' file not found` → 级联 `config.h not found` | **根因：`which clang` 指向 `~/toolchains/ATfE-*/bin/clang`（Arm 裸机编译器，无 host sysroot）**；钉 `HOSTCC=/usr/bin/clang` |
| 24 | 修 HOSTCC 后重建 | ✅ `libopenblas_armv8p-r0.3.34.so`，真机 `dgemm` 正确 | `MAX_CPU_NUMBER` 也从空变成 12 |
| 25 | `make install` | 生成 `.dylib` 符号链接而非 `.so`（`install_name_tool` 报错但被 ignore） | **`make install` 也必须带 `OSNAME=Android`** |
| 26 | 想开 Fortran 编 LAPACK | `f_check` 要**运行**探针程序推断 ABI，交叉编译跑不了 | 不走这条 |
| 27 | 找 f2c 路径 | `lapack-netlib/SRC/` 有 **2067 个 `.c`**（`dgetrf.c`/`dgesv.c`/`dsyev.c`…） | 找到开关 |
| 28 | 读 `lapack-netlib/SRC/Makefile:60` | `ifneq ($(C_LAPACK),1)` → `.f`；`else` → `.c` | **用 `C_LAPACK=1`** |
| 29 | `NOFORTRAN=1 C_LAPACK=1` 构建（共享树） | LAPACK+LAPACKE 全部编完进静态库（26 MB）；**最后 `.so` 链接**报 `duplicate symbol: second_` | 见 #30 |
| 30 | 查重复符号根因 | `second_NONE.o` 是**另一个并发构建**用 flang 编出来的，与我们的 C 版 `second_INT_ETIME.o` 撞名 | **两个 agent 在同一个源码树并发构建**；改用隔离目录 |
| 31 | 快照静态库 + `llvm-ar d` 掉 flang 重复成员 + 手工链 `.so` | ✅ 12.3 MB，真机 `dgesv`/`dpotrf` 数值正确 | 临时验证 |
| 32 | **隔离目录干净重建**（`OPENBLAS_SRC=src/OpenBLAS-0.3.34-clapack`） | ✅ **`OPENBLAS_MAKE_RC=0`，0 error，约 2 分钟**；`_FortranA*` 未定义 = **0**；真机数值正确 | **最终交付路径** |

### 路线 B · 全 Fortran 分支（2026-10-16，并发 agent；详见 §3.5）

| # | 尝试 | 结果/错误 | 修法 |
|---|---|---|---|
| 33 | 宿主找 Fortran 编译器 | `/opt/homebrew/bin/flang-new` **已存在**（flang 23.1.3）、`gfortran` 16.2.0（仅 Darwin target） | **flang-new 是 target-agnostic 的**，直接加 `--target=` 即可 |
| 34 | `flang-new --target=aarch64-linux-android21 --sysroot=<NDK> -c fscale.f90` | ✅ `ELF 64-bit LSB relocatable, ARM aarch64`；导出 `fscale_`/`fdot_`；**undefined = 0** | 纯计算 Fortran **不需要运行时** |
| 35 | NDK clang 链接 + 真机跑 | ✅ `FORTRAN_GATE_OK fscale -> 2.5 5.0 7.5 10.0  fdot=25.0` | 闸门开 |
| 36 | 更硬的门：`matmul` 内建 + `sqrt/sin/cos` + `COMPLEX*16` + 格式化 `WRITE` | 需 12 个未定义符号：`_FortranAAssign`/`_FortranAMatmulReal8Real8`/`_FortranAio*`/`__divdc3`/`sin`/`cos`… | 需 flang 运行时 + compiler-rt builtins |
| 37 | 用 Termux `libflang_rt.runtime.a` + NDK `libclang_rt.builtins-aarch64-android.a` 链接 | ✅ 两者齐备：运行时 DEFINED 全部 `_FortranA*`，NDK 提供 `__divdc3` | — |
| 38 | **API 21 动态链接** | ❌ `undefined symbol: stderr` / `__gnu_strerror_r` / `__write_chk` | **改 API ≥ 24 + `-D_FORTIFY_SOURCE=2`** |
| 39 | API 24/28/30/34 动态链接 | ✅ 全部成功；真机 `RT_GATE_OK s=26.316947 …` | 静态链接在 API 21 也能过 |
| 40 | **数值交叉验证** | ✅ 宿主 `gfortran` 参考实现给出**完全相同的** `s=26.316947` | 交叉编译产物数值可信 |
| 41 | `flang-new` 作为链接驱动（OpenBLAS `.so`） | ❌ `-lflang_rt.runtime` / `libclang_rt.builtins.a` / `-l:libunwind.a` 找不到 | 写 wrapper：链接交给 NDK clang |
| 42 | wrapper 处理 `-v` | ❌ 旧 wrapper 把 `-v` 当链接、触发 bash 3.2 `objs[@]: unbound variable` → `f_check` 解析失败 | **后果**：OpenBLAS 判成 `F_COMPILER=FLANG`（经典 PGI flang）→ 注入 `-Mrecursive -Kieee`。修 wrapper 的 info-flag 分支 |
| 43 | `--whole-archive` 链 `.so` | ❌ `duplicate symbol: second_ / dsecnd_`（LAPACK `INSTALL/` 多个互斥变体） | `-Wl,--allow-multiple-definition` |
| 44 | 补 flang 运行时后链 `.so` | ❌ `relocation R_AARCH64_ADR_PREL_PG_HI21 cannot be used against 'Fortran::runtime::UTF8FirstByteTable'; recompile with -fPIC` | **Termux 运行时非 PIC** → **`-Wl,-Bsymbolic`**（`-Bsymbolic-functions` 不够） |
| 45 | `OPENBLAS_MAKE_RC`（`NOFORTRAN=0 F_COMPILER=FLANGNEW shared`） | ✅ **RC=0**：`.a` 26 MB + `.so` 12.6 MB；`make install` RC=0 | — |
| 46 | 真机 `dgesv`/`dgemm`（共享库） | ✅ `x=(2,3)`、`C=(23 34 31 46)` 与手算一致 | 完成 |
| 47 | 真机 **`-static`** 链接 | ❌ **SIGSEGV（exit 139）**；同代码「归档 + 动态 bionic(PIE)」正常 | Android 交付用 `.so`/PIE，**不阻塞** |
| 48 | ARPACK-ng GitHub archive 解包 | ❌ **没有 `configure`**（archive tarball 不含生成文件） | `autoreconf -ivf` 自生成（需 `glibtoolize`，Homebrew libtool 提供） |
| 49 | `./configure --host=aarch64-linux-android FC=<flang wrapper>` | ✅ `RC=0`、`Configuration OK`；`cross compiling... yes`；**`name-mangling: lower case, underscore, no extra underscore`** | autoconf Fortran 交叉检测**通过**，`ac_cv_f77_libs` 被采纳 |
| 50 | `make -j8`（320 个 `.f`） | ✅ **`RC=0`，零 error**；`libarpack.so` 848 KB、16 KiB 对齐、导出 `dsaupd_/dseupd_/…` | — |
| 51 | 链接示例时报 `undefined symbol: dmout_/ivout_/arscnd_/svout_` | ❌ **`UTIL/.libs/libarpackutil.a` 是空的（96 字节，0 成员）**，且 UTIL 例程未折进 `libarpack.so` | 显式把 `UTIL/.libs/*.o` 加进链接；可执行文件加 `-Wl,--allow-shlib-undefined` |
| 52 | 真机跑 `EXAMPLES/SYM/dsdrv1.f` | ✅ **4/4 Ritz 值收敛，残差 ~1e-14**；与独立计算的 `19.60540 / 48.21935 / 48.21935 / 76.83329` **精确一致** | **ARPACK 打通（Fortran-only 依赖闭环）** |
| 53 | qrupdate-ng `cmake -DCMAKE_SYSTEM_NAME=Linux` | ✅ `CMAKE_RC=0`；`Fortran compiler identification is LLVMFlang 23.1.3`、`works`、`Found BLAS/LAPACK` | 对 CMake 冒充 Linux 可绕开其 NDK 集成 |
| 54 | `FortranCInterface_VERIFY` 链接 | ❌ `undefined symbol: _FortranAioBeginExternalListOutput / _FortranAioOutputAscii / _FortranAioEndIoStatement`（混合 C/Fortran 测试走 **C 驱动**链接，没有 flang 运行时） | 把 flang 运行时 + builtins 加进 **`CMAKE_EXE_LINKER_FLAGS`** |
| 55 | 测试二进制链接 | ❌ `undefined symbol: aligned_alloc`（**bionic 从 API 28 才有**） | wrapper 支持 `ANDROID_API_LEVEL` 覆盖（默认 24）→ 测试用 28；库本身 24 也能建 |
| 56 | `make -j8`（451 个 Fortran 源） | ✅ **`MAKE_RC=0`，零 error**；`libqrupdate.so.1.3.1` 225 KB、`SONAME=libqrupdate.so.1` | — |
| 57 | 真机跑 qrupdate **自带验证套件** | ✅ **`10/10 PASS`**（`tch1up tch1dn tchdex tchinx tchshx tqr1up tqrinc tqrinr tqrshc tlu1up`） | **最后一个 Fortran-only 依赖打通** |

---

## 6. 下一步（优先级序）

数值内核（FFTW + BLAS + LAPACK + ARPACK + qrupdate）已在真机跑通，剩下的都是**工程量而非壁垒**：

1. ~~**ARPACK-ng**~~ ✅ **已完成**（§3.6，真机特征值精确验证）。
   ~~**qrupdate-ng**~~ ✅ **已完成**（§3.7，**自带测试套件真机 10/10 PASS**）。
   → **Fortran-only 依赖已全部清零**；Fortran 侧不再有任何未知点。
   已验证的关键事实：autoconf 交叉检测出的 ABI 是
   `lower case, underscore, no extra underscore`，与既有 LAPACK/BLAS/Octave 生态天然一致，
   不需要为 ABI 做任何妥协。
2. **其余纯 C 依赖**：`qhull`、`suitesparse`(CXSparse/COLAMD)、`glpk`、`hdf5`、`zlib`/`bzip2`、
   `readline`、`pcre2`、`curl`、`fftw`(已好)、`sundials`。
3. **Octave 本体**（最后一步）：
   - 宿主侧准备 autoconf **cache file**（把 §2.1 那 20 余个 `ac_cv_*` 固化）
   - 打上 Termux 的 3 个补丁（§2.1）
   - `--enable-fortran-calling-convention=f2c` + `--with-blas=openblas` + `--disable-openmp` + `--disable-java`
   - **rpath 版本号要剥掉冒号**（`11.3.0` 而不是 `2:11.3.0`），避免前任踩过的
     `normalize_path - invalid input: "11.3.0"` 刷屏
4. **运行时数据 + mkoctfile**：`share/octave/<ver>/m`（数十 MB）+ 设备侧 clang 工具链
   （`.oct` 模块动态加载需要）。
5. **JNI/UI 壳 + 打包**：APK 内 `jniLibs/arm64-v8a/`，全部 `.so` 必须
   `-Wl,-z,max-page-size=16384`（本仓库所有产物已满足）。
6. **性能后续**：`TARGET=ARMV8` 是通用基线；真机是 **MediaTek MT8799（Cortex-X4 + Cortex-A720，
   带 SVE2/i8mm/bf16）**，后续可换 `NEOVERSEV1`/`CORTEXA76` 或开 `DYNAMIC_ARCH`。
7. **【新增·技术债】自建 `-fPIC` 的 `flang-rt` 运行时**（§3.5.2 卡点 d）。
   Termux 预编译的 `libflang_rt.runtime.a` **非 PIC**，只能进静态可执行文件；
   目前靠 `-Wl,-Bsymbolic` 绕过。Octave 自身的共享库（`liboctinterp.so` 等）会持续撞上
   这个问题，且 `-Bsymbolic` 有语义副作用（关闭符号抢占）。
   正解：按 Termux 的 `packages/flang/build.sh` 里 `__flang_build_runtime` 的做法，
   用 `LLVM_ENABLE_RUNTIMES=flang-rt` + `-DLLVM_ENABLE_PIC=ON` 自建一份 aarch64 运行时。
   **建议在 ARPACK 之后、Octave 本体之前做**，避免后面反复绕。

---

## 7. 环境事实（本机）

- 主机：**macOS arm64**（Apple Silicon），`uname -m` = `arm64`
- 磁盘：`df -h ~` → 926 Gi 总，**构建期间可用量在 3.8–15 GiB 之间剧烈波动**（另一路
  `~/blender-android` 满核构建在同时吃磁盘/CPU）→ **大动作前必须 `df -h ~`**
- NDK：`~/Library/Android/sdk/ndk/28.2.13676358`（clang 19，**无 flang**）
- adb：`~/Library/Android/sdk/platform-tools/adb`（**不在 PATH**）
- flang：`/opt/homebrew/opt/flang/bin/flang-new`（23.1.3，`brew install flang`）
- 真机：Android 16 / arm64-v8a / **MT8799**（**IP 与 adb 端口不入库**；adb 端口每次会变，
  先 `adb devices`，离线则 `adb mdns services` 找活着的 `_adb-tls-connect._tcp`）；
  已装 `com.termux` + `com.termux.x11`，**不可 root**，但 `com.termux` 是 debuggable（`run-as` 可用）
- 模拟器：`emulator-5554`（`sdk_gphone64_arm64`，Android 16，未装 Termux）
- `web_search` 工具：402 Insufficient Balance，不可用 → 用 `curl` / `gh api`
- 网络：`curl` 前先 `unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY`
- **PATH 陷阱（重要）**：`which clang` → `~/toolchains/ATfE-23.1.0-Darwin-universal/bin/clang`
  （Arm 裸机编译器，**无 host sysroot**，`stdio.h` 找不到）。构建脚本里必须显式钉
  `HOSTCC=/usr/bin/clang`。见 `scripts/env.sh`。

### 7.1 并发构建警告

OpenBLAS 的构建**在原树内写 `.o`**。本轮实测：两个进程在同一个
`src/OpenBLAS-0.3.34/` 里并发构建，导致 flang 编出的 `second_NONE.o` 与 C 编出的
`second_INT_ETIME.o` 撞名，`.so` 链接失败。
→ **务必用 `OPENBLAS_SRC=<隔离目录>` 指定独立源码树**（`scripts/build_openblas.sh` 已支持）。

---

## 8. 可复现命令（脚本索引）

| 脚本 | 作用 |
|---|---|
| `scripts/env.sh` | 共享环境：NDK 路径、目标三元组、`HOSTCC` 钉法、flang 路径、16 KB 页 LDFLAGS |
| `scripts/fetch_flang_runtime.sh` | 下载 + **按 Termux 官方 sha256 校验** aarch64 `libflang_rt.runtime.a` |
| `scripts/build_fftw.sh` | 交叉编译 FFTW3（逐字复现成功构建的 configure 调用） |
| `scripts/build_openblas.sh` | 交叉编译 OpenBLAS，三模式 `blas` / `clapack` / `fortran`；支持 `OPENBLAS_SRC` 隔离 |
| `scripts/fortran_gate_test.sh` | 复现 Fortran 闸门三步（编译 → 链接 → 真机运行） |
| **`scripts/toolbin/aarch64-linux-android24-flang-new`** | **可复用的 flang 交叉驱动**（§3.5.1）：编译走 flang、链接走 NDK clang；已内含 `--allow-multiple-definition` + `-Bsymbolic` + `-D_FORTIFY_SOURCE=2`。**ARPACK/qrupdate/Octave 直接用 `FC=<此脚本>`** |
| **`scripts/ndk-flang-env.sh`** | 一键导出整套 NDK+flang 交叉环境变量（`CC/CXX/FC/F77/ac_cv_f77_libs/LIBS` 等），供 autoconf 类构建 `source` |
| **`scripts/fortran-gate.sh`** | 生成 `evidence/fortran_gate.log`（含 API21 失败与 API24 成功的对照，可复现） |
| **`scripts/build-openblas.sh`** | **全 Fortran** OpenBLAS 构建（`NOFORTRAN=0 F_COMPILER=FLANGNEW`），与 `build_openblas.sh` 的 `clapack` 模式互补 |
| `scripts/device_run.sh` | 设备端脚本：驱动 Termux `RunCommandService`（路线 A 归档用） |
| `scripts/probe_octave.sh` | 设备端脚本：探查 Termux 环境（路线 A 归档用） |

---

# 9. 2026-10-17 收尾轮：环境修复 + 纯 C 依赖 + **Octave core 交叉 configure 通过**

## 9.1 验收项：**在真机上重新取证**

本轮开工先复验上一轮的 LAPACK 结论（不是引用旧日志）：
```sh
adb push spike/openblas-lapack/lapack_gate /data/local/tmp/lapack_gate
adb push spike/openblas-lapack/libopenblas_armv8p-r0.3.34.so /data/local/tmp/libopenblas.so
adb shell 'cd /data/local/tmp && LD_LIBRARY_PATH=/data/local/tmp ./lapack_gate; echo EXIT_RC=$?'
```
```
LAPACK_GATE dgesv info=0  x = [0.090909 0.636364]
LAPACK_GATE expected  x = [0.090909 0.636364]  (1/11, 7/11)
LAPACK_GATE dpotrf info=0  L^T = [2.000000 1.000000 ; 0.500000 1.658312]
LAPACK_GATE check L11^2 = 4.000000 (expect 4)
EXIT_RC=0
```
→ OpenBLAS 0.3.34（含完整 Fortran LAPACK，纯 C 源码）在真机上**数值正确**，`dgesv` 精确解
= `[1/11, 7/11]`，`dpotrf` Cholesky 校验通过。

## 9.2 🔧 修掉一个**环境级阻塞**：`brew flang` 因 z3 升级而崩

本轮开工时 `flang-new --version` **直接崩**：
```
dyld: Library not loaded: /opt/homebrew/opt/z3/lib/libz3.5.1.dylib
  Referenced from: .../Cellar/llvm/23.1.3_1/lib/libLLVM.23.1.dylib
  Reason: tried: '/opt/homebrew/opt/z3/lib/libz3.5.1.dylib' (no such file)
```
**根因**：Homebrew 的 `z3` 已升到 **5.3.0**（提供 `libz3.5.3.dylib`），而 `llvm 23.1.3_1`
是链在 `libz3.5.1.dylib` 上的 —— 升级把旧 soname 带走了。

**修法**（最小、可逆）：
```sh
ln -sfn libz3.5.3.dylib /opt/homebrew/opt/z3/lib/libz3.5.1.dylib
/opt/homebrew/opt/flang/bin/flang-new --version   # Homebrew flang version 23.1.3  RC=0
```
z3 的 C API 在 5.1→5.3 之间稳定，且 flang 正常编译路径并不调用 z3（LLVM 只把它用于
SMT 相关的可选 pass），所以这个兼容链接是安全的。
> ⚠️ 这是**环境级**改动（在 `~/octave-android` 之外）。若日后 `brew upgrade z3` 再次
> 换 soname，需要重建同名链接；长期正解是 `brew reinstall llvm` 让它链到当前 z3。

## 9.3 🔴 本轮最大的坑：**交叉构建会静默用宿主的 `ar`/`ranlib`**

**症状**：依赖"构建成功"（`make` 返回 0、日志里 configure 全绿），但产出的 `.a`
**只有 96 字节、0 个符号**；下游链接时报 `undefined symbol`。

**根因**：autoconf/libtool 若未显式给出 `AR`/`RANLIB`，会回落到**宿主的 Apple `ar`/`ranlib`**。
Apple 的 `ranlib` 拒绝 ELF 目标文件：
```
ranlib: warning: archive member 'libpcre2_8_la-pcre2_auto_possess.o' not a mach-o file
```
**但它仍然返回 0**，于是留下一个空归档，看起来完全成功。

**受害范围（本轮实测）**：`pcre2`、`zlib`、`glpk`、`qhull`、`fftw(3f)` —— 全部中招。
`libz.a` / `libglpk.a` / `libqhull_r.a` 三个都是 96 字节的空档。

**修法**：所有构建脚本显式导出 NDK 归档器（已写进 `scripts/build-deps.sh`、
`build_fftwf.sh`、`build_fftw.sh`）：
```sh
export AR="$NDK/.../llvm-ar" RANLIB="$NDK/.../llvm-ranlib" \
       STRIP="$NDK/.../llvm-strip" NM="$NDK/.../llvm-nm" LD="$NDK/.../ld.lld"
```
修复后：`libz.a` 100 个符号（含 `gzclearerr`/`uncompress`）、`libglpk.a` 1100 个（含 `glp_simplex`）、
`libqhull_r.a` 53 个、`libpcre2-8.a` 76 个。

## 9.4 纯 C 依赖交叉编译（本轮新增）

| 依赖 | 产物 | 校验 |
|---|---|---|
| **zlib 1.3.1** | `libz.a` 131 KB | 100 个 `T` 符号；`gzclearerr`/`uncompress` 在 |
| **PCRE2 10.44** | `libpcre2-8.a` 422 KB | 76 个 `T pcre2_*`；ELF64 AArch64 |
| **qhull 2020.2** | `libqhull_r.a` 35 KB | 53 个符号；**11 个头文件全拷**（`libqhull_r.h` 会 `#include user_r.h`） |
| **glpk 5.0** | `libglpk.a` 2.0 MB | 1100 个符号；`glp_simplex` 在 |
| **fast_float 6.1.6** | 头文件库 | 见 §9.5 |
| **FFTW3F**（单精度） | `libfftw3f.so` | 见 §9.6 |

### 踩坑记录（都很有价值）

1. **zlib：`make` 会连测试程序一起编**，而交叉链接下 `example`/`minigzip` 会失败。
   → 只 `make libz.a`，然后手工装 `libz.a` + `zlib.h`/`zconf.h`。
2. **PCRE2：不能逐个 `src/pcre2_*.c` 全编**。`pcre2_jit_match.c` / `pcre2_jit_misc.c` 是被
   `pcre2_jit_compile.c` `#include` 的，`pcre2_dftables.c` 是构建期工具。
   → 正确做法是**从 PCRE2 自己的 `Makefile` 里取 `COMMON_SOURCES` 列表**（27 个 .c + `pcre2_chartables.c`）。
3. **Octave 探的是 `-lpcre2`，不是 `-lpcre2-8`**：
   ```
   ld.lld: error: unable to find library -lpcre2
   ```
   → 同时提供 `libpcre2.a`（`libpcre2-8.a` 的副本）即可。
4. **FFTW 不支持 out-of-tree 构建**：
   `configure: error: source directory already configured; run "make distclean" there first`
   → 单精度那一遍必须用**独立解包的新源码树**。（另：fftw 的 tarball 在 `src/` 而不是
   `downloads/`，容易找错。）

## 9.5 fast_float：configure 的一个硬性前置

configure 走到 gnulib 检查后失败：
```
checking whether C++ STL supports std::from_chars for double precision floating-point... no
configure: error: If the C++ STL does not support std::from_chars for double precision
floating-point, the fast-float header-only library needs to be installed.
```
NDK r28 的 libc++ 尚未实现浮点 `std::from_chars`，Octave 因此要求 fast_float。
→ 取 `fastfloat/fast_float v6.1.6` 的头文件装到 `prefix/arm64-v8a/fastfloat/include/fast_float/`，
并加入 `CPPFLAGS`。

## 9.6 ⭐ **Octave 11.3.0 core 交叉 configure 通过（首次）**

**provenance 先对齐**：我们的 `octave-11.3.0.tar.xz` 的 sha256
`2b80f3149b2de6d1f4f2fcb4fe6515a17eb363b52111bf57b90f37bf6f5e12e1`
**与 Termux 配方 pin 的值完全一致**；Termux 的 `build.sh` 与其 3 个补丁都用 `gh api` 取回，
存在 `downloads/termux-octave-build.sh` 与 `downloads/termux-patches/`。

复现脚本 **`scripts/octave-configure.sh`**（自动打 3 个 Termux 补丁 + 全部 `ac_cv_*`）：

```
Octave is now configured for aarch64-unknown-linux-android
  Fortran compiler:  .../scripts/toolbin/aarch64-linux-android24-flang-new
  BLAS libraries:    -L.../openblas/lib -lopenblas
  LAPACK libraries:  -L.../openblas/lib -lopenblas
CONFIGURE_RC=0
```

**这是路线 B 的最后一个未知点被清掉**：Octave 本体在 bionic 上的 autoconf 交叉检测
（含 gnulib、Fortran f77 调用约定、C++17、`std::from_chars`/fast_float）全部走通。

**Termux 配方里固化的 bionic 答案（已采纳）**：
```
--without-x --disable-java --disable-openmp --enable-link-all-dependencies
--with-blas=openblas --enable-fortran-calling-convention=f2c
ac_cv_header_glob_h=no
ac_cv_func_{endpwent,getegrent,geteuid,getgrent,getgrgid,getgrnam,getpwent,
            getpwnam,getpwnam_r,getpwuid,setgrent,setpwent,setpwuid}=no
gl_cv_cc_visibility=no
```

### 当前 feature 状态（configure 汇总里仍缺的项）
`zlib` / `qhull` / `glpk` 已在本轮修好（重跑 configure 后应转为可用）；
`FFTW3F` 正在补（§9.4）。其余按计划关闭：`HDF5`、`CURL`、`SUNDIALS`、`SuiteSparse` 全家、
`Qt/FLTK/OpenGL/Freetype/fontconfig`、`readline`（`--disable-readline`）、`Java`、`OpenMP`。

> `--disable-readline` 是刻意的：交叉编译 readline 需要 ncurses/terminfo，
> 而 CLI 的 `--eval`/脚本执行路径不需要行编辑。

## 9.7 下一步（按优先级）

1. **重跑 `scripts/octave-configure.sh`** 收下本轮修好的 zlib/qhull/glpk/FFTW3F。
2. **`make -j12`** 跑 Octave 本体（`libcruft` 里的 Fortran 走 `FC=<flang wrapper>`；
   这是 flang 驱动第一次被真正的 autotools 大工程使用）。
3. 补 `SuiteSparse`（CXSparse/COLAMD 用 NDK 的 CMake toolchain file —— 直接 `make library`
   会让 CMake 用宿主的 `-arch x86_64`）、`bzip2`、`readline`。
4. Octave 自身的 `.so`（`liboctinterp` 等）会再次撞上
   **Termux flang 运行时不 PIC** 的问题（§3.5.2 卡点 d）→ 依赖 `-Wl,-Bsymbolic` 绕过；
   长期正解仍是自建 `-fPIC` 的 `flang-rt`（§6 #7）。

## 9.8 磁盘注意

本轮期间 `df -h ~` 可用量在 **9.1–14 GiB** 之间波动（其他 agent 的满核构建在抢）。
Octave 全量构建前务必确认可用空间。


## 10. 图标与本轮的诚实结论（2026-10-19）

**图标**：原来的 launcher 图标是手绘的矢量占位（两个方括号 + 一段波形），既不
是 Octave 的图标，也不像它启动的程序。现在改成 Octave 源码树里自带的原版
artwork（`etc/icons/octave-logo-512.png`），五种密度 + adaptive icon，背景色从
图像自身采样。

**结论必须说清楚**：这个 APK 仍然只是**数值内核的验证外壳**——一个
"Run native tests" 按钮，跑 OpenBLAS / FFTW / ARPACK / qrupdate 的门禁。
它**不是 Octave 应用**：没有解释器、没有命令行、没有 GUI，因此也谈不上
"打开和保存文件"。`prefix/arm64-v8a/` 里目前只有依赖库（openblas、fftw、
suitesparse、glpk、qhull、pcre2、zlib、iconv、fastfloat、flang-runtime），
Octave 本体尚未构建。

要把它变成真的 Octave，下一步按顺序是：
1. 完成 `octave-configure.sh` 之后的核心构建（`liboctave`、`liboctinterp`）；
2. 链接成一个可执行的 `octave`（或 `liboctave.so` + JNI），先做 `--eval`；
3. 再考虑 GUI（Qt）——那需要整套 Qt for Android，工作量和 FreeCAD 同级。

---

# 第 11 节：Octave 本体跑起来了（2026-10-19）

之前这份文档的结论是「只有一个数值内核验证外壳」。这一节把它推翻了：
`liboctave` / `liboctinterp` / `octave-cli` 全部交叉编译完成并安装到
`prefix/arm64-v8a/octave`，在真机上能算、能画、能跑脚本。

## 11.1 最后一道坎：`src/octave-cli` 的链接

`make` 一路编译到最后一个可执行文件才失败，报两类错：

```
ld.lld: error: non-exported symbol '__divsc3' in 'libclang_rt.builtins-aarch64-android.a(divsc3.c.o)'
          is referenced by DSO 'liboctave/.libs/liboctave.so'
ld.lld: error: undefined reference: clogf
```

两个原因互不相干：

1. **compiler-rt 的符号是 hidden**。`liboctave.so` / `liboctinterp.so` 调用
   `__divsc3`、`__powisf2`、`__powidf2` 和 `__aarch64_*` outline atomics，但这两个
   DSO 在链接时没有引入 builtins，定义只落到了可执行文件里，而且是 hidden —— lld
   拒绝用「不可导出」的定义去满足 DSO 的未定义引用。
   解法：把 `libclang_rt.builtins-aarch64-android.a` 拆开，
   `llvm-objcopy --set-symbol-visibility=<sym>=default` 重写这 8 个符号，
   重新打归档后链进可执行文件（`scripts/build-octave-cli.sh`）。
2. **bionic 的 libm 没有 C99 复数函数**。`clogf` 等由 Octave 自带的实现提供，
   已经编译在 `build/complexmath/*.o`（20 个目标文件），只是没被链进去。

补上这两样之后，**同一条 libtool 链接命令**直接成功（81048 字节）。
`make install` 必须带 `-o src/octave-cli`，否则它会重新链接、再次失败，
并把已经链接好的二进制删掉——这个坑踩过一次。

## 11.2 图形：gnuplot 6.0.0 + SVG

这个构建里没有 Qt、没有 FLTK（那需要一整套更大的工具链），所以
`plot(...)` 唯一的出路是 gnuplot toolkit。gnuplot 用 `--without-x --without-qt
--without-cairo --without-gd --without-pango --disable-plugins` 交叉编译，
SVG 终端是内置的，不需要任何图像库；App 把 SVG 交给 WebView 渲染。

gnuplot 需要一处源码修改（`patches/gnuplot-android.patch`）：
`src/plot.c:231` 有一句 `setuid(getuid())`，用来防止「被误装成 suid」。
Android 的 seccomp 对应用进程禁止 `setuid`，于是子进程直接死掉：

```
F libc : Fatal signal 31 (SIGSYS), code 1 (SYS_SECCOMP), syscall 146 in tid (libgnuplot.so)
```

（146 = `__NR_setuid`。）Octave 只会把它报成
`The gnuplot executable '...' was not found or does not work`，看起来像路径问题，
其实是信号。加 `!defined(__ANDROID__)` 之后 toolkit 正常初始化。

## 11.3 可执行文件为什么放进 jniLibs

Android 10 起 `execve` 在 `app_data_file` 上被拒绝。文件权限 0755 也没用：

```
BOOT FAILED: java.io.IOException: Cannot run program ".../files/oct/octave/bin/octave-cli":
  error=13, Permission denied
```

APK 的 native library 目录是允许执行的，所以 `octave-cli` 打包成
`lib/arm64-v8a/liboctavecli.so`，gnuplot 同理打包成 `libgnuplot.so`，
运行时用 `getApplicationInfo().nativeLibraryDir` 取路径执行。
`libc++_shared.so` 也放在那里——否则 gnuplot 作为独立进程找不到它：

```
CANNOT LINK EXECUTABLE ".../libgnuplot.so": library "libc++_shared.so" not found
```

`scripts/stage-apk-assets.sh` 负责把 prefix 里的安装树、库和执行文件摆到正确位置，
其中「libtool 生成的符号链接必须实体化」是必须的：Gradle 会静默丢掉 assets 里的
符号链接，`bin/octave-cli` 就这样消失过一次。

## 11.4 真机证据

在 App 私有目录里直接跑（`run-as`，与应用进程同一个 uid 和 SELinux 域）：

```
$ ./octave/bin/octave-cli --no-gui --quiet --eval 'disp(2+3)'
5
```

画图（同一环境下）：

```
$ ./octave/bin/octave-cli --no-gui --quiet --eval "graphics_toolkit('gnuplot'); \
    f=figure('visible','off'); plot([1 2 3 4],[1 4 9 16],'-o'); \
    print(f,'-dsvg','plot.svg'); disp('PLOT_OK')"
PLOT_OK
$ ls -la plot.svg
-rw-rw-rw- 1 u0_a434 u0_a434 10513 ... plot.svg
```

生成的图见 `evidence/plot-from-device.png`（由 gnuplot 的 SVG 渲染而来）。

App 界面里（`uiautomator dump` 抓到的 console 文本）：

```
octave:1> warning: using the gnuplot graphics toolkit is discouraged
...
octave:2> octave:3>
2+3
octave:4> ans = 5
```

也就是说提示符接受表达式、gnuplot toolkit 初始化成功。

## 11.5 APK

- 包名 `org.octave.android`，版本 0.2.0，41,626,956 字节，sha256 `0567cf76…`
- 图标是 Octave 源码树里的原版 artwork（`etc/icons/octave-logo-512.png`），
  五档密度 + adaptive；`aapt2 dump badging`：
  `application: label='Octave' icon='res/mipmap-anydpi-v26/ic_launcher.xml'`
- 界面：工具行（Open .m / Save / Save as / Run script / Self-test）、输出控制台、
  WebView 图形区、脚本编辑框、命令输入行
- 文件读写走 SAF（ACTION_OPEN_DOCUMENT / ACTION_CREATE_DOCUMENT），
  Octave 本身只认 POSIX 路径，所以由 Java 侧把内容读进编辑框、再写回同一个 URI

## 11.6 这个 ROM 上 documentsui 是个壳

`com.android.documentsui` 虽然装着（有 `picker.PickActivity`），但实际
`ACTION_OPEN_DOCUMENT` 被 `com.android.filemanager/.selector.view.SelectorHomeActivity`
接管——即使用 `-p com.android.documentsui` 显式指定，前台落到的仍是 vivo 的文件管理器。
所以「`pidof com.android.documentsui` 非空」在这台机器上永远不成立；
真正的系统选择器在跑，只是包名不同。`uiautomator`/`dumpsys` 抓到的前台 Activity
与 pid 是可复现的证据。App 里仍然优先 pin 标准 documentsui（装了才 pin），
在没有被改写的 ROM 上就是 AOSP 选择器。

## 11.7 还没做完

- **SAF round-trip 没有在真机上完成**：需要打开 Downloads 里的 `.m`、改一行、
  存回同一个 URI，再用 `adb shell cat` 确认磁盘内容变了。设备在验证途中掉线
  （`192.168.0.108:42513` 不再响应，本机已换到 192.168.5.x 网段），
  这一步只能等设备回来再补。
- vivo 的媒体选择器对 `*/*` 只列图片/文件夹，`.m` 是否出现在「文档」视图里
  还没确认；如果不行，需要按 MIME 打开或者改用 ACTION_GET_CONTENT + 自定义 MIME。
- 新的 APK 里 Self-test（LAPACK/FFTW/ARPACK 门禁）还没重跑一遍。

## 11.8 发布

- APK：`Octave-0.2.0-android-arm64.apk`（41,626,956 字节，sha256 `0567cf76…`）
- Release：https://github.com/tzhazuma/octave-android/releases/tag/v0.2.0
- 仓库提交：`057b3fd`（解释器 + 绘图 + 控制台），`ca6f305`（APK 不入库）
- Release 资产只放 APK，不进 git（`.gitignore` 里加了 `*.apk`）

## 11.9 第二次真机窗口（2026-10-19 12:18）

设备以 `192.168.0.108:5555`（标准端口）重新上线，已装的就是发布版 0.2.0。
再次确认：

- App 启动后 console 出现 `octave:1>`，gnuplot toolkit 正常初始化
  （只剩 "using the gnuplot graphics toolkit is discouraged" 的提示）
- `uiautomator dump` 里能读到完整 console 文本

但 13:00 左右设备进入锁屏且启用了安全锁：

- `dumpsys window policy` → `showing=true`（KeyguardStateMonitor）
- `screencap` 全黑（这台 ROM 在锁屏下屏蔽截屏），`input` 事件被拦截
- `wm dismiss-keyguard` 无效，说明不是 swipe-only 锁

为了继续自动化，我在设备上执行过下面两条（**需要还原**）：

```
adb shell svc power stayon true
adb shell settings put system screen_off_timeout 1800000
adb shell locksettings set-disabled true      # ← 这条要还原
```

`locksettings set-disabled true` 只是「禁用锁屏界面」，不改变用户凭证；设备回来后执行
`adb shell locksettings set-disabled false` 即可恢复原状。

15:12 设备再次掉线（本机网段已变成 10.20.162.104/21，手机不在同一网段，
mDNS 也发现不到），因此这两项**仍未验证**：

1. SAF round-trip：打开 `/sdcard/Download/octtest.m`（设备上已有，28 字节）、
   改一行、Save 回同一 URI，再 `adb shell cat` 确认磁盘内容变化
2. Self-test（LAPACK / FFTW / ARPACK 门禁）在 0.2.0 上重跑

设备回来后按这个顺序补：解锁 → `adb connect <ip>:5555` → 装/确认 0.2.0 →
点 Self-test → 点 Open .m → 选 Downloads/octtest.m → 编辑一行 → Save →
`adb shell cat /sdcard/Download/octtest.m` → 点 Run script。

## 13. Octave GUI（octave-gui）能不能移植？—— 已实测到具体卡点

不是猜的，是真跑了一遍：

**configure 通过**（`CONFIGURE_RC=0`，`logs/gui-configure.log`）：Qt 依赖齐全，
警告只有 Qhull / BZIP2 / gl2ps / CAMD / KLU / SUNDIALS 这些可选库缺失，
属于功能裁剪，不阻塞构建。

**make 在 OpenGL 处断掉**（`logs/gui-make.log`，`MAKE_RC=2`）：

```
libgui/graphics/gl-select.cc:89:12: error: no member named 'glSelectBuffer' in 'octave::opengl_functions'
libgui/graphics/gl-select.cc:90:12: error: no member named 'glRenderMode' in 'octave::opengl_functions'
20 errors generated.
```

根因很明确：**Android 只有 OpenGL ES，没有桌面 GL 的 selection buffer**
（`glSelectBuffer` / `glRenderMode` 是固定管线的老 API，GLES 里根本不存在）。
Octave 的绘图控件用 GL selection 做「点选图元」，所以缺这两个符号。

两条可行路线（和 FreeCAD 遇到的是同一类问题）：

1. **gl4es**（FreeCAD 已经用这条路跑通了）：提供一个桌面 GL 的子集实现，
   把这 195 个桌面专用入口补齐，gl-select.cc 原样编译。
2. **改 CPU 拾取**：把 `gl-select.cc` 的 GL selection 换成把图元投影到屏幕坐标后
   自己算最近命中（Qt 新版本本身就是这么做的）。改动集中在一个文件，但需要理解
   Octave 的 graphics 对象模型。

结论：**GUI 可移植，卡点是 OpenGL ES 缺 selection API，不是 Qt 或平台能力不足。**
现有移植用的是自定义 Android 界面（控制台 + WebView 出图），功能上够用，
但和上游 `octave-gui` 不是同一个 UI。

## 2026-10-22：Octave GUI 在 Android 上编译链接通过（gl4es 路线）

之前 `libgui/graphics/gl-select.cc` 有 20 个错，根因是 Android 只有 GLES，没有桌面 GL 的
`glSelectBuffer` / `glRenderMode`。这一轮把它解决了：

1. **gl4es**（ptitSeb/gl4es）交叉编译成 `libGL.so.1`，导出 1223 个桌面 GL 符号，
   其中就有缺的那四个：`glSelectBuffer`、`glRenderMode`、`glLoadName`、`glPushName`。
2. configure 原本写的是 `--without-opengl` —— 这就是 `HAVE_OPENGL` 没定义、
   整个桌面 GL 分支被 `#if defined (HAVE_OPENGL)` 跳过的直接原因。
   改成 `--with-opengl`，并把 gl4es 的 include/lib 加进 CPPFLAGS/LDFLAGS：
   ```
   config.h: #define HAVE_GL_GL_H 1
             #define HAVE_OPENGL 1
   OPENGL_LIBS='-lGL -lGLU'
   ```
3. 两个后续坑：
   - gl4es 的 `glext.h` 里 `glShaderSource` 写作 `const GLchar* *`，而 Qt 的 GLES 头是
     `const GLchar* const *` —— 类型冲突。把 gl4es 那份改成 `const GLchar* const *`（语义相同）。
   - Octave 要 `-lGLU`，但 gl4es 不含 GLU，独立 GLU 项目（mesa3d/glu）已不存在。
     先放一个可安全降级的占位实现（`src/glu-stub/glu_stub.c`），只影响 gl2ps 的
     PS/PDF 多边形导出，不影响界面与屏上绘图；真正的镶嵌器（libtess2 已 clone）是后续工作。
4. 链接时 `ld.lld` 还挑剔 DSO 引用 libclang_rt.builtins 里非导出的原子符号，
   加 `-Wl,--allow-shlib-undefined` 通过。

**结果**（不是「应该能编」）：

```
libgui/.libs/liboctgui.so : ELF 64-bit LSB shared object, ARM aarch64     4.6 MB
NEEDED: liboctinterp.so liboctave.so libQt6Core/Gui/Widgets/Network_arm64-v8a.so
undefined (留给 gl4es 在运行期提供): glRenderMode, glSelectBuffer
```

即：GUI 那 4.6 MB 的库真的链出来了，selection 系列按设计留成未定义符号，
由 `libGL.so`（gl4es）在运行时满足。剩下的是把 gl4es + Qt 一起部署到设备上启动。

## 2026-10-22 (2)：Octave GUI 上线到真机的完整配方（已探明，待执行）

`liboctgui.so` 已经能编出来了，但「把 GUI 跑起来」不是把库塞进现有 APK 就行 —— 它需要
Qt for Android 的**进程内**初始化，而不是 exec 一个可执行文件。

FreeCAD 已经在同一台设备上跑通了 Qt，它的做法就是模板（`~/freecad-android`）：

1. **Activity 继承 Qt 的类**，而不是自己写：
   `public class MainActivity extends org.qtproject.qt.android.bindings.QtActivity`
   这个类来自 Qt 的 Android jar（Qt 6.8.3 kit 的 `jar/` 目录）。
2. **manifest 里声明 lib_name**：
   ```xml
   <meta-data android:name="android.app.lib_name" android:value="OctaveGui" />
   ```
   QtLoader 会把它拼成 `<value>_<abi>` → `OctaveGui_arm64-v8a` → `libOctaveGui_arm64-v8a.so`，
   并**在该库里找 `main()`**；Qt 会在调用它之前把 JNI/Android 环境准备好。
3. 因此 octave-gui 必须**编译成共享库并导出 main()**，而不是现在的可执行文件。
   （现有 `src/.libs/octave-gui` 是普通 ELF 可执行文件，需要加 `-shared -Wl,-e,main`
   或者用 Qt 的 `androiddeployqt` 方式重链接。）
4. `jniLibs/arm64-v8a/` 里要放：Qt6 Core/Gui/Widgets/Network/OpenGL/OpenGLWidgets、
   Qt 的 `libplugins_platforms_qtforandroid_arm64-v8a.so`（以及 imageformats/debug 插件）、
   gl4es 的 `libGL.so` + `libGLU.so`、`liboctgui.so` / `liboctinterp.so` / `liboctave.so` / `liboctmex.so`。
5. `useLegacyPackaging = true`（FreeCAD 的 build.gradle 就是这么设的），否则 native 库不解压。
6. 资源：现有的 `assets/oct`（75 MB，Octave 的 m 文件）继续用，另加 Qt 的 plugins 目录。

规模估算：库约 80 MB（Qt 22 + octave 49 + gl4es 5）+ 数据 75 MB ≈ 150 MB APK，
和 FreeCAD（406 MB）比是小量级。

**所以 Octave GUI 的剩余工作不是「能不能编」（已解决），而是这一步 Qt 打包集成** ——
路线清楚、没有未知数，属于机械执行。

## 2026-10-22 (3)：Octave GUI 的 APK 已能加载到最后一关

按 FreeCAD 的 Qt 配方做出了 `android-gui-app`（133 MB），QtLoader 能起、能找到 `main`、
`libGL.so` 也能解析了。逐层踩过的坑：

1. **`libpython3.11.so` 找不到** —— `res/values/libs.xml` 是 FreeCAD 的库清单，
   还带着 python 和一堆 TK* 条目。改写成 Octave 自己的（Qt 库 + oct* + GL/GLU + fftw/openblas）。
2. **`library "libGL.so.1" not found`** —— gl4es 的 `src/CMakeLists.txt` 里有一行
   `set_target_properties(GL PROPERTIES SUFFIX ".so.1")`，产出的文件名和 SONAME 都是
   `libGL.so.1`；而 Android 的打包器只解压 `lib*.so`，`.so.1` 根本不会被解出来。
   把那行改成 `.so` 重建，SONAME 变成 `libGL.so`，再强制重链 octave 的三个库，
   它们的 NEEDED 也跟着变成 `libGL.so`。
3. **`cannot locate symbol "__aarch64_ldadd4_acq_rel"`** —— clang 的 outline-atomics
   把原子操作编译成对编译器运行时辅助函数的调用，而这些符号在
   `libclang_rt.builtins`（静态库）里且不导出。写了 `src/atomic-shim/atomic_shim.c`
   提供 20 个 `__aarch64_ldadd/cas/swp` 符号（各自用 `__atomic_*` 内建实现，
   并用 `-mno-outline-atomics` 编译避免递归）。
   **这一步还没完全解决**：通过 `qt_libs` 预加载不够（符号没有全局可见），
   正解是让 liboctgui/liboctinterp/liboctave 在链接时**直接依赖** shim，
   或者干脆用 `-mno-outline-atomics` 全量重编（更慢但更干净）。

**当前状态**：GUI 的 APK 能装、Qt 能起、库能加载，卡在原子符号解析这一关。
编译/链接/打包/清单都已就绪，剩下的是原子符号这一个链接细节。

## 2026-10-22 (4)：原子符号这一关的进展与结论

上一轮卡在 `__aarch64_ldadd4_acq_rel`，这一轮把它推到了很后面：

1. `liboctave.so` 已被我上一轮误删，用 `make -n` 取出的 libtool 命令手工重建成功（22.4 MB）。
2. 手写 shim（`src/atomic-shim/atomic_shim.c`）从 20 个符号扩到 **48 个**
   （ldadd/cas/swp × 1/2/4/8 字节 × relax/acq/rel/acq_rel 四种内存序），
   再补上 `__powisf2` / `__powidf2`。
3. 让三个库（liboctave / liboctinterp / liboctgui）在链接时**直接依赖** shim
   （`-latomic-shim`），验证 `NEEDED` 里确实出现了 `libatomic-shim.so`。
   这一步真的生效了 —— 错误从 `__aarch64_ldadd4_acq_rel` 一路推进到 `__powisf2`、
   再到 `__divsc3`。

**结论：这是「补一个冒一个」的模式，不该继续逐个补。** 这些符号全部来自
`libclang_rt.builtins`，本该由 clang 在链接每个 DSO 时自动带进去；现在它们
「被引用但未定义」，说明 **libtool 的链接路径把 builtins 归档丢掉了**。

试过但没成功的两条：
- `-Wl,--whole-archive,<rt>,--no-whole-archive` 传给 libtool → 符号仍未定义
- 直接把 `.a` 路径放在命令行 → libtool 把它当**依赖**而不是静态链接，只报
  `warning: Linking the shared library against the static library ... is not portable!`

**正解（下一轮执行）**：绕开 libtool，用**直接 clang++ 链接**这三个库
（`libOctaveGui` 就是这么链的，所以它没有这个问题）。命令模板已经有了 ——
`/tmp/gui-shared-link.sh` 就是把 libtool 行转成直接 clang++ 的脚本，同样的转换
对三个库各做一次即可；clang 会自动把自己的 builtins 归档带进来，48 个 shim 符号
和 `__divsc3` 这类就一起消失了。

**当前真机状态**：APK 能装、Qt 能起、Qt/Octave/GL 库都能加载，
卡在 liboctave.so 的 `__divsc3`。
