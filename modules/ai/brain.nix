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
    import logging, sys, os, time, threading, json
    from flask import Flask, request, jsonify
    import requests
    from simpleeval import SimpleEval

    # Silence logs
    logging.getLogger('werkzeug').setLevel(logging.ERROR)
    logging.basicConfig(level=logging.INFO)
    app = Flask(__name__)

    HOME = os.path.expanduser("~")
    MODEL_PATH = os.path.join(HOME, ".local/share/ai-models", "${modelName}")
    DB_PATH = os.path.join(HOME, ".local/share/ai-memory-db")
    SEARXNG_URL = "http://127.0.0.1:8888/search"

    llm = None
    embed_model = None
    db_conn = None
    init_error = None
    
    # Thread Lock
    model_lock = threading.Lock()
    
    # Fast Action Model (GGUF)
    fast_model = None
    fast_loading_started = False
    fast_model_error = None
    FAST_REPO_ID = "bartowski/google_gemma-3-270m-it-GGUF"
    FAST_FILENAME = "google_gemma-3-270m-it-Q8_0.gguf"

    # --- SHORTCUTS ---
    # These override the AI for instant speed on common queries
    COMMON_SHORTCUTS = {
        "yt": "https://www.youtube.com",
        "gh": "https://github.com",
        "tw": "https://twitter.com",
        "red": "https://reddit.com",
        "hm": "https://home-manager-options.ext",
        "nix": "https://search.nixos.org/packages",
        "map": "https://www.google.com/maps",
        "chat": "https://chatgpt.com"
    }

    def _load_fast_thread():
        global fast_model, fast_model_error
        
        with model_lock:
             if fast_model: return
             try:
                 logging.info(f"Loading Fast Action Model (GGUF): {FAST_FILENAME}...")
                 from huggingface_hub import hf_hub_download
                 from llama_cpp import Llama
                 
                 model_path = hf_hub_download(
                     repo_id=FAST_REPO_ID, 
                     filename=FAST_FILENAME
                 )
                 
                 # Load Llama with 1 thread for safety/speed balance on small model
                 fast_model = Llama(
                     model_path=model_path, 
                     n_ctx=1024, 
                     n_threads=1, 
                     verbose=False
                 )
                 logging.info("Fast Action Model Loaded (GGUF).")
                 fast_model_error = None
             except Exception as e:
                 logging.error(f"Failed to load Fast Action Model: {e}")
                 fast_model_error = str(e)

    def ensure_fast_model():
        global fast_loading_started
        if fast_model: return
        
        # Start background load if not running
        if not fast_loading_started:
            fast_loading_started = True
            threading.Thread(target=_load_fast_thread, daemon=True).start()

    def ensure_main_model():
        global llm, embed_model, db_conn, init_error
        
        # Fast check
        if llm: return
        if init_error: return

        with model_lock:
            if llm: return
            if init_error: return

            logging.info("Lazy Loading: Starting Main Model Load...")
            
            # --- DB Connection (Fast) ---
            if db_conn is None:
                try: 
                    if os.path.exists(DB_PATH): 
                        import lancedb
                        db_conn = lancedb.connect(DB_PATH)
                        logging.info("Lazy Loading: DB Connected.")
                except Exception as e:
                    logging.error(f"DB Connect Error: {e}")

            # --- LAZY IMPORTS ---
            try:
                from llama_cpp import Llama
                from sentence_transformers import SentenceTransformer
            except Exception as e:
                 logging.error(f"Import Error: {e}")
                 init_error = f"Import Error: {e}"
                 return

            # --- LOAD LLM ---
            if not os.path.exists(MODEL_PATH):
                logging.info("Waiting for model file...")
                time.sleep(2)

            try:
                llm = Llama(
                    model_path=MODEL_PATH, 
                    n_ctx=4096,
                    n_threads=1, 
                    n_batch=256, 
                    n_gpu_layers=0, 
                    verbose=False
                )
                logging.info("LLM Loaded (Lazy).")
            except Exception as e:
                logging.error(f"FATAL: {e}")
                init_error = str(e)
                return

            # --- LOAD EMBEDDINGS ---
            try: 
                global embed_model
                embed_model = SentenceTransformer('all-MiniLM-L6-v2')
            except: pass

    def perform_web_search(query):
        """Full search for Context (Chat)"""
        logging.info(f"Performing SearXNG Search for: {query}")
        try:
            params = {
                'q': query,
                'format': 'json',
                'categories': 'general',
            }
            resp = requests.get(SEARXNG_URL, params=params, timeout=10)
            if resp.status_code != 200: return f"Error: Search status {resp.status_code}."

            data = resp.json()
            results = []
            
            for i, res in enumerate(data.get('results', [])):
                if i >= 4: break
                title = res.get('title', 'No Title')
                url = res.get('url', ' ')
                content = res.get('content', ' '.strip()) or res.get('snippet', ' '.strip())
                if content:
                    results.append(f"Source: {title} ({url})\nContent: {content}")
            
            if not results: return "No search results found."
            return "\n\n".join(results)
        except Exception as e:
            return f"Search failed: {str(e)}"

    def get_navigation_result(query):
        """Quick search for Action (Navigation) returning Rich metadata"""
        try:
            # We use a short timeout because this happens in the UI loop
            params = {'q': query, 'format': 'json'}
            resp = requests.get(SEARXNG_URL, params=params, timeout=2.0)
            if resp.status_code == 200:
                results = resp.json().get('results', [])
                if results:
                    first = results[0]
                    return {
                        "url": first.get('url'),
                        "title": first.get('title', 'Link'),
                        "description": first.get('content') or first.get('snippet', ' '.strip())
                    }
        except Exception as e:
            logging.error(f"Quick URL lookup failed: {e}")
        return None

    def get_person_result(name):
        """Search for a Person and return rich card details (Image context)"""
        logging.info(f"DEBUG: get_person_result called for '{name}'")
        try:
            # 1. Search for the most likely Wikipedia Page
            params = {'q': f"{name} wikipedia", 'format': 'json', 'categories': 'general', 'language': 'en-US'}
            resp = requests.get(SEARXNG_URL, params=params, timeout=5.0)
            
            wiki_title = None
            wiki_url = None
            
            if resp.status_code == 200:
                results = resp.json().get('results', [])
                for res in results:
                    url = res.get('url', ' '.strip())
                    if "wikipedia.org/wiki/" in url:
                        wiki_url = url
                        # Extract title from URL (last part)
                        wiki_title = url.split("wikipedia.org/wiki/")[-1]
                        break
            
            # 2. If we found a Wiki page, use the Official Wiki API for clean data
            if wiki_title:
                try:
                    logging.info(f"Fetching Wiki Summary for: {wiki_title}")
                    # Standard Wikipedia REST API
                    api_url = f"https://en.wikipedia.org/api/rest_v1/page/summary/{wiki_title}"
                    api_resp = requests.get(api_url, timeout=5.0)
                    
                    if api_resp.status_code == 200:
                        data = api_resp.json()
                        return {
                            "type": "person",
                            "name": data.get('title', name),
                            "description": data.get('extract', 'No description available.'),
                            "url": wiki_url,
                            "image": data.get('thumbnail', {}).get('source')
                        }
                except Exception as e:
                    logging.error(f"Wiki API failed: {e}")

            # 3. Fallback: Generic Search (if no wiki found or api failed)
            logging.info("Falling back to generic search for person...")
            params = {'q': name, 'format': 'json', 'categories': 'general', 'language': 'en-US'}
            resp = requests.get(SEARXNG_URL, params=params, timeout=5.0)
            
            if resp.status_code == 200:
                results = resp.json().get('results', [])
                if results:
                    best = results[0]
                    # Try to get an image via image search
                    image_url = None
                    try:
                        img_search = requests.get(SEARXNG_URL, params={'q': name, 'format': 'json', 'categories': 'images'}, timeout=4.0)
                        if img_search.status_code == 200:
                             imgs = img_search.json().get('results', [])
                             if imgs: image_url = imgs[0].get('thumbnail_src') or imgs[0].get('url')
                    except: pass
                    
                    return {
                        "type": "person",
                        "name": best.get('title', name),
                        "description": best.get('content') or best.get('snippet', ' '.strip()),
                        "url": best.get('url'),
                        "image": image_url
                    }

        except Exception as e:
             logging.error(f"Person lookup failed: {e}")
        return None


    def perform_calculation(expression):
        logging.info(f"Performing Calculation for: {expression}")
        try:
            lower_input = expression.lower()
            for prefix in ["calculate ", "what is ", "solve "]:
                if lower_input.startswith(prefix):
                    expression = expression[len(prefix):]
            
            s = SimpleEval()
            result = s.eval(expression)
            return (f"Expression: {expression}\n"
                    f"Result: {result}")
        except Exception as e:
            return f"Error calculating '{expression}': {str(e)}"

    @app.route('/ask', methods=['POST'])
    def ask():
        # Trigger load on first request
        ensure_main_model()

        if not llm:
            return jsonify({"answer": f"Error: Model failed to load. Reason: {init_error}"})

        try: req = request.get_json(force=True)
        except: return jsonify({"answer": "Error: Bad JSON"}), 400
        
        query = req.get('query', ' '.strip())
        logging.info(f"Received /ask query: {query}")
        
        # --- AUTOMONOUS DECISION ---
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
        
        decision = "3" 
        try:
            logging.info("Deciding category...")
            with model_lock:
                decision_output = llm(decision_prompt, max_tokens=3, stop=["<|im_end|>", "\n"])
            text = decision_output['choices'][0]['text'].strip()
            logging.info(f"Category decided: {text}")
            if "1" in text: decision = "1"
            elif "2" in text: decision = "2"
            elif "4" in text: decision = "4"
            else: decision = "3"
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
        
        launch_instruction = ""
        if not context_text:
            launch_instruction = (
                "4. **APP LAUNCHING:** If the user asks to 'open [app]' or 'launch [app]', return a JSON action: `{\"action\": \"launch\", \"app\": \"...\"}`. "
                "DO NOT use JSON for answering questions or searching."
            )

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
            logging.info("Generating answer...")
            with model_lock:
                output = llm(
                    prompt, max_tokens=1024, stop=["<|im_start|>", "<|im_end|>", "<|endoftext|>"], 
                    echo=True, temperature=0.7
                )
            logging.info("Answer generated.")
            full_result = output['choices'][0]['text']
            answer = full_result.split("<|im_start|>assistant\n")[-1].strip()
        except Exception as e: answer = f"Error: {e}"
        
        return jsonify({"answer": answer})

    @app.route('/search', methods=['POST'])
    def search_endpoint():
        ensure_main_model()
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

    @app.route('/action', methods=['POST'])
    def action_endpoint():
        # Ensure models are loading (non-blocking)
        ensure_fast_model()
        
        try: req = request.get_json(force=True)
        except: return jsonify({"action": None}), 400
        
        query = req.get('query', "").strip()
        if not query: return jsonify({"action": None})

        # 1. HARDCODED SHORTCUTS (Instant speed, perfect reliability)
        if query.lower() in COMMON_SHORTCUTS:
            url = COMMON_SHORTCUTS[query.lower()]
            return jsonify({
                "action": {
                    "type": "link",
                    "url": url,
                    "title": url.replace("https://", "").replace("www.", "").split('/')[0].title(),
                    "description": f"Direct Shortcut for {query.upper()}"
                }
            })

        # 2. MODEL INFERENCE
        if not fast_model:
            msg = fast_model_error if fast_model_error else "Model Loading..."
            return jsonify({"action": {"type": "status", "content": msg}})

        # Few-Shot Prompt: Teaches the model to delegate unknown sites to SEARCH:
        prompt = (
            f"Input: gh\nOutput: Open https://github.com\n"
            f"Input: yout\nOutput: Open https://www.youtube.com\n"
            f"Input: git status\nOutput: Run git status\n"
            f"Input: 2+2\nOutput: CALC:2+2\n"
            f"Input: sqrt(16)\nOutput: CALC:sqrt(16)\n"
            f"Input: zstib\nOutput: SEARCH:zstib\n"
            f"Input: weather in warsaw\nOutput: SEARCH:weather in warsaw\n"
            f"Input: best pizza place\nOutput: SEARCH:best pizza place\n"
            f"Input: who is elon musk\nOutput: PERSON:Elon Musk\n"
            f"Input: obama\nOutput: PERSON:Barack Obama\n"
            f"Input: taylor swift\nOutput: PERSON:Taylor Swift\n"
            f"Input: {query}\nOutput:"
        )

        try:
            # Run Inference
            with model_lock:
                output = fast_model(
                    prompt, 
                    max_tokens=32, 
                    stop=["\n", "Input:"], 
                    echo=False
                )
            
            result_text = output['choices'][0]['text'].strip()
            
            # 3. RESULT PROCESSING
            
            # Case A: Calculation
            if "CALC:" in result_text:
                expr = result_text.split("CALC:")[1].strip()
                calc_res = perform_calculation(expr) 
                if "Result: " in calc_res:
                    final_val = calc_res.split("Result: ")[1].strip()
                    return jsonify({"action": {"type": "calc", "content": final_val}})
                else:
                    return jsonify({"action": {"type": "calc", "content": calc_res}})
            
            # Case B: Search Delegation (Model doesn't know the URL)
            elif "SEARCH:" in result_text:
                search_q = result_text.split("SEARCH:")[1].strip()
                # Use Python to find the real URL via SearXNG
                rich_res = get_navigation_result(search_q)
                if rich_res:
                    return jsonify({
                        "action": {
                            "type": "link",
                            "url": rich_res['url'],
                            "title": rich_res['title'],
                            "description": rich_res['description']
                        }
                    })
                else:
                    # Fallback to a DuckDuckGo "Ducky" search if local search fails
                    url = f"https://duckduckgo.com/?q=!ducky+{search_q}"
                    return jsonify({
                        "action": {
                            "type": "link",
                            "url": url,
                            "title": "Search Result",
                            "description": f"Searching for '{search_q}'"
                        }
                    })

            # Case B2: Person Card
            elif "PERSON:" in result_text:
                name = result_text.split("PERSON:")[1].strip()
                
                # STRICT MATCHING: Rejct single-word generic queries (e.g. "John", "Steve")
                # We require at least 2 words (e.g. "Steve Jobs") for a Person Card to trigger automatically.
                if len(name.split()) < 2:
                    logging.info(f"Rejected Person Card for generic/short name: '{name}'. Falling back to Search.")
                    rich_res = get_navigation_result(name)
                    if rich_res:
                         return jsonify({
                             "action": {
                                 "type": "link",
                                 "url": rich_res['url'],
                                 "title": rich_res['title'],
                                 "description": rich_res['description']
                             }
                         })
                    else:
                        return jsonify({"action": {"type": "link", "url": f"https://www.google.com/search?q={name}", "title": name, "description": "Search Result"}})

                person_card = get_person_result(name)
                if person_card:
                    return jsonify({"action": person_card})
                else:
                    # Fallback to BASIC Person Card (Initials only)
                    return jsonify({
                        "action": {
                            "type": "person", 
                            "name": name.title(),
                            "description": "Press Enter to search info.",
                            "url": f"https://www.google.com/search?q={name}",
                            "image": None
                        }
                    })

            # Case C: Open URL directly from Model
            elif result_text.startswith("Open http"):
                 url = result_text.replace("Open ", "").strip()
                 
                 # Validate (Fix for "safelabs" -> "https://safelabs" invalid URL)
                 from urllib.parse import urlparse
                 valid = False
                 try:
                     if "." in urlparse(url).netloc: valid = True
                 except: pass
                 
                 # If invalid, try to find the REAL link via search
                 if not valid:
                     rich_res = get_navigation_result(query)
                     if rich_res:
                         return jsonify({
                             "action": {
                                 "type": "link",
                                 "url": rich_res['url'],
                                 "title": rich_res['title'],
                                 "description": rich_res['description']
                             }
                         })

                 return jsonify({
                    "action": {
                        "type": "link",
                        "url": url,
                        "title": url.replace("https://", "").replace("www.", "").split('/')[0].title(),
                        "description": "Suggested Link"
                    }
                 })

            # Case D: Generic Command
            return jsonify({"action": {"type": "command", "content": result_text}})

        except Exception as e:
            logging.error(f"Action Inference Error: {e}")
            return jsonify({"action": None, "error": str(e)})

    # --- BACKGROUND LOADER ---
    def _startup_sequence():
        """Gentle sequence to load models without freezing the UI"""
        logging.info("Startup: Waiting 5s for system stability...")
        time.sleep(5)
        
        # 1. Fast Model (Small)
        logging.info("Startup: Triggering Fast Model...")
        ensure_fast_model()
        
        # 2. Safety Buffer (Let Fast Model get a head start causing the lock to engage)
        time.sleep(2)
        
        # 3. Main Model (Large) - Will wait for Fast Model to release lock
        logging.info("Startup: Queueing Main Model...")
        # ensure_main_model runs synchronously in this thread, waiting for lock
        ensure_main_model()
        logging.info("Startup: Sequence Complete.")

    if __name__ == '__main__':
        # --- PRE-LOAD MODELS ON START -----
        threading.Thread(target=_startup_sequence, daemon=True).start()

        app.run(host='127.0.0.1', port=5500, threaded=True)

  '';
  # --- STARTUP WRAPPER ---
  brainWrapper = pkgs.writeShellScriptBin "start-brain-safe" ''
    export HF_TOKEN="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"
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