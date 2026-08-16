#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/app"
OUT="$APP/build/web"
DIST="$ROOT/dist"

BASE_HREF="${1:-/}"

cd "$APP"

if [[ ! -f assets/env.json ]]; then
  echo "Mangler assets/env.json — kopiér fra assets/env.json.example og udfyld Supabase-nøgler."
  exit 1
fi

flutter pub get
flutter build web --release --base-href "$BASE_HREF"

# Apache SPA fallback skal bruge samme base som Flutter-build.
sed "s|RewriteBase /|RewriteBase ${BASE_HREF}|" web/.htaccess > "$OUT/.htaccess"

mkdir -p "$DIST"
ARCHIVE="$DIST/event-map-web$(date +%Y%m%d).tar.gz"
tar -czf "$ARCHIVE" -C "$OUT" .

echo ""
echo "Web-build klar:"
echo "  Mappe: $OUT"
echo "  Arkiv: $ARCHIVE"
echo ""
echo "Upload indholdet af build/web/ til din webserver."
echo "Besøger-link: https://dit-domæne.dk${BASE_HREF}e/friland-2"
