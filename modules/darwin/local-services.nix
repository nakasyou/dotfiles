{ pkgs, username, ... }:

let
  homeDir = "/Users/${username}";
  servicesDir = "${homeDir}/services";
  logsDir = "${homeDir}/Library/Logs/nakasyou-services";
  dockerHost = "unix://${homeDir}/.colima/default/docker.sock";
  servicePath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  colima = "/opt/homebrew/bin/colima";
  docker = "/opt/homebrew/bin/docker";
  cloudflaredConfig = ../../services/cloudflared/config.yml;

  notionAsS3Script = pkgs.writeShellScript "notion-as-a-s3-launch" ''
    set -euo pipefail

    export HOME="${homeDir}"
    export LOCALAPPDATA="${servicesDir}/notion-as-a-s3/temp"
    export PATH="${servicePath}"

    cd "${servicesDir}/notion-as-a-s3"

    while /usr/bin/nc -z 127.0.0.1 9000; do
      echo "127.0.0.1:9000 is already in use; waiting before starting notion-as-a-s3" >&2
      sleep 30
    done

    if [ -x ./target/release/notion-fs ]; then
      exec ./target/release/notion-fs serve
    fi

    if [ -x ./target/debug/notion-fs ]; then
      exec ./target/debug/notion-fs serve
    fi

    "${pkgs.cargo}/bin/cargo" build --release
    exec ./target/release/notion-fs serve
  '';

  nextcloudScript = pkgs.writeShellScript "nextcloud-launch" ''
    set -euo pipefail

    export HOME="${homeDir}"
    export DOCKER_HOST="${dockerHost}"
    export PATH="${servicePath}"

    "${colima}" start

    for attempt in $(seq 1 60); do
      if /usr/bin/nc -z 127.0.0.1 9000; then
        break
      fi
      if [ "$attempt" = 60 ]; then
        echo "notion-as-a-s3 did not open 127.0.0.1:9000 before timeout; starting Nextcloud anyway" >&2
        break
      fi
      sleep 1
    done

    cd "${servicesDir}/nextcloud"
    exec "${docker}" compose up -d
  '';
in
{
  environment.systemPackages = with pkgs; [
    cargo
    nodejs_22
    rustc
    cloudflared
  ];

  system.activationScripts.nakasyouLocalServices.text = ''
    install -d -o ${username} -g staff -m 0755 \
      "${servicesDir}" \
      "${servicesDir}/nextcloud" \
      "${servicesDir}/nextcloud/docker" \
      "${servicesDir}/nextcloud/docker/php" \
      "${servicesDir}/nextcloud/data" \
      "${servicesDir}/notion-as-a-s3" \
      "${servicesDir}/notion-as-a-s3/temp" \
      "${logsDir}"

    install -o ${username} -g staff -m 0644 \
      "${../../services/nextcloud/compose.yml}" \
      "${servicesDir}/nextcloud/compose.yml"

    install -o ${username} -g staff -m 0644 \
      "${../../services/nextcloud/docker/php/zz-disable-jit.ini}" \
      "${servicesDir}/nextcloud/docker/php/zz-disable-jit.ini"

    install -d -o ${username} -g staff -m 0700 \
      "${homeDir}/.cloudflared"
    install -o ${username} -g staff -m 0600 \
      "${cloudflaredConfig}" \
      "${homeDir}/.cloudflared/config.yml"
  '';

  launchd.user.agents.nakasyou-notion-as-a-s3.serviceConfig = {
    Label = "how.nakasyou.notion-as-a-s3";
    ProgramArguments = [ "${notionAsS3Script}" ];
    RunAtLoad = true;
    KeepAlive = true;
    WorkingDirectory = "${servicesDir}/notion-as-a-s3";
    StandardOutPath = "${logsDir}/notion-as-a-s3.log";
    StandardErrorPath = "${logsDir}/notion-as-a-s3.err.log";
  };

  launchd.user.agents.nakasyou-nextcloud.serviceConfig = {
    Label = "how.nakasyou.nextcloud";
    ProgramArguments = [ "${nextcloudScript}" ];
    RunAtLoad = true;
    WorkingDirectory = "${servicesDir}/nextcloud";
    StandardOutPath = "${logsDir}/nextcloud.log";
    StandardErrorPath = "${logsDir}/nextcloud.err.log";
  };

  launchd.user.agents.nakasyou-cloudflared.serviceConfig = {
    Label = "how.nakasyou.cloudflared";
    ProgramArguments = [
      "${pkgs.cloudflared}/bin/cloudflared"
      "tunnel"
      "--config"
      "${homeDir}/.cloudflared/config.yml"
      "run"
    ];
    RunAtLoad = true;
    KeepAlive = true;
    ProcessType = "Interactive";
    WorkingDirectory = "${homeDir}";
    StandardOutPath = "${logsDir}/cloudflared.log";
    StandardErrorPath = "${logsDir}/cloudflared.err.log";
  };
}
