#!/usr/bin/env python3
"""Prepare verified patch-release artifacts without publishing or opening GUI apps."""
import argparse, hashlib, json, os
from pathlib import Path
import plistlib, re, shutil, subprocess

ROOT = Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / "scripts/icons/config.json").read_text())
NAME = CONFIG["name"]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    "--reuse-build",
    action="store_true",
    help="Use the already compiled release product",
)
args = parser.parse_args()


def run(command, **kwargs):
    subprocess.run(command, check=True, **kwargs)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


run(["python3", str(ROOT / "scripts/icons/build.py")])
if NAME == "VirtualMirror":
    project = ROOT / "VirtualMirror.xcodeproj/project.pbxproj"
    source = project.read_text()
    versions = set(re.findall(r"MARKETING_VERSION = ([^;]+);", source))
    assert len(versions) == 1
    version = versions.pop()
    out = ROOT / ".local/releases" / version
    archive = out / (NAME + ".xcarchive")
    if not args.reuse_build:
        run(
            [
                "nice",
                "-n",
                "10",
                "xcodebuild",
                "archive",
                "-project",
                str(ROOT / "VirtualMirror.xcodeproj"),
                "-scheme",
                NAME,
                "-configuration",
                "Release",
                "-destination",
                "generic/platform=macOS",
                "-archivePath",
                str(archive),
                "-derivedDataPath",
                str(out / "ArchiveDerivedData"),
                "-clonedSourcePackagesDirPath",
                str(ROOT / ".local/SourcePackages"),
                "CODE_SIGNING_ALLOWED=NO",
            ]
        )
    source_app = archive / "Products/Applications" / (NAME + ".app")
    assert source_app.exists(), "Compile release app first"
    info = plistlib.loads((source_app / "Contents/Info.plist").read_bytes())
else:
    plist = ROOT / (
        "Sources/OptaKube/Info.plist" if NAME == "OptaKube" else "Resources/Info.plist"
    )
    info = plistlib.loads(plist.read_bytes())
    version = info["CFBundleShortVersionString"]
    out = ROOT / ".local/releases" / version
    if not args.reuse_build:
        run(
            ["nice", "-n", "10", "swift", "test"],
            cwd=ROOT,
            env={**os.environ, "PGBRAIN_KEYCHAIN_TESTS": "0"},
        )
        run(["nice", "-n", "10", "swift", "build", "-c", "release"], cwd=ROOT)
    products = Path(
        subprocess.check_output(
            ["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT, text=True
        ).strip()
    )
    assert (products / NAME).exists(), "Compile release binary first"

out.mkdir(parents=True, exist_ok=True)
app = out / (NAME + ".app")
stage = out / (NAME + ".app.staging")
if stage.exists():
    shutil.rmtree(stage)
if NAME == "VirtualMirror":
    run(["ditto", str(source_app), str(stage)])
else:
    for directory in ["MacOS", "Resources", "Frameworks"]:
        (stage / "Contents" / directory).mkdir(parents=True, exist_ok=True)
    shutil.copy2(products / NAME, stage / "Contents/MacOS" / NAME)
    shutil.copy2(plist, stage / "Contents/Info.plist")
    shutil.copy2(ROOT / CONFIG["icon"], stage / "Contents/Resources/AppIcon.icns")
    bundle = products / "OptaKube_OptaKube.bundle"
    if NAME == "OptaKube":
        assert bundle.exists(), "SwiftPM icon resource bundle missing"
        run(["ditto", str(bundle), str(stage / "Contents/Resources" / bundle.name)])
    framework = (
        ROOT
        / ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    )
    assert framework.exists(), "Sparkle framework missing"
    run(["ditto", str(framework), str(stage / "Contents/Frameworks/Sparkle.framework")])
    (stage / "Contents/PkgInfo").write_bytes(b"APPL????")
    # OptaKube's SwiftPM binary needs the bundled framework search path.
    if NAME == "OptaKube":
        binary = stage / "Contents/MacOS" / NAME
        links = subprocess.check_output(["otool", "-l", str(binary)], text=True)
        if "@executable_path/../Frameworks" not in links:
            run(
                [
                    "install_name_tool",
                    "-add_rpath",
                    "@executable_path/../Frameworks",
                    str(binary),
                ]
            )

sparkle = stage / "Contents/Frameworks/Sparkle.framework"
for suffix in [
    "Versions/B/XPCServices/Downloader.xpc",
    "Versions/B/XPCServices/Installer.xpc",
    "Versions/B/Autoupdate",
    "Versions/B/Updater.app",
    "",
]:
    target = sparkle / suffix
    if target.exists():
        run(["codesign", "--force", "--sign", "-", str(target)])
run(["codesign", "--force", "--sign", "-", str(stage)])
run(["codesign", "--verify", "--deep", "--strict", str(stage)])
actual = plistlib.loads((stage / "Contents/Info.plist").read_bytes())
assert actual["CFBundleShortVersionString"] == version, "Stale bundle version"
icon_file = actual.get("CFBundleIconFile", "AppIcon")
if not icon_file.endswith(".icns"):
    icon_file += ".icns"
assert (stage / "Contents/Resources" / icon_file).is_file(), "Bundle icon is missing"
if app.exists():
    shutil.rmtree(app)
os.replace(stage, app)
dmg = out / f"{NAME}-{version}.dmg"
run([str(ROOT / "scripts/installer/build.sh"), str(app), str(dmg)])
run(
    [
        "swift",
        str(ROOT / "scripts/installer/render.swift"),
        "--name",
        NAME,
        "--subtitle",
        json.loads((ROOT / "scripts/installer/config.json").read_text())["subtitle"],
        "--icon",
        str(app / "Contents/Resources" / icon_file),
        "--output",
        str(out / "installer-preview.png"),
        "--scale",
        "2",
    ]
)
manifest = {
    "name": NAME,
    "version": version,
    "build": actual["CFBundleVersion"],
    "signing": "ad-hoc",
    "published": False,
    "notarized": False,
    "focus_taken": False,
    "architectures": subprocess.check_output(
        ["lipo", "-archs", str(app / "Contents/MacOS" / NAME)], text=True
    )
    .strip()
    .split(),
    "icon_sha256": sha(app / "Contents/Resources" / icon_file),
    "dmg": {"file": dmg.name, "sha256": sha(dmg), "bytes": dmg.stat().st_size},
}
(out / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Prepared verified local artifacts: {out}. No publication or GUI launch.")
