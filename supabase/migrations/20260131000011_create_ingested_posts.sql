-- Create ingested_posts table for archived post data

CREATE TABLE ingested_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Source tracking
  ingested_item_id UUID REFERENCES ingested_items(id) ON DELETE SET NULL,

  -- Platform information
  platform platform_enum NOT NULL,
  account_id UUID REFERENCES connected_accounts(id) ON DELETE SET NULL,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,

  -- Post identification
  platform_post_id TEXT NOT NULL,

  -- Post data in native format
  post_data JSONB NOT NULL,

  -- Processing tracking
  status processing_status_enum DEFAULT 'pending',
  attempts INTEGER DEFAULT 0,

  -- Timing
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,

  -- Error tracking
  error_message TEXT,
  error_details JSONB,
  last_error_at TIMESTAMPTZ,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Constraints
  CONSTRAINT valid_attempts CHECK (attempts >= 0)
)

-- Indexes for ingested_posts
CREATE INDEX idx_ingested_posts_status ON ingested_posts(status)
CREATE INDEX idx_ingested_posts_ingested_item_id ON ingested_posts(ingested_item_id)
CREATE INDEX idx_ingested_posts_platform ON ingested_posts(platform)
CREATE INDEX idx_ingested_posts_account_id ON ingested_posts(account_id)
CREATE INDEX idx_ingested_posts_user_id ON ingested_posts(user_id)
CREATE INDEX idx_ingested_posts_platform_post_id ON ingested_posts(platform, platform_post_id)
CREATE INDEX idx_ingested_posts_received_at ON ingested_posts(received_at DESC)
CREATE INDEX idx_ingested_posts_post_data ON ingested_posts USING GIN(post_data)

-- Trigger for updated_at
CREATE TRIGGER update_ingested_posts_updated_at
  BEFORE UPDATE ON ingested_posts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at()

-- Enable RLS
ALTER TABLE ingested_posts ENABLE ROW LEVEL SECURITY

-- RLS Policies
CREATE POLICY "Users can read own ingested posts"
  ON ingested_posts FOR SELECT
  USING (auth.uid() = user_id)

CREATE POLICY "Service role can manage ingested posts"
  ON ingested_posts FOR ALL
  USING (auth.role() = 'service_role')
