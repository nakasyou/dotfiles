{ pkgs, ... }:

{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # Android Studio's emulator binary is not Nix-patched, so nix-ld needs the desktop stack.
      stdenv.cc.cc.lib
      dbus
      fontconfig
      freetype
      glib
      libdrm
      libglvnd
      nspr
      nss
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
