{ stdenvNoCC, fetchFromGitHub, extism-so, ... }:
# to whoever has to maintain this, the only reason this exists 
# instead of using upstream is to patch out the use of environment variables
# while looking for the shared library
let
  upstream-ocaml-extism = fetchFromGitHub {
    owner = "extism";
    repo = "ocaml-sdk";
    rev = "v1.1.0";
    hash = "sha256-OkVz0NXRr3MVJ9zpMSzkNNGNyxgB5ETWMsWha4YGfCk=";
  };
in
stdenvNoCC.mkDerivation rec {
  pname = "ocaml-sdk";
  version = "1.1.0";
  src = upstream-ocaml-extism;
  phases = [ "unpackPhase" "patchPhase" "installPhase" ];
  patches = [ ./hardcode_extism_sofile_path.patch ];
  patchPhase = ''
    runHook patchPhase
    sed -i "s|EXTISM_SOFILE|${extism-so}/lib|g" src/bindings.ml
  '';
  installPhase = ''
    cp -r . $out
  '';
  propagatedBuildInputs = [ extism-so ];
}
