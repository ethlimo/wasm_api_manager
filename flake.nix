{
  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    opam-repository = {
      url = "github:ocaml/opam-repository";
      flake = false;
    };
    opam-nix = {
      url = "github:tweag/opam-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.opam-repository.follows = "opam-repository";
    };
  };

  outputs = { self, nixpkgs, flake-utils, opam-nix, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        extism-bin = pkgs.callPackage ./nix/pkgs/extism-bin.nix { };
        on = opam-nix.lib.${system};

        ocaml-extism =
          (pkgs.callPackage ./nix/pkgs/ocaml-extism.nix { extism-so = extism-bin; });

        limo_api_manager = (on.buildDuneProject
          {
            repos = [
              (on.makeOpamRepo ocaml-extism)
              inputs.opam-repository
            ];
          }
          "limo_api_manager" ./limo_api_manager
          {
            ocaml-system = "5.1.1";
            coq = "*";
            wasmtime = "*";
            extism = "dev";
          }).limo_api_manager.overrideAttrs (prev: {
          buildInputs = prev.buildInputs ++ [ ];
        });
      in
      {
        formatter = pkgs.nixpkgs-fmt;

        devShells.default = pkgs.mkShell {
          inputsFrom = [ limo_api_manager ];
        };

        packages.default = limo_api_manager;
      });
}
