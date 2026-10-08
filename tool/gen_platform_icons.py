"""assets/icon/icon.png 로 안드로이드/iOS/웹 아이콘을 만든다.
실행: python3 tool/gen_platform_icons.py
"""
import json
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
src = Image.open(os.path.join(ROOT, "assets/icon/icon.png")).convert("RGB")


def save(size, path):
    path = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    src.resize((size, size), Image.LANCZOS).save(path)


for name, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    save(size, f"android/app/src/main/res/mipmap-{name}/ic_launcher.png")

ios = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
contents = json.load(open(os.path.join(ios, "Contents.json")))
for img in contents["images"]:
    if "filename" not in img:
        continue
    pts = float(img["size"].split("x")[0])
    scale = int(img["scale"].rstrip("x"))
    save(int(round(pts * scale)), os.path.join(ios, img["filename"]))

save(192, "web/icons/Icon-192.png")
save(512, "web/icons/Icon-512.png")
save(192, "web/icons/Icon-maskable-192.png")
save(512, "web/icons/Icon-maskable-512.png")
save(32, "web/favicon.png")
print("ok")
