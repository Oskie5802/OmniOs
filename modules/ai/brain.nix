{ config, pkgs, lib, ... }:

let

# --- CONFIGURATION ---
modelName = "Qwen3-0.6B-Q8_0.gguf";
modelHash = "0cdh7c26vlcv4l3ljrh7809cfhvh2689xfdlkd6kbmdd48xfcrcl";
modelUrl  = "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf";

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
    
    # Always try to connect to DB if missing (files might be created later)
    if db_conn is None:
        try: 
            if os.path.exists(DB_PATH): 
                db_conn = lancedb.connect(DB_PATH)
                logging.info("Lazy Loading: DB Connected.")
            else:
                logging.warning(f"DB Path not found: {DB_PATH}")
                # Store this for debug
                init_error = f"DB Path not found: {DB_PATH}"
        except Exception as e:
            logging.error(f"DB Connect Error: {e}")
            init_error = f"DB Connect Error: {e}"

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
    
    # --- AUTOMONOUS DECISION: AI decides if context is needed ---
    # Fast micro-pass to classify query: 1 = Personal/Factual (needs files), 2 = Casual/Generic
    decision_prompt = f"<|im_start|>system\nDecision: 1 (Needs personal files) or 2 (Casual chat).<|im_end|>\n<|im_start|>user\n{query}<|im_end|>\n<|im_start|>assistant\nDecision:"
    try:
        decision_output = llm(decision_prompt, max_tokens=3, stop=["<|im_end|>", "\n"])
        need_context = "1" in decision_output['choices'][0]['text']
    except:
        need_context = True # Fallback to search if decision fails
    
    context_text = ""
    # Retrieve context only if AI decided it's needed
    if db_conn and embed_model and need_context:
        try:
            tbl = db_conn.open_table("files")
            res = tbl.search(embed_model.encode(query)).limit(3).to_pandas()
            if not res.empty:
                for _, row in res.iterrows():
                    context_text += f"--- Context from {row['filename']} ---\n{row['text'][:1500]}\n\n"
        except: pass
    
    # Dynamic instructional boost: if context exists, forbid actions
    action_instruction = (
        "**PERSONAL INFO FOUND:** Answer strictly using the context above. DO NOT use JSON actions. Answer as a conversational human." 
        if context_text else 
        "**ACTION CAPABILITIES:** If the user asks to 'open [app]' or 'search the web for [topic]', you MUST use JSON. Example: `{\"action\": \"browse\", \"url\": \"https://www.google.com/search?q=actual_topic\"}`. NEVER use the word 'query' as the search term."
    )

    prompt = (
        f"<|im_start|>system\nYou are Omni, a fast OS assistant. "
        f"You have access to the user's files via Context. Treat Context as your own memory.\n\n"
        f"**RULES:**\n"
        f"1. If Context contains the answer, you MUST answer directly. DO NOT trigger a web search or app launch.\n"
        f"2. {action_instruction}\n"
        f"3. Be extremely concise. Use a helpful, conversational tone.<|im_end|>\n"
        f"<|im_start|>user\nContext Info:\n{context_text or 'No context provided.'}\n\nQuestion: {query}<|im_end|>\n"
        f"<|im_start|>assistant\n<think>\n"
    )

    try:
        output = llm(
            prompt, max_tokens=384, stop=["<|im_start|>", "<|im_end|>", "<|endoftext|>"], 
            echo=True, temperature=0.0 # Echo=True because we start the assistant with <think>
        )
        # Process output to get ONLY the assistant's part (it will include our prefixed <think>)
        full_result = output['choices'][0]['text']
        answer = full_result.split("<|im_start|>assistant\n")[-1].strip()
    except Exception as e: answer = f"Error: {e}"
    
    return jsonify({"answer": answer})

@app.route('/search', methods=['POST'])
def search_endpoint():
    ensure_models_loaded()
    if not db_conn or not embed_model:
        return jsonify({"results": []})

    try: req = request.get_json(force=True)
    except: return jsonify({"results": []}), 400
    
    query = req.get('query', "").strip()
    if not query: return jsonify({"results": []})

    results = []
    try:
        tbl = db_conn.open_table("files")
        # Search top 3 semantic matches with distance threshold
        # Distance < 1.1 is usually a good threshold for MiniLM similarity
        res = tbl.search(embed_model.encode(query)).limit(3).to_pandas()
        if not res.empty:
            for _, row in res.iterrows():
                if row.get('_distance', 0) < 1.1:
                    results.append({
                        "name": row['filename'],
                        "path": row['path'],
                        "score": float(row.get('_distance', 0)),
                        "type": "file"
                    })
    except Exception as e:
        logging.error(f"Search error: {e}")

    return jsonify({"results": results})

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