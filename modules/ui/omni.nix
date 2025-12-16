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
        width: 6px;
        margin: 0px;
    }
    QScrollBar::handle:vertical {
        background: rgba(0, 0, 0, 0.1);
        min-height: 30px;
        border-radius: 3px;
    }
    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
        height: 0px;
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
            self.input_field.setPlaceholderText("Does this spark joy?")
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

        def on_text_changed(self, text):
            self.refresh_list(text)

        def refresh_list(self, query):
            self.list_widget.clear()
            
            # 1. ASK AI ROW
            display_text = f"Ask Omni: {query}" if query else "Ask Omni..."
            ai_item = QListWidgetItem(display_text)
            ai_item.setData(Qt.ItemDataRole.UserRole, {"type": "ai", "query": query})
            self.list_widget.addItem(ai_item)
            
            # 2. FILTERED APPS
            query_lower = query.lower()
            count = 0
            for app in self.apps:
                if count > 8: break 
                if query_lower in app['name'].lower():
                    item = QListWidgetItem(app['name'])
                    item.setData(Qt.ItemDataRole.UserRole, app)
                    self.list_widget.addItem(item)
                    count += 1
            
            self.list_widget.setCurrentRow(0)

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