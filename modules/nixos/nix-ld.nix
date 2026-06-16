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
      xorg.libX11
      xorg.libXcomposite
      xorg.libXcursor
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXrandr
      xorg.libXrender
      xorg.libXScrnSaver
      xorg.libXtst
      xorg.libxcb
      libxkbcommon
      zlib
    ];
  };
  environment.sessionVariables = {
    LD_LIBRARY_PATH = [
      "/run/current-system/sw/share/nix-ld/lib"
    ];
  };
}
