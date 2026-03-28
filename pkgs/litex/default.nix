pkgMeta:
{ lib
, buildPythonPackage
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
    # Fix nix store read-only permissions: files copied from the store retain their
    # read-only bits, breaking both picolibc.h generation (append fails) and picolibc
    # source builds (write fails). Make writable after each copy.
    substituteInPlace litex/soc/software/libc/Makefile \
      --replace-fail \
        'cp -a $(PICOLIBC_DIRECTORY) $(BUILDINC_DIRECTORY)/../picolibc_src' \
        'cp -a $(PICOLIBC_DIRECTORY) $(BUILDINC_DIRECTORY)/../picolibc_src && chmod -R u+w $(BUILDINC_DIRECTORY)/../picolibc_src' \
      --replace-fail \
        'cp $< $@' \
        'cp $< $@ && chmod u+w $@'

    # Fix JTAGPHY Signal width bug from PR #2410.
    # Signal(max=data_width) creates a (data_width-1).bit_length()-bit register
    # that can hold values 0..(data_width-1). For data_width=8 (default),
    # this is a 3-bit signal (0-7), so "count == data_width" (== 8) is
    # unreachable. Vivado optimizes the counter away, collapsing the FSM.
    # Fix: compare against data_width - 1.
    substituteInPlace litex/soc/cores/jtag.py \
      --replace-fail \
        'If(count == data_width,' \
        'If(count == (data_width - 1),'
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

    # Skip CPU integration tests for CPUs not packaged in this repo
    pytest -v test/ -k "not (femtorv or firev or marocchino or neorv32 or ibex or cv32e40p)"
  '';

  doCheck = true;
}
