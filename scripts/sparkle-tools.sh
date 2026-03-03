#!/usr/bin/env bash
#
# sparkle-tools.sh — Locate and run Sparkle CLI tools from SPM artifacts
#
# Usage: ./scripts/sparkle-tools.sh <tool> [args...]
#
# Available tools: generate_keys, sign_update, generate_appcast, BinaryDelta
#
# The Sparkle CLI tools are bundled with the Sparkle SPM package and end up in
# DerivedData after building the project. This script finds them reliably
# despite the hash in the DerivedData directory name.
#

set -euo pipefail

TOOL="${1:-}"
if [[ -z "$TOOL" ]]; then
    echo "Usage: $0 <tool> [args...]"
    echo "Tools: generate_keys, sign_update, generate_appcast, BinaryDelta"
    exit 1
fi
shift

# Search for the tool in DerivedData SPM artifacts
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
SPARKLE_BIN=""

for dir in "$DERIVED_DATA"/VirtualMirror-*/SourcePackages/artifacts/sparkle/Sparkle/bin; do
    if [[ -x "$dir/$TOOL" ]]; then
        SPARKLE_BIN="$dir/$TOOL"
        break
    fi
done

# Fallback: check if tool is on PATH
if [[ -z "$SPARKLE_BIN" ]] && command -v "$TOOL" &>/dev/null; then
    SPARKLE_BIN="$TOOL"
fi

if [[ -z "$SPARKLE_BIN" ]]; then
    echo "ERROR: Sparkle tool '$TOOL' not found." >&2
    echo "" >&2
    echo "The Sparkle CLI tools are resolved via Swift Package Manager." >&2
    echo "Build the project in Xcode first (or run xcodebuild build) to" >&2
    echo "download the Sparkle package, then try again." >&2
    exit 1
fi

exec "$SPARKLE_BIN" "$@"
