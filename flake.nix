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
        package = "limo_api_manager";

        package_location = ./limo_api_manager;

        devPackagesQuery = {
            ocaml-lsp-server = "*";
            ocamlformat = "*";
        };

        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;
        extism-bin = pkgs.callPackage ./nix/pkgs/extism-bin.nix { };
        on = opam-nix.lib.${system};

        ocaml-extism =
          (pkgs.callPackage ./nix/pkgs/ocaml-extism.nix { extism-so = extism-bin; });
        thePackageScope = (on.buildOpamProject'
          {
            repos = [
              (on.makeOpamRepo ocaml-extism)
              inputs.opam-repository
            ];
          }
          package_location
          devPackagesQuery // {
            ocaml-base-compiler = "*";
            coq = "*";
            wasmtime = "*";
            extism = "dev";
            cohttp = "*";
            eio = "*";
          }); #TODO: doNixSupport = false; needs to be added to the overrides
          overlay = final: prev: {
            ${package} = prev.${package}.overrideAttrs (_: {
              doNixSupport = false;
            });
          };
          thePackageScopeWithOverlay = thePackageScope.overrideScope overlay;
          main = thePackageScopeWithOverlay."${package}";
          devPackages = builtins.attrValues (lib.getAttrs (builtins.attrNames devPackagesQuery) thePackageScopeWithOverlay);
      in
      {
        formatter = pkgs.nixpkgs-fmt;

        devShells.default = (pkgs.mkShell {
          inputsFrom = [ main ];
          buildInputs = devPackages ++ [];
        }).overrideAttrs (_: {
          withFakeOpam = false;
        });

        packages.default = main;
      });
}
