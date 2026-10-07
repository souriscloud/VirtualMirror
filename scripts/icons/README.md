# Souris app icon family

Run `python3 scripts/icons/build.py` to regenerate the app icon and PNG from the committed renderer and original logo. Rendering is deterministic and uses sRGB with transparency. It does not launch an app or change the desktop.

All four apps share the same renderer and original logo. Only config.json differs. The original logo is scaled proportionally, without tracing, recolouring or cropping. The cool gray data circuit fades radially before the body edge. The detail is omitted at 16 pixels, and the original logo badge is omitted below 64 pixels for legibility.

Every macOS 1x/2x slot is rendered at its native size, then packaged with iconutil. The build verifies dimensions, transparent outer edges, original logo checksum and all ten ICNS representations. VirtualMirror also receives an Xcode appiconset. Config describes the approved design; rendering constants live in render.swift.
