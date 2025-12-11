{ pkgs, ... }:

let
  # Definiujemy ścieżkę do Twojej tapety
  # Nix "zamrozi" ten plik w systemie plików (w /nix/store/...)
  wallPath = ../../assets/bg.png; 
in
{
  # 1. Sprawiamy, że tapeta jest dostępna w systemie w stałym miejscu
  # Skopiujemy ją do /usr/share/backgrounds/omnios-bg.png (dla wygody)
  environment.etc."backgrounds/omnios-bg.png".source = wallPath;

  # 2. Ustawiamy tapetę w ekranie logowania (SDDM)
  services.displayManager.sddm = {
    theme = "breeze"; # Można zmienić na inny, ale breeze jest standardem w KDE/SDDM
    settings = {
        Theme = {
            Current = "breeze";
            # W niektórych tematach SDDM ścieżka do tapety ustawiana jest tak:
            Background = "/etc/backgrounds/omnios-bg.png";
        };
    };
  };
}