{ pkgs }:

let
  materialIcons = pkgs.callPackage ./dolphin-material-icons.nix { };
in
pkgs.symlinkJoin {
  name = "dolphin-material";
  paths = [ pkgs.kdePackages.dolphin pkgs.kdePackages.ark ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/dolphin \
      --set QT_QPA_PLATFORMTHEME qt6ct \
      --set QT_STYLE_OVERRIDE kvantum \
      --prefix XDG_CONFIG_DIRS : "${materialIcons}/etc/xdg" \
      --prefix PATH : "${pkgs.kdePackages.ark}/bin" \
      --prefix QT_PLUGIN_PATH : "${pkgs.qt6Packages.qt6ct}/lib/qt-6/plugins:${pkgs.kdePackages.qtstyleplugin-kvantum}/lib/qt-6/plugins:${pkgs.kdePackages.ark}/lib/qt-6/plugins" \
      --prefix XDG_DATA_DIRS : "${materialIcons}/share:${pkgs.papirus-icon-theme}/share" \
      --add-flags "-stylesheet ${../config/dolphin-material/material.qss}"
  '';
  meta.mainProgram = "dolphin";
}
