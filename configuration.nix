{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./modules/qemu/qemu_fix.nix
    ./modules/qemu/graphics.nix
    ./modules/system/boot.nix
    ./modules/system/user.nix
    ./modules/system/packages.nix
    ./modules/ui/desktop.nix
    ./modules/ui/theme.nix
    ./modules/ui/omni.nix

    # DODAJEMY NOWY PLIK:
    ./modules/ui/topbar.nix

    ./modules/ai/memory.nix
    ./modules/ai/brain.nix
    ./modules/system/searx.nix
  ];

  system.stateVersion = "25.12";
  networking.hostName = "omni-os-machine";
}
