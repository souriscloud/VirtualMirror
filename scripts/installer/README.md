# Souris.CLOUD installer kit — 1.0.0

Common artwork and packaging for Istrek, OptaKube, pgBrain and VirtualMirror.
The shared files are identical in each app repository; only `config.json` differs.
Update the common files together when changing the design.

## Design

- 720 × 440 logical-point canvas and Finder window.
- Deep blue-gray gradient, restrained grid and soft central light.
- 28-point app title, 13-point subtitle, consistent footer and installation hint.
- Ivory brush arrow with a broad swing, tapered pressure and subtle bristle marks.
- 96-point app and Applications icons at (180, 215) and (540, 215).
- Vector drawing in sRGB; packaged backgrounds at 1× (720 × 440, 72 DPI) and
  2× (1440 × 880, 144 DPI), combined into a multi-resolution TIFF.

The renderer also supports a 3× master export. It is deliberately not packed into
Finder's TIFF: Apple's conversion tool does not preserve its logical point size.

## Build

```bash
python3 -m venv .local/dmg-tools
.local/dmg-tools/bin/pip install -r scripts/installer/requirements.txt
scripts/installer/build.sh /path/to/App.app /path/to/output.dmg
```

The app filename must match `config.json`. `SOURIS_INSTALLER_PYTHON` can select
another environment with the same pinned dependencies.

The builder never controls Finder, opens an app, reads signing keys or publishes.
Temporary mounts disable browsing and automatic opening. The final image is
mounted read-only for checks, then detached. It verifies:

- source app and packaged app strict signatures;
- background references and Finder layout;
- both artwork representations' pixel sizes and DPI;
- Applications symlink and executable;
- the DMG checksum.

No Finder flags are written to the signed app bundle. Altering its FinderInfo
can invalidate strict signature verification.

## Off-screen preview

```bash
swift scripts/installer/render.swift --name 'App' --subtitle 'App subtitle' \
  --output preview.png --scale 2 --icon /path/to/AppIcon.icns
```

Icons in this render are for preview only. Finder supplies them in the actual DMG.
An off-screen render is not a Finder screenshot; visual acceptance remains a
separate check on an isolated desktop.
