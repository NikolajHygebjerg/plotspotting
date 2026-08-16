# Event Map

Kort- og navigationsapp til events (messer, spejderlejre, festivaler). Arrangører tegner stier og punkter; besøgende søger og får gå-ruter langs **de mappede stier** — ikke vej-navigation.

## Stack

| Lag | Teknologi |
|-----|-----------|
| App | Flutter (iOS + Android) |
| Kort udendørs | MapLibre + OpenStreetMap |
| Kort indendørs | Custom plantegning (Etape 2) |
| Backend | Supabase (Postgres + PostGIS + Storage) |
| Routing | Egen graf (A* på arrangør-tegnede stier) |

## Dokumentation

- [Datamodel](docs/DATA_MODEL.md) — tabeller, graf-struktur, API-kontrakter
- [Friland testcase](docs/FRILAND.md) — økosamfund: huse, stier, gæsteguide
- [Wireframes (canvas)](/Users/nikolajhygebjerg/.cursor/projects/Users-nikolajhygebjerg-Mapping/canvases/etape-1-wireframes.canvas.tsx) — visuel oversigt

## Database

SQL-migrationer ligger i `supabase/migrations/`.

Se **[Supabase-opsætning](docs/SUPABASE_SETUP.md)** for link til projektet og kørsel af migrationer.

```bash
supabase login
supabase link --project-ref gjbtmmmhplhqpbaqzsqj
supabase db push
```

## App (Flutter)

Kopiér `app/assets/env.json.example` til `app/assets/env.json` og indsæt anon key.

```bash
cd app
flutter pub get
flutter run
```

## Etaper

| # | Indhold | Status |
|---|---------|--------|
| 0 | Spike: MapLibre + tegn sti + A* | Planlagt |
| 1 | Udendørs MVP (lejr) | **Implementeret** |
| 2 | Indendørs plantegning | Planlagt |
| 3 | Walk & trace | Planlagt |
| 4 | Offline + polish | Planlagt |

## Designprincip

> OSM og Google er **baggrund**. Routing kører **altid** på arrangørens egen stigraf.
