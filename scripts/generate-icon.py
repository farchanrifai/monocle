#!/usr/bin/env python3
"""Generate the prototype icon from original geometric shapes, without external libraries."""
from pathlib import Path
import json
import math
import struct
import zlib

size = 1024
pixels = bytearray()
for y in range(size):
    pixels.append(0)
    for x in range(size):
        ring = abs(math.hypot(x - 484, y - 512) - 250)
        dot = math.hypot(x - 770, y - 305)
        if dot < 49:
            color = (212, 41, 31)
        elif ring < 35:
            color = (242, 240, 234)
        else:
            color = (25, 27, 25)
        pixels.extend(color)
def chunk(name, data):
    return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name + data) & 0xffffffff)
image = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')
root = Path(__file__).resolve().parents[1] / 'Ankka/Resources/Assets.xcassets'
(root / 'AppIcon.appiconset/Icon.png').write_bytes(image)
(root / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
(root / 'AppIcon.appiconset/Contents.json').write_text(json.dumps({'images': [{'filename': 'Icon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
(root / 'AccentColor.colorset/Contents.json').write_text(json.dumps({'colors': [{'idiom': 'universal', 'color': {'color-space': 'srgb', 'components': {'red': '0.83', 'green': '0.16', 'blue': '0.12', 'alpha': '1.0'}}}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
