{ pkgs }:
let
  python = pkgs.python3.withPackages (p: with p; [ dbus-python packaging psutil pyxdg ]);
in pkgs.stdenv.mkDerivation {
  pname = "chrome-remote-desktop";
  version = "154.0.8037.11";
  src = pkgs.fetchurl {
    url = "https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb";
    hash = "sha256-Vy3uCMoCT5IqTDW0sCir2jSMm1TxKIjqquU/aHDdWSQ=";
  };
  nativeBuildInputs = with pkgs; [ dpkg autoPatchelfHook makeWrapper ];
  buildInputs = with pkgs; [
    atk cairo dbus expat mesa glib gtk3 nspr nss pam pango systemd
    libx11 libxcb libxdamage libxext libxfixes libxkbcommon libxrandr libxtst
    stdenv.cc.cc.lib
  ];
  unpackPhase = "dpkg-deb -x $src .";
  installPhase = ''
    mkdir -p $out/lib $out/bin
    cp -r opt/google/chrome-remote-desktop $out/lib/
    hostDir=$out/lib/chrome-remote-desktop
    substituteInPlace $hostDir/chrome-remote-desktop \
      --replace-fail '#!/usr/bin/python3' '#!${python}/bin/python3' \
      --replace-fail '"/usr/bin/pkexec"' '"/run/wrappers/bin/pkexec"' \
      --replace-fail '"/usr/bin/sudo"' '"/run/wrappers/bin/sudo"' \
      --replace-fail '["systemctl", "enable", "--now",' '["systemctl", "start",'
    patchShebangs $hostDir
    for name in chrome-remote-desktop start-host; do
      makeWrapper $hostDir/$name $out/bin/$name \
        --set CHROME_REMOTE_DESKTOP_USE_XVFB 1 \
        --prefix PATH : ${pkgs.lib.makeBinPath (with pkgs; [ coreutils procps psmisc util-linux systemd xorg-server xauth xdpyinfo xrandr setxkbmap xdg-utils dbus pipewire wireplumber ])}
    done
  '';
  meta = {
    description = "Google Chrome Remote Desktop host";
    platforms = [ "x86_64-linux" ];
    license = pkgs.lib.licenses.unfree;
  };
}
