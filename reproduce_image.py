
import sys
import requests
from PyQt6.QtWidgets import QApplication, QLabel
from PyQt6.QtGui import QPixmap

app = QApplication(sys.argv)

url = "https://ts2.mm.bing.net/th?id=OIP.BvgI7WqDHRXWj2QcVRNwcwHaHY&pid=15.1"
headers = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"
}

print(f"Downloading {url}...")
try:
    r = requests.get(url, headers=headers, timeout=10, verify=False)
    print(f"Status: {r.status_code}")
    print(f"Content length: {len(r.content)}")
    
    pixmap = QPixmap()
    success = pixmap.loadFromData(r.content)
    print(f"Load from data success: {success}")
    if success:
        print(f"Pixmap size: {pixmap.width()}x{pixmap.height()}")
    else:
        print("Failed to load QPixmap from data")

except Exception as e:
    print(f"Error: {e}")
