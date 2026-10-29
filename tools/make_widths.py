#!/usr/bin/env python3
# Writes fonts/<font>.wid: the advance width of each glyph, in font units, so that
# meteoalarmkindle.sh can measure text without drawing (FBInk has no safe measure-only mode on
# every version). Line format: "<units> <character>". The script scales by PX / 2288
# (FBInk sizes text by ascent - descent = 1854 + 434 units for Liberation Sans).
import os
import sys
from PIL import ImageFont

here = os.path.dirname(os.path.abspath(__file__))
fonts = os.path.join(here, "..", "extensions", "meteoalarmkindle", "fonts")
chars = [chr(c) for c in range(0x20, 0x250) if not 0x7F <= c < 0xA0]
chars += [chr(c) for c in range(0x2010, 0x2027)] + ["−", "←", "→"]
for name in ("LiberationSans-Regular", "LiberationSans-Bold"):
    font = ImageFont.truetype(os.path.join(fonts, name + ".ttf"), 2048)
    with open(os.path.join(fonts, name + ".wid"), "w", encoding="utf-8") as out:
        for ch in chars:
            out.write("%d %s\n" % (round(font.getlength(ch)), ch))
    print(name, len(chars), file=sys.stderr)
