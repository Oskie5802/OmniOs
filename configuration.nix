{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/qemu/qemu_fix.nix
    ./modules/system/boot.nix
    ./modules/system/user.nix
    ./modules/system/packages.nix
    ./modules/ui/desktop.nix
    ./modules/ui/theme.nix # Nawet jeśli pusty, warto go mieć
    ./modules/ai/brain.nix
  ];

  # Podstawowe ustawienia tożsamości systemu
  system.stateVersion = "25.12";
  networking.hostName = "omni-os-machine";
}