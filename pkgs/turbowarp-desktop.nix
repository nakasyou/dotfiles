{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  at-spi2-core,
  atk,
  alsa-lib,
  cairo,
  cups,
  dbus,
  expat,
  gcc-unwrapped,
  gdk-pixbuf,
  glib,
  gtk3-x11,
  libdrm,
  libgbm,
  libnotify,
  libsecret,
  libxkbcommon,
  nspr,
  nss,
  pango,
  udev,
  wayland,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxrandr,
  libxrender,
  libxscrnsaver,
  libxtst,
}:

stdenv.mkDerivation rec {
  pname = "turbowarp-desktop";
  version = "1.15.5";

  src = fetchurl {
    url = "https://github.com/TurboWarp/desktop/releases/download/v${version}/TurboWarp-linux-x64-${version}.tar.gz";
    hash = "sha256-P3DlX6PCVlw+UP718TZCA4cPBdJQyrNCjoZzw4x99Bs=";
  };

  sourceRoot = "TurboWarp-linux-x64-${version}";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    at-spi2-core
    atk
    alsa-lib
    cairo
    cups.lib
    dbus.lib
    expat
    gcc-unwrapped
    gdk-pixbuf
    glib
    gtk3-x11
    libdrm
    libgbm
    libnotify
    libsecret
    libxkbcommon
    nspr
    nss
    pango
    udev
    wayland
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxscrnsaver
    libxtst
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/libexec $out/share/applications
    cp -a . $out/libexec/${pname}
    ln -s $out/libexec/${pname}/turbowarp-desktop $out/bin/turbowarp-desktop

    install -Dm644 linux-files/org.turbowarp.TurboWarp.desktop \
      $out/share/applications/org.turbowarp.TurboWarp.desktop
    substituteInPlace $out/share/applications/org.turbowarp.TurboWarp.desktop \
      --replace-fail "/opt/TurboWarp/turbowarp-desktop" "$out/bin/turbowarp-desktop"

    install -Dm644 resources/icon.png \
      $out/share/icons/hicolor/512x512/apps/org.turbowarp.TurboWarp.png
    install -Dm644 resources/icon.svg \
      $out/share/icons/hicolor/scalable/apps/org.turbowarp.TurboWarp.svg
    install -Dm644 linux-files/org.turbowarp.TurboWarp.metainfo.xml \
      $out/share/metainfo/org.turbowarp.TurboWarp.metainfo.xml
    install -Dm644 linux-files/org.turbowarp.TurboWarp.mime.xml \
      $out/share/mime/packages/org.turbowarp.TurboWarp.xml

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ udev gtk3-x11 ]}"
    )
  '';

  meta = {
    description = "Offline desktop app for the TurboWarp Scratch editor";
    homepage = "https://desktop.turbowarp.org/";
    downloadPage = "https://github.com/TurboWarp/desktop/releases";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.gpl3Only;
    mainProgram = "turbowarp-desktop";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
