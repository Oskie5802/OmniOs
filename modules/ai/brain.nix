{ config, pkgs, ... }:

{
  # Tu w przyszłości dodasz:
  # - LanceDB (baza wektorowa)
  # - Twój Rust Daemon
  
  environment.systemPackages = with pkgs; [
    llama-cpp
    # python311Packages.huggingface-hub # Do pobierania modeli skryptami
  ];

  systemd.user.services.ai-brain = {
    description = "AI Inference Server (Gemma/Llama)";
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      # Placeholder: Tu w przyszłości będzie komenda startująca Twojego agenta
      ExecStart = "${pkgs.coreutils}/bin/true"; 
      
      # Restartuj proces AI jeśli padnie (ważne dla stabilności OS)
      Restart = "always";
      RestartSec = "5s";
    };
  };
}