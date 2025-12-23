{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./modules/qemu/qemu_fix.nix
    ./modules/qemu/qemu_fix.nix
    # ./modules/qemu/graphics.nix <- Removed for hardware support (injected via flake for VM)
    ./modules/system/boot.nix
    ./modules/system/user.nix
    ./modules/system/packages.nix
    ./modules/system/hardware.nix
    ./modules/ui/desktop.nix
    ./modules/ui/theme.nix
    ./modules/ui/omni/omni.nix

    # DODAJEMY NOWY PLIK:
    ./modules/ui/topbar.nix

    ./modules/ai/memory.nix
    ./modules/ai/brain/brain.nix
    ./modules/system/searx.nix
  ];

  system.stateVersion = "25.12";
  nixpkgs.config.allowUnfree = true; # Needed for hardware firmware/drivers
  networking.hostName = "omni-os-machine";
}
