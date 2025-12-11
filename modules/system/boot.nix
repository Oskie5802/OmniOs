{ config, pkgs, lib, ... }:

{
  # USUŃ TO: system.configurationName = "OmniOS";

  # Bootloader
  boot.loader.timeout = lib.mkForce 0;
  
  # Silent Boot
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
  
  boot.kernelParams = [
    "quiet"
    "splash"
    "boot.shell_on_fail"
    "loglevel=3"
    "rd.systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
    "vt.global_cursor_default=0"
  ];

  # Wymuszenie własnej nazwy w pliku /etc/os-release (to działa)
  environment.etc."os-release".text = lib.mkForce ''
    NAME="OmniOS"
    ID=omnios
    PRETTY_NAME="OmniOS AI-Native"
    ANSI_COLOR="1;34"
    HOME_URL="https://omnios.ai"
  '';
}