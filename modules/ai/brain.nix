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
    ]
  );

  # --- SERVER SCRIPT ---
  brainServerScript = pkgs.writeScriptBin "ai-brain-server" ''
    #!${brainPython}/bin/python
    import logging, sys, os, time, threading, json
    from flask import Flask, request, jsonify
    from llama_cpp import Llama
    import lancedb
    from sentence_transformers import SentenceTransformer
    import requests
    from simpleeval import SimpleEval

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
                n_ctx=4096, # Increased context for search results
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

    def perform_web_search(query):
        logging.info(f"Performing SearXNG Search for: {query}")
        try:
            # Query local SearXNG instance
            url = "http://127.0.0.1:8888/search"
            headers = {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
            params = {
                'q': query,
                'format': 'json',
                'categories': 'general',
                'language': 'en-US'
            }
            
            # Short timeout, it's local but upstream could be slow
            resp = requests.get(url, params=params, headers=headers, timeout=10)
            
            if resp.status_code != 200:
                logging.error(f"SearXNG returned status: {resp.status_code} - {resp.text[:100]}")
                return f"Error: Search engine returned {resp.status_code}. Please check configuration."

            resp.raise_for_status()
            
            data = resp.json()
            results = []
            
            # Parse JSON results
            for i, res in enumerate(data.get('results', [])):
                if i >= 4: break # Top 4 results
                title = res.get('title', 'No Title')
                url = res.get('url', ' '.strip())
                content = res.get('content', ' '.strip()) or res.get('snippet', ' '.strip())
                
                # Basic validation
                if content:
                    results.append(f"Source: {title} ({url})\nContent: {content}")
            
            if not results:
                return "No search results found via SearXNG."
                
            return "\n\n".join(results)
        except Exception as e:
            logging.error(f"SearXNG failed: {e}")
            return f"Search failed: {str(e)}"

    def perform_calculation(expression):
        logging.info(f"Performing Calculation for: {expression}")
        try:
            # 1. Clean up "Calculate..." text if present (simple heuristic)
            lower_input = expression.lower()
            for prefix in ["calculate ", "what is ", "solve "]:
                if lower_input.startswith(prefix):
                    expression = expression[len(prefix):]
            
            # 2. Allow only basic math chars to be safe
            # SimpleEval is safe by design, but cleaning helps parse
            
            s = SimpleEval()
            result = s.eval(expression)
            return (f"Expression: {expression}\n"
                    f"Result: {result}")
        except Exception as e:
            return f"Error calculating '{expression}': {str(e)}"

    @app.route('/ask', methods=['POST'])
    def ask():
        # Trigger load on first request
        ensure_models_loaded()

        if not llm:
            return jsonify({"answer": f"Error: Model failed to load. Reason: {init_error}"})

        try: req = request.get_json(force=True)
        except: return jsonify({"answer": "Error: Bad JSON"}), 400
        
        query = req.get('query', ' '.strip())
        
        # --- AUTOMONOUS DECISION ---
        # Classify query: 
        # 1. Personal Files (Notes, Code, Config)
        # 2. Internet (Current events, Facts, People, Weather)
        # 3. Casual (Chat, Logic, Coding help)
        # 4. Math/Calculation (Arithmetic, "What is 2+2")
        decision_prompt = (
            f"<|im_start|>system\nClassify the user input into one category:\n"
            f"1 = Needs local files (e.g. \"what's in my notes\", \"check my code\")\n"
            f"2 = Needs Internet Search (e.g. \"who is...\", \"weather...\", \"latest news\")\n"
            f"3 = Casual/General (e.g. \"hello\", \"explain quantum physics\", \"logic\")\n"
            f"4 = Math/Calculation (e.g. \"2+2\", \"15*24\", \"calculate sqrt(4)\")\n"
            f"Reply with JUST the number (1, 2, 3, or 4).<|im_end|>\n"
            f"<|im_start|>user\n{query}<|im_end|>\n"
            f"<|im_start|>assistant\nDecision:"
        )
        
        decision = "3" # Default to casual
        try:
            decision_output = llm(decision_prompt, max_tokens=3, stop=["<|im_end|>", "\n"])
            text = decision_output['choices'][0]['text'].strip()
            if "1" in text: decision = "1"
            elif "2" in text: decision = "2"
            elif "4" in text: decision = "4"
            else: decision = "3"
            logging.info(f"Decision for '{query}': {decision}")
        except:
            decision = "3"
        
        context_text = ""
        source_type = "None"
        
        # Execute Decision
        if decision == "1" and db_conn and embed_model:
            source_type = "Local Files"
            try:
                tbl = db_conn.open_table("files")
                res = tbl.search(embed_model.encode(query)).limit(3).to_pandas()
                if not res.empty:
                    for _, row in res.iterrows():
                        context_text += f"--- Local File: {row['filename']} ---\n{row['text'][:1500]}\n\n"
            except: pass
            
        elif decision == "2":
            source_type = "Internet"
            context_text = f"--- Web Search Results ---\n{perform_web_search(query)}\n"

        elif decision == "4":
            source_type = "Calculator"
            context_text = f"--- Calculation Result ---\n{perform_calculation(query)}\n"
        
        # Dynamic Prompt Rules
        # If we have context (Files or Search), force valid natural language answer.
        # If no context (Casual), allow App Launching JSON.
        launch_instruction = ""
        if not context_text:
            launch_instruction = (
                "4. **APP LAUNCHING:** If the user asks to 'open [app]' or 'launch [app]', return a JSON action: `{\"action\": \"launch\", \"app\": \"...\"}`. "
                "DO NOT use JSON for answering questions or searching."
            )

        # Prompt Construction
        prompt = (
            f"<|im_start|>system\nYou are Omni, a smart OS assistant.\n"
            f"Context Source: {source_type}\n"
            f"Context Data:\n{context_text or 'No context.'}\n\n"
            f"**RULES:**\n"
            f"1. If Context is provided, use it to answer the question accurately.\n"
            f"2. If the user asked a question that required a search/calc, the answer IS in the Data above.\n"
            f"3. Be concise and helpful. Do not mention 'system context' or 'search tool' explicitly, just answer naturally.\n"
            f"{launch_instruction}<|im_end|>\n"
            f"<|im_start|>user\n{query}<|im_end|>\n"
            f"<|im_start|>assistant\n<think>\n"
        )

        try:
            output = llm(
                prompt, max_tokens=1024, stop=["<|im_start|>", "<|im_end|>", "<|endoftext|>"], 
                echo=True, temperature=0.7
            )
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
