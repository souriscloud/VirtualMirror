# VirtualMirror

AirPlay screen mirroring receiver for macOS. Mirror your iPhone or iPad screen to your Mac — no Apple TV required.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

<!-- TODO: Add screenshot here -->
<!-- ![Screenshot](screenshot.png) -->

## Features

- **Screen Mirroring** — Receive AirPlay mirroring from any iPhone or iPad
- **Audio** — Full audio passthrough with adjustable volume control
- **Rotation** — Seamlessly handles device rotation and lock/unlock
- **Low Latency** — Hardware-accelerated H.264 decoding via VideoToolbox
- **Menu Bar** — Runs quietly in the menu bar with live connection status
- **Auto-Update** — Built-in update checking via Sparkle
- **Secure** — Cryptographic identity stored in macOS Keychain; full AirPlay pairing and FairPlay DRM support

## Download

Download the latest `.dmg` from [GitHub Releases](https://github.com/souriscloud/VirtualMirror/releases/latest).

1. Open the `.dmg` and drag **VirtualMirror** to your Applications folder
2. Launch VirtualMirror — it will check for updates automatically

> VirtualMirror is signed and notarized by Apple. If macOS asks to confirm, right-click the app and select **Open**.

## Usage

1. Launch VirtualMirror — it appears in the menu bar and Dock
2. On your iPhone or iPad, open **Control Center**
3. Tap **Screen Mirroring**
4. Select **VirtualMirror**
5. Your device screen appears in the VirtualMirror window

### Volume Control

Hover over the mirroring window to reveal the volume slider. Click the speaker icon to mute/unmute.

### Menu Bar

The menu bar icon shows live connection status:
- **Show/Hide Window** — Toggle the main window
- **Check for Updates...** — Manually check for a new version
- **About VirtualMirror...** — Version info and credits

## Troubleshooting

### VirtualMirror doesn't appear in Screen Mirroring list

If the macOS built-in **AirPlay Receiver** is enabled, your iPhone may connect to it instead of VirtualMirror. To avoid confusion, you can disable it:

**System Settings > General > AirDrop & Handoff > AirPlay Receiver** — turn it off.

### Connection drops or won't connect

- Make sure your iPhone/iPad and Mac are on the **same Wi-Fi network**
- Restart VirtualMirror from the menu bar (Quit, then relaunch)
- Check that no firewall is blocking port **47000**

### Keychain prompt on first launch

VirtualMirror stores a cryptographic identity key in the macOS Keychain for AirPlay pairing. The system may prompt for your password once — this is expected and only happens on first launch.

## Building from Source

Requires macOS 14.0+ and Xcode 15+.

```bash
git clone https://github.com/souriscloud/VirtualMirror.git
cd VirtualMirror
open VirtualMirror.xcodeproj
```

Build and run from Xcode (Cmd+R), or from the command line:

```bash
xcodebuild build -project VirtualMirror.xcodeproj -scheme VirtualMirror -configuration Debug
```

## Acknowledgments

VirtualMirror builds on the work of several open-source projects:

- **[playfair](https://github.com/EstebanKubworta/playfair)** by EstebanKubata — FairPlay DRM reverse-engineering (GPL)
- **[UxPlay](https://github.com/antimof/UxPlay)** by antimof — AirPlay mirror server for Unix (GPL-3.0)
- **[shairplay](https://github.com/juhovh/shairplay)** by Juho Vaha-Herttua — AirPlay audio server (LGPL-2.1)
- **[RPiPlay](https://github.com/FD-/RPiPlay)** by FD- — AirPlay mirror server for Raspberry Pi (GPL-3.0)

See [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md) for full details.

## License

VirtualMirror is licensed under the [GNU General Public License v3.0](LICENSE).

Copyright 2026 [Souris.CLOUD](https://bio.souris.cloud) — Made by Souris
