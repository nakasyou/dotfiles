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
  pname = "chatgpt";
  version = "26.825.51511";

  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb";
    hash = "sha256-NVSwAixs+1EzJvQ/0R9xiDWncIasTXyi/z67ui1Mf0U=";
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

  autoPatchelfIgnoreMissingDeps = [
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libQt6Core.so.6"
    "libQt6Gui.so.6"
    "libQt6Widgets.so.6"
    "libc.musl-x86_64.so.1"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/libexec
    cp -a usr/lib/chatgpt $out/libexec/chatgpt
    cp -a usr/share $out/share
    ln -s $out/libexec/chatgpt/ChatGPT $out/bin/chatgpt

    runHook postInstall
  '';

  preFixup = ''
    # Native Node addons are shared libraries.  The Debian package marks them
    # executable, which makes autoPatchelf add an interpreter and turn them
    # into PIE executables that Electron cannot load with dlopen().
    find $out/libexec/chatgpt -type f -name '*.node' -exec chmod -x {} +

    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib:${lib.makeLibraryPath [
        libglvnd
        udev
        gtk3-x11
      ]}"
    )
  '';

  meta = {
    description = "Official ChatGPT desktop app for Linux";
    homepage = "https://learn.chatgpt.com/docs/linux/linux-app";
    downloadPage = "https://learn.chatgpt.com/docs/linux/linux-app";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.unfree;
    mainProgram = "chatgpt";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
