#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p assets
cat > assets/env.json <<EOF
{
  "SUPABASE_URL": "${SUPABASE_URL:-}",
  "SUPABASE_ANON_KEY": "${SUPABASE_ANON_KEY:-}",
  "PUBLIC_WEB_BASE_URL": "${PUBLIC_WEB_BASE_URL:-https://plotspotting.vercel.app}"
}
EOF

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "ERROR: SUPABASE_URL and SUPABASE_ANON_KEY must be set in Vercel environment variables."
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter SDK..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 /tmp/flutter
  export PATH="/tmp/flutter/bin:$PATH"
  flutter config --enable-web
  flutter precache --web
fi

flutter --version
flutter pub get
dart run flutter_native_splash:create
flutter build web --release
