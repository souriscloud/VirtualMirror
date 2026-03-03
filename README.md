# VirtualMirror

AirPlay screen mirroring receiver for macOS.

Mirror your iPhone or iPad screen to your Mac — no Apple TV required.

## Features

- Receives AirPlay screen mirroring from iOS/iPadOS devices
- Real-time H.264 video decoding and display
- Full AirPlay protocol support (pairing, FairPlay DRM, encryption)
- Menu bar integration with connection status
- Lightweight — runs quietly in the menu bar

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ to build
- iPhone or iPad on the same local network

## Building

```bash
open VirtualMirror.xcodeproj
```

Build and run from Xcode (Cmd+R), or from the command line:

```bash
xcodebuild build -project VirtualMirror.xcodeproj -scheme VirtualMirror
```

## Usage

1. Launch VirtualMirror — it appears in the menu bar and Dock
2. On your iPhone/iPad, open Control Center
3. Tap **Screen Mirroring**
4. Select **VirtualMirror**
5. Your device screen appears in the VirtualMirror window

### Tips

- If VirtualMirror doesn't appear in the Screen Mirroring list, disable the built-in **AirPlay Receiver** in System Settings > General > AirDrop & Handoff
- Close the window to hide it — the app keeps running in the menu bar
- Use the menu bar icon to show the window again, open About, or quit

## Architecture

| Module | Purpose |
|--------|---------|
| `AirPlay/` | Bonjour advertising, TCP server, HTTP/RTSP protocol |
| `Pairing/` | SRP-like pair-setup, Ed25519 pair-verify, session encryption |
| `FairPlay/` | DRM handshake and stream key decryption (C implementation) |
| `Video/` | Mirror stream reception, AES decryption, H.264 decoding, display |
| `Networking/` | HTTP/RTSP parser and response builder |

## License

© 2026 Souris.CLOUD. All rights reserved.

Made by Souris — [bio.souris.cloud](https://bio.souris.cloud)
