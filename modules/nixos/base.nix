{ pkgs, ... }:

{
  time.timeZone = "Asia/Tokyo";

  i18n.defaultLocale = "ja_JP.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  users.users.nakasyou = {
    isNormalUser = true;
    description = "Shotaro Nakamura";
    extraGroups = [ "networkmanager" "wheel" "video" "render" "kvm" "docker" ];
    packages = with pkgs; [ ];
  };

  nixpkgs.config = {
    allowUnfree = true;
    android_sdk.accept_license = true;
  };

  security.pki.certificateFiles = [
    ../../certificates/mitmproxy-ca-cert.pem
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    extra-substituters = [
      "https://cache.nakasyou.how"
    ];
    extra-trusted-public-keys = [
      "cache.nakasyou.how-1:BumjaqVgJE6uAuaJcoV1oeFKPEyPxZ73XNmxVskqQZM="
    ];
  };
  nix.nixPath = [
    "nixpkgs=${pkgs.path}"
    "nixos-config=/etc/nixos/nixos/configuration.nix"
  ];

  # Expose this repository at /etc/nixos so legacy nixos-rebuild can resolve <nixos-config>.
  environment.etc."nixos".source = builtins.path {
    path = ../..;
    name = "etc-nixos";
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
    usbutils
    networkmanager
    net-tools
    iproute2
    inetutils
    traceroute
    bind
    ethtool
    wirelesstools
    tcpdump
  ];

  system.stateVersion = "25.11";
}
