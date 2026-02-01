-- Create media_downloads table for tracking media archive status

CREATE TABLE media_downloads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ingested_post_id UUID NOT NULL REFERENCES ingested_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Media identification
  original_url TEXT NOT NULL,

  -- Download tracking
  status download_status_enum DEFAULT 'pending',
  attempts INTEGER DEFAULT 0,
  error TEXT,
  last_attempt_at TIMESTAMPTZ,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Constraints
  CONSTRAINT unique_user_url UNIQUE (user_id, original_url),
  CONSTRAINT valid_attempts CHECK (attempts >= 0)
)

-- Indexes
CREATE INDEX idx_media_downloads_ingested_post_id ON media_downloads(ingested_post_id)
CREATE INDEX idx_media_downloads_user_id ON media_downloads(user_id)
CREATE INDEX idx_media_downloads_status ON media_downloads(status)
CREATE INDEX idx_media_downloads_status_attempts ON media_downloads(status, attempts)

-- Enable RLS
ALTER TABLE media_downloads ENABLE ROW LEVEL SECURITY

-- RLS Policies
CREATE POLICY "Users can read own media downloads"
  ON media_downloads FOR SELECT
  USING (auth.uid() = user_id)

CREATE POLICY "Service role can manage media downloads"
  ON media_downloads FOR ALL
  USING (auth.role() = 'service_role')
