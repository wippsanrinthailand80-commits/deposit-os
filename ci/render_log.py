#!/usr/bin/env python3
"""Render a tool log file into a clean, content-sized PNG terminal screenshot.

Usage: render_log.py <logfile> <outfile> [title]

This is used by CI to embed a legible picture of the Deposit OS tooling
(.mlpds + AQA) output into the GitHub Actions job Summary. A real GUI
screenshot (scrot) is used as a fallback when this is unavailable.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

BG = (13, 17, 23)        # github dark canvas
FG = (230, 237, 243)     # light text
DIM = (139, 148, 158)    # dim text
TITLE = (88, 209, 222)   # cyan title
PAD = 18
LINE_H = 22
TITLE_H = 34
MAX_CHARS = 112


def load_font(size):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
        "/usr/share/fonts/truetype/freefont/FreeMono.ttf",
    ]
    for p in candidates:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    try:
        return ImageFont.truetype("DejaVuSansMono.ttf", size)
    except Exception:
        return ImageFont.load_default()


def wrap(line, max_chars):
    if len(line) <= max_chars:
        return [line]
    out = []
    cur = ""
    for word in line.split(" "):
        if len(cur) + len(word) + 1 <= max_chars:
            cur = (cur + " " + word).strip()
        else:
            if cur:
                out.append(cur)
            cur = word
    if cur:
        out.append(cur)
    return out or [""]


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: render_log.py <logfile> <outfile> [title]\n")
        return 2
    logfile, outfile = sys.argv[1], sys.argv[2]
    title = sys.argv[3] if len(sys.argv) > 3 else "Deposit OS — log"

    try:
        with open(logfile, "r", errors="replace") as f:
            raw = f.read().splitlines()
    except FileNotFoundError:
        raw = ["(log unavailable)"]

    font = load_font(15)
    lines = []
    for ln in raw:
        lines.extend(wrap(ln, MAX_CHARS))
    if not lines:
        lines = ["(empty log)"]

    # measure width
    max_w = 0
    for ln in lines:
        try:
            w = font.getlength(ln)
        except Exception:
            w = len(ln) * 8
        max_w = max(max_w, int(w))

    width = max(360, max_w) + PAD * 2
    height = TITLE_H + len(lines) * LINE_H + PAD

    img = Image.new("RGB", (width, height), BG)
    d = ImageDraw.Draw(img)

    # title bar
    d.rectangle([0, 0, width, TITLE_H], fill=(22, 27, 34))
    d.text((PAD, 7), title, font=font, fill=TITLE)

    y = TITLE_H + 4
    for ln in lines:
        color = FG
        if ln.startswith("#") or ln.startswith("=="):
            color = TITLE
        elif ln.startswith("[") or ln.startswith("aqa:") or ln.startswith("[mlpds]"):
            color = DIM
        d.text((PAD, y), ln, font=font, fill=color)
        y += LINE_H

    img.save(outfile)
    sys.stderr.write("wrote %s (%dx%d)\n" % (outfile, width, height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
