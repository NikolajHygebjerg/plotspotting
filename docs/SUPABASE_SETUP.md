# Supabase-opsætning — Rønde spejder

Projekt-URL: `https://gjbtmmmhplhqpbaqzsqj.supabase.co`  
Project ref: `gjbtmmmhplhqpbaqzsqj`

## 1. Kør migrationer

### Valg A: Supabase CLI (anbefalet)

```bash
cd /Users/nikolajhygebjerg/Mapping

# Log ind (åbner browser)
supabase login

# Link til dit projekt
supabase link --project-ref gjbtmmmhplhqpbaqzsqj

# Push migrationer
supabase db push
```

### Valg B: SQL Editor i dashboard

1. Gå til **SQL Editor** i Supabase
2. Kør indholdet af `001_initial_schema.sql`, `002_rls_and_rpc.sql`, `003_save_graph.sql` og `004_poi_metadata.sql` (i den rækkefølge)

## 2. Aktivér PostGIS

PostGIS aktiveres automatisk via migration 001. Verificér under **Database → Extensions** at `postgis` og `pg_trgm` er slået til.

## 3. Hent API-nøgler

1. **Project Settings → API**
2. Kopiér **Project URL** og **anon public** key
3. Kopiér `app/assets/env.json.example` til `app/assets/env.json` og indsæt anon key.

```bash
cd app
cp assets/env.json.example assets/env.json
# rediger assets/env.json — indsæt anon key
flutter run
```
