{ config, lib, pkgs, codex-desktop-linux, system, ... }:

let
  androidSdkRoot = "${androidSdk}/libexec/android-sdk";
  javaHome = "${pkgs.jdk17_headless}/lib/openjdk";
  flameshotGui = pkgs.writeShellScriptBin "flameshot-gui" ''
    exec env QT_QPA_PLATFORM=wayland ${pkgs.flameshot}/bin/flameshot gui "$@"
  '';
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    abiVersions = [ "x86_64" ];
    buildToolsVersions = [ "35.0.0" ];
    includeCmake = false;
    includeEmulator = "if-supported";
    includeNDK = false;
    includeSystemImages = true;
    platformVersions = [ "35" ];
    systemImageTypes = [ "google_apis" ];

    extraLicenses = [
      "android-sdk-preview-license"
      "android-sdk-arm-dbt-license"
      "google-gdk-license"
      "intel-android-extra-license"
      "intel-android-sysimage-license"
    ];
  };
  androidSdk = androidComposition.androidsdk;
  androidStudio = pkgs.android-studio.withSdk androidSdk;
  gtk4PkgConfigPackages = with pkgs; [
    cairo
    gdk-pixbuf
    glib
    graphene
    harfbuzz
    gtk4
    pango
    vulkan-loader
  ];
  eclipsa-android-emulator = pkgs.writeShellScriptBin "eclipsa-android-emulator" ''
    set -euo pipefail

    export ANDROID_SDK_ROOT="${androidSdkRoot}"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    export JAVA_HOME="${javaHome}"
    export QT_QPA_PLATFORM="xcb"

    exec steam-run \
      "$ANDROID_SDK_ROOT/emulator/emulator" \
      -gpu host \
      -feature -Vulkan \
      -no-snapshot-load \
      -no-snapshot-save \
      "''${@:-@Eclipsa_API35}"
  '';
  turbowarp-desktop = pkgs.callPackage ../../pkgs/turbowarp-desktop.nix { };
  # Upstream stable lags behind the current nightly release.
  yt-dlp-nightly = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "yt-dlp";
    version = "nightly-2026.04.30.234007";

    src = pkgs.fetchurl {
      url = "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/2026.04.30.234007/yt-dlp_linux";
      hash = "sha256-AWMW3DpUNVXxDhUhXHe0SAQSc5EoNdnOWToDdpzgwEI=";
    };

    dontUnpack = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 $src $out/bin/yt-dlp

      runHook postInstall
    '';

    meta = with lib; {
      description = "Feature-rich command-line audio/video downloader";
      homepage = "https://github.com/yt-dlp/yt-dlp";
      downloadPage = "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases";
      license = licenses.unlicense;
      mainProgram = "yt-dlp";
      platforms = platforms.linux;
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    };
  };
  codexStandalonePath = "${config.home.homeDirectory}/.codex/packages/standalone/current/codex";
  codexStandalone = pkgs.writeShellScriptBin "codex" ''
    exec "${codexStandalonePath}" "$@"
  '';
  codexInstallerPath = lib.makeBinPath (with pkgs; [
    coreutils
    curl
    findutils
    gawk
    gnugrep
    gnused
    gnutar
    gzip
    util-linux
  ]);
  vastai = pkgs.python3Packages.buildPythonApplication rec {
    pname = "vastai";
    version = "1.0.8";
    pyproject = true;

    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-CIj6hS0x3OPBXynE8EGr2WqfbDEjx4JEf3wQNCO1blY=";
    };

    build-system = with pkgs.python3Packages; [
      poetry-core
      poetry-dynamic-versioning
    ];

    pythonRelaxDeps = [
      "aiodns"
      "borb"
      "cryptography"
      "psutil"
      "pycares"
    ];

    dependencies = with pkgs.python3Packages; [
      xdg
      (borb.overridePythonAttrs (_: {
        doCheck = false;
      }))
      requests
      python-dateutil
      urllib3
      pyparsing
      aiohttp
      aiodns
      pycares
      anyio
      psutil
      pycryptodome
      argcomplete
      curlify
      rich
      cryptography
    ];

    pythonImportsCheck = [
      "vastai"
      "vastai_sdk"
    ];

    meta = with lib; {
      description = "CLI and SDK for Vast.ai GPU Cloud Service";
      homepage = "https://vast.ai";
      changelog = "https://github.com/vast-ai/vast-cli/releases";
      license = licenses.mit;
      mainProgram = "vastai";
    };
  };
  codex-desktop = codex-desktop-linux.packages.${system}.codex-desktop;
in
{
  home.username = "nakasyou";
  home.homeDirectory = "/home/nakasyou";
  home.stateVersion = "25.11";
  home.sessionVariables = {
    ANDROID_HOME = androidSdkRoot;
    ANDROID_SDK_ROOT = androidSdkRoot;
    DOTFILES_DIR = "${config.home.homeDirectory}/dotfiles";
    JAVA_HOME = javaHome;
    PKG_CONFIG_PATH = lib.makeSearchPathOutput "dev" "lib/pkgconfig" gtk4PkgConfigPackages;
    CODEX_CLI_PATH = codexStandalonePath;
  };
  home.sessionPath = [
    "${javaHome}/bin"
    "${androidSdkRoot}/emulator"
    "${androidSdkRoot}/platform-tools"
  ];

  programs.home-manager.enable = true;
  services.flameshot = {
    enable = true;
  };

  xdg.configFile."autostart/proton.vpn.app.gtk.desktop".source =
    "${pkgs.proton-vpn}/share/applications/proton.vpn.app.gtk.desktop";
  xdg.configFile."mimeapps.list".force = true;
  xdg.dataFile."applications/mimeapps.list".force = true;
  home.file.".profile".text = ''
    for hm_session_vars in \
      "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" \
      "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
    do
      if [ -f "$hm_session_vars" ]; then
        . "$hm_session_vars"
        break
      fi
    done

    if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
      . "$HOME/.bashrc"
    fi
  '';
  home.file.".bashrc" = {
    force = true;
    text = ''
      if [ -d "$HOME/.nix-profile/bin" ]; then
        export PATH="$HOME/.nix-profile/bin:$PATH"
      fi

      for hm_session_vars in \
        "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" \
        "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
      do
        if [ -f "$hm_session_vars" ]; then
          . "$hm_session_vars"
          break
        fi
      done

      export PATH="$HOME/.npm-global/bin:$PATH"

      alias nakasyou-nix-rebuild="sudo nixos-rebuild switch --flake path:/home/nakasyou/dotfiles#p14s"
    '';
  };

  home.activation.installCodexStandalone = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    codex_standalone="${codexStandalonePath}"

    if [ ! -x "$codex_standalone" ]; then
      echo "Installing Codex standalone"
      tmp_dir="$(${pkgs.coreutils}/bin/mktemp -d)"

      cleanup_codex_installer() {
        ${pkgs.coreutils}/bin/rm -rf "$tmp_dir"
      }
      trap cleanup_codex_installer EXIT INT TERM

      ${pkgs.curl}/bin/curl -fsSL https://chatgpt.com/codex/install.sh -o "$tmp_dir/install.sh"
      install_bin_dir="$tmp_dir/bin"
      env \
        PATH="$install_bin_dir:${codexInstallerPath}:$PATH" \
        CODEX_NON_INTERACTIVE=1 \
        CODEX_INSTALL_DIR="$install_bin_dir" \
        CODEX_HOME="${config.home.homeDirectory}/.codex" \
        ${pkgs.bash}/bin/bash "$tmp_dir/install.sh"
    fi
  '';
  home.packages = with pkgs; [
    androidStudio
    androidSdk
    android-tools
    eclipsa-android-emulator
    gcc
    gnumake
    jdk17_headless
    pkg-config
    gtk4
    xorg-server
    xauth
    google-chrome
    vscode
    libreoffice
    gimp
    imagemagick
    inkscape
    obsidian
    lmstudio
    git
    gh
    gnupg
    google-cloud-sdk
    google-cloud-sql-proxy
    wrangler
    ffmpeg
    pulseaudio
    easyeffects
    kooha
    gnome-sound-recorder
    nodejs_22
    vite-plus
    bun
    deno
    moonbit-bin.moonbit.latest
    rustc
    cargo
    rust-analyzer
    clippy
    rustfmt
    yt-dlp-nightly
    uv
    discord
    prismlauncher
    nextcloud-client
    zed-editor
    ghostty
    fuzzel
    wofi
    macchanger
    pavucontrol
    v4l-utils
    ripgrep
    grim
    slurp
    swaybg
    waybar
    wlogout
    networkmanagerapplet
    mpvpaper
    proton-vpn
    zip
    brave
    gpaste
    gnomeExtensions.appindicator
    gnomeExtensions.dash-to-dock
    gnomeExtensions.blur-my-shell
    gnomeExtensions."hidden-input-method-panel"
    vesktop
    gnome-tweaks
    turbowarp-desktop
    vastai
    codexStandalone
    codex-desktop
    (llm-agents.grok.overrideAttrs (_: {
      # grok's version check invokes bubblewrap, which GitHub-hosted Linux
      # runners cannot use because unprivileged UID maps are disabled.
      doInstallCheck = false;
    }))
    llm-agents.mimo-code
    flameshotGui
    tmux
    screen
    apktool
    apksigner
    jadx
    unzip
    zip
    dex2jar
    radare2
    ghidra
    frida-tools
    mitmproxy
    apkid
    (python3.withPackages (ps: with ps; [
      frida-python
      lief
      r2pipe
    ]))
  ];

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "brave-browser.desktop";
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "application/msword" = [ "writer.desktop" ];
      "application/vnd.ms-word" = [ "writer.desktop" ];
      "application/vnd.ms-word.document.macroEnabled.12" = [ "writer.desktop" ];
      "application/vnd.ms-word.template.macroEnabled.12" = [ "writer.desktop" ];
      "application/vnd.oasis.opendocument.text" = [ "writer.desktop" ];
      "application/vnd.oasis.opendocument.text-template" = [ "writer.desktop" ];
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = [ "writer.desktop" ];
      "application/vnd.openxmlformats-officedocument.wordprocessingml.template" = [ "writer.desktop" ];

      "application/vnd.ms-excel" = [ "calc.desktop" ];
      "application/vnd.ms-excel.sheet.macroEnabled.12" = [ "calc.desktop" ];
      "application/vnd.ms-excel.template.macroEnabled.12" = [ "calc.desktop" ];
      "application/vnd.oasis.opendocument.spreadsheet" = [ "calc.desktop" ];
      "application/vnd.oasis.opendocument.spreadsheet-template" = [ "calc.desktop" ];
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = [ "calc.desktop" ];
      "application/vnd.openxmlformats-officedocument.spreadsheetml.template" = [ "calc.desktop" ];

      "application/vnd.ms-powerpoint" = [ "impress.desktop" ];
      "application/vnd.ms-powerpoint.presentation.macroEnabled.12" = [ "impress.desktop" ];
      "application/vnd.ms-powerpoint.template.macroEnabled.12" = [ "impress.desktop" ];
      "application/vnd.oasis.opendocument.presentation" = [ "impress.desktop" ];
      "application/vnd.oasis.opendocument.presentation-template" = [ "impress.desktop" ];
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" = [ "impress.desktop" ];
      "application/vnd.openxmlformats-officedocument.presentationml.template" = [ "impress.desktop" ];
    };
  };
}
