{ config, pkgs, lib, ... }:

{
  # --- SKRYPTY STARTOWE ---
  system.activationScripts.setupUserConfig = lib.mkAfter ''
    USER_HOME="/home/omnios"
    CONFIG_DIR="$USER_HOME/.config"
    
    if [ -d "$USER_HOME" ]; then
      mkdir -p "$CONFIG_DIR/autostart"

      # A. SKRYPT: USTAWIENIE ROZDZIELCZOŚCI I TAPETY
      # Używamy kscreen-doctor do wymuszenia 1920x1080 po załadowaniu pulpitu
      # CAUSES FREEZE - DISABLED
      # cat > "$CONFIG_DIR/autostart/fix-screen.desktop" <<EOF
      # [Desktop Entry]
      # Type=Application
      # Name=Fix Screen and Wallpaper
      # # Czekamy 5 sekund aż Plasma wstanie, ustawiamy tapetę i wymuszamy rozdzielczość
      # Exec=sh -c "sleep 5 && plasma-apply-wallpaperimage /etc/backgrounds/omnios-bg.png && kscreen-doctor output.Virtual-1.mode.1920x1080@60"
      # X-KDE-AutostartScript=true
      # EOF
 
      # B. CZYSZCZENIE UKŁADU (Usuwanie dolnego paska KDE)
      # CAUSES FREEZE - DISABLED
      # cat > "$USER_HOME/clean_layout.js" <<EOF
      # var allPanels = panels();
      # for (var i = 0; i < allPanels.length; i++) {
      #     allPanels[i].remove();
      # }
      # EOF
 
      # cat > "$CONFIG_DIR/autostart/cleanup-panels.desktop" <<EOF
      # [Desktop Entry]
      # Type=Application
      # Name=Cleanup Panels
      # Exec=qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$USER_HOME/clean_layout.js"
      # X-KDE-AutostartScript=true
      # EOF

      # B. KONFIGURACJA SKRÓTU: CTRL + SPACJA
      # Edytujemy plik kglobalshortcutsrc
      
      ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
        --file "$CONFIG_DIR/kglobalshortcutsrc" \
        --group "omni-bar.desktop" \
        --key "_k_friendly_name" "Omni Bar"
        
      # ZMIANA: Ustawiamy Ctrl+Space
      ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
        --file "$CONFIG_DIR/kglobalshortcutsrc" \
        --group "omni-bar.desktop" \
        --key "_launch" "Ctrl+Space,none,Open Omni Bar"

      # C. SKRYPT POMOCNICZY (FIX)
      # Aktualizujemy też skrypt ręczny, żeby w razie czego ustawił Ctrl+Space
      mkdir -p "$USER_HOME/bin"
      cat > "$USER_HOME/bin/fix-omni" <<EOF
#!/bin/sh
echo "🔧 Setting Omni Key to Ctrl+Space..."
pkill kglobalaccel
kwriteconfig6 --file ~/.config/kglobalshortcutsrc --group "omni-bar.desktop" --key "_launch" "Ctrl+Space,none,Open Omni Bar"
echo "✅ Done. Try pressing Ctrl + Space."
EOF
      chmod +x "$USER_HOME/bin/fix-omni"

      chown -R omnios:users "$USER_HOME"
    fi
  '';
}
