{ config, pkgs, lib, ... }:

{
  imports = [
    ./topbar.nix
    ./plasma.nix
    ./environment.nix
    ./startup-scripts.nix
    ./startup-scripts.nix
    # ../qemu/graphics.nix <- Removed to allow bare-metal hardware drivers
  ];
}