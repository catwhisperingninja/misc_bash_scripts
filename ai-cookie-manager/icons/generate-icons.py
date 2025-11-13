#!/usr/bin/env python3
"""
Generate PNG icons from SVG for the Chrome extension.
Requires: pip install cairosvg
"""

import sys

try:
    import cairosvg
except ImportError:
    print("Error: cairosvg not installed")
    print("Install with: pip install cairosvg")
    sys.exit(1)

sizes = [16, 48, 128]
svg_file = "icon.svg"

for size in sizes:
    output_file = f"icon{size}.png"
    print(f"Generating {output_file}...")

    cairosvg.svg2png(
        url=svg_file,
        write_to=output_file,
        output_width=size,
        output_height=size
    )

print("Icons generated successfully!")
