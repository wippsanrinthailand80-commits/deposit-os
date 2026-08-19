#!/usr/bin/env python3
# Render a text log to a terminal-style PNG (used as a screenshot fallback).
import sys, os
from PIL import Image, ImageDraw, ImageFont

log_path = sys.argv[1]
out_path = sys.argv[2]
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 18)
except Exception:
    font = ImageFont.load_default()

with open(log_path, "r", errors="replace") as f:
    text = f.read()

cols = 120
lines = []
for raw in text.splitlines():
    while len(raw) > cols:
        lines.append(raw[:cols])
        raw = raw[cols:]
    lines.append(raw)

cw = font.getbbox("M")[2]
lh = font.getbbox("M")[3] + 6
pad = 16
W = pad * 2 + cols * cw
H = pad * 2 + lh * max(len(lines), 1)
img = Image.new("RGB", (W, H), (15, 17, 26))
d = ImageDraw.Draw(img)
for i, ln in enumerate(lines):
    d.text((pad, pad + i * lh), ln, fill=(180, 220, 170), font=font)
img.save(out_path)
print("rendered", out_path, img.size)
