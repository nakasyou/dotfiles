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
  version = "1.2.0";

  src = fetchurl {
    url = "https://downloads.cursor.com/grokbot/stable/cf0aa5097b8fdfea8f2ecd33ce9f71a72655ef08/linux/x64/grok-bot_${version}_amd64.deb";
    hash = "sha256-FVQenZYlc6pW+syh4FLOL/GiHS0W5OgG/ptyh9XxagM=";
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
