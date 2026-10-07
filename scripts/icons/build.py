#!/usr/bin/env python3
"""Render, verify and atomically update the approved Souris icon assets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
LOGO_SHA256 = "3ac383a78042c21b12600e8cf11a5e8e368a1a76200a1126872562be66ce9751"
SIZES = (16, 32, 64, 128, 256, 512, 1024)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dimensions(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[25] != 6:
        raise ValueError(f"Expected RGBA PNG: {path}")
    return struct.unpack(">II", data[16:24])


def atomic_copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = destination.with_name(destination.name + ".new")
    shutil.copyfile(source, temp)
    os.replace(temp, destination)


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--force", action="store_true")
parser.add_argument("--output", type=Path)
args = parser.parse_args()
config = json.loads((HERE / "config.json").read_text())
assert digest(HERE / "souris-original.png") == LOGO_SHA256, "Original logo changed"
icon = args.output.resolve() if args.output else ROOT / config["icon"]
png = ROOT / config["png"]
manifest = HERE / "manifest.json"
inputs = {
    name: digest(HERE / name)
    for name in (
        "render.swift",
        "config.json",
        "souris-original.png",
        "build.py",
        "verify.swift",
    )
}
if not args.force and not args.output and manifest.exists():
    previous = json.loads(manifest.read_text())
    if (
        previous.get("inputs") == inputs
        and all(
            (ROOT / name).is_file() and digest(ROOT / name) == expected
            for name, expected in previous.get("outputs", {}).items()
        )
        and previous.get("outputs")
    ):
        print(f"{config['name']}: approved icon assets are current")
        raise SystemExit(0)
with tempfile.TemporaryDirectory(prefix="souris-icons-") as temp:
    work = Path(temp)
    renderer = work / "render"
    subprocess.run(
        ["swiftc", str(HERE / "render.swift"), "-o", str(renderer)], check=True
    )
    for size in SIZES:
        output = work / f"{size}.png"
        subprocess.run(
            [
                str(renderer),
                "--app",
                config["name"],
                "--size",
                str(size),
                "--logo",
                str(HERE / "souris-original.png"),
                "--output",
                str(output),
            ],
            check=True,
        )
        assert dimensions(output) == (size, size), output
    subprocess.run(
        [
            "swift",
            str(HERE / "verify.swift"),
            *[str(work / f"{size}.png") for size in SIZES],
        ],
        check=True,
    )
    iconset = work / "AppIcon.iconset"
    iconset.mkdir()
    entries = []
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{size}x{size}" + ("@2x" if scale == 2 else "") + ".png"
            shutil.copyfile(work / f"{size * scale}.png", iconset / name)
            entries.append(
                {
                    "idiom": "mac",
                    "size": f"{size}x{size}",
                    "scale": f"{scale}x",
                    "filename": name,
                }
            )
    packed = work / "AppIcon.icns"
    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset), "-o", str(packed)], check=True
    )
    check = work / "check.iconset"
    subprocess.run(
        ["iconutil", "-c", "iconset", str(packed), "-o", str(check)], check=True
    )
    assert len(list(check.glob("*.png"))) == 10
    for entry in entries:
        size = int(entry["size"].split("x")[0]) * int(entry["scale"][0])
        assert dimensions(check / entry["filename"]) == (size, size)
    atomic_copy(packed, icon)
    if args.output:
        print(f"Verified icon: {icon}")
        raise SystemExit(0)
    atomic_copy(work / "1024.png", png)
    outputs = [icon, png]
    if config.get("appiconset"):
        asset = ROOT / config["appiconset"]
        asset.mkdir(parents=True, exist_ok=True)
        for size in SIZES:
            path = asset / f"icon_{size}x{size}.png"
            atomic_copy(work / f"{size}.png", path)
            outputs.append(path)
        for entry in entries:
            size = int(entry["size"].split("x")[0]) * int(entry["scale"][0])
            entry["filename"] = f"icon_{size}x{size}.png"
        contents = work / "Contents.json"
        contents.write_text(
            json.dumps(
                {"images": entries, "info": {"author": "xcode", "version": 1}}, indent=2
            )
            + "\n"
        )
        atomic_copy(contents, asset / "Contents.json")
        outputs.append(asset / "Contents.json")
    result = {
        "design": config["design"],
        "inputs": inputs,
        "outputs": {str(path.relative_to(ROOT)): digest(path) for path in outputs},
        "native_png_sizes": list(SIZES),
        "icns_representations": 10,
        "original_logo_sha256": LOGO_SHA256,
    }
    receipt = work / "manifest.json"
    receipt.write_text(json.dumps(result, indent=2) + "\n")
    atomic_copy(receipt, manifest)
print(f"{config['name']}: generated and verified native PNGs, ICNS and transparency")
