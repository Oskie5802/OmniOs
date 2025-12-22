{ pkgs, config, lib, ... }:

let
  # 1. SETUP: Python with requests app and PyQt6
  omniPython = pkgs.python3.withPackages (ps: with ps; [ requests pyqt6 ]);

  # --- 2. LOGIC & UI (Custom Qt Launcher) ---
  omniLauncher = pkgs.writeScriptBin "omni-launcher" ''
    export OMNI_LOGO="${../../../assets/logo-trans.png}"
    export OMNI_STYLE="${./omni.css}"
    ${omniPython}/bin/python ${./omni.py}
  '';

  # --- 3. WRAPPER ---
  openOmniScript = pkgs.writeShellScriptBin "open-omni" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.xclip}/bin:${pkgs.kdePackages.kservice}/bin:${pkgs.libnotify}/bin:$PATH"
    ${omniLauncher}/bin/omni-launcher
  '';

  omniDesktopItem = pkgs.makeDesktopItem {
    name = "omni-bar";
    desktopName = "Omni";
    genericName = "Universal Search & AI";
    comment = "Your intelligent companion for search and system control";
    exec = "${openOmniScript}/bin/open-omni";
    icon = "${../../../assets/logo-trans.png}";
    categories = [ "Utility" ];
  };

in
{
  environment.systemPackages = with pkgs; [
    omniLauncher omniDesktopItem xclip libnotify kdePackages.kservice papirus-icon-theme fd dex
  ];
  # Manrope: A modern, geometric sans-serif that is excellent for UI clarity and style.
  fonts.packages = with pkgs; [ manrope ];
}