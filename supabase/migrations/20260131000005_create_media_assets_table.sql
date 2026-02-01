-- Create media_assets table

CREATE TABLE media_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- Denormalized

  -- Media information
  media_type media_type_enum NOT NULL,
  original_url TEXT NOT NULL, -- URL from platform
  storage_path TEXT, -- Path in Supabase Storage
  storage_bucket TEXT DEFAULT 'media', -- Supabase Storage bucket

  -- Dimensions
  width INTEGER,
  height INTEGER,
  duration INTEGER, -- Seconds, for video/audio
  aspect_ratio DECIMAL(10,6), -- Calculated

  -- File info
  file_size BIGINT, -- Bytes
  mime_type TEXT,
  file_extension TEXT,

  -- Metadata
  alt_text TEXT, -- Accessibility
  caption TEXT, -- Platform-provided caption
  position INTEGER DEFAULT 0, -- Order in carousel/album

  -- Download tracking
  download_status download_status_enum DEFAULT 'pending',
  download_attempts INTEGER DEFAULT 0,
  last_download_attempt TIMESTAMPTZ,
  download_error TEXT,

  -- Content hash (for deduplication)
  content_hash TEXT, -- SHA-256 of file

  -- Platform metadata
  metadata JSONB DEFAULT '{}',
  -- Example: {thumbnail_url, variants[], encoding_status}

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Constraints
  CONSTRAINT valid_position CHECK (position >= 0),
  CONSTRAINT valid_dimensions CHECK (width > 0 AND height > 0 OR width IS NULL),
  CONSTRAINT valid_duration CHECK (duration >= 0 OR duration IS NULL)
)

-- Indexes
CREATE INDEX idx_media_assets_post_id ON media_assets(post_id)
CREATE INDEX idx_media_assets_user_id ON media_assets(user_id)
CREATE INDEX idx_media_assets_post_position ON media_assets(post_id, position)
CREATE INDEX idx_media_assets_download_status ON media_assets(download_status)
CREATE INDEX idx_media_assets_download_retry ON media_assets(download_status, download_attempts)
CREATE INDEX idx_media_assets_content_hash ON media_assets(content_hash)
CREATE INDEX idx_media_assets_storage_path ON media_assets(storage_path)
