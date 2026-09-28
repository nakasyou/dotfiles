{
  lib,
  stdenv,
  fetchurl,
  dpkg,
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
  libglvnd,
  libnotify,
  libsecret,
  libusb1,
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
  pname = "grok-bot";
  version = "0.51.0";

  src = fetchurl {
    url = "https://downloads.cursor.com/grokbot/stable/e872793eb9471205c1f37e91891fedd0b827e3c1/linux/x64/grok-bot_${version}_amd64.deb";
    hash = "sha256-hXs8Klk2n1oWQ5Q/1Bobl/VF8Kyg9pWdJyp+YsTMWeA=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
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
    libglvnd
    libnotify
    libsecret
    libusb1
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

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/libexec
    cp -a "opt/Grok Bot" $out/libexec/grok-bot
    cp -a usr/share $out/share
    ln -s $out/libexec/grok-bot/grok-bot $out/bin/grok-bot
    substituteInPlace $out/share/applications/*.desktop \
      --replace-fail 'Exec=grok-bot' "Exec=$out/bin/grok-bot"
    runHook postInstall
  '';

  preFixup = ''
    # Keep autoPatchelf from treating shared libraries as executables.
    find $out/libexec/grok-bot -type f \( -name '*.node' -o -name '*.so' \) -exec chmod -x {} +
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib:${lib.makeLibraryPath [ libglvnd udev gtk3-x11 ]}"
    )
  '';

  meta = {
    description = "Grok Bot desktop agent";
    homepage = "https://x.ai/bot";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.unfree;
    mainProgram = "grok-bot";
    platforms = [ "x86_64-linux" ];
  };
}
