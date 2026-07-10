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
  startColima = ''
    colimaSocket="${homeDir}/.colima/default/docker.sock"
    colimaLock="/tmp/nakasyou-colima-start.lock"

    if "${docker}" info >/dev/null 2>&1; then
      :
    else
      for attempt in $(seq 1 120); do
        if mkdir "$colimaLock" 2>/dev/null; then
          trap 'rmdir "$colimaLock" 2>/dev/null || true' EXIT
          "${colima}" start
          rmdir "$colimaLock"
          trap - EXIT
          break
        fi

        if [ -S "$colimaSocket" ] && "${docker}" info >/dev/null 2>&1; then
          break
        fi

        if [ "$attempt" = 120 ]; then
          echo "timed out waiting for another colima start to finish" >&2
          exit 1
        fi

        sleep 1
      done
    fi

    for attempt in $(seq 1 60); do
      if [ -S "$colimaSocket" ] && "${docker}" info >/dev/null 2>&1; then
        break
      fi
      if [ "$attempt" = 60 ]; then
        echo "colima docker socket did not become ready" >&2
        exit 1
      fi
      sleep 1
    done
  '';

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

    ${startColima}

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
    "${docker}" compose up -d --build

    for attempt in $(seq 1 60); do
      if "${docker}" compose exec -T -u www-data app php occ status --no-warnings >/dev/null 2>&1; then
        break
      fi
      if [ "$attempt" = 60 ]; then
        echo "Nextcloud occ did not become ready; skipping preview provider setup" >&2
        exit 0
      fi
      sleep 2
    done

    "${docker}" compose exec -T -u www-data app php occ config:system:set enable_previews --type=boolean --value=true
    "${docker}" compose exec -T -u www-data app php occ config:system:set preview_ffmpeg_path --value=/usr/bin/ffmpeg
    "${docker}" compose exec -T -u www-data app php occ config:system:set preview_ffprobe_path --value=/usr/bin/ffprobe
    "${docker}" compose exec -T -u www-data app php occ config:system:set preview_concurrency_new --type=integer --value=1
    "${docker}" compose exec -T -u www-data app php occ config:system:set preview_concurrency_all --type=integer --value=2

    "${docker}" compose exec -T -u www-data app php occ config:system:delete enabledPreviewProviders || true
    i=0
    for provider in \
      'OC\Preview\PNG' \
      'OC\Preview\JPEG' \
      'OC\Preview\GIF' \
      'OC\Preview\BMP' \
      'OC\Preview\XBitmap' \
      'OC\Preview\Krita' \
      'OC\Preview\WebP' \
      'OC\Preview\MarkDown' \
      'OC\Preview\TXT' \
      'OC\Preview\OpenDocument' \
      'OC\Preview\Movie' \
      'OC\Preview\MP3'
    do
      "${docker}" compose exec -T -u www-data app php occ config:system:set enabledPreviewProviders "$i" --value="$provider"
      i=$((i + 1))
    done
  '';

  litellmScript = pkgs.writeShellScript "litellm-launch" ''
    set -euo pipefail

    export HOME="${homeDir}"
    export DOCKER_HOST="${dockerHost}"
    export PATH="${servicePath}"

    ${startColima}

    cd "${servicesDir}/litellm"
    exec "${docker}" compose up -d
  '';

  uptimeKumaScript = pkgs.writeShellScript "uptime-kuma-launch" ''
    set -euo pipefail

    export HOME="${homeDir}"
    export DOCKER_HOST="${dockerHost}"
    export PATH="${servicePath}"

    ${startColima}

    cd "${servicesDir}/uptime-kuma"
    "${docker}" compose up -d uptime-kuma

    for attempt in $(seq 1 60); do
      if [ -f ./data/kuma.db ] && /usr/bin/sqlite3 ./data/kuma.db \
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'setting';" | /usr/bin/grep -q 1; then
        break
      fi
      if [ "$attempt" = 60 ]; then
        echo "uptime-kuma setting table did not become ready" >&2
        exit 1
      fi
      sleep 1
    done

    if [ "$(/usr/bin/sqlite3 ./data/kuma.db "SELECT COUNT(*) FROM user;")" = "0" ]; then
      bootstrapPassword="$(/usr/bin/openssl rand -base64 48)"
      bootstrapHash="$("${docker}" exec -e KUMA_BOOTSTRAP_PASSWORD="$bootstrapPassword" uptime-kuma \
        node -e 'require("./server/password-hash").generate(process.env.KUMA_BOOTSTRAP_PASSWORD).then((hash) => console.log(hash))')"
      /usr/bin/sqlite3 ./data/kuma.db \
        "INSERT INTO user (username, password, active) VALUES ('admin', '$bootstrapHash', 1);"
    fi

    "${docker}" compose stop uptime-kuma
    /usr/bin/sqlite3 ./data/kuma.db < ./monitors/seed.sql

    exec "${docker}" compose up -d
  '';

  csbieScript = pkgs.writeShellScript "csbie-launch" ''
    set -euo pipefail

    export HOME="${homeDir}"
    export DOCKER_HOST="${dockerHost}"
    export PATH="${servicePath}"

    ${startColima}

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
      "${servicesDir}/uptime-kuma" \
      "${servicesDir}/uptime-kuma/data" \
      "${servicesDir}/uptime-kuma/monitors" \
      "${servicesDir}/csbie" \
      "${servicesDir}/csbie/data" \
      "${homeDir}/.config/litellm" \
      "${homeDir}/.config/litellm/xai_oauth" \
      "${logsDir}"

    install -o ${username} -g staff -m 0644 \
      "${../../services/nextcloud/compose.yml}" \
      "${servicesDir}/nextcloud/compose.yml"

    install -o ${username} -g staff -m 0644 \
      "${../../services/nextcloud/Dockerfile}" \
      "${servicesDir}/nextcloud/Dockerfile"

    install -o ${username} -g staff -m 0644 \
      "${../../services/nextcloud/.dockerignore}" \
      "${servicesDir}/nextcloud/.dockerignore"

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
      "${../../services/uptime-kuma/compose.yml}" \
      "${servicesDir}/uptime-kuma/compose.yml"

    install -o ${username} -g staff -m 0644 \
      "${../../services/uptime-kuma/monitors/seed.sql}" \
      "${servicesDir}/uptime-kuma/monitors/seed.sql"

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

  launchd.user.agents.nakasyou-uptime-kuma.serviceConfig = {
    Label = "how.nakasyou.uptime-kuma";
    ProgramArguments = [ "${uptimeKumaScript}" ];
    RunAtLoad = true;
    WorkingDirectory = "${servicesDir}/uptime-kuma";
    StandardOutPath = "${logsDir}/uptime-kuma.log";
    StandardErrorPath = "${logsDir}/uptime-kuma.err.log";
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
