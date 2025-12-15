{ config, pkgs, lib, ... }:

let
  # --- macOS Light Theme Palette ---
  colors = {
    bg = "rgba(255, 255, 255, 0.65)"; # Glassy White
    bgDock = "rgba(255, 255, 255, 0.85)";
    fg = "#000000";
    fgDim = "#4a4a4a";
    accent = "#007AFF"; # Apple Blue
    border = "rgba(0, 0, 0, 0.1)";
    hover = "rgba(0, 0, 0, 0.05)";
  };

  # --- Top Bar Configuration ---
  topBarConfig = {
    name = "topbar";
    layer = "top";
    position = "top";
    height = 32;
    spacing = 4;
    
    # Full width, no margins
    margin-top = 0;
    margin-left = 0;
    margin-right = 0;

    modules-left = [ "custom/logo" "custom/spacer" "wlr/taskbar" ]; # Keep taskbar for now as window switcher
    modules-center = [ "clock" ];
    modules-right = [ "group/status" "custom/control" ];

    "custom/logo" = {
      format = "  "; # Apple logo or similar
      tooltip = false;
      on-click = "${pkgs.kdePackages.krunner}/bin/krunner";
    };
    
    "custom/spacer" = {
      format = "|";
    };

    "clock" = {
      format = "{:%a %d %b  %H:%M}";
      tooltip-format = "<tt><small>{calendar}</small></tt>";
    };

    "group/status" = {
      orientation = "horizontal";
      modules = [ "network" "bluetooth" "battery" ];
    };

    "network" = {
      format-wifi = "";
      format-ethernet = "";
      format-disconnected = "";
      tooltip-format = "{essid}";
      on-click = "${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw";
    };

    "bluetooth" = {
      format = "";
      on-click = "${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw";
    };

    "battery" = {
      format = "{icon}";
      format-icons = ["" "" "" "" ""];
    };

    "custom/control" = {
      format = "  ";
      tooltip = false;
      on-click = "${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw";
    };
  };

  # --- Dock Configuration ---
  dockConfig = {
    name = "dock";
    layer = "top";
    position = "bottom";
    height = 50;
    margin-bottom = 12;
    
    modules-center = [ 
      "custom/files" 
      "custom/browser" 
      "custom/terminal" 
      "custom/settings" 
    ];

    "custom/files" = {
      format = "";
      tooltip = "Files";
      on-click = "dolphin";
    };
    "custom/browser" = {
      format = "";
      tooltip = "Web";
      on-click = "firefox"; # Assuming firefox is installed
    };
    "custom/terminal" = {
      format = "";
      tooltip = "Terminal";
      on-click = "konsole";
    };
    "custom/settings" = {
      format = "";
      tooltip = "Settings";
      on-click = "systemsettings";
    };
  };

  # Combine configs
  waybarConfig = [ topBarConfig dockConfig ];

  # --- Waybar CSS ---
  waybarStyle = ''
    * {
      font-family: "Inter", "Font Awesome 6 Free", sans-serif;
      font-size: 14px;
      font-weight: 500;
    }

    /* --- TOP BAR STYLES --- */
    window#waybar.topbar {
      background: ${colors.bg};
      color: ${colors.fg};
      border-bottom: 1px solid ${colors.border};
    }

    window#waybar.topbar .modules-right {
      margin-right: 10px;
    }
    
    window#waybar.topbar .modules-left {
      margin-left: 10px;
    }

    #custom-logo {
      font-size: 18px;
      padding: 0 10px;
    }
    
    #custom-spacer {
      color: ${colors.border};
      padding: 0 5px;
    }

    #clock {
      font-weight: 600;
    }

    #network, #bluetooth, #battery {
      padding: 0 8px;
      color: ${colors.fgDim};
    }

    #custom-control {
      background: ${colors.hover};
      border-radius: 6px;
      padding: 2px 8px;
      margin-left: 8px;
    }

    /* --- DOCK STYLES --- */
    window#waybar.dock {
      background: ${colors.bgDock};
      border: 1px solid ${colors.border};
      border-radius: 16px;
      color: ${colors.fg};
    }
    
    window#waybar.dock .modules-center {
      padding: 0 15px;
    }

    #custom-files, #custom-browser, #custom-terminal, #custom-settings {
      font-size: 24px;
      padding: 0 15px;
      margin: 5px 0;
      border-radius: 8px;
      transition: all 0.2s ease;
      color: ${colors.fgDim};
    }

    #custom-files:hover, #custom-browser:hover, #custom-terminal:hover, #custom-settings:hover {
      background: ${colors.accent};
      color: #ffffff;
      box-shadow: 0 4px 6px rgba(0,0,0,0.1);
    }
  '';

  # --- SwayNC Config (Adapted for Light Mode) ---
  swayncConfig = {
    positionX = "right";
    positionY = "top";
    layer = "overlay";
    control-center-layer = "top";
    control-center-margin-top = 10;
    control-center-margin-bottom = 10;
    control-center-margin-right = 10;
    control-center-margin-left = 10;
    widgets = [ "title" "buttons-grid" "volume" "backlight" "dnd" ];
    widget-config = {
      title = { text = "Control Center"; clear-all-button = true; button-text = "Clear"; };
      buttons-grid = {
        actions = [
            { label = "Wi-Fi"; command = "kcmshell6 kcm_networkmanagement"; }
            { label = "Bluetooth"; command = "kcmshell6 kcm_bluetooth"; }
            { label = "Settings"; command = "systemsettings"; }
            { label = "Display"; command = "kcmshell6 kcm_kscreen"; }
        ];
      };
    };
  };

  swayncStyle = ''
    * { font-family: "Inter", sans-serif; }
    .control-center {
      background: rgba(255, 255, 255, 0.9);
      border: 1px solid #e5e7eb;
      border-radius: 16px;
      padding: 16px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.1);
    }
    .widget-title { color: #000; font-weight: bold; margin-bottom: 12px; font-size: 16px; }
    .widget-title > button { background: #f3f4f6; color: #4b5563; border: none; border-radius: 8px; padding: 6px 12px; }
    
    .widget-buttons-grid > flowbox > flowboxchild > button {
      background: #f3f4f6; color: #000; border-radius: 12px; margin: 4px; padding: 12px; border: none;
    }
    .widget-buttons-grid > flowbox > flowboxchild > button:hover {
      background: #007AFF; color: #fff;
    }
    
    .widget-volume, .widget-backlight { background: #f3f4f6; border-radius: 12px; padding: 12px; margin: 8px 0; }
    trough { background: #e5e7eb; border-radius: 6px; min-height: 6px; }
    highlight { background: #007AFF; border-radius: 6px; }
    slider { background: #fff; border: 1px solid #e5e7eb; border-radius: 50%; }
  '';

  wbConfig = pkgs.writeText "waybar-config" (builtins.toJSON waybarConfig);
  wbStyle = pkgs.writeText "waybar-style" waybarStyle;
  sncConfig = pkgs.writeText "swaync-config" (builtins.toJSON swayncConfig);
  sncStyle = pkgs.writeText "swaync-style" swayncStyle;

in
{
  environment.systemPackages = with pkgs; [ 
    waybar 
    swaynotificationcenter 
    font-awesome 
    libnotify 
    networkmanagerapplet
    bibata-cursors
  ];

  environment.etc."xdg/waybar/config".source = wbConfig;
  environment.etc."xdg/waybar/style.css".source = wbStyle;
  environment.etc."xdg/swaync/config.json".source = sncConfig;
  environment.etc."xdg/swaync/style.css".source = sncStyle;

  system.activationScripts.setupUI = lib.mkAfter ''
    USER_HOME="/home/omnios"
    cat > "$USER_HOME/start-ui.sh" <<EOF
#!/bin/sh
pkill waybar
pkill swaync
${pkgs.swaynotificationcenter}/bin/swaync &
sleep 1
${pkgs.waybar}/bin/waybar &
EOF
    chmod +x "$USER_HOME/start-ui.sh"
  '';
}
