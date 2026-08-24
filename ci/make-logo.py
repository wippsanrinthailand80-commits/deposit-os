#!/usr/bin/env python3
"""Deposit OS logo maker — cuts the Andromeda galaxy out of the photograph.

Luminance becomes alpha (black sky -> transparent, faint outer disc fades),
real photo colours are kept, result is trimmed and square-padded at 512px.
Used by build-rootfs.sh and the brand-assets CI workflow.
"""
import sys
from PIL import Image

SRC = "assets/wallpaper-andromeda-galaxy.jpg"
OUT = "deposit-logo.png"
LO, HI = 5, 115          # luminance stretch -> alpha ramp


def main() -> int:
    im = Image.open(SRC).convert("RGB")
    g = im.convert("L")

    lut = []
    for v in range(256):
        a = (v - LO) * 255 // (HI - LO)
        lut.append(max(0, min(255, a)))
    alpha = g.point(lut)

    rgba = im.convert("RGBA")
    rgba.putalpha(alpha)

    bbox = alpha.getbbox()
    if bbox:
        rgba = rgba.crop(bbox)

    side = max(rgba.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(rgba, ((side - rgba.width) // 2, (side - rgba.height) // 2))
    canvas = canvas.resize((512, 512), Image.LANCZOS)
    canvas.save(OUT)
    print(f"[logo] wrote {OUT} ({canvas.size[0]}x{canvas.size[1]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
