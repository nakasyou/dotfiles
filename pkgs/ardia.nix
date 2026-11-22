{ appimageTools, fetchurl, lib }:

let
  pname = "ardia";
  version = "0.2.47-nightly.4";
  src = fetchurl {
    url = "https://github.com/ardia-browser/ardia/releases/download/v${version}/Ardia-${version}-linux-x64.AppImage";
    hash = "sha256-K07vGKEaRAA/FSjuTOGxr44GxXj0J4KxYWKbHFoXM+c=";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;
  extraInstallCommands = ''
    install -Dm644 ${contents}/ardia.desktop $out/share/applications/ardia.desktop
    substituteInPlace $out/share/applications/ardia.desktop --replace-fail 'Exec=AppRun' 'Exec=ardia'
    install -Dm644 ${contents}/ardia.png $out/share/icons/hicolor/256x256/apps/ardia.png
  '';
  meta = {
    description = "Chromium-based browser with a sidebar";
    homepage = "https://ardia.dev/";
    platforms = [ "x86_64-linux" ];
    mainProgram = "ardia";
  };
}
