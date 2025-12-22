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
    import threading
    from urllib.parse import urlparse
    from PyQt6.QtWidgets import (QApplication, QWidget, QVBoxLayout, QHBoxLayout, QLineEdit, 
                                 QListWidget, QListWidgetItem, QFrame, QAbstractItemView,
                                 QGraphicsDropShadowEffect, QLabel, QScrollArea)
    from PyQt6.QtCore import Qt, QSize, QThread, pyqtSignal, QPropertyAnimation, QEasingCurve, QPoint, QRect, QEvent, QTimer
    from PyQt6.QtGui import QColor, QFont, QIcon, QPixmap, QPainter, QPainterPath, QBrush
    import traceback
    import json
    import re
    import logging

    # --- LOGGING SETUP ---
    logging.basicConfig(
        filename="/tmp/omni_debug.log",
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )

    def exception_hook(exctype, value, tb):
        logging.critical("Uncaught exception:", exc_info=(exctype, value, tb))
        sys.__excepthook__(exctype, value, tb)
        
    sys.excepthook = exception_hook


    # CONFIG
    BRAIN_URL = "http://127.0.0.1:5500/ask"
    LOGO_PATH = "${../../assets/logo-trans.png}";
    
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
        padding: 20px 28px;
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
        padding: 4px 12px;
        icon-size: 32px;
    }
    
    QListWidget::item {
        padding: 12px 20px;
        margin-bottom: 6px;
        border-radius: 16px;
        color: #1d1d1f;
        font-size: 18px;
        font-weight: 500;
        border: 1px solid transparent;
    }

    /* Selected Item (The "Active" State) */
    QListWidget::item:selected {
        background-color: rgba(0, 0, 0, 0.06); /* Subtle Light Gray Accent */
        color: #1d1d1f;
        font-weight: 600;
        border: none;
    }
    
    /* Scrollbar Styling (Hidden/Minimalist) */
    QScrollBar:vertical {
        border: none;
        background: transparent;
        width: 8px; /* Slightly wider for better interaction */
        margin: 0px;
    }
    QScrollBar::handle:vertical {
        background: rgba(0, 0, 0, 0.15); /* Soft Gray Handle */
        min-height: 40px;
        border-radius: 4px;
    }
    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
        height: 0px;
    }
    QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {
        background: transparent;
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

    class LinkActionWidget(QWidget):
        icon_downloaded = pyqtSignal(object) # Use object for safer passing of bytes

        def __init__(self, title, url, description, parent=None):
            super().__init__(parent)
            self.url = url
            self.icon_thread = None # Keep reference
            
            # Connect signal
            self.icon_downloaded.connect(self.update_icon)
            
            # Layout
            layout = QVBoxLayout(self)
            layout.setContentsMargins(16, 16, 16, 16)
            layout.setSpacing(6)
            
            # 1. Top Row: Icon + Action Text
            top_row = QWidget()
            top_layout = QHBoxLayout(top_row)
            top_layout.setContentsMargins(0, 0, 0, 0)
            top_layout.setSpacing(10)
            
            # Icon Label
            self.icon_label = QLabel("🌐") 
            self.icon_label.setFixedSize(16, 16)
            self.icon_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
            self.icon_label.setStyleSheet("color: #007AFF; font-size: 12px;")
            
            # Action Label ("Open Link")
            self.action_label = QLabel(f"Open {url}")
            self.action_label.setStyleSheet("color: #007AFF; font-size: 13px; font-weight: 600;")
            
            top_layout.addWidget(self.icon_label)
            top_layout.addWidget(self.action_label)
            top_layout.addStretch() 
            
            # Main Title
            self.title_label = QLabel(title)
            self.title_label.setWordWrap(True)
            self.title_label.setStyleSheet("color: #1d1d1f; font-size: 16px; font-weight: 700;")
            
            # Description
            self.desc_label = QLabel(description)
            self.desc_label.setWordWrap(True)
            self.desc_label.setStyleSheet("color: #8E8E93; font-size: 13px; font-weight: 400;")
            
            layout.addWidget(top_row)
            layout.addWidget(self.title_label)
            layout.addWidget(self.desc_label)
            
            self.fetch_icon()

        def fetch_icon(self):
            try:
                # print(f"DEBUG: Fetching icon for URL: {self.url}")
                if not self.url: return
                
                # 1. Clean URL
                clean_url = self.url.strip().strip('<>').strip('"').strip("'")
                
                # 2. Add schema if missing for parsing
                if not clean_url.startswith("http") and not clean_url.startswith("//"):
                    clean_url = "https://" + clean_url
                    
                parsed = urlparse(clean_url)
                domain = parsed.netloc
                
                # Fallback for simple strings like "google.com" passed through logic
                if not domain and parsed.path:
                    possible = parsed.path.split('/')[0]
                    if '.' in possible: domain = possible

                if not domain: return

                # Normalize domain (strip www.) for better favicon hit rate
                if domain.startswith("www."):
                    domain = domain[4:]
                
                # 3. Fetch
                icon_url = f"https://www.google.com/s2/favicons?domain={domain}&sz=64"
                
                self.icon_thread = threading.Thread(target=self._download_icon, args=(icon_url,), daemon=True)
                self.icon_thread.start()
            except Exception as e:
                print(f"Error starting icon thread: {e}")

        def _download_icon(self, url):
            try:
                headers = {
                    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                }
                r = requests.get(url, headers=headers, timeout=3)
                if r.status_code == 200:
                    self.icon_downloaded.emit(r.content)
            except: pass

        def update_icon(self, data):
            try:
                pixmap = QPixmap()
                pixmap.loadFromData(data)
                if not pixmap.isNull():
                    self.icon_label.setText("") 
                    self.icon_label.setPixmap(pixmap.scaled(16, 16, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation))
            except: pass

        def sizeHint(self):
            w = 520 
            header_h = 32
            title_h = self.title_label.heightForWidth(w)
            desc_h = self.desc_label.heightForWidth(w)
            h = 32 + 12 + header_h + title_h + desc_h + 20 
            return QSize(600, h)

    class PersonActionWidget(QWidget):
        image_downloaded = pyqtSignal(object)

        def __init__(self, name, description, image_url, url, parent=None):
            super().__init__(parent)
            self.image_url = image_url
            self.url = url
            
            self.image_downloaded.connect(self.update_image)
            
            # Layout
            layout = QHBoxLayout(self)
            layout.setContentsMargins(24, 24, 24, 24)
            layout.setSpacing(24)
            
            # 1. Avatar (Vertical Portrait)
            self.avatar = QLabel()
            self.avatar.setFixedSize(100, 150)
            self.avatar.setStyleSheet("background-color: #E5E5EA; border-radius: 12px; border: 1px solid rgba(0,0,0,0.05);")
            self.avatar.setAlignment(Qt.AlignmentFlag.AlignCenter)
            
            # 2. Info (Right)
            info_layout = QVBoxLayout()
            info_layout.setSpacing(6)
            info_layout.setContentsMargins(0, 4, 0, 0) 
            
            # Clean Name
            display_name = name.replace(" - Wikipedia", "").strip()
            
            self.name_label = QLabel(display_name)
            self.name_label.setFont(QFont("Manrope", 24, QFont.Weight.Bold))
            self.name_label.setStyleSheet("color: #1d1d1f; letter-spacing: -0.5px;")
            self.name_label.setWordWrap(True)
            self.name_label.setAlignment(Qt.AlignmentFlag.AlignTop | Qt.AlignmentFlag.AlignLeft)
            
            self.desc_label = QLabel(description)
            self.desc_label.setFont(QFont("Manrope", 15, QFont.Weight.Normal))
            self.desc_label.setStyleSheet("color: #3A3A3C; line-height: 1.4;")
            self.desc_label.setWordWrap(True)
            self.desc_label.setAlignment(Qt.AlignmentFlag.AlignTop | Qt.AlignmentFlag.AlignLeft)
            
            # Small link indicator
            domain = urlparse(url).netloc.replace("www.", "")
            self.link_label = QLabel(f"Source: {domain}" if url else "Unknown Source")
            self.link_label.setFont(QFont("Manrope", 12, QFont.Weight.DemiBold))
            self.link_label.setStyleSheet("color: #007AFF; margin-top: 8px;")
            
            info_layout.addWidget(self.name_label)
            info_layout.addWidget(self.desc_label)
            info_layout.addWidget(self.link_label)
            info_layout.addStretch()
            
            layout.addWidget(self.avatar, 0, Qt.AlignmentFlag.AlignTop)
            layout.addLayout(info_layout)
            
            # Default to Initials
            self.avatar.setText(display_name[0])
            self.avatar.setStyleSheet("background-color: #007AFF; color: white; font-size: 48px; font-weight: bold; border-radius: 12px;")
            
            if self.image_url:
                threading.Thread(target=self._download_image, daemon=True).start()

        def _download_image(self):
            try:
                # 0. Handle Data URIs (Base64)
                if self.image_url.startswith("data:"):
                    try:
                        import base64
                        header, encoded = self.image_url.split(",", 1)
                        data = base64.b64decode(encoded)
                        self.image_downloaded.emit(data)
                        return
                    except: pass

                headers = {
                    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                    "Accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"
                }
                
                # verify=False to avoid SSL issues
                r = requests.get(self.image_url, headers=headers, timeout=10, verify=False)
                if r.status_code == 200:
                    self.image_downloaded.emit(r.content)
            except Exception as e:
                print(f"Image download error: {e}")

        def update_image(self, data):
            # 1. Safety Check
            try:
                if not self.avatar: return 
            except RuntimeError:
                return

            try:
                pixmap = QPixmap()
                pixmap.loadFromData(data)
                if not pixmap.isNull():
                    # Target Size
                    w, h = 100, 150
                    rounded = QPixmap(w, h)
                    rounded.fill(Qt.GlobalColor.transparent)
                    
                    painter = QPainter(rounded)
                    try:
                        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
                        path = QPainterPath()
                        # Rounded Rect
                        path.addRoundedRect(0, 0, w, h, 12, 12)
                        painter.setClipPath(path)
                        
                        # Scale to cover (KeepAspectRatioByExpanding)
                        scaled = pixmap.scaled(w, h, Qt.AspectRatioMode.KeepAspectRatioByExpanding, Qt.TransformationMode.SmoothTransformation)
                        
                        # Center crop
                        x = (scaled.width() - w) // 2
                        y = (scaled.height() - h) // 2
                        
                        painter.drawPixmap(-x, -y, scaled)
                    finally:
                        painter.end()
                    
                    self.avatar.setPixmap(rounded)
                    self.avatar.setStyleSheet("background-color: transparent;")
                    self.avatar.repaint()
            except Exception as e:
                print(f"Error updating person image: {e}")

        def sizeHint(self):
            # Dynamic Height Calculation
            # Available Width for Text = Window(720) - Margins/Pads(~150) - Avatar(100) - Spacing(24) ~= 440px
            w_text = 440
            
            name_h = self.name_label.heightForWidth(w_text)
            # 4. Accurate Height Calculation
            # NOTE: Qt heightForWidth DOES NOT respect CSS line-height (1.4).
            # We must apply the multiplier manually or the text will be cutoff.
            desc_h_raw = self.desc_label.heightForWidth(w_text)
            desc_h = int(desc_h_raw * 1.5) # 1.4 CSS + 0.1 Safety margin
            
            link_h = self.link_label.heightForWidth(w_text) + 8
            
            # Sum + Spacing
            # We reduced the buffer from 30+20 to just 12px for tight fit
            text_total_h = name_h + desc_h + link_h + 12 
            
            # Final Height
            # Height must accommodate the 150px image + margins(24+24) = 198px minimum
            img_min_h = 150 + 48
            
            final_h = max(img_min_h, text_total_h + 24)
            
            return QSize(600, final_h)

    class ActionWorker(QThread):
        action_found = pyqtSignal(object, str) # action_data (dict), query

        def __init__(self, query):
            super().__init__()
            self.query = query

        def run(self):
            try:
                # Fast Action Inference
                r = requests.post("http://127.0.0.1:5500/action", json={"query": self.query}, timeout=15)
                data = r.json()
                action_data = data.get("action")
                self.action_found.emit(action_data, self.query)
            except:
                self.action_found.emit(None, self.query)

    class ThinkingWidget(QWidget):
    # ... (Keep ThinkingWidget as is, reusing existing code)
        def __init__(self, text, parent=None):
            super().__init__(parent)
            self.full_text = text
            self.is_expanded = False
            
            self.main_layout = QVBoxLayout(self)
            self.main_layout.setContentsMargins(0, 4, 0, 4) # Remove horizontal margins here, list handles it
            self.main_layout.setSpacing(0)
            
            # Header acting as a button
            self.header = QLabel("▾  Thinking")
            self.header.setCursor(Qt.CursorShape.PointingHandCursor)
            self.header.setFixedHeight(34)
            self.header.setMinimumWidth(120)
            self.header.setStyleSheet("""
                QLabel {
                    background-color: rgba(0, 0, 0, 0.05);
                    border-radius: 8px;
                    padding: 0px 14px;
                    font-size: 13px;
                    font-weight: 600;
                    color: rgba(60, 60, 67, 0.5);
                }
                QLabel:hover {
                    background-color: rgba(0, 0, 0, 0.08);
                }
            """)
            self.header.mousePressEvent = self.toggle_expand
            
            # Scroll area for content
            self.scroll_area = QScrollArea()
            self.scroll_area.setWidgetResizable(True)
            self.scroll_area.setFrameShape(QFrame.Shape.NoFrame)
            self.scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
            self.scroll_area.setHidden(True)
            self.scroll_area.setMaximumHeight(200)
            self.scroll_area.setStyleSheet("""
                QScrollArea {
                    background-color: transparent;
                    border: none;
                    margin-top: 6px;
                }
                QScrollBar:vertical {
                    border: none;
                    background: transparent;
                    width: 4px;
                }
                QScrollBar::handle:vertical {
                    background: rgba(0, 0, 0, 0.1);
                    border-radius: 2px;
                }
            """)
            
            self.content_label = QLabel(text)
            self.content_label.setWordWrap(True)
            self.content_label.setStyleSheet("""
                QLabel {
                    background-color: transparent;
                    padding: 8px 12px 12px 12px;
                    font-size: 14px;
                    line-height: 1.5;
                    color: rgba(60, 60, 67, 0.7);
                    font-style: italic;
                }
            """)
            self.scroll_area.setWidget(self.content_label)
            
            self.main_layout.addWidget(self.header)
            self.main_layout.addWidget(self.scroll_area)
            
            # Initial size
            self.setMinimumHeight(42)

        def sizeHint(self):
            # Stable width estimate: Window(720) - Margins(80) - ListPadding(24) = 616
            w = 616
            # Header (34) + Margins (4+4) = 42
            h = 42 
            if self.is_expanded:
                content_h = self.content_label.heightForWidth(w) + 20
                h += min(content_h, 200) + 6
            return QSize(w, h)

        def toggle_expand(self, event):
            self.is_expanded = not self.is_expanded
            self.scroll_area.setHidden(not self.is_expanded)
            self.header.setText("▴ Thinking" if self.is_expanded else "▾ Thinking")
            
            # Update minimum height to help layout
            self.setMinimumHeight(self.sizeHint().height())
            self.update_item_size()

        def update_item_size(self):
            list_widget = self.window().findChild(QListWidget)
            if list_widget:
                for i in range(list_widget.count()):
                    item = list_widget.item(i)
                    if list_widget.itemWidget(item) == self:
                        item.setSizeHint(self.sizeHint())
                        break
                # Trigger window height adjustment
                if hasattr(self.window(), "adjust_window_height"):
                    self.window().adjust_window_height()

    class AnswerWidget(QWidget):
    # ... (Keep AnswerWidget as is, no changes needed)
        def __init__(self, text, parent=None):
            super().__init__(parent)
            self.layout = QVBoxLayout(self)
            self.layout.setContentsMargins(15, 5, 15, 5)
            self.layout.setSpacing(0)
            
            self.label = QLabel(text)
            self.label.setWordWrap(True)
            self.label.setFont(QFont("Manrope", 20, QFont.Weight.Medium))
            self.label.setStyleSheet("color: #1d1d1f; line-height: 1.3;")
            
            self.layout.addWidget(self.label)
            
        def sizeHint(self):
            # Reduced width estimate to ensure height calculation handles wrapping correctly
            # Window(720) - Margins(80) - ListPadding(24) - WidgetInternalPadding(30) = 586
            # We use 550 to be safe (underestimating width -> overestimating height -> no cutoff)
            w = 550
            # Increased buffer to 60 to prevent any bottom cutoff
            h = self.label.heightForWidth(w) + 60
            return QSize(w, h)

    class OmniWindow(QWidget):
        def __init__(self):
            super().__init__()
            # Frameless & Translucent
            self.setWindowFlags(Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint | Qt.WindowType.Dialog)
            self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
            self.setWindowIcon(QIcon(LOGO_PATH))
            self.setWindowTitle("Omni Intelligence")
            self.resize(720, 140) # Start minimal
            self.center()
            # Remember initial top position for stability
            self.initial_top = self.y()
            
            # Main Layout
            main_layout = QVBoxLayout(self)
            main_layout.setContentsMargins(40, 40, 40, 40) # Generous margins for large soft shadow
            
            # The Content Frame (Card)
            self.frame = QFrame()
            self.frame.setObjectName("MainFrame")
            
            # Soft High-End Drop Shadow
            shadow = QGraphicsDropShadowEffect(self)
            shadow.setBlurRadius(20) # Reduced from 60 to 20 for performance
            shadow.setXOffset(0)
            shadow.setYOffset(10)
            shadow.setColor(QColor(0, 0, 0, 40)) 
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
            self.input_field.installEventFilter(self) # Capture keys
            
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
            self.list_widget.verticalScrollBar().setSingleStep(20) # Smoother scroll step
            self.list_widget.setStyleSheet("QListWidget { outline: none; }") # Extra safety
            
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
            
            # Initial height adjustment
            self.adjust_window_height()

            # Search Worker
            self.search_worker = None
            # Action Worker
            self.action_worker = None
            
            # Debounce Timer
            self.debounce_timer = QTimer()
            self.debounce_timer.setSingleShot(True)
            self.debounce_timer.setInterval(400) # 400ms delay
            self.debounce_timer.timeout.connect(self.trigger_async_searches)

        def adjust_window_height(self):
            # 1. Precise Item Summation
            list_h = 0
            has_ai_answer = False
            for i in range(self.list_widget.count()):
                item = self.list_widget.item(i)
                widget = self.list_widget.itemWidget(item)
                # Check for AI Answer Widget to apply safety buffers
                if widget and widget.__class__.__name__ == "AnswerWidget":
                    has_ai_answer = True
                list_h += item.sizeHint().height() + 6
            
            # 2. Window Content Height
            # Shadow margins: 80 (40+40) -> We reduced shadow so we can reduce margins, but keeping for safety
            # But let's account for simpler shadow
            # Input Area: 74
            # Divider: 1
            # List Padding: 20 for AI answer (truncation safety), 4 for search
            buffer = 20 if has_ai_answer else 4
            target_list_h = list_h + buffer if self.list_widget.count() > 0 else 0
            
            target_h = 80 + 74 + 1 + target_list_h
            
            # 3. Strict Constraints
            screen_geo = self.screen().availableGeometry()
            screen_h = screen_geo.height()
            screen_center_y = screen_geo.center().y()
            
            # Ultra Compact Max: 540px
            target_h = min(target_h, 540)
            
            if self.list_widget.count() == 0:
                target_h = 160 # Search-bar only

            # 4. Instant Geometry Change (No Animation to prevent rendering freeze)
            target_y = int(screen_center_y - 120 - (target_h / 2))
            
            self.setGeometry(self.x(), target_y, self.width(), int(target_h))

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
                item.setData(Qt.ItemDataRole.UserRole, res)
                item.setSizeHint(QSize(600, 50)) # Explicit size for height calculation
                self.list_widget.addItem(item)
                added_count += 1
            
                self.list_widget.scrollToBottom()
                self.adjust_window_height()

        def handle_action_result(self, action_data, query):
            # Check if input matches
            if self.input_field.text() != query: return
            if not action_data: return
            
            # Check if we already have an action item at top
            # Check if we already have an action item at top
            first_item = self.list_widget.item(0)
            if first_item:
                data = first_item.data(Qt.ItemDataRole.UserRole)
                if data and isinstance(data, dict) and data.get('type') == 'fast_action':
                     # Update existing? For now, easier to remove and re-add to handle widget reset
                     self.list_widget.takeItem(0)
            
            # Insert at top
            item = QListWidgetItem()
            
            # --- RICH UI ---
            if isinstance(action_data, dict) and action_data.get('type') == 'link':
                # Rich Link Card
                widget = LinkActionWidget(
                    title=action_data.get('title', 'Link'),
                    url=action_data.get('url', ' '.strip()),
                    description=action_data.get('description', ' '.strip())
                )
                item.setSizeHint(widget.sizeHint()) # Dynamic height
                item.setData(Qt.ItemDataRole.UserRole, {"type": "fast_action", "action_data": action_data})
                self.list_widget.insertItem(0, item)
                self.list_widget.setItemWidget(item, widget)
                
            elif isinstance(action_data, dict) and action_data.get('type') == 'person':
                # Person Card
                widget = PersonActionWidget(
                    name=action_data.get('name', 'Person'),
                    description=action_data.get('description', ' '),
                    image_url=action_data.get('image'),
                    url=action_data.get('url')
                )
                item.setSizeHint(widget.sizeHint())
                item.setData(Qt.ItemDataRole.UserRole, {"type": "fast_action", "action_data": action_data})
                self.list_widget.insertItem(0, item)
                self.list_widget.setItemWidget(item, widget)

            elif isinstance(action_data, dict) and action_data.get('type') == 'status':
                 # Status Text (Gray)
                 text = f"⚡ {action_data.get('content')}"
                 item.setText(text)
                 item.setForeground(QColor("#8E8E93"))
                 font = item.font(); font.setItalic(True); item.setFont(font)
                 item.setData(Qt.ItemDataRole.UserRole, {"type": "fast_action", "action_data": action_data})
                 self.list_widget.insertItem(0, item)

            elif isinstance(action_data, dict) and action_data.get('type') == 'calc':
                 # Calculator
                 val = action_data.get('content')
                 item.setText(f"  {val}")
                 item.setIcon(QIcon.fromTheme("accessories-calculator"))
                 item.setForeground(QColor("#AF52DE"))
                 font = item.font(); font.setBold(True); font.setPointSize(22); item.setFont(font)
                 item.setData(Qt.ItemDataRole.UserRole, {"type": "fast_action", "action_data": action_data})
                 self.list_widget.insertItem(0, item)
                 
            else:
                # Fallback / Command
                # Support old string format just in case
                if isinstance(action_data, str):
                     text = action_data
                else:
                     text = action_data.get('content', str(action_data))
                     
                item.setText(f"⚡ {text}")
                item.setForeground(QColor("#007AFF"))
                font = item.font(); font.setBold(True); item.setFont(font)
                item.setData(Qt.ItemDataRole.UserRole, {"type": "fast_action", "action_data": action_data})
                self.list_widget.insertItem(0, item)
            
            self.list_widget.setCurrentRow(0)
            self.adjust_window_height()


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
            
        def eventFilter(self, obj, event):
            if obj == self.input_field and event.type() == QEvent.Type.KeyPress:
                key = event.key()

                if key == Qt.Key.Key_Down:
                    current = self.list_widget.currentRow()
                    if current < self.list_widget.count() - 1:
                        self.list_widget.setCurrentRow(current + 1)
                    return True
                elif key == Qt.Key.Key_Up:
                    current = self.list_widget.currentRow()
                    if current > 0:
                        self.list_widget.setCurrentRow(current - 1)
                    return True
            return super().eventFilter(obj, event)

        def load_apps(self):
            apps = []
            paths = ["/run/current-system/sw/share/applications", os.path.expanduser("~/.nix-profile/share/applications")]
            seen = set()
            for p in paths:
                if not os.path.exists(p): continue
                try:
                    for f in os.listdir(p):
                        if f.endswith(".desktop"):
                            full_path = os.path.join(p, f)
                            
                            # Defaults
                            name = f.replace(".desktop", "").replace("-", " ").title()
                            icon = "application-x-executable"
                            no_display = False
                            
                            try:
                                with open(full_path, 'r', errors='ignore') as df:
                                    for line in df:
                                        stripped = line.strip()
                                        if stripped.startswith("[") and stripped != "[Desktop Entry]":
                                            break # Stop parsing if we hit a new section (e.g. Actions)

                                        if stripped.startswith("Name="):
                                            name = stripped.split("=", 1)[1]
                                        elif stripped.startswith("Icon="):
                                            icon = stripped.split("=", 1)[1]
                                        elif stripped.startswith("NoDisplay=true"):
                                            no_display = True
                            except:
                                pass # If reading fails, just use filename fallback
                            
                            if no_display: continue
                            if name in seen: continue
                            seen.add(name)
                            apps.append({"name": name, "path": full_path, "icon": icon, "type": "app"})
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
                    if not name: name = p # Fallback if basename is empty
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
            ai_item.setSizeHint(QSize(600, 50)) # Explicit size
            
            # 2. Apps
            query_lower = query.lower()
            app_matches = []
            for app in self.apps:
                if query_lower in app['name'].lower():
                    app_matches.append(app)
            
            # 3. Files
            file_matches = []
            if query:
                file_matches = self.search_files(query)

            # --- SMART ORDERING ---
            final_items = []
            
            # If we have app matches, show them first!
            if app_matches:
                # Add apps
                for app in app_matches[:9]: # Limit apps
                    item = QListWidgetItem(app['name'])
                    if app['icon']:
                        if os.path.isabs(app['icon']) and os.path.exists(app['icon']):
                             item.setIcon(QIcon(app['icon']))
                        else:
                             item.setIcon(QIcon.fromTheme(app['icon']))
                    item.setData(Qt.ItemDataRole.UserRole, app)
                    item.setSizeHint(QSize(600, 50)) # Explicit size
                    final_items.append(item)
                
                # Then AI
                final_items.append(ai_item)
            else:
                # No apps? AI comes first
                final_items.append(ai_item)
            
            # Then files
            remaining_slots = 10 - len(final_items)
            for f in file_matches[:remaining_slots]:
                 item = QListWidgetItem(f['name'])
                 item.setIcon(QIcon.fromTheme(f['icon']))
                 item.setToolTip(f['path'])
                 item.setData(Qt.ItemDataRole.UserRole, f)
                 item.setSizeHint(QSize(600, 50)) # Explicit size
                 final_items.append(item)
            
            # Add to widget
            for item in final_items:
                self.list_widget.addItem(item)

            self.list_widget.setCurrentRow(0)
            self.adjust_window_height()

            self.list_widget.setCurrentRow(0)
            self.adjust_window_height()

            # 4. Debounce Async Search
            if len(query) >= 1:
                self.debounce_timer.start()

        def trigger_async_searches(self):
            query = self.input_field.text()
            if len(query) < 1: return

            # Trigger Semantic Search
            if self.search_worker and self.search_worker.isRunning():
                 # Let it finish or ignore, we will spawn new one
                 pass
            self.search_worker = SearchWorker(query)
            self.search_worker.results_found.connect(self.handle_semantic_results)
            self.search_worker.start()

            # Trigger Fast Action
            if self.action_worker and self.action_worker.isRunning():
                 pass
            self.action_worker = ActionWorker(query)
            self.action_worker.action_found.connect(self.handle_action_result)
            self.action_worker.start()

        def on_entered(self):
            if self.list_widget.currentRow() < 0: return
            
            item = self.list_widget.currentItem()
            data = item.data(Qt.ItemDataRole.UserRole)
            
            if data['type'] == 'ai':
                query = data['query']
                if not query: return
                self.start_ai_inference(query)
                
            elif data['type'] == 'app':
                subprocess.Popen(["dex", data['path']], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self.close()
                
            elif data['type'] == 'file':
                # Open files/folders with xdg-open
                subprocess.Popen(["xdg-open", data['path']], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self.close()

            elif data['type'] == 'fast_action':
                action_data = data['action_data']
                
                # Handle Dict format
                if isinstance(action_data, dict):
                    if action_data.get('type') == 'link':
                        url = action_data.get('url')
                        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        self.close()
                    elif action_data.get('type') == 'person':
                        url = action_data.get('url')
                        if url:
                            subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            self.close()
                    elif action_data.get('type') == 'calc':
                        val = action_data.get('content')
                        subprocess.run(["xclip", "-selection", "clipboard"], input=val.encode(), stderr=subprocess.DEVNULL)
                        self.close()
                    elif action_data.get('type') == 'status':
                        pass
                    else:
                        # Command?
                        content = action_data.get('content', ' '.strip())
                        subprocess.run(["xclip", "-selection", "clipboard"], input=content.encode(), stderr=subprocess.DEVNULL)
                        self.close()
                else:
                    # Old String Fallback (shouldn't happen with new brain.nix but safe to keep)
                    action_text = str(action_data)
                    if action_text.startswith("Open http"):
                        url = action_text.replace("Open ", "").strip()
                        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        self.close()
                    else:
                         subprocess.run(["xclip", "-selection", "clipboard"], input=action_text.encode(), stderr=subprocess.DEVNULL)
                         self.close()

        def start_ai_inference(self, query):
            self.list_widget.clear()
            
            loading_item = QListWidgetItem("Thinking...")
            loading_item.setFlags(loading_item.flags() & ~Qt.ItemFlag.ItemIsSelectable)
            loading_item.setFont(QFont("Manrope", 24, QFont.Weight.Medium))
            loading_item.setForeground(QColor(60, 60, 67, 120))
            self.list_widget.addItem(loading_item)
            
            self.input_field.setDisabled(True)
            self.input_field.setStyleSheet("color: rgba(60, 60, 67, 0.6);")
            
            self.worker = AIWorker(query)
            self.worker.finished.connect(self.display_ai_result)
            self.worker.start()

        def display_ai_result(self, answer):
            logging.info("display_ai_result called.")
            try:
                self.input_field.setDisabled(False)
                self.input_field.setStyleSheet("")
                self.input_field.setFocus()
                self.list_widget.clear()
                logging.info(f"Raw Answer length: {len(answer)}")
            except Exception as e:
                 logging.error(f"Error resetting UI: {e}")
            
            # --- PARSING ---
            display_text = answer
            action_data = None
            thinking_text = ""
            
            # 1. Extract Thinking
            # More robust: handle <think>...</think> OR just <think> if not closed
            thinking_match = re.search(r'<think>(.*?)(?:</think>|$)', answer, re.DOTALL)
            if thinking_match:
                thinking_text = thinking_match.group(1).strip()
                # Clean full match from display text
                full_match_text = re.search(r'<think>.*?(?:</think>|$)', answer, re.DOTALL).group(0)
                display_text = answer.replace(full_match_text, "").strip()
            
            # 2. Extract JSON Actions
            try:
                # 1. Try to find JSON in code blocks
                if "```json" in display_text:
                    parts = display_text.split("```json")
                    display_text = parts[0].strip()
                    json_str = parts[1].split("```")[0].strip()
                    action_data = json.loads(json_str)
                else:
                    # 2. Try to find any {...} block using regex
                    match = re.search(r'(\{.*\})', display_text, re.DOTALL)
                    if match:
                        json_str = match.group(1)
                        action_data = json.loads(json_str)
                        # If the whole remaining answer was just JSON, give a default feedback
                        if display_text.strip() == json_str:
                            display_text = "Executing action..."
                        else:
                            # Strip the JSON part from the display text
                            display_text = display_text.replace(json_str, "").strip()
            except Exception as e:
                pass
            
            # 3. Clean up Punctuation (remove trailing ... or .)
            display_text = display_text.rstrip(".… ")
            
            # --- UI CONSTRUCTION ---
            
            # Add Thinking Block if present
            if thinking_text:
                tw = ThinkingWidget(thinking_text)
                # Pass parent to automatically add to list
                item = QListWidgetItem(self.list_widget)
                item.setSizeHint(tw.sizeHint())
                item.setFlags(item.flags() & ~Qt.ItemFlag.ItemIsSelectable)
                # self.list_widget.addItem(item) <--- REMOVED REDUNDANT CALL
                self.list_widget.setItemWidget(item, tw)

            if display_text:
                aw = AnswerWidget(display_text)
                answer_item = QListWidgetItem(self.list_widget)
                answer_item.setFlags(answer_item.flags() & ~Qt.ItemFlag.ItemIsSelectable)
                
                # Set size hint FIRST to help the list
                answer_item.setSizeHint(aw.sizeHint())
                
                # self.list_widget.addItem(answer_item) <--- REMOVED REDUNDANT CALL
                self.list_widget.setItemWidget(answer_item, aw)
                
                try:
                    subprocess.Popen(["xclip", "-selection", "clipboard"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).communicate(input=display_text.encode())
                except: pass
            
            self.adjust_window_height()

            # --- ACTION EXECUTION ---
            if action_data:
                action = action_data.get("action")
                info_msg = ""
                success = False
                
                try:
                    if action == "browse":
                        url = action_data.get("url") or action_data.get("link")
                        if url:
                            info_msg = f"Opening {url}..."
                            subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            success = True
                    elif action == "search":
                        query = action_data.get("query") or action_data.get("url")
                        if query:
                            # If it's not a URL, make it a search URL
                            if not query.startswith("http"):
                                url = f"https://www.google.com/search?q={query.replace(' ', '+')}"
                            else:
                                url = query
                            info_msg = f"Searching for '{query}'..."
                            subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            success = True
                    elif action in ["launch", "open"]:
                        name = action_data.get("name") or action_data.get("path") or action_data.get("app")
                        if name:
                            info_msg = f"Launching {name}..."
                            # ... rest of launch logic
                            found = False
                            for app in self.apps:
                                if name.lower() in app['name'].lower():
                                    subprocess.Popen(["dex", app['path']], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                                    found = True
                                    break
                            if not found:
                                 subprocess.Popen(["xdg-open", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            success = True
                    
                    if success:
                        # Update UI briefly before closing
                        if not display_text or display_text == "Executing action...":
                            self.list_widget.clear()
                            item = QListWidgetItem(info_msg)
                            item.setFont(QFont("Manrope", 20, QFont.Weight.Medium))
                            self.list_widget.addItem(item)
                        
                        # Close after a tiny delay for feedback
                        QThread.msleep(800) 
                        self.close()
                    else:
                        # If we have action data but couldn't execute (missing fields), just show it
                        if not display_text or display_text == "Executing action...":
                             self.list_widget.clear()
                             err_item = QListWidgetItem(f"Could not execute '{action}'. Missing parameters.")
                             err_item.setForeground(QColor(200, 50, 50))
                             self.list_widget.addItem(err_item)

                except Exception as e:
                    self.list_widget.clear()
                    err_item = QListWidgetItem(f"System Error: {str(e)}")
                    err_item.setForeground(QColor(200, 50, 50))
                    self.list_widget.addItem(err_item)

        def keyPressEvent(self, event):
            if event.key() == Qt.Key.Key_Escape:
                self.close()

    if __name__ == "__main__":
        try:
            app = QApplication(sys.argv)
            app.setApplicationName("Omni")
            app.setApplicationDisplayName("Omni")
            app.setDesktopFileName("omni-bar")
            window = OmniWindow()
            window.show()
            sys.exit(app.exec())
        except Exception as e:
            with open("/tmp/omni_crash.log", "w") as f:
                f.write(traceback.format_exc())

  '';

  # --- 3. WRAPPER ---
  openOmniScript = pkgs.writeShellScriptBin "open-omni" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.xclip}/bin:${pkgs.kdePackages.kservice}/bin:${pkgs.libnotify}/bin:$PATH"
    ${omniLauncher}/bin/omni-launcher
  '';

  omniDesktopItem = pkgs.makeDesktopItem {
    name = "omni-bar";
    desktopName = "Omni";
    genericName = "Universal Search & AI";
    comment = "Your intelligent companion for search and system control";
    exec = "${openOmniScript}/bin/open-omni";
    icon = "${../../assets/logo-trans.png}";
    categories = [ "Utility" ];
  };

in
{
  environment.systemPackages = with pkgs; [
    omniLauncher omniDesktopItem xclip libnotify kdePackages.kservice papirus-icon-theme fd dex
  ];
  # Manrope: A modern, geometric sans-serif that is excellent for UI clarity and style.
  fonts.packages = with pkgs; [ manrope ];
}