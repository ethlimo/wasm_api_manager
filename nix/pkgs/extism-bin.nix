{ autoPatchelfHook
, stdenv
, ...
}:

stdenv.mkDerivation rec {
  name = "extism";
  version = "1.2.0";

  src = builtins.fetchurl {
    url = "https://github.com/extism/extism/releases/download/v${version}/libextism-x86_64-unknown-linux-gnu-v${version}.tar.gz";
    sha256 = "sha256:0m09wgazi8h1v4cq6hjxf5jhxkxyc197c8vg0q54nhjlm7fa42b0";
  };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = [
    stdenv.cc.cc.lib
  ];

  unpackPhase = ''
    tar xzf $src
  '';

  installPhase = ''
    mkdir -p $out/include
    mkdir -p $out/lib/pkgconfig

    cp extism.h $out/include

    cp libextism.a $out/lib
    cp libextism.so $out/lib

    sed "s|@CMAKE_INSTALL_PREFIX@|''${out}|g" extism.pc.in > $out/lib/pkgconfig/extism.pc
    sed "s|@CMAKE_INSTALL_PREFIX@|''${out}|g" extism-static.pc.in > $out/lib/pkgconfig/extism-static.pc
  '';

  meta = {
    platforms = [ "x86_64-linux" ];
  };
}
