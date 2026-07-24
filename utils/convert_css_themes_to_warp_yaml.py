#!/usr/bin/env python3
"""Convert CSS color-variable themes into Warp terminal theme YAML files."""

from __future__ import annotations

import argparse
import colorsys
import re
from pathlib import Path


CSS_VAR_RE = re.compile(r"--([A-Za-z0-9_-]+)\s*:\s*([^;]+);")
HEX_RE = re.compile(r"#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\b")
RGB_RE = re.compile(r"rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})")


COLOR_ORDER = ("black", "blue", "cyan", "green", "magenta", "red", "white", "yellow")


def clamp(value: float) -> float:
    return max(0.0, min(1.0, value))


def normalize_hex(value: str) -> str | None:
    hex_match = HEX_RE.search(value)
    if hex_match:
        raw = hex_match.group(0).lstrip("#")
        if len(raw) == 3:
            raw = "".join(char * 2 for char in raw)
        return f"#{raw.upper()}"

    rgb_match = RGB_RE.search(value)
    if rgb_match:
        red, green, blue = (max(0, min(255, int(part))) for part in rgb_match.groups())
        return f"#{red:02X}{green:02X}{blue:02X}"

    return None


def parse_css_vars(css_path: Path) -> dict[str, str]:
    variables: dict[str, str] = {}
    for name, value in CSS_VAR_RE.findall(css_path.read_text(encoding="utf-8")):
        color = normalize_hex(value)
        if color:
            variables[name] = color
    return variables


def pick(variables: dict[str, str], *names: str, fallback: str) -> str:
    for name in names:
        if name in variables:
            return variables[name]
    return fallback


def hex_to_rgb(color: str) -> tuple[float, float, float]:
    color = color.lstrip("#")
    return tuple(int(color[index : index + 2], 16) / 255 for index in (0, 2, 4))


def rgb_to_hex(red: float, green: float, blue: float) -> str:
    return f"#{round(clamp(red) * 255):02X}{round(clamp(green) * 255):02X}{round(clamp(blue) * 255):02X}"


def relative_luminance(color: str) -> float:
    def linearize(channel: float) -> float:
        return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4

    red, green, blue = (linearize(channel) for channel in hex_to_rgb(color))
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def adjust_lightness(color: str, delta: float) -> str:
    red, green, blue = hex_to_rgb(color)
    hue, lightness, saturation = colorsys.rgb_to_hls(red, green, blue)
    red, green, blue = colorsys.hls_to_rgb(hue, clamp(lightness + delta), saturation)
    return rgb_to_hex(red, green, blue)


def rotate_hue(color: str, degrees: float) -> str:
    red, green, blue = hex_to_rgb(color)
    hue, lightness, saturation = colorsys.rgb_to_hls(red, green, blue)
    red, green, blue = colorsys.hls_to_rgb((hue + degrees / 360) % 1, lightness, saturation)
    return rgb_to_hex(red, green, blue)


def readable_yellow(candidate: str, is_dark: bool) -> str:
    luminance = relative_luminance(candidate)
    if is_dark and luminance >= 0.25:
        return candidate
    if not is_dark and luminance <= 0.55:
        return candidate
    return "#D4A539" if is_dark else "#B8860B"


def build_theme(variables: dict[str, str]) -> dict[str, object]:
    background = pick(variables, "bg", "background", fallback="#000000")
    foreground = pick(variables, "fg", "foreground", fallback="#FFFFFF")
    accent = pick(variables, "accent", "link", "sidebar-active", fallback=foreground)
    is_dark = relative_luminance(background) < 0.5

    code_bg = pick(
        variables,
        "code-bg",
        "sidebar-bg",
        fallback=adjust_lightness(background, -0.08 if is_dark else 0.08),
    )
    border = pick(variables, "border", fallback=adjust_lightness(background, 0.1 if is_dark else -0.1))
    secondary = pick(variables, "fg-secondary", "sidebar-fg", fallback=border)
    heading = pick(variables, "heading", "blockquote-border", fallback=accent)
    code_fg = pick(variables, "code-fg", fallback=heading)
    link = pick(variables, "link", fallback=accent)
    accent_hover = pick(variables, "accent-hover", "link-hover", fallback=adjust_lightness(accent, 0.12 if is_dark else -0.12))
    highlight = readable_yellow(pick(variables, "highlight", fallback=rotate_hue(accent, -40)), is_dark)

    blue = rotate_hue(accent, 130)
    cyan = rotate_hue(accent, 85)

    normal = {
        "black": code_bg if is_dark else foreground,
        "blue": adjust_lightness(blue, -0.08 if is_dark else -0.18),
        "cyan": adjust_lightness(cyan, -0.08 if is_dark else -0.18),
        "green": accent if is_dark else link,
        "magenta": heading,
        "red": code_fg,
        "white": foreground if is_dark else code_bg,
        "yellow": highlight,
    }
    bright = {
        "black": border if is_dark else secondary,
        "blue": adjust_lightness(blue, 0.12 if is_dark else 0.02),
        "cyan": adjust_lightness(cyan, 0.12 if is_dark else 0.02),
        "green": accent_hover,
        "magenta": adjust_lightness(heading, 0.12 if is_dark else 0.03),
        "red": adjust_lightness(code_fg, 0.12 if is_dark else 0.08),
        "white": "#FFFFFF",
        "yellow": adjust_lightness(highlight, 0.12 if is_dark else 0.04),
    }

    return {
        "accent": accent,
        "background": background,
        "details": "darker" if is_dark else "lighter",
        "foreground": foreground,
        "terminal_colors": {
            "bright": bright,
            "normal": normal,
        },
    }


def render_theme(theme: dict[str, object]) -> str:
    terminal_colors = theme["terminal_colors"]
    assert isinstance(terminal_colors, dict)

    lines = [
        f'accent: "{theme["accent"]}"',
        f'background: "{theme["background"]}"',
        f'details: {theme["details"]}',
        f'foreground: "{theme["foreground"]}"',
        "terminal_colors:",
    ]

    for group_name in ("bright", "normal"):
        group = terminal_colors[group_name]
        assert isinstance(group, dict)
        lines.append(f"  {group_name}:")
        for color_name in COLOR_ORDER:
            lines.append(f'    {color_name}: "{group[color_name]}"')

    return "\n".join(lines) + "\n"


def convert_css_file(css_path: Path, output_dir: Path, force: bool, dry_run: bool) -> str:
    output_path = output_dir / f"{css_path.stem}.yaml"
    if output_path.exists() and not force:
        return f"skip {output_path.name}: already exists"

    variables = parse_css_vars(css_path)
    if not variables:
        return f"skip {css_path.name}: no CSS color variables found"

    yaml_text = render_theme(build_theme(variables))
    if dry_run:
        action = "would overwrite" if output_path.exists() else "would write"
        return f"{action} {output_path.name}"

    output_path.write_text(yaml_text, encoding="utf-8")
    return f"wrote {output_path.name}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert *.css files with :root color variables into Warp *.yaml themes.")
    parser.add_argument("directory", nargs="?", default=".", type=Path, help="Directory containing CSS theme files.")
    parser.add_argument("--output-dir", type=Path, help="Directory for generated YAML files. Defaults to the input directory.")
    parser.add_argument("--force", action="store_true", help="Overwrite existing YAML files.")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be generated without writing files.")
    args = parser.parse_args()

    input_dir = args.directory.expanduser().resolve()
    output_dir = (args.output_dir or input_dir).expanduser().resolve()

    if not input_dir.is_dir():
        parser.error(f"{input_dir} is not a directory")
    if not args.dry_run:
        output_dir.mkdir(parents=True, exist_ok=True)

    css_files = sorted(input_dir.glob("*.css"))
    if not css_files:
        print(f"no CSS files found in {input_dir}")
        return 0

    for css_path in css_files:
        print(convert_css_file(css_path, output_dir, args.force, args.dry_run))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
