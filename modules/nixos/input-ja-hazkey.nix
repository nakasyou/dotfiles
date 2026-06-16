{ lib, pkgs, ... }:

let
  hazkeySrc = builtins.fetchTarball {
    url = "https://github.com/aster-void/nix-hazkey/archive/05527ef2659aab53c1cb0d0972a25347ef3161d4.tar.gz";
    sha256 = "10lnrv63imyapp368cs0xl1s52rbcsxp1k2nj18z988nshsny6yb";
  };

  hazkeyPackages = rec {
    dictionary = import "${hazkeySrc}/packages/dictionary" { inherit pkgs; };
    fcitx5-hazkey = import "${hazkeySrc}/packages/fcitx5-hazkey" { inherit pkgs; };
    hazkey-server = import "${hazkeySrc}/packages/hazkey-server" { inherit pkgs; };
    hazkey-settings = import "${hazkeySrc}/packages/hazkey-settings" { inherit pkgs; };
    zenzai_v3_1-small = import "${hazkeySrc}/packages/zenzai_v3_1-small" { inherit pkgs; };
  };
in
{
  programs.dconf = {
    enable = true;
    profiles.user.databases = [{
      lockAll = true;
      settings = {
        "org/gnome/desktop/input-sources" = {
          sources = [ (lib.gvariant.mkTuple [ "xkb" "jp" ]) ];
        };
      };
    }];
  };

  services.xserver.xkb = {
    layout = "jp";
    model = "jp106";
    variant = "";
  };

  console.keyMap = "jp106";

  environment.systemPackages = [
    hazkeyPackages.hazkey-settings
  ];

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-mozc
      qt6Packages.fcitx5-configtool
    ] ++ [ hazkeyPackages.fcitx5-hazkey ];
  };

  systemd.user.services.hazkey-server = {
    description = "Hazkey server";
    wantedBy = [ "default.target" ];
    after = [ "hazkey-fcitx-profile.service" ];
    serviceConfig = {
      ExecStart = "${lib.getExe hazkeyPackages.hazkey-server}";
      Restart = "on-failure";
      Environment = [
        "HAZKEY_DICTIONARY=${hazkeyPackages.dictionary}/share/hazkey/Dictionary"
        "HAZKEY_ZENZAI_MODEL=${hazkeyPackages.zenzai_v3_1-small}/share/zenzai/zenzai.gguf"
        "GGML_BACKEND_DIR=${hazkeyPackages.hazkey-server}/lib/hazkey/libllama/backends/"
      ];
    };
  };

  systemd.user.services.hazkey-fcitx-profile = {
    description = "Force fcitx5 current and default input method to Hazkey";
    wantedBy = [ "graphical-session.target" ];
    after = [
      "graphical-session.target"
      "app-org.fcitx.Fcitx5@autostart.service"
      "hazkey-server.service"
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p "$HOME/.config/fcitx5"
      cat > "$HOME/.config/fcitx5/profile" <<'EOF'
      [Groups/0]
      Name=デフォルト
      Default Layout=jp
      DefaultIM=hazkey

      [Groups/0/Items/0]
      Name=keyboard-jp
      Layout=

      [Groups/0/Items/1]
      Name=hazkey
      Layout=

      [GroupOrder]
      0=デフォルト
      EOF

      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

      for _ in $(seq 1 20); do
        if ${pkgs.systemd}/bin/busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 CurrentInputMethod >/dev/null 2>&1; then
          ${pkgs.systemd}/bin/busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 SetInputMethodGroupInfo "ssa(ss)" デフォルト jp 2 keyboard-jp "" hazkey ""
          ${pkgs.systemd}/bin/busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 Activate
          ${pkgs.systemd}/bin/busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 SetCurrentIM s hazkey || true
          exit 0
        fi
        sleep 1
      done
    '';
  };
}
