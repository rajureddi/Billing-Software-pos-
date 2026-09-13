#!/usr/bin/env bash
set -e

echo "=== Vercel Build: SRS AGENCIES Flutter Web ==="

# Install Flutter if not cached
if [ ! -d "$HOME/flutter" ]; then
  echo "Downloading Flutter SDK (stable channel)..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi

export PATH="$PATH:$HOME/flutter/bin"

echo "Flutter version:"
flutter --version

echo "Building Flutter Web Release..."
flutter config --enable-web
flutter pub get
flutter build web --release

echo "=== Flutter Web Build Complete! Output at build/web ==="
