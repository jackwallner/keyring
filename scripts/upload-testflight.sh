#!/usr/bin/env bash
# Upload an existing Keyring archive without rebuilding.
cd "$(dirname "$0")/.." || exit 1
exec "$HOME/ios/release/testflight.sh" --project Keyring.xcodeproj --scheme Keyring --upload-only "$@"
