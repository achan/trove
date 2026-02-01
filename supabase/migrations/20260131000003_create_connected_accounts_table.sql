-- Create connected_accounts table

CREATE TABLE connected_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform platform_enum NOT NULL,
  platform_user_id TEXT NOT NULL,

  -- Platform profile information
  platform_profile JSONB NOT NULL,
  -- {username, display_name, avatar_url, ...platform-specific fields}

  -- Connection details (OAuth + webhooks)
  connection JSONB NOT NULL,
  -- Platform determines structure:
  -- Strava: {access_token, refresh_token, token_expires_at, scope, webhook_subscription_id}
  -- Bluesky: {access_token, refresh_token, token_expires_at, dpop_key, scope}
  -- Instagram: {access_token, token_expires_at, scope}

  -- Sync tracking
  last_sync_at TIMESTAMPTZ,
  sync_enabled BOOLEAN DEFAULT TRUE,

  -- Account status
  status account_status_enum DEFAULT 'active',
  error_message TEXT,
  error_count INTEGER DEFAULT 0,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Constraints
  CONSTRAINT unique_platform_account UNIQUE (user_id, platform, platform_user_id)
)

-- Indexes
CREATE INDEX idx_connected_accounts_user_id ON connected_accounts(user_id)
CREATE INDEX idx_connected_accounts_platform ON connected_accounts(platform)
CREATE INDEX idx_connected_accounts_status ON connected_accounts(status)
CREATE INDEX idx_connected_accounts_sync_enabled ON connected_accounts(sync_enabled, last_sync_at)
CREATE INDEX idx_connected_accounts_platform_profile ON connected_accounts USING GIN(platform_profile)
CREATE INDEX idx_connected_accounts_connection ON connected_accounts USING GIN(connection)
