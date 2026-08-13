{ pkgs, ... }:

{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # Android Studio's emulator binary is not Nix-patched, so nix-ld needs the desktop stack.
      alsa-lib
      at-spi2-atk
      atk
      cairo
      cups
      stdenv.cc.cc.lib
      dbus
      expat
      fontconfig
      freetype
      glib
      gtk3
      libdrm
      libgbm
      libglvnd
      mesa
      nspr
      nss
      pango
      systemd
      libx11
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
      libxcb
      libxkbcommon
      zlib
    ];
  };
}
