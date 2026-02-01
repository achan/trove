-- Create storage buckets for media assets

-- Create media bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'media',
  'media',
  false,
  52428800, -- 50MB in bytes
  ARRAY['image/*', 'video/*', 'audio/*']
)

-- RLS Policy for media bucket
CREATE POLICY "Users can access own media"
  ON storage.objects FOR ALL
  USING (
    bucket_id = 'media' AND
    (storage.foldername(name))[1] = auth.uid()::text
  )
