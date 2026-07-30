#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-stable}"

if [ ! -d ".vercel-flutter" ]; then
  git clone https://github.com/flutter/flutter.git .vercel-flutter --depth 1 --branch "$FLUTTER_VERSION"
fi

export PATH="$PWD/.vercel-flutter/bin:$PATH"

flutter config --enable-web
flutter pub get
flutter build web --release \
  --dart-define=BACKEND_BASE_URL="${BACKEND_BASE_URL:-}" \
  --dart-define=PAYLOAD_ENCRYPTION_KEY="${PAYLOAD_ENCRYPTION_KEY:-}"
