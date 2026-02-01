-- Create ingested_items table for archived webhook/fetch payloads

-- Ingestion source types
CREATE TYPE ingestion_source_enum AS ENUM (
  'webhook',      -- Incoming webhook from platform
  'fetch',        -- Scheduled/manual fetch
  'backfill',     -- Initial backfill operation
  'retry'         -- Retry of failed operation
)

-- Processing status
CREATE TYPE processing_status_enum AS ENUM (
  'pending',      -- Waiting to be processed
  'processing',   -- Currently being processed
  'completed',    -- Successfully processed
  'failed',       -- Processing failed
  'dead_letter'   -- Moved to dead letter after max retries
)

CREATE TABLE ingested_items (
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

-- Indexes for ingested_items
CREATE INDEX idx_ingested_items_status ON ingested_items(status)
CREATE INDEX idx_ingested_items_platform ON ingested_items(platform)
CREATE INDEX idx_ingested_items_account_id ON ingested_items(account_id)
CREATE INDEX idx_ingested_items_user_id ON ingested_items(user_id)
CREATE INDEX idx_ingested_items_source ON ingested_items(source)
CREATE INDEX idx_ingested_items_received_at ON ingested_items(received_at DESC)
CREATE INDEX idx_ingested_items_payload ON ingested_items USING GIN(payload)
CREATE INDEX idx_ingested_items_external_id ON ingested_items(platform, external_id) WHERE external_id IS NOT NULL

-- Trigger for updated_at
CREATE TRIGGER update_ingested_items_updated_at
  BEFORE UPDATE ON ingested_items
  FOR EACH ROW EXECUTE FUNCTION update_updated_at()

-- Enable RLS
ALTER TABLE ingested_items ENABLE ROW LEVEL SECURITY

-- RLS Policies
CREATE POLICY "Users can read own ingested items"
  ON ingested_items FOR SELECT
  USING (auth.uid() = user_id)

CREATE POLICY "Service role can manage ingested items"
  ON ingested_items FOR ALL
  USING (auth.role() = 'service_role')
