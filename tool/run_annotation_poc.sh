#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
flutter_bin="${FLUTTER_BIN:-flutter}"
annotation_workspace="${COMICNOTES_WORKSPACE:-true}"
if [[ "$annotation_workspace" != true && "$annotation_workspace" != false ]]; then
  echo 'COMICNOTES_WORKSPACE must be true or false.' >&2
  exit 1
fi
if ! command -v "$flutter_bin" >/dev/null 2>&1; then
  echo 'Flutter 3.41.4 is required. Set FLUTTER_BIN to its bin/flutter path.' >&2
  exit 1
fi
if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  echo 'A full Xcode installation must be selected before running the macOS app.' >&2
  exit 1
fi
python3 .github/scripts/prepare_flutter_compat.py --flutter-bin "$flutter_bin"
# Keep even error-path device discovery within this launcher's macOS scope.
export FLUTTER_WEB=false
exec "$flutter_bin" run -d macos --dart-define=COMICNOTES_POC=true --dart-define="COMICNOTES_WORKSPACE=$annotation_workspace" "$@"
