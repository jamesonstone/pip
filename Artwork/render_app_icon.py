#!/usr/bin/env python3
"""Regenerate Pip's AppIcon PNGs and the docs preview.

Requires cairosvg and Pillow. Run from anywhere:

    python3 Artwork/render_app_icon.py

octopus.svg is the artwork for 32 px and up. OPTICAL_16 is the pixel grid for
the 16 px share-menu slot, where the vector collapses. The script writes every
slot in AppIcon.appiconset/Contents.json and docs/octopus-icon-preview.png.
"""

from __future__ import annotations

import io
import json
from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SVG_PATH = Path(__file__).with_name("octopus.svg")
ICONSET = ROOT / "App" / "Assets.xcassets" / "AppIcon.appiconset"
PREVIEW_PATH = ROOT / "docs" / "octopus-icon-preview.png"
CONTENTS = ICONSET / "Contents.json"

# App window background, so the preview sits on the same field as Settings.
CANVAS = (18, 18, 20)
# Flatten any renderer fringe onto the tile instead of black.
MATTE = (20, 16, 44)
TILE_TOP = (58, 46, 134)  # #3A2E86
TILE_BOT = (20, 16, 44)  # #14102C
GLOW_PURPLE = (139, 120, 255)
GLOW_BLUE = (97, 199, 250)  # PipPalette.accent
BODY = (246, 248, 255)
EYE = (26, 20, 56)

# Optical 16 px mark for the non-retina share menu. The SVG collapses at this
# size, so the limbs and the two eyes are placed on the pixel grid.
OPTICAL_16 = (
    "................",
    ".....#....#.....",
    "....##....##....",
    "...#..####..#...",
    "..#..######..#..",
    "..#.########.#..",
    "..#.#EE##EE#.#..",
    "..#.#EE##EE#.#..",
    "....########....",
    "..###.#..#.###..",
    ".###..#..#..###.",
    ".##...#..#...##.",
    ".##...#..#...##.",
    "..#...#..#...#..",
    "................",
    "................",
)


def mix(start: tuple[int, int, int], end: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    return tuple(int(start[channel] + (end[channel] - start[channel]) * amount) for channel in range(3))


def optical_16() -> Image.Image:
    if any(len(row) != 16 for row in OPTICAL_16) or len(OPTICAL_16) != 16:
        raise SystemExit("optical 16 px grid must be 16 by 16")
    image = Image.new("RGB", (16, 16))
    pixels = image.load()
    for y, row in enumerate(OPTICAL_16):
        for x, mark in enumerate(row):
            amount = (x + y) / 30
            base = mix(TILE_TOP, TILE_BOT, amount)
            dx = (x - 7.5) / 16
            dy = (y - 6.2) / 16
            falloff = max(0.0, 1 - (dx * dx * 1.4 + dy * dy * 1.6) * 3.2)
            glow = mix(GLOW_PURPLE, GLOW_BLUE, amount)
            color = mix(base, glow, falloff * 0.82)
            if mark == "#":
                color = BODY
            elif mark == "E":
                color = EYE
            pixels[x, y] = color
    # Two separate eyes, with body between them, and a gap between the middle legs.
    if pixels[5, 6] != EYE or pixels[9, 6] != EYE or pixels[7, 6] != BODY:
        raise SystemExit("16 px eyes are not separated")
    if pixels[7, 11] == BODY or pixels[8, 11] == BODY:
        raise SystemExit("16 px middle legs are not separated")
    return image


def load_svg(pixel_size: int) -> str:
    svg = SVG_PATH.read_text(encoding="utf-8")
    # Catchlights wash the eyes out once the eye is only a couple of pixels.
    if pixel_size <= 48:
        svg = svg.replace('id="catchlight"', 'id="catchlight" display="none"')
    return svg


def rasterize(pixel_size: int) -> Image.Image:
    if pixel_size == 16:
        return optical_16()
    png = cairosvg.svg2png(
        bytestring=load_svg(pixel_size).encode("utf-8"),
        output_width=pixel_size,
        output_height=pixel_size,
    )
    image = Image.open(io.BytesIO(png)).convert("RGBA")
    flat = Image.new("RGB", image.size, MATTE)
    flat.paste(image, mask=image.getchannel("A"))
    return flat


def pixel_size(entry: dict) -> int:
    width, height = (int(part) for part in entry["size"].split("x"))
    if width != height:
        raise SystemExit(f"non-square icon slot: {entry}")
    scale = entry.get("scale", "1x")
    factor = int(scale.removesuffix("x"))
    return width * factor


def appearance(entry: dict) -> str:
    for item in entry.get("appearances", []):
        if item.get("appearance") == "luminosity":
            return str(item.get("value"))
    return "any"


def to_dark(image: Image.Image) -> Image.Image:
    """Deepen the tile and glow. Leave the light octopus alone."""
    pixels = image.convert("RGB")
    source = pixels.load()
    width, height = pixels.size
    for y in range(height):
        for x in range(width):
            red, green, blue = source[x, y]
            luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            if luma < 150:
                source[x, y] = (int(red * 0.70), int(green * 0.68), int(blue * 0.76))
    return pixels


def to_tinted(image: Image.Image) -> Image.Image:
    """Grayscale, no alpha. iOS colorizes this slot."""
    return image.convert("L")


def render_slot(entry: dict, cache: dict[int, Image.Image]) -> None:
    size = pixel_size(entry)
    if size not in cache:
        cache[size] = rasterize(size)
    image = cache[size]
    kind = appearance(entry)
    if kind == "dark":
        image = to_dark(image)
    elif kind == "tinted":
        image = to_tinted(image)
    elif kind != "any":
        raise SystemExit(f"unsupported appearance: {kind}")
    if image.size != (size, size):
        raise SystemExit(f"rendered {image.size} for a {size} slot")
    expected = "L" if kind == "tinted" else "RGB"
    if image.mode != expected:
        raise SystemExit(f"{entry['filename']} is {image.mode}, expected {expected}")
    image.save(ICONSET / entry["filename"], format="PNG", optimize=True)


def squircle_mask(size: int) -> Image.Image:
    """Apple-like superellipse, so the preview shows the rounded tile."""
    mask = Image.new("L", (size, size), 0)
    pixels = mask.load()
    radius = (size - 1) / 2
    power = 4.2
    for y in range(size):
        for x in range(size):
            nx = abs(x - radius) / radius
            ny = abs(y - radius) / radius
            if nx**power + ny**power <= 1:
                pixels[x, y] = 255
    return mask


def nearest(image: Image.Image, scale: int) -> Image.Image:
    width, height = image.size
    return image.resize((width * scale, height * scale), Image.Resampling.NEAREST)


def write_preview(master: Image.Image, small: Image.Image, medium: Image.Image) -> None:
    canvas = Image.new("RGB", (1200, 860), CANVAS)
    icon = master.resize((680, 680), Image.Resampling.LANCZOS)
    mask = squircle_mask(680)
    rounded = Image.new("RGBA", (680, 680))
    rounded.paste(icon, mask=mask)
    plate = Image.new("RGB", (680, 680), CANVAS)
    plate.paste(rounded, mask=rounded.getchannel("A"))
    canvas.paste(plate, (70, 90))

    draw = ImageDraw.Draw(canvas)
    draw.text((820, 150), "16 px", fill=(255, 255, 255))
    canvas.paste(nearest(small, 14), (820, 190))
    draw.text((820, 470), "32 px", fill=(255, 255, 255))
    canvas.paste(nearest(medium, 7), (820, 510))

    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(PREVIEW_PATH, format="PNG", optimize=True)


def main() -> None:
    catalog = json.loads(CONTENTS.read_text(encoding="utf-8"))
    cache: dict[int, Image.Image] = {}
    seen: list[str] = []
    for entry in catalog["images"]:
        render_slot(entry, cache)
        seen.append(entry["filename"])
    write_preview(cache[1024], cache[16], cache[32])
    print(f"wrote {len(seen)} icons and {PREVIEW_PATH.relative_to(ROOT)}")
    for name in seen:
        path = ICONSET / name
        with Image.open(path) as image:
            print(f"  {name} {image.size[0]}x{image.size[1]} {image.mode}")


if __name__ == "__main__":
    main()
