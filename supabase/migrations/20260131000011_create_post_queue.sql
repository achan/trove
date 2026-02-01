-- Create post queue for individual post processing

CREATE TABLE post_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Source tracking
  ingestion_queue_id UUID REFERENCES ingestion_queue(id) ON DELETE SET NULL,

  -- Platform information
  platform platform_enum NOT NULL,
  account_id UUID REFERENCES connected_accounts(id) ON DELETE SET NULL,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,

  -- Post identification
  platform_post_id TEXT NOT NULL,

  -- Post data in native format
  post_data JSONB NOT NULL,

  -- Processing tracking
  status queue_status_enum DEFAULT 'pending',
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

-- Indexes for post queue
CREATE INDEX idx_post_queue_status ON post_queue(status)
CREATE INDEX idx_post_queue_ingestion_queue_id ON post_queue(ingestion_queue_id)
CREATE INDEX idx_post_queue_platform ON post_queue(platform)
CREATE INDEX idx_post_queue_account_id ON post_queue(account_id)
CREATE INDEX idx_post_queue_user_id ON post_queue(user_id)
CREATE INDEX idx_post_queue_platform_post_id ON post_queue(platform, platform_post_id)
CREATE INDEX idx_post_queue_received_at ON post_queue(received_at DESC)
CREATE INDEX idx_post_queue_post_data ON post_queue USING GIN(post_data)

-- Trigger for updated_at
CREATE TRIGGER update_post_queue_updated_at
  BEFORE UPDATE ON post_queue
  FOR EACH ROW EXECUTE FUNCTION update_updated_at()

-- Enable RLS
ALTER TABLE post_queue ENABLE ROW LEVEL SECURITY

-- RLS Policies
CREATE POLICY "Users can read own queue items"
  ON post_queue FOR SELECT
  USING (auth.uid() = user_id)

CREATE POLICY "Service role can manage queue"
  ON post_queue FOR ALL
  USING (auth.role() = 'service_role')
