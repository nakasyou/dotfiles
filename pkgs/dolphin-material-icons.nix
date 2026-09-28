{ pkgs }:

pkgs.runCommand "dolphin-material-icons" {
  nativeBuildInputs = [ pkgs.python3 ];
  meta = {
    description = "Material Symbols Rounded icon theme for Dolphin";
    license = pkgs.lib.licenses.asl20;
  };
} ''
  python ${../config/dolphin-material/icons}/build.py "$out"
  mkdir -p "$out/etc/xdg"
  cat > "$out/etc/xdg/kdeglobals" <<'CONFIG'
  [Icons]
  Theme=MaterialDolphin
  CONFIG
''
