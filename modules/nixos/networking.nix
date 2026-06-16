{
  networking.networkmanager = {
    enable = true;
    wifi = {
      # Randomize only the physical Wi-Fi MAC. ProtonVPN's tunnel interfaces are unaffected.
      macAddress = "random";
      scanRandMacAddress = true;
    };
  };
}
