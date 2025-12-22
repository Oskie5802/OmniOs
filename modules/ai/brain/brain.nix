{
  config,
  pkgs,
  lib,
  ...
}:

let

  # --- CONFIGURATION ---
  modelName = "Qwen3-0.6B-Q8_0.gguf";
  modelHash = "0cdh7c26vlcv4l3ljrh7809cfhvh2689xfdlkd6kbmdd48xfcrcl";
  modelUrl = "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf";

  # --- BAKED IN MODEL ---
  builtInModel = pkgs.fetchurl {
    url = modelUrl;
    sha256 = modelHash;
  };

  # --- PYTHON ENVIRONMENT ---
  brainPython = pkgs.python3.withPackages (
    ps: with ps; [
      lancedb
      sentence-transformers
      numpy
      pandas
      flask
      gunicorn
      llama-cpp-python
      requests
      simpleeval
      transformers
      torch
      protobuf
      accelerate
      sentencepiece
      huggingface-hub
    ]
  );

  # --- SERVER SCRIPT ---
  brainServerScript = pkgs.writeScriptBin "ai-brain-server" ''
    #!${brainPython}/bin/python
    ${builtins.readFile ./brain.py}
  '';
  # --- STARTUP WRAPPER ---
  brainWrapper = pkgs.writeShellScriptBin "start-brain-safe" ''
    export HF_TOKEN="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"
    export MODEL_FILENAME="${modelName}"
    mkdir -p "$HOME/.local/share/ai-models"
    DEST="$HOME/.local/share/ai-models/${modelName}"

    # Ensure symlink exists
    if [ ! -L "$DEST" ]; then
      ln -sf "${builtInModel}" "$DEST"
    fi

    exec ${brainServerScript}/bin/ai-brain-server
  '';

in
{
  environment.systemPackages = with pkgs; [ brainWrapper python3Packages.huggingface-hub ];
  services.ollama.enable = false;

  # --- SYSTEMD SERVICE ---
  systemd.user.services.ai-brain = {
    enable = true;
    description = "OmniOS Brain Native Server";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 15";
      ExecStart = "${brainWrapper}/bin/start-brain-safe";
      Restart = "always";
      RestartSec = 5;
      
      # --- RESOURCE PROTECTION ---
      CPUQuota = "150%";       # Max 1.5 cores (out of 4)
      MemoryHigh = "3072M";    # Throttle at 3GB
      MemoryMax = "4096M";     # Kill at 4GB
      
      Nice = 19;
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
      IOSchedulingPriority = 7;
    };
  };
}