{ config, pkgs, lib, ... }:

{
  boot.initrd.kernelModules = [ "virtio_gpu" "virtio_pci" "virtio_blk" "virtio_input" "uinput" ];

  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;

  environment.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1"; 
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
  };
  
  services.xserver.videoDrivers = [ "modesetting" "fbdev" ];
}