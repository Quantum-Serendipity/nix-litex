# nix-litex

Nix flake providing package definitions for the [LiteX](https://github.com/enjoy-digital/litex) FPGA SoC builder ecosystem.

This is an actively maintained fork of the original
[nix-litex](https://github.com/lschuermann/nix-litex) by Leon Schuermann,
which is no longer maintained. Packages have been updated to current upstream
revisions, new packages have been added, and the build infrastructure has been converted to a Nix flake.

## Warning

This is the first thing I have attempted to package for Nix, and is the result of taking "hacked together garbage that finally managed to work" and converting it into a usable package which can be published and used by others.  I have attempted to test this to the best of my [limited] Nix ability and It Works On My Machine™ but if I'm doing something wrong or it doesn't work for you please let me know and I'll try to fix it.  This package is being used by an openxc7 package I am currently working on upgrading to current versions as well so that it can all be used for litex FOSS SOC generation, and that package will be used to create an upstream PR for the litex m2 sdr project providing it with an alternative bitstream synthesis toolchain utilizing only FOSS tools and removing the tempermental Vivado requirement.

## Usage

This flake is designed to be consumed as an input by your own project flake. It provides **overlays** that add all LiteX packages to your nixpkgs Python
package set.

### Adding to your flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-litex = {
      url = "github:Quantum-Serendipity/nix-litex";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-litex }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          nix-litex.overlays.default
        ];
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs.python3Packages; [
          litex
          litex-boards
          litedram
          liteeth
          # ... add whichever LiteX packages you need
        ];
      };
    };
}
```

After applying the overlay, all LiteX packages are available under
`pkgs.python3Packages` just like any other nixpkgs Python package.

### Available overlays

| Overlay | Description |
|---------|-------------|
| `overlays.default` | Adds all LiteX packages to `python3Packages` (recommended) |
| `overlays.python` | Python-only overlay for use with `python3.override { packageOverrides = ...; }` |

### Included packages

**Core:**
litex, litex-boards

**Peripherals:**
litedram, liteeth, litehyperbus, liteiclink, litepcie, litescope, litesdcard,
litespi, litevideo, litesata, litejesd204b, litei2c

**USB:**
valentyusb (hw_cdc_eptri)

**CPU cores:**
pythondata-cpu-vexriscv, pythondata-cpu-vexriscv\_smp, pythondata-cpu-serv,
pythondata-cpu-lm32, pythondata-cpu-mor1kx, pythondata-cpu-minerva,
pythondata-cpu-naxriscv, pythondata-cpu-sentinel, pythondata-cpu-vexiiriscv

**Support data:**
pythondata-misc-tapcfg, pythondata-misc-usb\_ohci,
pythondata-software-compiler\_rt, pythondata-software-picolibc

## Requirements

- Nix >= 2.4 with flakes enabled

## Updating packages

Package versions are pinned in `pkgs/litex_packages.toml`. The maintenance
scripts in `maintenance/` can be used to update all packages to the latest
upstream revisions:

```bash
nix-shell -p python3Packages.toml python3Packages.gitpython --run \
  "python maintenance/update_packages.py pkgs/litex_packages.toml"
```

## Contributors

- Leon Schuermann (original author)
- Las Safin
- Colin Rushton (current maintainer)

## License

The code contained in this repository is licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
  http://www.apache.org/licenses/LICENSE-2.0)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or
  http://opensource.org/licenses/MIT)

at your option.

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall be
dual licensed as above, without any additional terms or conditions.

This license does not necessarily apply to the packages built using this build
infrastructure. It might also not apply to patches included in this repository,
which may be derivative works of the packages to which they apply. The
aforementioned artifacts are all covered by the licenses of the respective
packages.
