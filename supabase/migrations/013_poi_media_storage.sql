-- Billeder og video til steder (POI) — gemmes i metadata.media + Supabase Storage

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'poi-media',
  'poi-media',
  true,
  52428800,
  ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'video/mp4',
    'video/quicktime',
    'video/webm'
  ]
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "poi_media_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'poi-media');

CREATE POLICY "poi_media_anon_upload"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'poi-media');

CREATE POLICY "poi_media_anon_update"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'poi-media');

CREATE POLICY "poi_media_anon_delete"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'poi-media');
