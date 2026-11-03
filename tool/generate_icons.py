"""Derive launcher icons from the approved OpenAI-generated AppStore/icon.png.

Requires Pillow. Run from repository root: python3 tool/generate_icons.py
"""
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'AppStore/icon.png'
ANDROID = ROOT / 'android/app/src/main/res'
IOS = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
WINDOWS = ROOT / 'windows/runner/resources/app_icon.ico'


def generate():
    with Image.open(SOURCE) as image:
        image.load()
        if image.size != (1024, 1024) or image.mode != 'RGB':
            raise ValueError('Source must be an opaque 1024x1024 RGB PNG')
        for density, pixels in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                                ('xxhdpi', 144), ('xxxhdpi', 192)]:
            image.resize((pixels, pixels), Image.Resampling.LANCZOS).save(
                ANDROID / f'mipmap-{density}/ic_launcher.png')
        manifest = json.loads((IOS / 'Contents.json').read_text())
        for entry in manifest['images']:
            size = float(entry['size'].split('x')[0])
            pixels = round(size * int(entry['scale'][0]))
            image.resize((pixels, pixels), Image.Resampling.LANCZOS).save(
                IOS / entry['filename'])
        image.save(WINDOWS, format='ICO', sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])
    print('source sha256:', hashlib.sha256(SOURCE.read_bytes()).hexdigest())


if __name__ == '__main__':
    generate()
