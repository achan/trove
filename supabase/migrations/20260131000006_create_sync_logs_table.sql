-- Create sync_logs table

CREATE TABLE sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID REFERENCES connected_accounts(id) ON DELETE SET NULL,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,

  -- Sync details
  sync_type sync_type_enum NOT NULL,
  status sync_status_enum DEFAULT 'running',

  -- Metrics
  posts_fetched INTEGER DEFAULT 0,
  posts_created INTEGER DEFAULT 0,
  posts_updated INTEGER DEFAULT 0,
  posts_deleted INTEGER DEFAULT 0,
  media_downloaded INTEGER DEFAULT 0,
  media_failed INTEGER DEFAULT 0,

  -- Error tracking
  error_message TEXT,
  error_details JSONB,

  -- Timing
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  duration_ms INTEGER, -- Calculated

  -- Metadata
  metadata JSONB DEFAULT '{}',
  -- Example: {trigger_reason, cursor, page_count, rate_limit_remaining}

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

-- Indexes
CREATE INDEX idx_sync_logs_account_id ON sync_logs(account_id)
CREATE INDEX idx_sync_logs_user_id ON sync_logs(user_id)
CREATE INDEX idx_sync_logs_started_at ON sync_logs(started_at DESC)
CREATE INDEX idx_sync_logs_account_started ON sync_logs(account_id, started_at DESC)
CREATE INDEX idx_sync_logs_status ON sync_logs(status)
CREATE INDEX idx_sync_logs_sync_type ON sync_logs(sync_type)
