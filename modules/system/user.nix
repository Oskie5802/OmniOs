{ config, pkgs, lib, ... }:

{
  users.users.omnios = {
    isNormalUser = true;
    description = "OmniOS Admin";
    extraGroups = [ "wheel" "networkmanager" "video" "input" ]; # input ważny dla gestów/AI
    initialPassword = "omnios"; 
  };

  # Auto-login konsolowy (wymuszenie)
  services.getty.autologinUser = lib.mkForce "omnios";
}