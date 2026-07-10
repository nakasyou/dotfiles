{ pkgs, ... }:

{
  programs.steam = {
    enable = true;
    extest.enable = true;
    extraPackages = with pkgs; [
      libdrm
      libglvnd
      libcxx
      libpulseaudio
      mesa
      libx11
      libxcomposite
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxi
      libxinerama
      libxrandr
      libxrender
      libxscrnsaver
      libxtst
      libxxf86vm
      libice
      libsm
      libxcb
      libxkbfile
      libxshmfence
      libxcb-util
      libxcb-cursor
      libxcb-image
      libxcb-keysyms
      libxcb-render-util
      libxcb-wm
    ];
  };
}