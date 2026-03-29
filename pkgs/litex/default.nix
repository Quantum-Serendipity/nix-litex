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

    # Fix JTAGPHY bugs from PR #2410 (enjoy-digital/litex#2410).
    # PR #2410 restructured JTAGPHY to fix TDO pipeline timing, but introduced
    # three bugs:
    #
    # Bug 1: Signal(max=data_width) comparison.
    # Signal(max=N) creates a register that holds 0..N-1. For data_width=8,
    # count is 3 bits (0-7), so "count == data_width" (== 8) is unreachable.
    # Vivado optimizes the counter away, collapsing the FSM.
    # Fix: compare against data_width - 1.
    substituteInPlace litex/soc/cores/jtag.py \
      --replace-fail \
        'If(count == data_width,' \
        'If(count == (data_width - 1),'

    # Bug 2 & 3: Missing sync/comb logic after FSM.
    # PR #2410 moved ready/rx_valid/rx_data updates outside the FSM (to survive
    # FSM resets via ResetInserter), declared update_ready/update_rx trigger
    # signals and set them in the FSM, but never added the actual sync.jtag
    # logic to act on those triggers. Result: ready is permanently 0 (host
    # thinks FIFO is full), and received data is never written to the CDC FIFO.
    # Fix: add the missing self.sync.jtag and self.comb assignments.
    python3 -c "
import pathlib
p = pathlib.Path('litex/soc/cores/jtag.py')
src = p.read_text()
marker = '        )\n\n# ECP5 JTAG PHY'
I = '        '
lines = [
    '',
    I + '# RX path - connect to CDC FIFO write side.',
    I + 'self.comb += [',
    I + '    source.valid.eq(rx_valid),',
    I + '    source.data.eq(rx_data),',
    I + ']',
    '',
    I + '# Update ready from FIFO writable (outside FSM, survives resets).',
    I + 'self.sync.jtag += If(update_ready, ready.eq(source.ready))',
    '',
    I + '# Update RX registers (outside FSM, survives resets).',
    I + '# Clear rx_valid after FIFO accepts the data to prevent duplicates.',
    I + 'self.sync.jtag += [',
    I + '    If(update_rx,',
    I + '        rx_valid.eq(rx_valid_in),',
    I + '        rx_data.eq(data),',
    I + '    ).Elif(source.valid & source.ready,',
    I + '        rx_valid.eq(0),',
    I + '    )',
    I + ']',
    '',
]
insert = '\n'.join(lines) + '\n'
assert marker in src, 'Marker not found in jtag.py'
src = src.replace(marker, insert + '# ECP5 JTAG PHY')
p.write_text(src)
print('JTAGPHY: added missing sync/comb logic after FSM')
    "
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
