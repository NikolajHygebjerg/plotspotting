# Datamodel — Event Map

Datamodel til **Etape 1 (udendørs lejr-MVP)** med hooks til **Etape 2 (indendørs plantegning)**.

Designprincip: **Arrangøren tegner stier → appen gemmer en graf → routing kører på den graf.** OSM er kun baggrund, aldrig routing-kilde.

---

## Entiteter (overblik)

```
Event
 ├── path_vertices  ──┐
 ├── path_edges     ──┴── routing-graf (arrangør-ejet)
 ├── pois               søgbare steder
 └── floor_plan         (Etape 2, indendørs)
```

---

## `events`

Et event er en isoleret kortpakke (messe, lejr, festival).

| Felt | Type | Beskrivelse |
|------|------|-------------|
| `id` | UUID | Primærnøgle |
| `name` | text | "Spejderlejr 2026" |
| `description` | text | Valgfri |
| `mode` | `outdoor` \| `indoor` | Etape 1: kun `outdoor` |
| `status` | `draft` \| `published` \| `archived` | |
| `public_slug` | text | URL/QR: `/e/spejder-2026` |
| `edit_code` | text | Hemmelig kode til mapper-redigering (MVP-auth) |
| `bounds` | polygon (WGS84) | Kartografisk afgrænsning |
| `center` | point (WGS84) | Standard zoom-center |
| `published_at` | timestamptz | |

---

## `path_vertices` + `path_edges`

Stinetværket er en **graf**, ikke bare pixels på et kort.

### Vertices (knudepunkter)

Kryds, hjørner, indgange — steder hvor stier mødes.

| Felt | Beskrivelse |
|------|-------------|
| `location` | GPS (udendørs): `(lat, lng)` |
| `local_x`, `local_y` | Meter på plantegning (indendørs, Etape 2) |
| `is_entrance` | Markeret indgang (QR / "start her") |
| `label` | Valgfri: "Hovedindgang" |

**Snap-regel:** Når mapper placerer et punkt inden for ~5 m af eksisterende vertex, merges de (én vertex-id).

### Edges (kanter)

Walkable segment mellem to vertices.

| Felt | Beskrivelse |
|------|-------------|
| `from_vertex_id`, `to_vertex_id` | Graf-kant |
| `geometry` | LineString til visning (kan bue) |
| `length_meters` | Beregnet ved gem |
| `bidirectional` | `true` for gangstier |

### Mapping-flow (udendørs)

1. Mapper vælger "Tegn sti"
2. Tap på kort → ny vertex (eller snap til eksisterende)
3. Hver ny tap opretter edge fra forrige vertex
4. "Afslut sti" → segment gemmes
5. App beregner `length_meters` via haversine på geometry

---

## `pois`

Points of interest — det besøgende søger efter.

| Felt | Beskrivelse |
|------|-------------|
| `name` | "Toilet blok B", "Udstiller Acme" |
| `category` | `toilet`, `food`, `info`, `exhibitor`, `activity`, `other` |
| `location` | GPS eller local coords |
| `access_vertex_id` | Nærmeste vertex på stinet (routing-snap) |
| `metadata` | JSON: `{ "booth": "A12", "logo_url": "..." }` |

**Snap ved gem:** Find nærmeste edge, projicer POI onto edge, opret access-vertex hvis nødvendigt.

---

## `floor_plans` (Etape 2)

| Felt | Beskrivelse |
|------|-------------|
| `storage_path` | Supabase Storage URL |
| `image_width_px`, `image_height_px` | |
| `width_meters` | Skala |
| `calibration` | 3–4 punkter: pixel ↔ local meter |

---

## Koordinatsystemer

| Mode | Lagring | Visning |
|------|---------|---------|
| Outdoor | WGS84 (`geography`) | MapLibre lat/lng |
| Indoor | Local meter (`local_x/y`) | Custom image overlay |

Routing-algoritmen er identisk — den opererer på `{vertices, edges}` uanset koordinatsystem.

---

## Routing (klient-side, Etape 1)

```
Input:  start_vertex_id, goal_vertex_id (fra POI.access_vertex_id)
Graph:  edges som adjacency list med weights = length_meters
Algo:   A* (eller Dijkstra — graf er lille)
Output: liste af vertex_ids → polyline til kort
```

Besøgendes GPS → snap til nærmeste vertex (max 30 m, ellers "Du er for langt fra en sti").

---

## API-kontrakter (Supabase)

### Public (besøgende)

| Operation | Beskrivelse |
|-----------|-------------|
| `GET event by slug` | Event metadata + status = published |
| `GET event_routing_graph` | View: vertices + edges + pois som JSON |

### Organizer (edit_code i header)

| Operation | Beskrivelse |
|-----------|-------------|
| CRUD vertices/edges | Batch upsert ved "Gem kort" |
| CRUD pois | |
| `PATCH event` | Publish, opdatér navn |
| `POST publish` | Sæt status = published, generér slug |

MVP: Edge Function validerer `X-Edit-Code` header mod `events.edit_code`.

---

## GeoJSON-export (offline-pakke, Etape 4)

```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "LineString", "coordinates": [[lng, lat], ...] },
      "properties": { "kind": "path_edge", "id": "..." }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [lng, lat] },
      "properties": { "kind": "poi", "name": "Toilet", "category": "toilet" }
    }
  ]
}
```

---

## POI-kategorier (Etape 1)

| `category` | Ikon | Eksempel |
|------------|------|----------|
| `exhibitor` | Stand | Messe (Etape 2+) |
| `activity` | Flag | Aktivitetstelt |
| `food` | Bestik | Kiosk |
| `toilet` | WC | Toilet |
| `info` | i | Infobod |
| `other` | Pin | Diverse |

---

## Indeks & performance

- Events: ~1–500 POI, ~50–500 vertices per event → routing på klient er <1 ms
- PostGIS GIST på alle geography-kolonner
- pg_trgm på `pois.name` for søgning
- Hele grafen caches lokalt ved event-download

---

## Migrationer

| Fil | Indhold |
|-----|---------|
| `supabase/migrations/001_initial_schema.sql` | Tabeller, indexes, view |
| `002_rls_edit_code.sql` | (Etape 1b) RLS + edge function policies |
