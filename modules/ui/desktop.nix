{ config, pkgs, lib, ... }:

{
  imports = [
    ./topbar.nix
    ./plasma.nix
    ./environment.nix
    ./startup-scripts.nix
    ../qemu/graphics.nix
  ];
}