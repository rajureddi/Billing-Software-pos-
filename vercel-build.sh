#!/usr/bin/env bash
set -e

echo "=== Vercel Build: Counterday Flutter Web ==="

# Install Flutter if not cached
if [ ! -d "$HOME/flutter" ]; then
  echo "Downloading Flutter SDK (stable channel)..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi

export PATH="$PATH:$HOME/flutter/bin"

echo "Flutter version:"
flutter --version

echo "Building Flutter Web Release with environment variables..."
flutter config --enable-web
flutter pub get

# Inject Vercel Project Environment Variables at compile-time
flutter build web --release \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"

echo "=== Flutter Web Build Complete! Output at build/web ==="
