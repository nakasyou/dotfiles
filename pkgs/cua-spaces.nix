{ lib, appimageTools, fetchurl }:

let
  pname = "cua-spaces";
  version = "0.16.0";
  src = fetchurl {
    url = "https://github.com/trycua/cua/releases/download/cua-spaces-v${version}/cua-spaces-${version}-linux-x64.AppImage";
    hash = "sha256-QIMJouV66cc3IlNJQQogi2MLbN7ZafVPkrvNZzlUANQ=";
  };
  contents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;
  # Relaunching via /usr/bin/sg loses the Nix AppImage environment.
  profile = ''
    export CUA_SPACES_SG_DOCKER=1
  '';
  extraInstallCommands = ''
    install -Dm444 ${contents}/*.desktop "$out/share/applications/cua-spaces.desktop"
    substituteInPlace "$out/share/applications/cua-spaces.desktop" \
      --replace-fail 'Exec=AppRun' 'Exec=cua-spaces'
    if [ -d ${contents}/usr/share/icons ]; then
      mkdir -p "$out/share"
      cp -r ${contents}/usr/share/icons "$out/share/"
    fi
  '';
  meta = {
    description = "Cua Spaces desktop app";
    homepage = "https://github.com/trycua/cua";
    platforms = [ "x86_64-linux" ];
    mainProgram = "cua-spaces";
  };
}
