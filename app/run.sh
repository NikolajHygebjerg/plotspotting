#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f assets/env.json ]]; then
  cp assets/env.json.example assets/env.json
  echo "Oprettet assets/env.json — indsæt SUPABASE_ANON_KEY og kør igen."
  exit 1
fi

flutter run "$@"
