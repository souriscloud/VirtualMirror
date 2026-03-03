# VirtualMirror — Progress Log

## Status: Polishing Phase (In Progress)

Core AirPlay protocol works end-to-end: pairing, FairPlay, video decryption/decoding/display.
Currently applying final polish for a release-quality app.

---

## Completed

### Core Protocol (Pre-polish)
- [x] Bonjour service advertising (`_airplay._tcp`, `_raop._tcp`)
- [x] HTTP/RTSP AirPlay protocol handler
- [x] Pair-setup (SRP-like authentication)
- [x] Pair-verify (Ed25519 + ECDH shared secret derivation)
- [x] FairPlay DRM handshake (3-message exchange)
- [x] FairPlay stream key decryption (ekey → AES key via playfair)
- [x] Mirror stream AES-128-CTR key derivation (SHA-512 chain)
- [x] Mirror stream packet parsing (128-byte headers)
- [x] AES-128-CTR video decryption
- [x] H.264 avcC codec configuration parsing
- [x] VideoToolbox decompression session
- [x] Real-time video display via CALayer
- [x] NTP timing server for sender sync

### Polishing Phase
- [x] **Bundle ID**: Changed from `com.virtualmirror.app` → `cloud.souris.virtualmirror`
- [x] **Copyright**: Added `NSHumanReadableCopyright` to Info.plist
- [x] **App Icon**: Generated 1024x1024 icon (blue-to-purple gradient, monitor with AirPlay triangle), all macOS sizes (16–1024px) in Assets.xcassets
- [x] **Accent Color**: Blue accent color in Assets.xcassets
- [x] **Menu Bar**: NSStatusItem with `airplayvideo` SF Symbol, dropdown with status line, Show/Hide Window, About, Quit
- [x] **State in menu bar**: Combine observation of AirPlayManager.state — shows Idle/Connected/Mirroring with device name
- [x] **Window close → hide**: NSWindowDelegate intercepts close to hide instead of terminate; app stays alive in menu bar
- [x] **About dialog**: SwiftUI view in standalone NSWindow — icon, title, version, copyright, link to bio.souris.cloud, "Made by Souris"
- [x] **AirPlayState update**: Added device name to `.mirroring(String)` so menu bar can show which device is mirroring
- [x] **Debug logging cleanup**:
  - Removed all `fprintf(stderr, ...)` from `playfair.c`
  - Reduced packet logging to first 3 (was 5/10) in `MirrorStreamReceiver.swift`
  - Removed hex dumps of video payloads, codec data, AES key/IV
  - Removed FairPlay key hex dump from `AirPlayConnection.swift`
  - Reduced frame logging to first 3 (was 5) in `VideoDecoder.swift`
- [x] **Xcode project**: AboutView.swift and Assets.xcassets registered in pbxproj
- [x] **Build**: `xcodebuild build` succeeds clean

---

## Remaining / TODO

- [ ] **Test AirPlay mirroring end-to-end** — connect iPhone and verify video still displays correctly after all changes
- [ ] **Verify menu bar behavior** — status updates, show/hide toggle, about dialog, quit
- [ ] **App icon in Dock** — verify the icon renders correctly at all sizes in Dock, Finder, and app switcher
- [ ] **Code signing** — set up proper signing identity for distribution (currently "Sign to Run Locally")
- [ ] **Audio support** — stream type 96 is acknowledged but not decoded
- [ ] **Reconnection handling** — graceful recovery when sender disconnects and reconnects
- [ ] **Multiple connections** — currently only handles one connection at a time

---

## File Change Summary

Files **created**:
- `VirtualMirror/AboutView.swift`
- `VirtualMirror/Assets.xcassets/` (entire directory with AppIcon + AccentColor)

Files **modified**:
- `VirtualMirror.xcodeproj/project.pbxproj` — bundle ID, new file refs, resource/source build phases
- `VirtualMirror/Info.plist` — added NSHumanReadableCopyright
- `VirtualMirror/VirtualMirrorApp.swift` — complete rewrite: AppDelegate, menu bar, window management
- `VirtualMirror/AirPlayManager.swift` — `.mirroring` → `.mirroring(String)`, added `deviceName` computed property
- `VirtualMirror/ContentView.swift` — updated switch case for `.mirroring(_)`
- `VirtualMirror/FairPlay/playfair.c` — removed all fprintf debug logging
- `VirtualMirror/Video/MirrorStreamReceiver.swift` — reduced logging, removed hex dumps
- `VirtualMirror/AirPlay/AirPlayConnection.swift` — removed ekey/FairPlay key hex dumps
- `VirtualMirror/Video/VideoDecoder.swift` — reduced frame logging, removed hex dumps
