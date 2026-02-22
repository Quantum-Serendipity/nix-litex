{
  description = "LiteX FPGA SoC builder - Nix packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      litex = import ./pkgs {
        inherit pkgs;
        skipChecks = true;
      };
    in
    {
      # Wrap overlays with the final/prev names that nix flake check expects
      overlays = {
        default = final: prev: litex.overlay final prev;
        python = final: prev: litex.pythonOverlay final prev;
      };

      packages.${system} = builtins.removeAttrs litex.packages [ "mkSbtDerivation" ];
    };
}
