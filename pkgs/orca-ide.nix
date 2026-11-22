{ appimageTools, fetchurl, makeDesktopItem }:

let
  pname = "orca-ide";
  version = "1.4.268";
  desktopItem = makeDesktopItem {
    name = pname;
    desktopName = "Orca";
    exec = pname;
    icon = pname;
    categories = [ "Development" ];
  };
  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-linux.AppImage";
    hash = "sha256-ITO6RoRXiy4FIQvzD4boyvH6oXlDBFAeJ57LIwyqPv4=";
  };
  contents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm644 ${desktopItem}/share/applications/orca-ide.desktop \
      "$out/share/applications/orca-ide.desktop"
    install -Dm644 ${contents}/.DirIcon "$out/share/pixmaps/orca-ide.png"
  '';

  meta = {
    description = "Development environment for coding agents";
    homepage = "https://orca.dev/";
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
