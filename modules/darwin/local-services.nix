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

  litellmScript = pkgs.writeShellScript "litellm-launch" ''
    set -euo pipefail

    export HOME="${homeDir}"
    export DOCKER_HOST="${dockerHost}"
    export PATH="${servicePath}"

    "${colima}" start

    # Wait for colima docker socket to become available
    colimaSocket="${homeDir}/.colima/default/docker.sock"
    for attempt in $(seq 1 30); do
      if [ -S "$colimaSocket" ]; then
        break
      fi
      if [ "$attempt" = 30 ]; then
        echo "colima socket did not appear in time" >&2
        exit 1
      fi
      sleep 1
    done

    cd "${servicesDir}/litellm"
    exec "${docker}" compose up -d
  '';

  csbieScript = pkgs.writeShellScript "csbie-launch" ''
    set -euo pipefail

    export HOME="${homeDir}"
    export DOCKER_HOST="${dockerHost}"
    export PATH="${servicePath}"

    "${colima}" start

    colimaSocket="${homeDir}/.colima/default/docker.sock"
    for attempt in $(seq 1 30); do
      if [ -S "$colimaSocket" ]; then
        break
      fi
      if [ "$attempt" = 30 ]; then
        echo "colima socket did not appear in time" >&2
        exit 1
      fi
      sleep 1
    done

    cd "${servicesDir}/csbie"
    if [ ! -f .env ]; then
      echo "missing ${servicesDir}/csbie/.env; create it from env.example before starting csbie" >&2
      exit 1
    fi

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

  system.activationScripts.postActivation.text = ''
    install -d -o ${username} -g staff -m 0755 \
      "${servicesDir}" \
      "${servicesDir}/nextcloud" \
      "${servicesDir}/nextcloud/docker" \
      "${servicesDir}/nextcloud/docker/php" \
      "${servicesDir}/nextcloud/data" \
      "${servicesDir}/notion-as-a-s3" \
      "${servicesDir}/notion-as-a-s3/temp" \
      "${servicesDir}/litellm" \
      "${servicesDir}/litellm/data" \
      "${servicesDir}/litellm/data/postgres" \
      "${servicesDir}/csbie" \
      "${servicesDir}/csbie/data" \
      "${homeDir}/.config/litellm" \
      "${homeDir}/.config/litellm/xai_oauth" \
      "${logsDir}"

    install -o ${username} -g staff -m 0644 \
      "${../../services/nextcloud/compose.yml}" \
      "${servicesDir}/nextcloud/compose.yml"

    install -o ${username} -g staff -m 0644 \
      "${../../services/nextcloud/docker/php/zz-disable-jit.ini}" \
      "${servicesDir}/nextcloud/docker/php/zz-disable-jit.ini"

    install -o ${username} -g staff -m 0644 \
      "${../../services/litellm/compose.yml}" \
      "${servicesDir}/litellm/compose.yml"

    install -o ${username} -g staff -m 0644 \
      "${../../services/litellm/litellm_config.yaml}" \
      "${servicesDir}/litellm/litellm_config.yaml"

    install -o ${username} -g staff -m 0644 \
      "${../../services/litellm/Dockerfile}" \
      "${servicesDir}/litellm/Dockerfile"

    install -o ${username} -g staff -m 0644 \
      "${../../services/csbie/compose.yml}" \
      "${servicesDir}/csbie/compose.yml"

    if [ ! -f "${servicesDir}/csbie/env.example" ]; then
      install -o ${username} -g staff -m 0600 \
        "${../../services/csbie/env.example}" \
        "${servicesDir}/csbie/env.example"
    fi

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

  launchd.user.agents.nakasyou-litellm.serviceConfig = {
    Label = "how.nakasyou.litellm";
    ProgramArguments = [ "${litellmScript}" ];
    RunAtLoad = true;
    WorkingDirectory = "${servicesDir}/litellm";
    StandardOutPath = "${logsDir}/litellm.log";
    StandardErrorPath = "${logsDir}/litellm.err.log";
  };

  launchd.user.agents.nakasyou-csbie.serviceConfig = {
    Label = "how.nakasyou.csbie";
    ProgramArguments = [ "${csbieScript}" ];
    RunAtLoad = true;
    WorkingDirectory = "${servicesDir}/csbie";
    StandardOutPath = "${logsDir}/csbie.log";
    StandardErrorPath = "${logsDir}/csbie.err.log";
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
