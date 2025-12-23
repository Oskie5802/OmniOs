import logging, sys, os, time, threading, json
from flask import Flask, request, jsonify
import requests
from simpleeval import SimpleEval

# Silence logs
logging.getLogger('werkzeug').setLevel(logging.ERROR)
logging.basicConfig(level=logging.INFO)
app = Flask(__name__)

HOME = os.path.expanduser("~")
MODEL_PATH = os.path.join(HOME, ".local/share/ai-models", os.environ.get("MODEL_FILENAME", "Qwen2.5-0.5B-Instruct-Q8_0.gguf"))
DB_PATH = os.path.join(HOME, ".local/share/ai-memory-db")
SEARXNG_URL = "http://127.0.0.1:8888/search"

llm = None
embed_model = None
db_conn = None
init_error = None

# Thread Lock
# Thread Lock
main_lock = threading.Lock()
fast_lock = threading.Lock()

# Fast Action Model (GGUF)
fast_model = None
fast_loading_started = False
fast_model_error = None
FAST_REPO_ID = "unsloth/gemma-3-1b-it-GGUF"
FAST_FILENAME = "gemma-3-1b-it-Q8_0.gguf"

# --- SHORTCUTS ---
# These override the AI for instant speed on common queries
COMMON_SHORTCUTS = {
    "yt": "https://www.youtube.com",
    "gh": "https://github.com",
    "x": "https://x.com",
    "red": "https://reddit.com",
    "map": "https://www.google.com/maps",
    "chat": "https://chatgpt.com"
}

def ensure_model_loaded():
    """Smart Loader: Loads models separately or unified based on config"""
    global llm, fast_model, init_error, embed_model, db_conn, fast_lock, main_lock
    
    # Fast check
    if llm and fast_model: return

    logging.info("Smart Loader: Starting...")
    
    # 1. DB Connect
    logging.info("Smart Loader: Connecting to DB...")
    if db_conn is None:
        try: 
            if os.path.exists(DB_PATH): 
                import lancedb
                db_conn = lancedb.connect(DB_PATH)
                logging.info("Smart Loader: DB Connected.")
            else:
                logging.info("Smart Loader: DB Path not found, skipping.")
        except Exception as e:
            logging.error(f"Smart Loader: DB Error: {e}")

    # 2. Imports
    logging.info("Smart Loader: Importing Libraries...")
    try:
        from llama_cpp import Llama
        from sentence_transformers import SentenceTransformer
        import torch
        logging.info("Smart Loader: Libraries Imported.")
    except Exception as e:
        logging.error(f"Smart Loader: Import Error: {e}")
        init_error = str(e)
        return

    # 3. Determine Paths
    main_path = MODEL_PATH
    fast_path = os.path.join(HOME, ".local/share/ai-models", FAST_FILENAME)
    
    # Fallback if specific fast model doesn't exist but main does
    if not os.path.exists(fast_path) and os.path.exists(main_path):
            fast_path = main_path
            
    # Resolve absolute paths to compare
    try:
        abs_main = os.path.abspath(main_path)
        abs_fast = os.path.abspath(fast_path)
    except:
        abs_main = main_path
        abs_fast = fast_path

    gpu_layers = int(os.environ.get("N_GPU_LAYERS", 0))

    # --- SCENARIO A: IDENTICAL MODELS (Optimization) ---
    if abs_main == abs_fast:
        # Use MAIN LOCK for initialization of shared model
        with main_lock:
                if llm and fast_model: return 
                logging.info(f"Smart Loader: Identical Models. Unifying...")
                try:
                    shared_model = Llama(
                        model_path=abs_main, n_ctx=4096, n_threads=4, n_gpu_layers=gpu_layers, verbose=True
                    )
                    llm = shared_model
                    fast_model = shared_model
                    
                    # CRITICAL: If sharing models, we must share the lock to prevent concurrent inference segfaults
                    # in llama.cpp (unless compiled thread-safe for same context, which usually isn't)
                    fast_lock = main_lock 
                    logging.info("Shared Model Loaded (One Lock).")
                except Exception as e:
                    logging.error(f"Shared Load Error: {e}")
                    init_error = str(e)

    # --- SCENARIO B: DISTINCT MODELS (Parallel/Separate) ---
    else:
        logging.info(f"Smart Loader: Distinct Models detected.")
        
        # 1. Fast Model (Priority) - Load First
        if not fast_model:
            with fast_lock:
                if not fast_model and os.path.exists(abs_fast):
                    try:
                        logging.info(f"Loading Fast Model: {os.path.basename(abs_fast)}")
                        fast_model = Llama(
                            model_path=abs_fast, n_ctx=1024, n_threads=4, n_gpu_layers=gpu_layers, verbose=True
                        )
                    except Exception as e: logging.error(f"Fast Load Error: {e}")

        # 2. Main Model (Background/Secondary)
        if not llm:
            with main_lock:
                if not llm:
                    try:
                        target = abs_main if os.path.exists(abs_main) else abs_fast
                        logging.info(f"Loading Main Model: {os.path.basename(target)}")
                        llm = Llama(
                            model_path=target, n_ctx=4096, n_threads=4, n_gpu_layers=gpu_layers, verbose=True
                        )
                    except Exception as e: 
                        init_error = str(e)
                        logging.error(f"Main Load Error: {e}")

    # 4. Embeddings (CPU/GPU)
    try:
        device = 'cuda' if torch.cuda.is_available() else 'cpu'
        logging.info(f"Loading Embeddings on device: {device.upper()}")
        embed_model = SentenceTransformer('all-MiniLM-L6-v2', device=device)
    except: pass

def ensure_fast_model():
    ensure_model_loaded()

def ensure_main_model():
    ensure_model_loaded()



def search_api(query, categories='general'):
    try:
        # SearXNG uses 'categories' (comma separated)
        params = {
            'q': query, 
            'format': 'json', 
            'categories': categories,
            'language': 'en-US' 
        }
        resp = requests.get(SEARXNG_URL, params=params, timeout=5.0)
        if resp.status_code == 200:
            return resp.json().get('results', [])
        else:
            logging.warn(f"Search API returned status: {resp.status_code}")
    except Exception as e:
        logging.error(f"Search API Error: {e}")
    return []



def perform_web_search(query):
    """Full search for Context (Chat)"""
    logging.info(f"Performing SearXNG Search for: {query}")
    try:
        results = search_api(query, categories='general')
        if not results: return "No search results found."
        
        text_res = []
        for i, res in enumerate(results):
            if i >= 3: break
            title = res.get('title', 'No Title')
            url = res.get('url', ' ')
            content = res.get('content', ' '.strip()) or res.get('snippet', ' '.strip())
            if content:
                text_res.append(f"Source: {title} ({url})\nContent: {content}")
        
        return "\n\n".join(text_res)
    except Exception as e:
        return f"Search failed: {str(e)}"

def get_navigation_result(query):
    """Quick search for Action (Navigation) returning Rich metadata"""
    try:
        # We use a short timeout because this happens in the UI loop
        # Increased to 5.0s to allow Google/Bing to respond
        params = {'q': query, 'format': 'json'}
        resp = requests.get(SEARXNG_URL, params=params, timeout=5.0)
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
            logging.info(f"Wiki Search Results: found {len(results)} items.")
            for res in results:
                url = res.get('url', ' '.strip())
                logging.info(f"Checking Result URL: {url}")
                if "wikipedia.org/wiki/" in url:
                    wiki_url = url
                    # Extract title from URL (last part)
                    wiki_title = url.split("wikipedia.org/wiki/")[-1]
                    logging.info(f"Found Wiki Title: {wiki_title}")
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

        # 2.5 DIRECT WIKI FALLBACK (Bypass Search Engine if failed)
        if not wiki_title:
            try:
                # Guess the title: "Elon Musk" -> "Elon_Musk"
                guess_title = name.strip().replace(" ", "_").title()
                logging.info(f"Attempting Direct Wiki Lookup for: {guess_title}")
                
                api_url = f"https://en.wikipedia.org/api/rest_v1/page/summary/{guess_title}"
                headers = {
                    "User-Agent": "OmniOS/1.0 (Local Research Assistant; +http://omni.local)"
                }
                api_resp = requests.get(api_url, headers=headers, timeout=5.0)
                
                if api_resp.status_code == 200:
                    data = api_resp.json()
                    if 'title' in data and 'extract' in data:
                        if data.get('type') != 'disambiguation':
                            return {
                                "type": "person",
                                "name": data.get('title', name),
                                "description": data.get('extract', 'No description available.'),
                                "url": data.get('content_urls', {}).get('desktop', {}).get('page', f"https://en.wikipedia.org/wiki/{guess_title}"),
                                "image": data.get('thumbnail', {}).get('source')
                            }
                else:
                    logging.info(f"Direct Wiki Fallback Failed. Status: {api_resp.status_code}")
            except Exception as e:
                    logging.error(f"Direct Wiki Fallback failed: {e}")

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


def get_place_result(query):
    """Search for a Place and return rich details (Map, Image)"""
    try:
        # Use OpenStreetMap via SearXNG for map data
        params = {'q': query, 'format': 'json', 'categories': 'map'}
        resp = requests.get(SEARXNG_URL, params=params, timeout=5.0)
        
        if resp.status_code == 200:
            results = resp.json().get('results', [])
            if results:
                best = results[0]
                
                # Fetch an image for the place
                image_url = None
                try:
                    img_search = requests.get(SEARXNG_URL, params={'q': query, 'format': 'json', 'categories': 'images'}, timeout=4.0)
                    if img_search.status_code == 200:
                        imgs = img_search.json().get('results', [])
                        if imgs: image_url = imgs[0].get('thumbnail_src') or imgs[0].get('url')
                except: pass

                return {
                    "type": "place",
                    "name": best.get('title', query),
                    "address": best.get('content', '') or best.get('address', {}).get('road', ''),
                    "latitude": best.get('latitude'),
                    "longitude": best.get('longitude'),
                    "url": best.get('url'),
                    "image": image_url
                }
    except Exception as e:
        logging.error(f"Place lookup failed: {e}")
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
    
    # --- AUTOMONOUS DECISION (FAST MODEL) ---
    decision_prompt_sys = (
        "You are the routing brain of an OS. Your job is to decide which tool to use for the user's query.\n"
        "Return ONLY a JSON object with these keys:\n"
        "- \"thought\": short reasoning\n"
        "- \"type\": one of [\"knowledge\", \"files\", \"search\", \"calc\"]\n"
        "- \"query\": the specific query strings to use for the tool.\n\n"
        "Tool Definitions:\n"
        "- \"files\": User asks about local files, notes, code, etc. (Query: keywords)\n"
        "- \"search\": User asks about current events, news, weather, or specific facts. (Query: optimized search terms)\n"
        "- \"calc\": User asks for math or logic. (Query: valid python expression, e.g. \"12*14\", \"math.sqrt(16)\")\n"
        "- \"knowledge\": General chat, greetings, philosophy, or simple questions.\n"
    )
    
    # Defaults
    decision = "knowledge"
    tool_query = query
    
    try:
        logging.info("Deciding category with Fast Model...")
        with fast_lock:
            # Use chat completion for instruction following
            dec_out = fast_model.create_chat_completion(
                messages=[
                    {"role": "system", "content": decision_prompt_sys},
                    {"role": "user", "content": f"Query: {query}"}
                ],
                max_tokens=128,
                temperature=0.0
            )
        
        raw_json = dec_out['choices'][0]['message']['content'].strip()
        # Attempt to clean potential markdown
        if "```json" in raw_json:
            raw_json = raw_json.split("```json")[1].split("```")[0].strip()
        elif "```" in raw_json:
            raw_json = raw_json.split("```")[1].split("```")[0].strip()
            
        logging.info(f"Decision JSON: {raw_json}")
        parsed = json.loads(raw_json)
        
        decision = parsed.get("type", "knowledge")
        tool_query = parsed.get("query", query)
        logging.info(f"Routed to: {decision} | Query: {tool_query}")
        
    except Exception as e:
        logging.error(f"Decision failed, defaulting to Knowledge. Error: {e}")
    
    context_text = ""
    source_type = "None"
    
    # Execute Decision
    if decision == "files" and db_conn and embed_model:
        source_type = "Local Files"
        try:
            tbl = db_conn.open_table("files")
            res = tbl.search(embed_model.encode(tool_query)).limit(3).to_pandas()
            if not res.empty:
                for _, row in res.iterrows():
                    context_text += f"--- Local File: {row['filename']} ---\n{row['text'][:1500]}\n\n"
        except: pass
        
    elif decision == "search":
        source_type = "Internet"
        context_text = f"--- Web Search Results ---\n{perform_web_search(tool_query)}\n"

    elif decision == "calc":
        source_type = "Calculator"
        context_text = f"--- Calculation Result ---\n{perform_calculation(tool_query)}\n"
    
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
        f"<|im_start|>assistant\n"
    )

    try:
        logging.info("Generating answer...")
        with main_lock:
            output = llm(
                prompt, max_tokens=1024, stop=["<|im_start|>", "<|im_end|>", "<|endoftext|>"], 
                echo=False, temperature=0.7
            )
        logging.info("Answer generated.")
        full_result = output['choices'][0]['text']
        # Since echo=False, the outputs is just the answer
        answer = full_result.strip()
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
    except: return jsonify({"actions": []}), 400
    
    query = req.get('query', "").strip()
    if not query: return jsonify({"actions": []})

    logging.info(f"Received /action query: {query}")

    # 1. HARDCODED SHORTCUTS (Instant speed, perfect reliability)
    if query.lower() in COMMON_SHORTCUTS:
        url = COMMON_SHORTCUTS[query.lower()]
        act = {
                "type": "link",
                "url": url,
                "title": url.replace("https://", "").replace("www.", "").split('/')[0].title(),
                "description": f"Direct Shortcut for {query.upper()}"
            }
        return jsonify({
            "action": act,
            "actions": [act]
        })

    # 2. MODEL INFERENCE
    if not fast_model:
        msg = fast_model_error if fast_model_error else "Model Loading..."
        return jsonify({"actions": [{"type": "status", "content": msg}]})

    # --- Specific Prompting Strategy (User Defined, Now inside function) ---
    system_prompt = (
        "You are a smart search assistant. Your job is to output ONLY the matching action(s) for the user's current query.\n\n"
        "Possible actions (output exactly in this format):\n"
        "- PERSON:[Full name] → for famous people\n"
        "- PLACE:[Proper name with correct capitalization] → for famous places\n"
        "- OPEN:https://[full URL] → for website completions\n"
        "- CALC:[math expression] → for calculations\n"
        "- SEARCH:[exact query] → if none of the above clearly fit\n\n"
        "Rules:\n"
        "- Output ONLY the action line(s), one per line if multiple.\n"
        "- Never add explanations, greetings, or extra text.\n"
        "- Never output actions for examples."
    )
    
    user_prompt = f"""Here are examples of how to respond. Follow them exactly:

Query: yout
Response:
OPEN:https://youtube.com

Query: faceb
Response:
OPEN:https://facebook.com

Query: insta
Response:
OPEN:https://instagram.com

Query: what is 12*9
Response:
CALC:12*9

Query: elon musk
Response:
PERSON:ELON MUSK

Query: stev jobs
Response:
PERSON:STEVE JOBS

Query: steve jobbs
Response:
PERSON:STEVE JOBS

Query: paris
Response:
PLACE:Paris

Query: new york
Response:
PLACE:New York

Query: eiffel tower
Response:
PLACE:Eiffel Tower

Query: zstib
Response:
SEARCH:zstib

Query: xyzabc
Response:
SEARCH:xyzabc

Query: randomschool123
Response:
SEARCH:randomschool123

Query: asdfgh
Response:
SEARCH:asdfgh

Query: my local shop
Response:
SEARCH:my local shop

Query: obscure thing
Response:
SEARCH:obscure thing

Query: google
Response:
SEARCH:google

Query: something unknown
Response:
SEARCH:something unknown

Query: any weird letters
Response:
SEARCH:any weird letters

Query: no idea what this is
Response:
SEARCH:no idea what this is

If nothing clearly matches PERSON, PLACE, OPEN, or CALC, ALWAYS use SEARCH.

Now respond ONLY to this query:
{query}
"""

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prompt}
    ]

    try:
        logging.info(f"LLM Input Messages: {json.dumps(messages)}")
        # Run Inference (Chat Completion)
        with fast_lock:
            # Gemma-2/3 models work best with their chat template
            output = fast_model.create_chat_completion(
                messages=messages,
                max_tokens=64, # Increased for multi-lines
                temperature=0.1 # Lower temp for strict format
            )
        
        result_text = output['choices'][0]['message']['content'].strip()
        logging.info(f"LLM Raw Output (Pass 1): {result_text}")
        
        # --- RAG LOOP ---
        if "SEARCH:" in result_text:
            # Extract query
            try:
                search_q = result_text.split("SEARCH:")[1].strip().split('\n')[0]
                logging.info(f"Triggering RAG Search for: {search_q}")
                
                # Perform Search (Using search_api)
                search_results = search_api(search_q, categories='general')
                snippet = ""
                for res in search_results[:2]:
                        snippet += f"- {res.get('title')}: {res.get('content') or res.get('snippet')} ({res.get('url')})\n"
                
                if not snippet: snippet = "No results found."

                logging.info(f"RAG Search Results Snippet: {snippet}")

                # RE-PROMPT
                messages.append({"role": "assistant", "content": result_text})
                messages.append({
                    "role": "user", 
                    "content": (
                        f"Search Results for '{search_q}':\n{snippet}\n"
                        "Based on this, what is the action?"
                    )
                })
                
                with fast_lock:
                    output = fast_model.create_chat_completion(messages=messages, max_tokens=64, temperature=0.2)
                
                result_text = output['choices'][0]['message']['content'].strip()
                logging.info(f"LLM Raw Output (Pass 2): {result_text}")
            except Exception as e:
                logging.error(f"RAG Loop Error: {e}")

        actions = []

        # 3. RESULT PROCESSING LOOP
        for line in result_text.split('\n'):
            line = line.strip()
            if not line: continue
            
            # Case A: Calculation
            if "CALC:" in line:
                expr = line.split("CALC:")[1].strip()
                calc_res = perform_calculation(expr) 
                if "Result: " in calc_res:
                    final_val = calc_res.split("Result: ")[1].strip()
                    actions.append({"type": "calc", "content": final_val})
                else:
                    actions.append({"type": "calc", "content": calc_res})
            
            # Case B: Search Delegation (Fallback/Direct)
            elif "SEARCH:" in line:
                search_q = line.split("SEARCH:")[1].strip()
                # Use navigation result or just link
                rich_res = get_navigation_result(search_q)
                if rich_res:
                    actions.append({
                        "type": "link",
                        "url": rich_res['url'],
                        "title": rich_res['title'],
                        "description": rich_res['description']
                    })
                else:
                    url = f"https://duckduckgo.com/?q=!ducky+{search_q}"
                    actions.append({
                        "type": "link",
                        "url": url,
                        "title": f"Open {search_q.title()}",
                        "description": "Redirect to Website"
                    })

            # Case B2: Person Card
            elif "PERSON:" in line:
                name = line.split("PERSON:")[1].strip()
                if len(name.split()) >= 2:
                    person_card = get_person_result(name)
                    if person_card:
                        actions.append(person_card)
                    else:
                        actions.append({
                            "type": "person", 
                            "name": name.title(),
                            "description": "Press Enter to search info.",
                            "url": f"https://www.google.com/search?q={name}",
                            "image": None
                        })
                else:
                    # Fallback to search
                        actions.append({
                        "type": "link", 
                        "url": f"https://duckduckgo.com/?q=!ducky+{name}", 
                        "title": f"Open {name.title()}", 
                        "description": "Redirect to Website"
                    })

            # Case B3: Place Card (NEW)
            elif "PLACE:" in line:
                place_q = line.split("PLACE:")[1].strip()
                place_card = get_place_result(place_q)
                if place_card:
                    actions.append(place_card)
                else:
                    # Fallback to Maps
                    actions.append({
                        "type": "link",
                        "url": f"https://www.google.com/maps/search/{place_q}",
                        "title": f"Map of {place_q}",
                        "description": "Open in Google Maps"
                    })

            # Case C: Open URL OR Malformed Open
            elif line.startswith("OPEN:") or line.upper().startswith("OPEN:"):
                # Handle OPEN:https://...
                parts = line.split("OPEN:")
                if len(parts) > 1:
                    content = parts[1].strip()
                    actions.append({
                        "type": "link",
                        "url": content,
                        "title": content.replace("https://", "").replace("www.", "").split('/')[0].title(),
                        "description": "Suggested Link"
                    })
        
        # Backward Compatibility: 'action' field (Legacy Frontend Support)
        primary_action = actions[0] if actions else None
        
        logging.info(f"Final Actions List: {actions}")
        
        return jsonify({
            "action": primary_action,
            "actions": actions
        })

    except Exception as e:
        logging.error(f"Action Inference Error: {e}")
        return jsonify({"actions": [], "action": None, "error": str(e)})

# --- BACKGROUND LOADER ---
def _startup_sequence():
    """Gentle sequence to load models without freezing the UI"""
    logging.info("Startup: Waiting 5s for system stability...")
    time.sleep(5)
    ensure_model_loaded()
    
    # Warm-up Inference
    if fast_model:
        try:
            logging.info("Startup: Warming up model...")
            with fast_lock:
                 fast_model.create_chat_completion(
                    messages=[{"role": "user", "content": "hi"}], 
                    max_tokens=1
                )
            logging.info("Startup: Warmup complete. System ready.")
        except Exception as e:
            logging.error(f"Startup Warmup Failed: {e}")

if __name__ == '__main__':
    # --- PRE-LOAD MODELS ON START -----
    threading.Thread(target=_startup_sequence, daemon=True).start()

    app.run(host='127.0.0.1', port=5500, threaded=True)
