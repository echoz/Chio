#!/usr/bin/env python3
"""Render chio-maps --snapshot-json cells for inspection (requires Pillow).

This exports a native SwiftTUI raster, not a screenshot of an emulator. The font
and cell dimensions are explicit; live-terminal glyph/capability checks are separate.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('input', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--font', type=Path, default=Path('/System/Library/Fonts/Menlo.ttc'))
parser.add_argument('--symbol-font', type=Path, default=Path('/System/Library/Fonts/Apple Symbols.ttf'),
                    help='Font with Unicode braille coverage; Pillow does not perform font fallback')
parser.add_argument('--cell-width', type=int, default=12)
parser.add_argument('--cell-height', type=int, default=24)
args = parser.parse_args()
if args.cell_width <= 0 or args.cell_height <= 0:
    parser.error('cell dimensions must be positive')
rows = json.loads(args.input.read_text())
height, width = len(rows), max(map(len, rows))
font = ImageFont.truetype(str(args.font), size=20)
symbols = ImageFont.truetype(str(args.symbol_font), size=28)
image = Image.new('RGB', (width * args.cell_width, height * args.cell_height))
draw = ImageDraw.Draw(image)

def rgb(color):
    return tuple(round(max(0, min(1, color[channel])) * 255) for channel in ('red', 'green', 'blue'))

for y, row in enumerate(rows):
    for x, cell in enumerate(row):
        draw.rectangle((x * args.cell_width, y * args.cell_height,
                        (x + 1) * args.cell_width - 1, (y + 1) * args.cell_height - 1),
                       fill=rgb(cell['background']))
# Paint glyphs after backgrounds so a native wide character can cover its continuation cell.
for y, row in enumerate(rows):
    for x, cell in enumerate(row):
        if cell['character'].strip():
            glyph = cell['character']
            if len(glyph) == 1 and 0x2800 <= ord(glyph) <= 0x28ff:
                # Center the complete braille block; glyph bounds vary with lit dots.
                left, top, right, bottom = symbols.getbbox('\u28ff')
                origin = (x * args.cell_width + (args.cell_width - right + left) / 2 - left,
                          y * args.cell_height + (args.cell_height - bottom + top) / 2 - top)
                draw.text(origin, glyph, font=symbols, fill=rgb(cell['foreground']))
            else:
                draw.text((x * args.cell_width, y * args.cell_height + 1), glyph,
                          font=font, fill=rgb(cell['foreground']))
args.output.parent.mkdir(parents=True, exist_ok=True)
image.save(args.output)
print(f'{width}x{height} native cells -> {args.output}')
