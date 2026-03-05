# Changelog

All notable changes to VirtualMirror will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Video frozen after lock/unlock — `AVSampleBufferDisplayLayer` entered `.failed` state but `flush()` alone did not clear the error; now uses `flushAndRemoveImage()` and re-enqueues the frame to recover
- Video frozen after lock/unlock (decode errors -12909) — `configureWithAVCC` was destroying and recreating the decompression session on resume even when SPS/PPS hadn't changed, losing all reference frames; now skips session recreation when codec parameters are identical, preserving decoder state for P-frames
- Distorted audio — dangling pointer in `AudioDecoder` C callback; `withUnsafeMutablePointer` returned a pointer only valid inside its closure scope, but it was used by `AudioConverterFillComplexBuffer` after the closure ended, causing corrupted `AudioStreamPacketDescription` values; now uses a heap-allocated pointer with stable lifetime

## [0.3.0] - 2026-03-03

### Fixed

- Sparkle appcast URL changed from `main` to `master` branch
- Auto-update now enabled by default (`SUAutomaticallyUpdate`)

### Changed

- License updated to GPL-3.0

## [0.2.0] - 2026-03-03

### Added

- GPL-3.0 license
- Acknowledgments file for third-party dependencies
- Polished UI with improved waiting screen and connection progress
- About dialog with version info, links, and acknowledgments

### Changed

- Signing configuration extracted to `scripts/.env` for portability
- Release script improvements

## [0.1.0] - 2026-03-03

### Added

- AirPlay screen mirroring receiver for macOS
- Bonjour service advertising (`_airplay._tcp`, `_raop._tcp`)
- Pair-setup and pair-verify authentication
- FairPlay DRM handshake support
- H.264 video decoding via VideoToolbox
- AES-128-CTR encrypted mirror stream decryption
- Native macOS window with real-time video display
- Menu bar integration (app hides on close, lives in menu bar)
- NTP timing synchronization with sender devices
- Sparkle auto-update framework
- Automated release pipeline (archive, sign, notarize, DMG, GitHub Release)
- Branded DMG installer with background artwork

[Unreleased]: https://github.com/souriscloud/VirtualMirror/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/souriscloud/VirtualMirror/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/souriscloud/VirtualMirror/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/souriscloud/VirtualMirror/releases/tag/v0.1.0
