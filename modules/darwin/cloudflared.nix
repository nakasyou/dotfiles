{ username, ... }:

let
  homeDir = "/Users/${username}";
  cloudflaredDir = "${homeDir}/.cloudflared";
in
{
  system.activationScripts.nakasyouCloudflared.text = ''
    install -d -o ${username} -g staff -m 0700 "${cloudflaredDir}"

    install -o ${username} -g staff -m 0600 \
      "${../../services/cloudflared/config.yml}" \
      "${cloudflaredDir}/config.yml"
  '';
}