{ lib, stdenv, fetchurl, autoPatchelfHook, makeWrapper, libx11, libxi, libxtst, libxcb }:

stdenv.mkDerivation rec {
  pname = "cua";
  version = "0.9.0";
  src = fetchurl {
    url = "https://github.com/trycua/cua/releases/download/cua-sdk-v${version}/cua-cli-${version}-linux-x64.tar.gz";
    hash = "sha256-l4Af9MOqLz2Z+POa4tCHldzOwkFZOrN0vnypJXYUIco=";
  };
  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
  buildInputs = [ stdenv.cc.cc.lib ];
  sourceRoot = ".";
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    find . -maxdepth 2 -type f -executable -exec cp {} "$out/bin/" \;
    runHook postInstall
  '';
  postFixup = ''
    # Host setup uses ldd, which does not read NIX_LD_LIBRARY_PATH.
    wrapProgram "$out/bin/cua" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ stdenv.cc.cc.lib libx11 libxi libxtst libxcb ]}
  '';
  meta = {
    description = "Cua sandbox SDK command-line tools";
    homepage = "https://github.com/trycua/cua";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "cua";
  };
}
