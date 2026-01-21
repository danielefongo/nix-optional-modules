{
  description = "Nix optional modules";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-tests.url = "github:danielefongo/nix-tests";
  };
  outputs =
    {
      self,
      flake-utils,
      nixpkgs,
      nix-tests,
    }:
    {
      lib = import ./lib/modules.nix {
        inherit (nixpkgs) lib;
        config = { };
      };
    }
    // flake-utils.lib.eachDefaultSystem (system: {
      devShells.default = nixpkgs.legacyPackages.${system}.mkShell {
        packages = [ nix-tests.packages.${system}.default ];
      };
    });
}
