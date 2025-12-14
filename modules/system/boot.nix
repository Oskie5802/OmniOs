{ config, pkgs, lib, ... }:
let
  # Ensure these files are tracked by git!
  lightLogoPath = ../../assets/light.jpeg; 
  splashLogoPath = ../../assets/logo-trans.png; 

  customPlymouth = pkgs.stdenv.mkDerivation {
    name = "plymouth-omnios-theme";
    buildInputs = [ pkgs.imagemagick ];
    unpackPhase = "true";
    installPhase = ''
      mkdir -p $out/share/plymouth/themes/omnios
      
      # Convert to JPEG for stability
      ${pkgs.imagemagick}/bin/convert \
        ${lightLogoPath} \
        -resize 400x400 \
        -background black -gravity center -extent 1920x1080 \
        -flatten \
        -quality 90 \
        $out/share/plymouth/themes/omnios/background.jpg
      
      cat > $out/share/plymouth/themes/omnios/omnios.plymouth <<EOF
[Plymouth Theme]
Name=OmniOS
Description=OmniOS Boot Theme
ModuleName=script

[script]
ImageDir=$out/share/plymouth/themes/omnios
ScriptFile=$out/share/plymouth/themes/omnios/omnios.script
EOF

      cat > $out/share/plymouth/themes/omnios/omnios.script <<'EOF'
Window.GetMaxWidth = fun() { return 1920; };
Window.GetMaxHeight = fun() { return 1080; };
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);

logo.image = Image("background.jpg");
logo.sprite = Sprite(logo.image);
logo.sprite.SetX(Window.GetWidth() / 2 - logo.image.GetWidth() / 2);
logo.sprite.SetY(Window.GetHeight() / 2 - logo.image.GetHeight() / 2);
logo.sprite.SetOpacity(1);
logo.sprite.SetZ(1000);

spinner_image = Image.Text("●", 1, 1, 1);
spinner.sprite = Sprite(spinner_image);
spinner.sprite.SetX(Window.GetWidth() / 2);
spinner.sprite.SetY(Window.GetHeight() / 2 + 250);

angle = 0;
fun refresh_callback() {
  logo.sprite.SetOpacity(1);
  angle = angle + 0.1;
  spinner.sprite.SetRotation(angle);
}
Plymouth.SetRefreshFunction(refresh_callback);
EOF
    '';
  };

  customKdeSplash = pkgs.stdenv.mkDerivation {
    name = "omnios-kde-splash";
    buildInputs = [ pkgs.imagemagick ];
    unpackPhase = "true";
    installPhase = ''
      mkdir -p $out/share/plasma/look-and-feel/OmniOS-Splash/contents/splash/images
      
      # KDE Splash Image
      ${pkgs.imagemagick}/bin/convert \
        ${splashLogoPath} \
        -resize 400x400 \
        -background black -alpha remove -alpha off \
        $out/share/plasma/look-and-feel/OmniOS-Splash/contents/splash/images/logo.png

      cat > $out/share/plasma/look-and-feel/OmniOS-Splash/metadata.json <<EOF
{
    "KPlugin": {
        "Id": "OmniOS-Splash",
        "Name": "OmniOS Splash",
        "ServiceTypes": [ "Plasma/LookAndFeel" ]
    }
}
EOF

      cat > $out/share/plasma/look-and-feel/OmniOS-Splash/contents/splash/Splash.qml <<EOF
import QtQuick 2.0
Rectangle {
    id: root
    color: "black"
    anchors.fill: parent
    Image {
        source: "images/logo.png"
        anchors.centerIn: parent
        width: 400
        height: 400
        fillMode: Image.PreserveAspectFit
    }
}
EOF
    '';
  };
in
{
  environment.systemPackages = [ customKdeSplash ];

  # 1. Logs: Set to 3 (Error) instead of 0 (Silent) for safety
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;

  # 2. Kernel Params: Keep cursor hidden and quiet
  boot.kernelParams = [
    "quiet"
    "splash"
    "vt.global_cursor_default=0"
    "loglevel=3"
    "rd.systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
  ];

  # 3. Plymouth
  boot.plymouth = {
    enable = true;
    theme = "omnios";
    themePackages = [ customPlymouth ];
  };
  
  # 4. Systemd Silence
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.emergencyAccess = false;
  
  boot.initrd.systemd.settings.Manager = {
    ShowStatus = "no";
    DefaultStandardOutput = "journal";
    DefaultStandardError = "journal";
    LogLevel = "notice";
  };
  
  systemd.settings.Manager = {
    ShowStatus = "no";
    DefaultStandardOutput = "journal";
    DefaultStandardError = "journal";
    LogLevel = "notice";
  };
  
  # REMOVED: systemd.services.display-manager = { after = [ "plymouth-quit.service" ]; ... };
  # Removing this prevents the infinite black screen hang.

  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@".enable = false;
  
  environment.etc."os-release".text = lib.mkForce ''
    NAME="OmniOS"
    ID=omnios
    PRETTY_NAME="OmniOS AI-Native"
    ANSI_COLOR="1;34"
    HOME_URL="https://omnios.ai"
  '';

  environment.etc."xdg/ksplashrc".text = lib.mkForce ''
    [KSplash]
    Engine[$i]=KSplashQML
    Theme[$i]=OmniOS-Splash
  '';

  environment.etc."xdg/kdeglobals".text = lib.mkForce ''
    [Colors:Window]
    BackgroundNormal=0,0,0
  '';
}
