# VirtualMirror — Claude Code Guide

## Project Overview

VirtualMirror is a macOS AirPlay screen mirroring receiver. It receives screen mirroring from iPhones/iPads and displays the video stream in a native macOS window.

## Build & Run

```bash
xcodebuild build -project VirtualMirror.xcodeproj -scheme VirtualMirror -configuration Debug
```

Open in Xcode: `open VirtualMirror.xcodeproj`

- Deployment target: macOS 14.0
- Swift version: 5.0
- Uses C bridging header for FairPlay code (`VirtualMirror/FairPlay/BridgingHeader.h`)

## Architecture

```
VirtualMirrorApp.swift     — @main entry, AppDelegate with menu bar, window management
AirPlayManager.swift       — Central state machine (idle → connecting → mirroring)
ContentView.swift          — State-driven UI (waiting screen, progress, video display)
AboutView.swift            — About dialog (shown from menu bar)

AirPlay/
  AirPlayConfig.swift      — Device identity, feature flags, /info response
  AirPlayService.swift     — Bonjour service advertising (_airplay._tcp, _raop._tcp)
  AirPlayServer.swift      — TCP listener accepting AirPlay connections
  AirPlayConnection.swift  — HTTP/RTSP protocol handler (SETUP, RECORD, TEARDOWN, etc.)
  NTPTimingServer.swift    — NTP time sync with sender device

Pairing/
  PairSetupHandler.swift   — Pair-setup (SRP-like) authentication
  PairVerifyHandler.swift  — Pair-verify with Ed25519 + ECDH shared secret
  SessionEncryption.swift  — ChaCha20-Poly1305 session encryption

FairPlay/
  FairPlayHandler.swift    — FairPlay handshake (3 messages)
  fairplay_playfair.c/h    — FairPlay response generation (C)
  playfair.c/h             — Key decryption from ekey
  omg_hax.c, hand_garble.c, sap_hash.c, modified_md5.c — Crypto primitives

Video/
  MirrorStreamReceiver.swift — TCP mirror stream, packet parsing, AES key derivation
  VideoDecryptor.swift       — AES-128-CTR decryption of video frames
  VideoDecoder.swift         — H.264 decoding via VideoToolbox
  VideoDisplayView.swift     — CALayer-based video display

Networking/
  HTTPParser.swift         — HTTP/RTSP request parser
  HTTPResponse.swift       — HTTP/RTSP response builder
```

## Key Patterns

- **State machine**: `AirPlayState` enum with associated values (`.idle`, `.connecting(name)`, `.mirroring(name)`, `.error(msg)`)
- **Combine**: `@Published var state` observed by both SwiftUI views and the AppDelegate menu bar
- **MainActor**: `AirPlayManager` and `AppDelegate` are `@MainActor`; connection callbacks use `nonisolated` + `Task { @MainActor in }`
- **C interop**: FairPlay crypto uses C files via a bridging header
- **Port allocation**: AirPlay on 47000, video stream on 47100, events on 47101, NTP on 47102

## Bundle & Identity

- Bundle ID: `cloud.souris.virtualmirror`
- Copyright: `© 2026 Souris.CLOUD. All rights reserved.`
- AirPlay device name: "VirtualMirror" (set in `AirPlayConfig.swift`)
- Emulates AppleTV3,2 model

## Important Notes

- The app hides on window close (doesn't quit) — lives in the menu bar
- macOS built-in AirPlay Receiver runs on port 7000; we use 47000 to avoid conflicts
- Users should disable "AirPlay Receiver" in System Settings for best results
- FairPlay C code should not be modified unless the protocol changes
- Logger subsystem is `"com.virtualmirror"` (historical, not the bundle ID)
