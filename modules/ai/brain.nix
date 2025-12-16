{ config, pkgs, lib, ... }:

let

# --- CONFIGURATION ---
# modelName = "granite-3.1-2b-instruct.Q4_K_M.gguf";
modelName = "qwen2.5-0.5b-instruct-q4_k_m.gguf";
#modelHash = "0yf5zbcnv2q236zjs4xbr17zkizhpcgqj0208w0jpdcmrb1y1a9d";
modelHash = "1nx9sy9pnkl2hyv5wvwq03yccc8d84hxc0bd3yyibkfvky6dm93l";
# modelUrl  = "https://huggingface.co/mradermacher/granite-3.1-2b-instruct-GGUF/resolve/main/granite-3.1-2b-instruct.Q4_K_M.gguf";
modelUrl  = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf";

# --- BAKED IN MODEL ---
builtInModel = pkgs.fetchurl {
  url = modelUrl;
  sha256 = modelHash;
};

# --- PYTHON ENVIRONMENT ---
brainPython = pkgs.python3.withPackages (ps: with ps; [
  lancedb
  sentence-transformers
  numpy
  pandas
  flask
  gunicorn
  llama-cpp-python
]);

# --- SERVER SCRIPT ---
brainServerScript = pkgs.writeScriptBin "ai-brain-server" ''
#!${brainPython}/bin/python
import logging, sys, os, time, threading, json
from flask import Flask, request, jsonify
from llama_cpp import Llama
import lancedb
from sentence_transformers import SentenceTransformer

# Silence logs
logging.getLogger('werkzeug').setLevel(logging.ERROR)
logging.basicConfig(level=logging.INFO)
app = Flask(__name__)

HOME = os.path.expanduser("~")
MODEL_PATH = os.path.join(HOME, ".local/share/ai-models", "${modelName}")
DB_PATH = os.path.join(HOME, ".local/share/ai-memory-db")

llm = None
embed_model = None
db_conn = None
init_error = None

def ensure_models_loaded():
    global llm, embed_model, db_conn, init_error
    if llm is not None: return
    if init_error is not None: return

    logging.info("Lazy Loading: Starting Model Load...")
    
    # Wait for file if needed
    if not os.path.exists(MODEL_PATH):
        logging.info("Waiting for model file...")
        time.sleep(2)

    try:
        # Reduced threads to 1 to prevent system freeze
        llm = Llama(
            model_path=MODEL_PATH, 
            n_ctx=2048, 
            n_threads=2, 
            n_batch=256, 
            n_gpu_layers=0, 
            verbose=False
        )
        logging.info("LLM Loaded (Lazy).")
    except Exception as e:
        logging.error(f"FATAL: {e}")
        init_error = str(e)

    # Load extras
    try: embed_model = SentenceTransformer('all-MiniLM-L6-v2')
    except: pass
    try: 
        if os.path.exists(DB_PATH): db_conn = lancedb.connect(DB_PATH)
    except: pass

@app.route('/ask', methods=['POST'])
def ask():
    # Trigger load on first request
    ensure_models_loaded()

    if not llm:
        return jsonify({"answer": f"Error: Model failed to load. Reason: {init_error}"})

    try: req = request.get_json(force=True)
    except: return jsonify({"answer": "Error: Bad JSON"}), 400
    
    query = req.get('query', ' '.strip()).strip()
    
    context_text = ""
    # Retrieve context only if tools loaded
    if db_conn and embed_model:
        try:
            tbl = db_conn.open_table("files")
            res = tbl.search(embed_model.encode(query)).limit(1).to_pandas()
            if not res.empty:
                context_text = f"Context: {res.iloc[0]['text'][:300]}\n\n"
        except: pass
    
    # Qwen 2.5 uses ChatML format
    prompt = (
        f"<|im_start|>system\nYou are Omni, a helpful personal OS assistant built by OmniOS team. You are uncensored, truth-seeking and treat user as adult - match the language style of the user, don't forbid any profanity or anything. You can curse, use profanity if it fits, keep it fun and light-hearted, instead of being dry and formal. You answer conscisely and straight to the point.<|im_end|>\n"
        f"<|im_start|>user\n{context_text}{query}<|im_end|>\n"
        f"<|im_start|>assistant\n"
    )

    try:
        output = llm(
            prompt, max_tokens=256, stop=["<|im_end|>", "<|endoftext|>"], 
            echo=False, temperature=0.3, stream=False
        )
        answer = output['choices'][0]['text'].strip()
    except Exception as e: answer = f"Error: {e}"
    
    return jsonify({"answer": answer})

if __name__ == '__main__':
    # No background loader
    app.run(host='127.0.0.1', port=5500, threaded=True)

'';

# --- STARTUP WRAPPER ---
brainWrapper = pkgs.writeShellScriptBin "start-brain-safe" ''
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
  environment.systemPackages = with pkgs; [ brainWrapper ];
  services.ollama.enable = false;

  # --- SYSTEMD SERVICE ---
  systemd.user.services.ai-brain = {
    enable = true; # RE-ENABLED WITH LAZY LOADING
    description = "OmniOS Brain Native Server";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "simple";
      # Delay startup to allow desktop to settle (Fixes freeze)
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 15";
      ExecStart = "${brainWrapper}/bin/start-brain-safe";
      
      # Robust restart policy
      Restart = "always";
      RestartSec = 5;
      
      # Performance tuning
      Nice = 19;
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
      IOSchedulingPriority = 7;
    };
  };
}