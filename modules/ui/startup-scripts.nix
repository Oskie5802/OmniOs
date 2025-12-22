{ config, pkgs, lib, ... }:

{
  # --- SKRYPTY STARTOWE ---
  system.activationScripts.setupUserConfig = lib.mkAfter ''
    USER_HOME="${config.users.users.omnios.home}"
    CONFIG_DIR="$USER_HOME/.config"
    
    if [ -d "$USER_HOME" ]; then
      mkdir -p "$CONFIG_DIR/autostart"

      # A. SKRYPT: USTAWIENIE ROZDZIELCZOŚCI I TAPETY
      cat > "$CONFIG_DIR/autostart/fix-screen.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Fix Screen and Wallpaper
Exec=sh -c "sleep 8 && plasma-apply-wallpaperimage /etc/backgrounds/omnios-bg.png && kscreen-doctor output.Virtual-1.mode.1920x1080@60"
X-KDE-AutostartScript=true
EOF

      # B. KONFIGURACJA DOCKA (Usuwamy paski i tworzymy nowy)
      cat > "$USER_HOME/setup_dock.js" <<EOF
// Usuń stare panele
var allPanels = panels();
for (var i = 0; i < allPanels.length; i++) {
    allPanels[i].remove();
}

// Stwórz nowy "Dock"
var dock = new Panel();
dock.location = "bottom";
dock.height = 60;
dock.floating = true;
dock.alignment = "center";
dock.maximumLength = 800;
dock.minimumLength = 200;

// Dodaj widgety
dock.addWidget("org.kde.plasma.kickoff"); // Menu
dock.addWidget("org.kde.plasma.icontasks"); // Ikony aplikacji
dock.addWidget("org.kde.plasma.marginsseparator");
dock.addWidget("org.kde.plasma.systemtray");
dock.addWidget("org.kde.plasma.digitalclock");
EOF

      cat > "$CONFIG_DIR/autostart/setup-dock.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Setup Dock
Exec=sh -c "sleep 12 && (qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \"\$(cat $USER_HOME/setup_dock.js)\" || qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \"\$(cat $USER_HOME/setup_dock.js)\")"
X-KDE-AutostartScript=true
EOF

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

      chown -R ${config.users.users.omnios.name}:users "$USER_HOME"
    fi
  '';
}
