-- Tillad lydfiler til lydvandring på POI-markører

UPDATE storage.buckets
SET
  allowed_mime_types = ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'video/mp4',
    'video/quicktime',
    'video/webm',
    'audio/mpeg',
    'audio/mp4',
    'audio/x-m4a',
    'audio/aac',
    'audio/wav',
    'audio/ogg',
    'audio/webm'
  ],
  file_size_limit = 104857600
WHERE id = 'poi-media';
