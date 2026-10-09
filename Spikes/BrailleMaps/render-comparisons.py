#!/usr/bin/env python3
"""Render captured native raster variants and assemble comparisons (requires Pillow)."""

import argparse
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import textwrap

from PIL import Image, ImageDraw, ImageFont


CELL_WIDTH = 12
CELL_HEIGHT = 24
VARIANTS = (
    ("existing", "Existing renderer"),
    ("outlines", "Braille outlines"),
    ("textured", "Braille textured"),
)
RENDER_SCRIPT = Path(__file__).resolve().parents[2] / "Scripts/maps/render-snapshot.py"


def integer(value, name, minimum=1):
    if type(value) is not int or value < minimum:
        raise ValueError(f"{name} must be an integer >= {minimum}")
    return value


def read_manifest(directory):
    scenes = json.loads((directory / "manifest.json").read_text())
    if not isinstance(scenes, list) or not scenes:
        raise ValueError("manifest.json must contain a nonempty array of scenes")
    ids = set()
    for scene in scenes:
        if not isinstance(scene, dict):
            raise ValueError("each manifest scene must be an object")
        scene_id = scene.get("id")
        if not isinstance(scene_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", scene_id):
            raise ValueError("scene id must contain only letters, numbers, underscores or hyphens")
        if scene_id in ids:
            raise ValueError(f"duplicate scene id: {scene_id}")
        ids.add(scene_id)
        for field in ("title", "detail"):
            if not isinstance(scene.get(field), str) or not scene[field]:
                raise ValueError(f"{scene_id}: {field} must be a nonempty string")
        source = scene.get("source")
        if not isinstance(source, dict):
            raise ValueError(f"{scene_id}: source must be an object")
        for field in ("attribution", "license", "licenseURL"):
            if not isinstance(source.get(field), str) or not source[field]:
                raise ValueError(f"{scene_id}: source.{field} must be a nonempty string")
        attribution_url = source.get("attributionURL")
        if attribution_url is not None and not isinstance(attribution_url, str):
            raise ValueError(f"{scene_id}: source.attributionURL must be a string or null")
        width = integer(scene.get("width"), f"{scene_id}: width")
        height = integer(scene.get("height"), f"{scene_id}: height")
        camera = scene.get("camera")
        if not isinstance(camera, dict):
            raise ValueError(f"{scene_id}: camera must be an object")
        center = camera.get("center")
        if not isinstance(center, dict):
            raise ValueError(f"{scene_id}: camera.center must be an object")
        for field, value in (("center.latitude", center.get("latitude")),
                             ("center.longitude", center.get("longitude")),
                             ("longitudeSpan", camera.get("longitudeSpan"))):
            if type(value) not in (int, float) or not math.isfinite(value):
                raise ValueError(f"{scene_id}: camera.{field} must be finite")
        if "crop" in scene:
            crop = scene["crop"]
            if not isinstance(crop, dict):
                raise ValueError(f"{scene_id}: crop must be an object in cell coordinates")
            x = integer(crop.get("x"), f"{scene_id}: crop.x", 0)
            y = integer(crop.get("y"), f"{scene_id}: crop.y", 0)
            crop_width = integer(crop.get("width"), f"{scene_id}: crop.width")
            crop_height = integer(crop.get("height"), f"{scene_id}: crop.height")
            if x + crop_width > width or y + crop_height > height:
                raise ValueError(f"{scene_id}: crop exceeds the captured cell dimensions")
        for variant, _ in VARIANTS:
            snapshot = directory / f"{scene_id}-{variant}.json"
            if not snapshot.is_file():
                raise ValueError(f"missing capture: {snapshot}")
    return scenes


def comparison(images, scene, font, output, crop=None):
    """Paste native PNGs unchanged; only detail crops are enlarged by the caller."""
    padding, gap, line_height = 16, 16, 20
    panel_width, panel_height = images[0].size
    content_width = 3 * panel_width + 2 * gap
    camera = scene["camera"]
    source = scene["source"]
    credit_url = source.get("attributionURL") or source["licenseURL"]
    captions = [
        f"{scene['title']} | scene {scene['id']} | detail {scene['detail']}",
        f"{scene['width']} x {scene['height']} cells | cell {CELL_WIDTH} x {CELL_HEIGHT} px | "
        f"camera lat {camera['center']['latitude']}, lon {camera['center']['longitude']}, "
        f"longitude span {camera['longitudeSpan']} degrees",
        f"Source: {source['attribution']} | License: {source['license']} | {credit_url}",
        "Native-raster export, not an emulator screenshot. "
        "Legend: existing renderer | braille outlines | braille textured.",
        "Prototype legend: route = bright pink; position = amber dot ring. "
        "Existing renderer retains the selected diamond.",
    ]
    if crop is not None:
        captions.append(
            f"Detail crop: x={crop['x']}, y={crop['y']}, "
            f"{crop['width']} x {crop['height']} cells (top-left origin); "
            "exactly 2x nearest-neighbor enlargement of rendered pixels."
        )
    character_width = font.getlength("M")

    def lines(text, width):
        return textwrap.wrap(text, width=max(1, int(width / character_width)))

    caption_lines = [line for caption in captions for line in lines(caption, content_width)]
    label_lines = [lines(label, panel_width) for _, label in VARIANTS]
    header_height = (len(caption_lines) + max(map(len, label_lines))) * line_height + gap
    canvas = Image.new("RGB", (content_width + 2 * padding,
                               panel_height + header_height + 2 * padding), "#131922")
    draw = ImageDraw.Draw(canvas)
    for index, line in enumerate(caption_lines):
        draw.text((padding, padding + index * line_height), line, font=font, fill="#dbe4ef")
    labels_y = padding + len(caption_lines) * line_height + gap
    images_y = padding + header_height
    for index, image in enumerate(images):
        x = padding + index * (panel_width + gap)
        for line_index, line in enumerate(label_lines[index]):
            draw.text((x, labels_y + line_index * line_height), line, font=font, fill="#ffffff")
        canvas.paste(image, (x, images_y))
    canvas.save(output)
    print(output)


def render_scene(directory, scene, args, font):
    images = []
    for variant, _ in VARIANTS:
        output = directory / f"{scene['id']}-{variant}.png"
        subprocess.run([
            sys.executable, str(RENDER_SCRIPT),
            str(directory / f"{scene['id']}-{variant}.json"), str(output),
            "--font", str(args.font), "--symbol-font", str(args.symbol_font),
            "--cell-width", str(CELL_WIDTH), "--cell-height", str(CELL_HEIGHT),
        ], check=True)
        with Image.open(output) as image:
            expected_size = (scene["width"] * CELL_WIDTH, scene["height"] * CELL_HEIGHT)
            if image.size != expected_size:
                raise ValueError(f"{output.name}: expected {expected_size} pixels, got {image.size}")
            images.append(image.convert("RGB"))
    comparison(images, scene, font, directory / f"{scene['id']}-comparison.png")
    if "crop" in scene:
        crop = scene["crop"]
        box = (crop["x"] * CELL_WIDTH, crop["y"] * CELL_HEIGHT,
               (crop["x"] + crop["width"]) * CELL_WIDTH,
               (crop["y"] + crop["height"]) * CELL_HEIGHT)
        size = (crop["width"] * CELL_WIDTH * 2, crop["height"] * CELL_HEIGHT * 2)
        crops = [image.crop(box).resize(size, Image.Resampling.NEAREST) for image in images]
        comparison(crops, scene, font, directory / f"{scene['id']}-detail.png", crop)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture_directory", type=Path)
    parser.add_argument("--font", type=Path, default=Path("/System/Library/Fonts/Menlo.ttc"))
    parser.add_argument("--symbol-font", type=Path,
                        default=Path("/System/Library/Fonts/Apple Symbols.ttf"))
    args = parser.parse_args()
    try:
        directory = args.capture_directory.resolve(strict=True)
        scenes = read_manifest(directory)
        font = ImageFont.truetype(str(args.font), size=14)
        for scene in scenes:
            render_scene(directory, scene, args, font)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{parser.prog}: {error}\n")


if __name__ == "__main__":
    main()
