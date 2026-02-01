-- Create ingestion queue for webhooks and fetches

-- Ingestion source types
CREATE TYPE ingestion_source_enum AS ENUM (
  'webhook',      -- Incoming webhook from platform
  'fetch',        -- Scheduled/manual fetch
  'backfill',     -- Initial backfill operation
  'retry'         -- Retry of failed operation
)

-- Queue processing status
CREATE TYPE queue_status_enum AS ENUM (
  'pending',      -- Waiting to be processed
  'processing',   -- Currently being processed
  'completed',    -- Successfully processed
  'failed',       -- Processing failed
  'dead_letter'   -- Moved to dead letter queue after max retries
)

CREATE TABLE ingestion_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Source information
  source ingestion_source_enum NOT NULL,
  platform platform_enum NOT NULL,
  account_id UUID REFERENCES connected_accounts(id) ON DELETE SET NULL,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,

  -- Event identification
  event_type TEXT NOT NULL, -- e.g., 'activity.create', 'post.new', 'media.update'
  external_id TEXT, -- Platform's event/webhook ID if available

  -- Complete payload
  payload JSONB NOT NULL,

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

-- Indexes for ingestion queue
CREATE INDEX idx_ingestion_queue_status ON ingestion_queue(status)
CREATE INDEX idx_ingestion_queue_platform ON ingestion_queue(platform)
CREATE INDEX idx_ingestion_queue_account_id ON ingestion_queue(account_id)
CREATE INDEX idx_ingestion_queue_user_id ON ingestion_queue(user_id)
CREATE INDEX idx_ingestion_queue_source ON ingestion_queue(source)
CREATE INDEX idx_ingestion_queue_received_at ON ingestion_queue(received_at DESC)
CREATE INDEX idx_ingestion_queue_payload ON ingestion_queue USING GIN(payload)
CREATE INDEX idx_ingestion_queue_external_id ON ingestion_queue(platform, external_id) WHERE external_id IS NOT NULL

-- Trigger for updated_at
CREATE TRIGGER update_ingestion_queue_updated_at
  BEFORE UPDATE ON ingestion_queue
  FOR EACH ROW EXECUTE FUNCTION update_updated_at()

-- Enable RLS
ALTER TABLE ingestion_queue ENABLE ROW LEVEL SECURITY

-- RLS Policies
CREATE POLICY "Users can read own queue items"
  ON ingestion_queue FOR SELECT
  USING (auth.uid() = user_id)

CREATE POLICY "Service role can manage queue"
  ON ingestion_queue FOR ALL
  USING (auth.role() = 'service_role')
