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
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [ nix-tests.packages.${system}.default ];
        };

        lib = import ./lib/modules.nix {
          inherit (pkgs) lib;
          config = { };
        };
        mkLib =
          {
            lib,
            config ? { },
          }:
          import ./lib/modules.nix { inherit lib config; };
      }
    );
}
