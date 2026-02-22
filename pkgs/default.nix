let
  # Use builtins.fromTOML if available, otherwise use remarshal to
  # generate JSON which can be read. Code taken from
  # nixpkgs/pkgs/development/tools/poetry2nix/poetry2nix/lib.nix.
  fromTOML = pkgs: builtins.fromTOML or (
    toml: builtins.fromJSON (
      builtins.readFile (
        pkgs.runCommand "from-toml"
          {
            inherit toml;
            allowSubstitutes = false;
            preferLocalBuild = true;
          }
          ''
            ${pkgs.remarshal}/bin/remarshal \
              -if toml \
              -i <(echo "$toml") \
              -of json \
              -o $out
          ''
      )
    )
  );

  # Pin a Nixpkgs revision to source the `sbt` package and JRE from,
  # in order to build softcores written in Scala DSLs (e.g. VexRiscv).
  # We use `mkSbtDerivation`, which produces a fixed output hash
  # derivation of all package dependencies before building the actual
  # package. However, this intermediate dependency derivation seem to
  # be dependent on the used Nixpkgs from which sbt, the JRE and all
  # other packages for the sbt build is taken. Hence, we pin a version
  # here (preferably from the current Nixpkgs release). It can be
  # overriden by passing the `sbtNixpkgs` argument.
  sbtPinnedNixpkgsSrc = builtins.fetchTarball {
    # Descriptive name to make the store path easier to identify
    name = "nixos-22.05-2022-08-06";
    # Commit hash for nixos-22.05 as of 2022-08-06
    url = "https://github.com/nixos/nixpkgs/archive/72f492e275fc29d44b3a4daf952fbeffc4aed5b8.tar.gz";
    # Hash obtained using `nix-prefetch-url --unpack <url>`
    sha256 = "1n06bz81x5ij3if032w4hggq13mgsqly3bn54809szajxnazfm0v";
  };
in

# pkgMetas: Metadata for the packages such that you can control which revisions
  # are used. If not specified, the versions will be taken from
  # `litex_packages.toml`.
{ pkgs
, skipChecks ? false
, pkgMetas ? fromTOML pkgs (builtins.readFile ./litex_packages.toml)
, sbtNixpkgs ? import sbtPinnedNixpkgsSrc { system = pkgs.stdenv.hostPlatform.system; }
}:

let
  lib = pkgs.lib;

  unchecked = drv: drv.overrideAttrs (_: {
    doCheck = false;
  });

  testedPkgs = [
    {
      name = "litex";
      path = ./litex;
    }
    "litedram"
    "litex-boards"
    "liteeth"
    "litedram"
    "litehyperbus"
    "liteiclink"
    "litepcie"
    "litescope"
    "litesdcard"
    "litespi"
    "litevideo"
    "litesata"
    "litejesd204b"
    {
      name = "litei2c";
      path = ./litei2c.nix;
    }
    {
      name = "valentyusb-hw_cdc_eptri";
      path = ./valentyusb/valentyusb-hw_cdc_eptri.nix;
    }
  ];

  testedPkgsNames =
    builtins.map (pkg: if (lib.isString pkg) then pkg else pkg.name) testedPkgs;

  testedPkgsPaths =
    builtins.listToAttrs (
      builtins.map
        (pkg:
          if (lib.isString pkg)
          then (lib.nameValuePair pkg (./. + "/${pkg}.nix"))
          else (lib.nameValuePair pkg.name pkg.path))
        testedPkgs);

  # Make an unchecked package
  makeUnchecked = self: name:
    let
      f = import testedPkgsPaths."${name}" pkgMetas.${name};
      argNames = lib.intersectLists testedPkgsNames (builtins.attrNames (lib.functionArgs f));
      args = builtins.foldl' (acc: name: acc // { ${name} = self.${"${name}-unchecked"}; }) { } argNames;
      maker = attrs: self.buildPythonPackage (attrs // {
        pname = "${attrs.pname}-pkg";
        doCheck = false;
        format = attrs.format or "setuptools";
        passthru._base_name = attrs.pname;
        passthru._src = attrs.src;
      });
    in
    self.callPackage f (args // { buildPythonPackage = maker; });

  # Make a test for the package
  makeTest = self: name:
    let
      f = import testedPkgsPaths."${name}" pkgMetas.${name};
      argNames = lib.intersectLists testedPkgsNames (builtins.attrNames (lib.functionArgs f));
      args = builtins.foldl' (acc: name: acc // { ${name} = self.${"${name}-unchecked"}; }) { } argNames;
      maker = attrs: self.buildPythonPackage (attrs // {
        pname = "${attrs.pname}-${if attrs.doCheck then "test" else "untested" }";
        format = attrs.format or "setuptools";

        # It's important that we don't provide any packages as part of this
        # derivation's output to avoid errors such as the following:
        #
        #    Package duplicates found in closure, see above. Usually this
        #    happens if two packages depend on different version of the same
        #    dependency.
        #
        # However, we can't simply replace the installPhase by something else,
        # because the checkPhase in buildPythonPackage is actually corresponding
        # to the installCheckPhase of stdenv.mkDerivation.
        #
        # Thus our workaround here is to delete all contents of $out in the
        # postCheck hook. Because that will be executed after the installPhase
        # and checkPhase, the tests will have already run. However, the $out
        # directory is still mutable.
        postCheck = ''
          rm -rf "$out"
          mkdir -p "$out"
        '';

        # Technically at build time this will have both the -pkg and the here
        # built test derivation present, which both provide the respective
        # Python package. This skips this check. All proper conflicts should be
        # found at build time of the -pkg derivation, whose result this just
        # reexposes.
        pythonCatchConflictsPhase = "true";
      });
    in
    self.callPackage f (args // { buildPythonPackage = maker; });

  # Forward the unchecked package but depend on tests
  makeFinal = self: name:
    let
      f = import testedPkgsPaths."${name}" pkgMetas.${name};
      argNames = lib.intersectLists testedPkgsNames (builtins.attrNames (lib.functionArgs f));
      pkg = self.${"${name}-unchecked"};
      passthru = [ "meta" ];
      args = {
        pname = pkg._base_name;
        inherit (pkg) version;
        format = "other";

        src = pkg._src;

        nativeBuildInputs =
          if skipChecks
          then [ ]
          else builtins.foldl' (acc: name: acc ++ [ self.${"${name}-test"} ]) [ self.${"${name}-test"} ] argNames;

        # Technically at build time this will have both the -pkg and -test
        # derivation present, which both provide the respective Python
        # package. This skips this check. All proper conflicts should be found
        # at build time of the -pkg derivation, whose result this just
        # reexposes.
        pythonCatchConflictsPhase = "true";

        unpackPhase = "true";
        patchPhase = "true";
        configurePhase = "true";
        buildPhase = "true";

        installPhase = ''
          ln -s ${pkg} $out
          runHook postInstall
        '';

        fixupPhase = "true";
        setupToolsCheckPhase = "true";

        doCheck = false;
      };
    in
    self.buildPythonPackage (
      builtins.foldl'
        (acc: elem: acc // (if pkg ? ${elem} then { ${elem} = pkg.${elem}; } else { }))
        args
        passthru
    );

  # Overlay for python packages.
  pythonOverlay = self: super:
    builtins.foldl'
      (acc: name: acc // {
        "${name}-unchecked" = makeUnchecked self name;
        "${name}-test" = makeTest self name;
        "${name}" = makeFinal self name;
      })
      { }
      testedPkgsNames
    // {
      pythondata-cpu-vexriscv =
        self.callPackage (import ./pythondata-cpu-vexriscv pkgMetas.pythondata-cpu-vexriscv) { };
      pythondata-cpu-vexriscv_smp =
        self.callPackage (import ./pythondata-cpu-vexriscv_smp pkgMetas.pythondata-cpu-vexriscv_smp) { };
      pythondata-misc-tapcfg =
        self.callPackage (import ./pythondata-misc-tapcfg.nix pkgMetas.pythondata-misc-tapcfg) { };
      pythondata-software-compiler_rt =
        self.callPackage (import ./pythondata-software-compiler_rt.nix pkgMetas.pythondata-software-compiler_rt) { };
      pythondata-cpu-serv =
        self.callPackage (import ./pythondata-cpu-serv.nix pkgMetas.pythondata-cpu-serv) { };
      pythondata-software-picolibc =
        self.callPackage (import ./pythondata-software-picolibc.nix pkgMetas.pythondata-software-picolibc) { };
      pythondata-cpu-lm32 =
        self.callPackage (import ./pythondata-cpu-lm32.nix pkgMetas.pythondata-cpu-lm32) { };
      pythondata-cpu-mor1kx =
        self.callPackage (import ./pythondata-cpu-mor1kx.nix pkgMetas.pythondata-cpu-mor1kx) { };
      pythondata-cpu-minerva =
        self.callPackage (import ./pythondata-cpu-minerva.nix pkgMetas.pythondata-cpu-minerva) { };
      pythondata-cpu-naxriscv =
        self.callPackage (import ./pythondata-cpu-naxriscv.nix pkgMetas.pythondata-cpu-naxriscv) { };
      pythondata-cpu-sentinel =
        self.callPackage (import ./pythondata-cpu-sentinel.nix pkgMetas.pythondata-cpu-sentinel) { };
      pythondata-cpu-vexiiriscv =
        self.callPackage (import ./pythondata-cpu-vexiiriscv.nix pkgMetas.pythondata-cpu-vexiiriscv) { };
      pythondata-misc-usb_ohci =
        self.callPackage (import ./pythondata-misc-usb_ohci.nix pkgMetas.pythondata-misc-usb_ohci) { };
    };

  applyOverlay = python: python.override {
    packageOverrides = pythonOverlay;
  };

  overlay = self: super: {
    mkSbtDerivation = sbtNixpkgs.callPackage ./sbt-derivation.nix { };

    python3 = applyOverlay super.python3;
    python3Packages = self.python3.pkgs;
  };

  extended = pkgs.extend overlay;

  pkgSet =
    (builtins.foldl'
      (acc: elem: acc // {
        ${elem} = extended.python3Packages.${elem};
      })
      { }
      (
        builtins.concatLists (builtins.map (x: [ "${x}-unchecked" "${x}-test" x ]) testedPkgsNames)
        ++ [
          "pythondata-cpu-vexriscv"
          "pythondata-cpu-vexriscv_smp"
          "pythondata-misc-tapcfg"
          "pythondata-software-compiler_rt"
          "pythondata-cpu-serv"
          "pythondata-software-picolibc"
          "pythondata-cpu-lm32"
          "pythondata-cpu-mor1kx"
          "pythondata-cpu-minerva"
          "pythondata-cpu-naxriscv"
          "pythondata-cpu-sentinel"
          "pythondata-cpu-vexiiriscv"
          "pythondata-misc-usb_ohci"
        ]
      )) // {
      mkSbtDerivation = extended.mkSbtDerivation;
    };

  # Build a special "maintainance" package which contains tools to
  # work with the TOML-based pkgMetas definition
  maintenance = pkgs.python3Packages.buildPythonPackage {
    name = "nix-litex-maintenance";

    # Simply include the entire /maintenance directory as the
    # source. It is only a loose collection of (Python scripts), which
    # will be copied to the $out/bin path in the installPhase.
    src = ../maintenance;
    format = "other";

    buildInputs = [
      pkgs.python3Packages.toml
      pkgs.python3Packages.gitpython
    ];

    installPhase = ''
      mkdir -p $out/bin/
      cp *.py $out/bin/
      chmod +x $out/bin/*
    '';
  };

in
pkgSet // {
  inherit overlay pythonOverlay maintenance;
  packages = pkgSet;
  nixpkgsExtended = extended;
}
