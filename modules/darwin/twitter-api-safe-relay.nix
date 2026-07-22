{ inputs, lib, pkgs, username, ... }:

let
  homeDir = "/Users/${username}";
  stateDir = "${homeDir}/Library/Application Support/twitter-api-safe-relay";
  workingDir = "${stateDir}/runtime/packages/server";
  logsDir = "${homeDir}/Library/Logs/nakasyou-services";
  package = pkgs.callPackage ../../pkgs/twitter-api-safe-relay.nix {
    src = inputs.twitter-api-safe-relay;
  };
  settings = (pkgs.formats.json { }).generate "twitter-api-safe-relay-settings.json" {
    port = 3010;
    logLevel = "info";
    profiles = [{
      name = "account1";
      pageReloadIntervalMinutes = 1;
      browser = {
        type = "launch";
        browserType = "chromium";
        executablePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
        userDataDir = "${stateDir}/account1";
        headless = false;
        viewport = {
          width = 720;
          height = 720;
        };
      };
    }];
  };
in
{
  environment.systemPackages = [ package ];

  system.activationScripts.postActivation.text = lib.mkAfter ''
    install -d -o ${username} -g staff -m 0700 \
      "${stateDir}" \
      "${stateDir}/account1" \
      "${stateDir}/runtime" \
      "${stateDir}/runtime/packages" \
      "${workingDir}"
    install -d -o ${username} -g staff -m 0755 "${logsDir}"
    install -o ${username} -g staff -m 0600 \
      "${settings}" \
      "${stateDir}/runtime/settings.json"
  '';

  launchd.user.agents.twitter-api-safe-relay.serviceConfig = {
    Label = "how.nakasyou.twitter-api-safe-relay";
    ProgramArguments = [ "${package}/bin/twitter-api-safe-relay" ];
    RunAtLoad = true;
    KeepAlive = {
      SuccessfulExit = false;
    };
    ProcessType = "Interactive";
    WorkingDirectory = workingDir;
    StandardOutPath = "${logsDir}/twitter-api-safe-relay.log";
    StandardErrorPath = "${logsDir}/twitter-api-safe-relay.err.log";
  };
}
