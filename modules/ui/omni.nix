{ pkgs, config, lib, ... }:

let
  # 1. SETUP: Python with requests app and PyQt6
  omniPython = pkgs.python3.withPackages (ps: with ps; [ requests pyqt6 ]);

  # --- 2. LOGIC & UI (Custom Qt Launcher) ---
  omniLauncher = pkgs.writeScriptBin "omni-launcher" ''
    #!${omniPython}/bin/python
    import sys
    import os
    import subprocess
    import requests
    from PyQt6.QtWidgets import (QApplication, QWidget, QVBoxLayout, QLineEdit, 
                                 QListWidget, QListWidgetItem, QFrame, QAbstractItemView,
                                 QGraphicsDropShadowEffect)
    from PyQt6.QtCore import Qt, QSize, QThread, pyqtSignal, QPropertyAnimation, QEasingCurve, QPoint, QRect
    from PyQt6.QtGui import QColor, QFont, QIcon

    # CONFIG
    BRAIN_URL = "http://127.0.0.1:5500/ask"
    
    # --- DESIGN SYSTEM ---
    # Aesthetic: "Ethereal Day"
    # Font: Manrope (Modern, Geometric, Clean)
    STYLE_SHEET = """
    /* Global Reset */
    * {
        font-family: "Manrope", "Urbanist", sans-serif;
        outline: none;
    }

    /* Main Window Container */
    QWidget {
        background-color: transparent;
        color: #1d1d1f; /* Apple Text Black */
    }

    /* The Content Card */
    QFrame#MainFrame {
        background-color: rgba(255, 255, 255, 0.92); /* Frosted White */
        border: 1px solid rgba(255, 255, 255, 0.8);
        border-radius: 24px;
    }

    /* Input Field */
    QLineEdit {
        background-color: transparent;
        border: none;
        padding: 24px 28px;
        font-size: 22px;
        font-weight: 500; 
        color: #000000;
        selection-background-color: #A3D3FF;
    }
    QLineEdit::placeholder {
        color: rgba(60, 60, 67, 0.3); /* Apple Secondary Label */
        font-weight: 400;
    }

    /* Divider Line */
    QFrame#Divider {
        background-color: rgba(60, 60, 67, 0.1); /* Subtle Separator */
        min-height: 1px;
        max-height: 1px;
        margin: 0px 24px;
    }

    /* Result List */
    QListWidget {
        background-color: transparent;
        border: none;
        padding: 12px;
    }
    
    QListWidget::item {
        padding: 14px 20px;
        margin-bottom: 4px;
        border-radius: 16px;
        color: #1d1d1f;
        font-size: 16px;
        font-weight: 500;
        border: 1px solid transparent;
    }

    /* Selected Item (The "Active" State) */
    QListWidget::item:selected {
        background-color: #000000; /* Bold Black Accent */
        color: #FFFFFF;
        font-weight: 600;
        border: none;
    }
    
    /* Scrollbar Styling (Hidden/Minimalist) */
    QScrollBar:vertical {
        border: none;
        background: transparent;
        width: 4px;
        margin: 0px;
    }
    QScrollBar::handle:vertical {
        background: #C7C7CC; /* Apple System Gray */
        min-height: 20px;
        border-radius: 2px;
    }
    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
        height: 0px;
    }
    QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {
        background: none;
    }
    """

    class AIWorker(QThread):
        finished = pyqtSignal(str)

        def __init__(self, query):
            super().__init__()
            self.query = query

        def run(self):
            try:
                r = requests.post(BRAIN_URL, json={"query": self.query}, timeout=45)
                answer = r.json().get("answer", "No answer received.")
                self.finished.emit(answer)
            except requests.exceptions.ConnectionError:
                self.finished.emit("The Omni AI hasn't loaded yet. Please try again in a moment.")
            except Exception as e:
                self.finished.emit(f"System Error: {str(e)}")

    class SearchWorker(QThread):
        results_found = pyqtSignal(list, str) # results, query_at_start

        def __init__(self, query):
            super().__init__()
            self.query = query

        def run(self):
            try:
                # Semantic Search
                r = requests.post("http://127.0.0.1:5500/search", json={"query": self.query}, timeout=5)
                results = r.json().get("results", [])
                self.results_found.emit(results, self.query)
            except:
                self.results_found.emit([], self.query)

    class OmniWindow(QWidget):
        def __init__(self):
            super().__init__()
            # Frameless & Translucent
            self.setWindowFlags(Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint | Qt.WindowType.Dialog)
            self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
            self.resize(720, 500) 
            self.center()
            
            # Main Layout
            main_layout = QVBoxLayout(self)
            main_layout.setContentsMargins(40, 40, 40, 40) # Generous margins for large soft shadow
            
            # The Content Frame (Card)
            self.frame = QFrame()
            self.frame.setObjectName("MainFrame")
            
            # Soft High-End Drop Shadow
            shadow = QGraphicsDropShadowEffect(self)
            shadow.setBlurRadius(60)
            shadow.setXOffset(0)
            shadow.setYOffset(20)
            shadow.setColor(QColor(0, 0, 0, 30)) # Very subtle, pure black shadow
            self.frame.setGraphicsEffect(shadow)
            
            # Inner Layout
            frame_layout = QVBoxLayout(self.frame)
            frame_layout.setContentsMargins(0, 0, 0, 0)
            frame_layout.setSpacing(0)
            
            # Input
            self.input_field = QLineEdit()
            self.input_field.setPlaceholderText("Search or ask Omni...")
            self.input_field.textChanged.connect(self.on_text_changed)
            self.input_field.returnPressed.connect(self.on_entered)
            
            # Divider
            self.divider = QFrame()
            self.divider.setObjectName("Divider")
            
            # List
            self.list_widget = QListWidget()
            self.list_widget.setVerticalScrollMode(QAbstractItemView.ScrollMode.ScrollPerPixel)
            self.list_widget.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
            self.list_widget.itemClicked.connect(self.on_entered)
            self.list_widget.setWordWrap(True) 
            self.list_widget.setFocusPolicy(Qt.FocusPolicy.NoFocus) # Keep focus on input
            
            frame_layout.addWidget(self.input_field)
            frame_layout.addWidget(self.divider)
            frame_layout.addWidget(self.list_widget)
            main_layout.addWidget(self.frame)
            
            self.setStyleSheet(STYLE_SHEET)
            
            # Data
            self.apps = self.load_apps()
            self.refresh_list("")

            # Entry Animation
            self.animate_entry()

            # Search Worker
            self.search_worker = None

        def handle_semantic_results(self, results, original_query):
            # Only update if the query hasn't changed significantly or if we want to show results anyway
            # Check if input still matches roughly what was searched
            current_text = self.input_field.text()
            if current_text != original_query: return 

            if not results: return

            # Add separator if needed or just append
            # To avoid duplicate items if file is found by both 'fd' and 'semantic', we can check paths
            existing_paths = set()
            for i in range(self.list_widget.count()):
                item = self.list_widget.item(i)
                d = item.data(Qt.ItemDataRole.UserRole)
                if d and 'path' in d: existing_paths.add(d['path'])

            added_count = 0
            for res in results:
                if res['path'] in existing_paths: continue
                
                item = QListWidgetItem(res['name'])
                item.setIcon(QIcon.fromTheme("emblem-symbolic-link")) # Use distinct icon for semantic matches
                item.setData(Qt.ItemDataRole.UserRole, res)
                self.list_widget.addItem(item)
                added_count += 1
            
            if added_count > 0:
                self.list_widget.scrollToBottom()

        def center(self):
            qr = self.frameGeometry()
            cp = self.screen().availableGeometry().center()
            qr.moveCenter(cp)
            qr.moveTop(qr.top() - 100) # Visual center slightly higher
            self.move(qr.topLeft())

        def animate_entry(self):
            # Animate the geometry (Slide Up with springy feel)
            self.anim_geo = QPropertyAnimation(self, b"geometry")
            self.anim_geo.setDuration(600)
            self.anim_geo.setStartValue(QRect(self.x(), self.y() + 30, self.width(), self.height()))
            self.anim_geo.setEndValue(QRect(self.x(), self.y(), self.width(), self.height()))
            self.anim_geo.setEasingCurve(QEasingCurve.Type.OutBack) # Slight overshoot for delight
            
            # Animate Opacity (Fade In)
            self.anim_opa = QPropertyAnimation(self, b"windowOpacity")
            self.anim_opa.setDuration(400)
            self.anim_opa.setStartValue(0)
            self.anim_opa.setEndValue(1)
            
            self.anim_geo.start()
            self.anim_opa.start()
            
        def load_apps(self):
            apps = []
            paths = ["/run/current-system/sw/share/applications", os.path.expanduser("~/.nix-profile/share/applications")]
            seen = set()
            for p in paths:
                if not os.path.exists(p): continue
                try:
                    for f in os.listdir(p):
                        if f.endswith(".desktop"):
                            name = f.replace(".desktop", "").replace("-", " ").title()
                            if name in seen: continue
                            seen.add(name)
                            full_path = os.path.join(p, f)
                            apps.append({"name": name, "path": full_path, "type": "app"})
                except: continue
            return sorted(apps, key=lambda x: x['name'])

        def search_files(self, query):
            if not query or len(query) < 2: return []
            try:
                # Use fd to search in home directory, max 10 results, excluding hidden files by default
                cmd = ["fd", "--max-results", "5", "--type", "f", "--type", "d", "--exclude", ".*", query, os.path.expanduser("~")]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=1)
                paths = result.stdout.strip().split('\n')
                items = []
                for p in paths:
                    if not p: continue
                    name = os.path.basename(p)
                    is_dir = os.path.isdir(p)
                    icon = "folder" if is_dir else "text-x-generic"
                    items.append({"name": name, "path": p, "icon": icon, "type": "file"})
                return items
            except:
                return []

        def on_text_changed(self, text):
            self.refresh_list(text)

        def refresh_list(self, query):
            self.list_widget.clear()
            
            # Prepare Items
            # 1. AI Item (Always created but placed efficiently)
            display_text = f"Ask Omni: {query}" if query else "Ask Omni..."
            ai_item = QListWidgetItem(display_text)
            ai_item.setData(Qt.ItemDataRole.UserRole, {"type": "ai", "query": query})
            
            query_lower = query.lower()
            
            # 2. FILTERED APPS
            app_matches = []
            for app in self.apps:
                if count > 8: break 
                if query_lower in app['name'].lower():
                    app_matches.append(app)
            
            # 3. FILES (Only if query present)
            file_matches = []
            if query:
                file_matches = self.search_files(query)

            # Combine Results (max 8 items total)
            remaining_slots = 9 
            
            # Apps first
            for app in app_matches[:remaining_slots]:
                item = QListWidgetItem(app['name'])
                if app['icon']:
                    if os.path.isabs(app['icon']) and os.path.exists(app['icon']):
                         item.setIcon(QIcon(app['icon']))
                    else:
                         item.setIcon(QIcon.fromTheme(app['icon']))
                item.setData(Qt.ItemDataRole.UserRole, app)
                self.list_widget.addItem(item)
                remaining_slots -= 1
                
            # Then files
            for f in file_matches[:remaining_slots]:
                 item = QListWidgetItem(f['name'])
                 # Try to be smarter with file icons if possible, but generic fallback is fine
                 item.setIcon(QIcon.fromTheme(f['icon'])) 
                 item.setToolTip(f['path'])
                 item.setData(Qt.ItemDataRole.UserRole, f)
                 self.list_widget.addItem(item)

            self.list_widget.setCurrentRow(0)

            # 4. Trigger Semantic Search (Async)
            if len(query) > 1:
                if self.search_worker and self.search_worker.isRunning():
                    self.search_worker.terminate()
                    self.search_worker.wait()
                
                self.search_worker = SearchWorker(query)
                self.search_worker.results_found.connect(self.handle_semantic_results)
                self.search_worker.start()

        def on_entered(self):
            if self.list_widget.currentRow() < 0: return
            
            item = self.list_widget.currentItem()
            data = item.data(Qt.ItemDataRole.UserRole)
            
            if data['type'] == 'ai':
                query = data['query']
                if not query: return
                self.start_ai_inference(query)
                
            elif data['type'] == 'app':
                subprocess.Popen(["kstart6", data['path']], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self.close()

        def start_ai_inference(self, query):
            self.list_widget.clear()
            
            loading_item = QListWidgetItem("Thinking...")
            loading_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            self.list_widget.addItem(loading_item)
            
            self.input_field.setDisabled(True)
            self.input_field.setStyleSheet("color: rgba(60, 60, 67, 0.6);")
            
            self.worker = AIWorker(query)
            self.worker.finished.connect(self.display_ai_result)
            self.worker.start()

        def display_ai_result(self, answer):
            self.input_field.setDisabled(False)
            self.input_field.setStyleSheet("")
            self.input_field.setFocus()
            self.list_widget.clear()
            
            answer_item = QListWidgetItem(answer)
            self.list_widget.addItem(answer_item)
            
            subprocess.run(["xclip", "-selection", "clipboard"], input=answer.encode(), stderr=subprocess.DEVNULL)

        def keyPressEvent(self, event):
            if event.key() == Qt.Key.Key_Escape:
                self.close()

    if __name__ == "__main__":
        app = QApplication(sys.argv)
        window = OmniWindow()
        window.show()
        sys.exit(app.exec())
  '';

  # --- 3. WRAPPER ---
  openOmniScript = pkgs.writeShellScriptBin "open-omni" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.xclip}/bin:${pkgs.kdePackages.kservice}/bin:${pkgs.libnotify}/bin:$PATH"
    ${omniLauncher}/bin/omni-launcher
  '';

  omniDesktopItem = pkgs.makeDesktopItem {
    name = "omni-bar";
    desktopName = "Omni";
    exec = "${openOmniScript}/bin/open-omni";
    icon = "system-search";
    categories = [ "Utility" ];
  };

in
{
  environment.systemPackages = with pkgs; [
    omniLauncher omniDesktopItem xclip libnotify kdePackages.kservice papirus-icon-theme
  ];
  # Manrope: A modern, geometric sans-serif that is excellent for UI clarity and style.
  fonts.packages = with pkgs; [ manrope ];
}