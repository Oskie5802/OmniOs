{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Core utils
    git
    wget
    curl
    vim
    
    # Terminal & UI Utils
    kitty
    jq # Do parowania JSONów z AI w bashu (tymczasowo)
  ];
  
  # Włączenie czcionek (ważne, żeby Hyprland miał ikony)
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    font-awesome
  ];
}