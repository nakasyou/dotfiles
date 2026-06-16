{ pkgs, ... }:

{
  hardware.graphics.enable = true;
  hardware.amdgpu = {
    initrd.enable = true;
    opencl.enable = true;
  };

  environment.systemPackages = with pkgs; [
    clinfo
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
  ];
}
