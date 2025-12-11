{ config, pkgs, lib, ... }:
{
  # --- 1. CONFIG VM ---
  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 4096;
      cores = 4;
      graphics = true;
      qemu.options = [
        "-vga virtio"
        "-display gtk,gl=on"
      ];
    };
  };

  # --- 2. PAKIETY ---
  environment.systemPackages = with pkgs; [
    kitty
    mesa
    libglvnd
    desktop-file-utils
  ];

  # --- 3. DISPLAY MANAGER - WAYLAND ENABLED ---
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "omnios";
  };

  services.displayManager.defaultSession = "hyprland";

  # --- 4. HYPRLAND ---
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # --- 5. ZMIENNE ŚRODOWISKOWE ---
  environment.sessionVariables = {
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
    WLR_NO_HARDWARE_CURSORS = "1";
    LIBGL_ALWAYS_SOFTWARE = "1";
    GALLIUM_DRIVER = "llvmpipe";
    NIXOS_OZONE_WL = "1";
  };

  # --- 6. KONFIGURACJA HYPRLAND ---
  environment.etc."hypr/hyprland.conf".text = ''
    monitor=Virtual-1,1920x1080@60,auto,1
    
    $mainMod = SUPER
    
    general {
      gaps_in = 5
      gaps_out = 10
      border_size = 2
      col.active_border = rgba(33ccffee)
      col.inactive_border = rgba(595959aa)
      layout = dwindle
    }
    ``
    decoration {
      rounding = 5
      blur {
        enabled = false
      }
      drop_shadow = no
    }
    
    animations {
      enabled = false
    }
    
    misc {
      disable_hyprland_logo = true
      disable_splash_rendering = true
      force_default_wallpaper = 0
    }
    
    # Bindy
    bind = $mainMod, Q, exec, kitty
    bind = $mainMod, M, exit
    bind = $mainMod, RETURN, exec, kitty
    
    # Exec na start
    exec-once = kitty
  '';

  # --- 7. BOOTLOADER ---
  boot.kernelParams = [ "quiet" ];

  # --- 8. DESKTOP ENTRY DLA FILE EXPLORERA ---
  
  # --- 9. SKOPIUJ PLIK .DESKTOP NA PULPIT ---
  system.activationScripts.createDesktopEntry = lib.mkAfter ''
  if [ -d /home/omnios ]; then
    mkdir -p /home/omnios/Desktop
  fi
'';

  # --- 10. GETTY NA KONSOLI SZEREGOWEJ (backup) ---
  systemd.services."serial-getty@ttyS0".enable = true;
}