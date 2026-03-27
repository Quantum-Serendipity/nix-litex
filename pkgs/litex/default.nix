pkgMeta:
{ lib
, writeText
, buildPythonPackage
, fetchpatch
, pythondata-software-compiler_rt
, pythondata-software-picolibc
, pythondata-cpu-vexriscv
, pythondata-cpu-vexriscv_smp
, pythondata-cpu-serv
, pythondata-misc-tapcfg
, pyserial
, migen
, requests
, packaging
, colorama
, litedram
, liteeth
, liteiclink
, litescope
, pytest
, pexpect
, meson
, ninja
, pkgsCross
, verilator
, libevent
, json_c
, zlib
, zeromq
}:

buildPythonPackage rec {
  pname = "litex";
  version = pkgMeta.git_revision;

  src = builtins.fetchGit {
    url = "https://github.com/${pkgMeta.github_user}/${pkgMeta.github_repo}";
    rev = pkgMeta.git_revision;
  };

  postPatch = ''
    # Fix JTAGPHY count comparison regression (LiteX commits 2eef758..4a086cc, Feb 2026):
    # Signal(max=data_width) holds values 0..data_width-1, so count == data_width is
    # always false, preventing the XFER-DATA FSM state from transitioning. This causes
    # Vivado to optimize away the count register, breaking all JTAG communication.
    substituteInPlace litex/soc/cores/jtag.py \
      --replace-fail \
        'If(count == data_width,' \
        'If(count == (data_width - 1),'

    # Fix picolibc copy from read-only nix store: cp -a preserves permissions, so the
    # copied tree remains read-only and subsequent builds fail. Make writable after copy.
    substituteInPlace litex/soc/software/libc/Makefile \
      --replace-fail \
        'cp -a $(PICOLIBC_DIRECTORY) $(BUILDINC_DIRECTORY)/../picolibc_src' \
        'cp -a $(PICOLIBC_DIRECTORY) $(BUILDINC_DIRECTORY)/../picolibc_src && chmod -R u+w $(BUILDINC_DIRECTORY)/../picolibc_src'
  '';

  propagatedBuildInputs = [
    # LLVM's compiler-rt data downloaded and importable as a python
    # package
    pythondata-software-compiler_rt

    # libc for the LiteX BIOS
    pythondata-software-picolibc

    # BIOS build tools. Must be propagated because LiteX will require
    # them to be in PATH when building any SoC with BIOS.
    meson
    ninja

    pyserial
    migen
    requests
    packaging
    colorama
  ];

  checkInputs = [
    litedram
    liteeth
    liteiclink
    litescope
    pythondata-cpu-vexriscv
    pythondata-cpu-vexriscv_smp
    pythondata-cpu-serv
    pythondata-misc-tapcfg
    pkgsCross.riscv64-embedded.buildPackages.gcc
    pexpect
    pytest

    # For Verilator simulation
    verilator
    libevent
    json_c
    zlib
    zeromq
  ];

  checkPhase = ''
    # The tests will try to execute the litex_sim command, which is
    # installed as part of this package. While $out is already added
    # to PYTHONPATH here, it isn't yet added to PATH.
    export PATH="$out/bin:$PATH"

    # This needs to be exported manually because checkInputs doesn't
    # propagate to these variables
    export NIX_CFLAGS_COMPILE=" \
      -isystem ${libevent.dev}/include \
      -isystem ${json_c.dev}/include \
      -isystem ${zlib.dev}/include \
      -isystem ${zeromq}/include \
      $NIX_CFLAGS_COMPILE"
    export NIX_LDFLAGS=" \
      -L${libevent}/lib \
      -L${json_c}/lib \
      -L${zlib}/lib \
      -L${zeromq}/lib \
      $NIX_LDFLAGS"

    # Only test CPU variants we actually package and want to support
    # as part of this repository. Others are disabled by the following
    # patch:
    patch -p1 < ${writeText "disable-litex-test-cpus.patch" (
      builtins.readFile ./0001-Disable-LiteX-CPU-tests-for-select-CPUs.patch)}

    pytest -v test/
  '';

  doCheck = true;
}
