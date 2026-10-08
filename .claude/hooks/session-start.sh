#!/bin/bash
# 클라우드 세션 시작 시 Flutter SDK 설치 + 패키지 받기 (테스트/분석이 바로 되도록)
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

FLUTTER_DIR="$HOME/flutter"
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$FLUTTER_DIR/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

flutter config --no-analytics >/dev/null 2>&1 || true
flutter --version
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
flutter pub get
