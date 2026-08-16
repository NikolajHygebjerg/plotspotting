-- Event Map — initial schema (Etape 1: outdoor MVP)
-- Requires: Supabase with PostGIS enabled

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

CREATE TYPE event_mode AS ENUM ('outdoor', 'indoor');
CREATE TYPE event_status AS ENUM ('draft', 'published', 'archived');

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

CREATE TABLE events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  description     TEXT,
  mode            event_mode NOT NULL DEFAULT 'outdoor',
  status          event_status NOT NULL DEFAULT 'draft',

  -- Public access via slug (QR / deep link). Unique when set.
  public_slug     TEXT UNIQUE,

  -- Secret code for organizers to edit without full auth (MVP).
  edit_code       TEXT NOT NULL DEFAULT encode(gen_random_bytes(16), 'hex'),

  -- Outdoor bounding box (WGS84). Null until mapper sets area.
  bounds          GEOGRAPHY(POLYGON, 4326),

  -- Default map center for visitors (WGS84 point).
  center          GEOGRAPHY(POINT, 4326),

  published_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX events_public_slug_idx ON events (public_slug) WHERE public_slug IS NOT NULL;
CREATE INDEX events_status_idx ON events (status);

-- ---------------------------------------------------------------------------
-- Floor plans (Etape 2 — indoor). Table created now for stable schema.
-- ---------------------------------------------------------------------------

CREATE TABLE floor_plans (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id        UUID NOT NULL REFERENCES events (id) ON DELETE CASCADE,

  storage_path    TEXT NOT NULL,
  image_width_px  INTEGER NOT NULL,
  image_height_px INTEGER NOT NULL,

  -- Real-world width of the image in meters (scale).
  width_meters    DOUBLE PRECISION,

  -- Affine transform: image pixel coords → local meters (JSON 3×3 or 4-point calibration).
  calibration     JSONB NOT NULL DEFAULT '{}',

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (event_id)
);

-- ---------------------------------------------------------------------------
-- Path network — vertices & edges (organizer-drawn, full control)
-- ---------------------------------------------------------------------------

CREATE TABLE path_vertices (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id        UUID NOT NULL REFERENCES events (id) ON DELETE CASCADE,

  -- WGS84 for outdoor; for indoor Etape 2, local_x/local_y used instead.
  location        GEOGRAPHY(POINT, 4326),
  local_x         DOUBLE PRECISION,
  local_y         DOUBLE PRECISION,

  label           TEXT,
  is_entrance     BOOLEAN NOT NULL DEFAULT false,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT path_vertices_coords_check CHECK (
    (location IS NOT NULL AND local_x IS NULL AND local_y IS NULL)
    OR (location IS NULL AND local_x IS NOT NULL AND local_y IS NOT NULL)
  )
);

CREATE INDEX path_vertices_event_idx ON path_vertices (event_id);
CREATE INDEX path_vertices_location_idx ON path_vertices USING GIST (location);

CREATE TABLE path_edges (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id        UUID NOT NULL REFERENCES events (id) ON DELETE CASCADE,
  from_vertex_id  UUID NOT NULL REFERENCES path_vertices (id) ON DELETE CASCADE,
  to_vertex_id    UUID NOT NULL REFERENCES path_vertices (id) ON DELETE CASCADE,

  -- Geometry follows the walkable path (may curve). Used for map display.
  geometry        GEOGRAPHY(LINESTRING, 4326),

  -- Cached walk distance in meters (computed on save).
  length_meters   DOUBLE PRECISION NOT NULL DEFAULT 0,

  -- Bidirectional walking (default true for event paths).
  bidirectional   BOOLEAN NOT NULL DEFAULT true,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT path_edges_distinct_vertices CHECK (from_vertex_id <> to_vertex_id),
  UNIQUE (event_id, from_vertex_id, to_vertex_id)
);

CREATE INDEX path_edges_event_idx ON path_edges (event_id);
CREATE INDEX path_edges_geometry_idx ON path_edges USING GIST (geometry);

-- ---------------------------------------------------------------------------
-- Points of interest (stands, telte, toiletter, …)
-- ---------------------------------------------------------------------------

CREATE TABLE pois (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id        UUID NOT NULL REFERENCES events (id) ON DELETE CASCADE,

  name            TEXT NOT NULL,
  category        TEXT NOT NULL DEFAULT 'other',
  description     TEXT,

  location        GEOGRAPHY(POINT, 4326),
  local_x         DOUBLE PRECISION,
  local_y         DOUBLE PRECISION,

  -- Nearest vertex on path network for routing snap.
  access_vertex_id UUID REFERENCES path_vertices (id) ON DELETE SET NULL,

  metadata        JSONB NOT NULL DEFAULT '{}',

  sort_order      INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT pois_coords_check CHECK (
    (location IS NOT NULL AND local_x IS NULL AND local_y IS NULL)
    OR (location IS NULL AND local_x IS NOT NULL AND local_y IS NOT NULL)
  )
);

CREATE INDEX pois_event_idx ON pois (event_id);
CREATE INDEX pois_location_idx ON pois USING GIST (location);
CREATE INDEX pois_name_trgm_idx ON pois USING gin (name gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- Updated-at trigger
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER events_updated_at
  BEFORE UPDATE ON events
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER pois_updated_at
  BEFORE UPDATE ON pois
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER floor_plans_updated_at
  BEFORE UPDATE ON floor_plans
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security (MVP: public read for published events)
-- ---------------------------------------------------------------------------

ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE path_vertices ENABLE ROW LEVEL SECURITY;
ALTER TABLE path_edges ENABLE ROW LEVEL SECURITY;
ALTER TABLE pois ENABLE ROW LEVEL SECURITY;
ALTER TABLE floor_plans ENABLE ROW LEVEL SECURITY;

-- Published events: anyone can read
CREATE POLICY events_public_read ON events
  FOR SELECT USING (status = 'published');

-- Draft events: read/write via service role only in MVP (app uses edge function + edit_code)
-- Full RLS policies added in migration 002 when auth flow is defined.

-- ---------------------------------------------------------------------------
-- Helper: export event as routing graph (for client cache / offline)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW event_routing_graph AS
SELECT
  e.id AS event_id,
  json_build_object(
    'vertices', (
      SELECT coalesce(json_agg(json_build_object(
        'id', v.id,
        'lat', ST_Y(v.location::geometry),
        'lng', ST_X(v.location::geometry),
        'local_x', v.local_x,
        'local_y', v.local_y,
        'is_entrance', v.is_entrance,
        'label', v.label
      )), '[]'::json)
      FROM path_vertices v WHERE v.event_id = e.id
    ),
    'edges', (
      SELECT coalesce(json_agg(json_build_object(
        'id', ed.id,
        'from', ed.from_vertex_id,
        'to', ed.to_vertex_id,
        'length_meters', ed.length_meters,
        'bidirectional', ed.bidirectional,
        'coordinates', ST_AsGeoJSON(ed.geometry::geometry)::json -> 'coordinates'
      )), '[]'::json)
      FROM path_edges ed WHERE ed.event_id = e.id
    ),
    'pois', (
      SELECT coalesce(json_agg(json_build_object(
        'id', p.id,
        'name', p.name,
        'category', p.category,
        'description', p.description,
        'access_vertex_id', p.access_vertex_id,
        'lat', ST_Y(p.location::geometry),
        'lng', ST_X(p.location::geometry),
        'metadata', p.metadata
      )), '[]'::json)
      FROM pois p WHERE p.event_id = e.id
    )
  ) AS graph
FROM events e
WHERE e.status = 'published';
