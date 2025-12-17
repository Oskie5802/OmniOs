{ config, pkgs, lib, ... }:

let
  memoryPython = pkgs.python3.withPackages (ps: with ps; [
    lancedb
    sentence-transformers
    watchdog
    pandas
    numpy
    pyarrow
    pypdf
    python-docx
  ]);

  indexerScript = pkgs.writeScriptBin "ai-mem-daemon" ''
    #!${memoryPython}/bin/python
    import sys
    import time
    import os
    import shutil
    
    sys.stdout.reconfigure(line_buffering=True)
    
    print("🚀 [INIT] Script starting...", flush=True)

    import lancedb
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler
    from sentence_transformers import SentenceTransformer
    from pypdf import PdfReader
    import docx

    # --- CONFIG ---
    HOME_DIR = os.path.expanduser("~")
    WATCH_DIR = os.path.join(HOME_DIR, "Documents")
    DB_PATH = os.path.join(HOME_DIR, ".local/share/ai-memory-db")
    MODEL_NAME = 'all-MiniLM-L6-v2' 

    if not os.path.exists(WATCH_DIR):
        os.makedirs(WATCH_DIR, exist_ok=True)

    print(f"🧠 [Memory] Loading AI Model ({MODEL_NAME})...", flush=True)
    model = SentenceTransformer(MODEL_NAME)
    
    # --- DB SETUP ---
    tbl = None
    try:
        db = lancedb.connect(DB_PATH)
        try:
            tbl = db.open_table("files")
        except:
            print("✨ [Memory] Creating new database table...", flush=True)
            dummy_vec = model.encode("init")
            data = [{"vector": dummy_vec, "text": "init", "path": "init", "filename": "init", "last_mod": 0.0}]
            tbl = db.create_table("files", data)
            tbl.delete("path = 'init'")
    except Exception as e:
        print(f"⚠️ [Memory] DB Corruption detected, rebuilding...", flush=True)
        if os.path.exists(DB_PATH): shutil.rmtree(DB_PATH)
        db = lancedb.connect(DB_PATH)
        dummy_vec = model.encode("init")
        data = [{"vector": dummy_vec, "text": "init", "path": "init", "filename": "init", "last_mod": 0.0}]
        tbl = db.create_table("files", data)
        tbl.delete("path = 'init'")

    def extract_text(filepath):
        text = ""
        try:
            if filepath.endswith('.pdf'):
                reader = PdfReader(filepath)
                for page in reader.pages:
                    txt = page.extract_text()
                    if txt: text += txt + "\n"
            elif filepath.endswith('.docx'):
                doc = docx.Document(filepath)
                text = "\n".join([para.text for para in doc.paragraphs])
            else:
                with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                    text = f.read()
        except Exception:
            pass
        return text

    def index_file(filepath):
        if "/." in filepath or filepath.endswith('~'): return

        filename = os.path.basename(filepath)
        print(f"👁️ [Memory] Processing: {filename}", flush=True)
        
        content = extract_text(filepath)
        if not content or not content.strip(): return

        # --- ZMIANA: KONTEKST ŚCIEŻKI ---
        # Łączymy ścieżkę z treścią, aby AI "widziało" foldery
        # Np: "Path: /Documents/Wrzesień/faktura.pdf Content: Usługa IT..."
        full_context = f"File Path: {filepath}\nFile Name: {filename}\nFile Content:\n{content}"

        # Tworzymy wektor z CAŁOŚCI
        vector = model.encode(full_context[:8000])
        last_mod = os.path.getmtime(filepath)

        try:
            tbl.delete(f"path = '{filepath}'")
            tbl.add([{
                "vector": vector,
                "text": content, # Zapisujemy samą treść do czytania przez człowieka/LLM
                "path": filepath,
                "filename": filename,
                "last_mod": last_mod
            }])
            print(f"✅ [Memory] Indexed with path context: {filename}", flush=True)
        except Exception as e:
            print(f"⚠️ Write failed: {e}", flush=True)

    class AIFileHandler(FileSystemEventHandler):
        def on_modified(self, event):
            if not event.is_directory: index_file(event.src_path)
        def on_created(self, event):
            if not event.is_directory: index_file(event.src_path)
        def on_moved(self, event):
            if not event.is_directory:
                try: tbl.delete(f"path = '{event.src_path}'")
                except: pass
                index_file(event.dest_path)

    if __name__ == "__main__":
        print("🔎 [Memory] Performing startup scan...", flush=True)
        for root, dirs, files in os.walk(WATCH_DIR):
            for file in files:
                if file.endswith(('.txt', '.md', '.py', '.nix', '.pdf', '.docx')):
                    index_file(os.path.join(root, file))

        observer = Observer()
        observer.schedule(AIFileHandler(), WATCH_DIR, recursive=True)
        observer.start()
        print(f"👀 [Memory] WATCHER STARTED on {WATCH_DIR}", flush=True)
        try:
            while True: time.sleep(1)
        except KeyboardInterrupt:
            observer.stop()
        observer.join()
  '';

  searchScript = pkgs.writeScriptBin "ai-mem-search" ''
    #!${memoryPython}/bin/python
    import sys
    import lancedb
    from sentence_transformers import SentenceTransformer
    import os

    if len(sys.argv) < 2:
        print("Usage: ai-mem-search 'your query'")
        sys.exit(1)

    query = sys.argv[1]
    HOME_DIR = os.path.expanduser("~")
    DB_PATH = os.path.join(HOME_DIR, ".local/share/ai-memory-db")
    os.environ["TOKENIZERS_PARALLELISM"] = "false"

    try:
        model = SentenceTransformer('all-MiniLM-L6-v2')
        db = lancedb.connect(DB_PATH)
        tbl = db.open_table("files")
        
        results = tbl.search(model.encode(query)).limit(5).to_pandas()

        if results.empty:
            print("No results found.")
        else:
            print(f"\n🔍 Search Results for: '{query}'\n")
            for index, row in results.iterrows():
                print(f"📄 {row['filename']}")
                print(f"📂 {row['path']}")
                print("-" * 40)
    except Exception as e:
        print(f"Error: {e}")
    except Exception as e:
        print(f"Error: {e}")
  '';

  statusScript = pkgs.writeScriptBin "ai-mem-status" ''
    #!${pkgs.bash}/bin/bash
    echo "=== 1. Service Status ==="
    systemctl --user status ai-memory --no-pager
    
    echo -e "\n=== 2. Recent Logs ==="
    journalctl --user -u ai-memory -n 20 --no-pager
    
    echo -e "\n=== 3. Documents Folder Content ==="
    ls -R ~/Documents 2>/dev/null || echo "No Documents folder found"
    
    echo -e "\n=== 4. Index Content ==="
    ${memoryPython}/bin/python -c "
import lancedb, os
HOME = os.path.expanduser('~')
DB = os.path.join(HOME, '.local/share/ai-memory-db')
try:
    db = lancedb.connect(DB)
    print(db.open_table('files').to_pandas())
except Exception as e: print(e)
"
  '';

  listScript = pkgs.writeScriptBin "ai-mem-list" ''
    #!${memoryPython}/bin/python
    import lancedb
    import os
    import pandas as pd

    HOME_DIR = os.path.expanduser("~")
    DB_PATH = os.path.join(HOME_DIR, ".local/share/ai-memory-db")
    
    try:
        db = lancedb.connect(DB_PATH)
        tbl = db.open_table("files")
        df = tbl.to_pandas()
        if df.empty:
            print("Index is empty.")
        else:
            print(f"Found {len(df)} files in index:")
            for _, row in df.iterrows():
                print(f"- {row['filename']} ({row['path']})")
    except Exception as e:
        print(f"Error reading index (might be empty): {e}")
  '';

in
{
  environment.systemPackages = [ indexerScript searchScript listScript statusScript ];

  systemd.user.services.ai-memory = {
    enable = true; # RE-ENABLED
    description = "OmniOS Semantic Memory Service";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    environment = { PYTHONUNBUFFERED = "1"; };
    serviceConfig = {
      ExecStart = "${indexerScript}/bin/ai-mem-daemon";
      Restart = "always";
      RestartSec = 5;
    };
  };
}