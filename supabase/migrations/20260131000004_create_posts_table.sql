-- Create posts table

CREATE TABLE posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES connected_accounts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- Denormalized for performance

  -- Platform identification
  platform platform_enum NOT NULL,
  platform_post_id TEXT NOT NULL, -- ID from the platform
  content_type content_type_enum DEFAULT 'post',

  -- Content
  text_content TEXT,
  html_content TEXT, -- If platform provides rich formatting

  -- Timestamps
  created_at_platform TIMESTAMPTZ NOT NULL, -- When posted on platform
  updated_at_platform TIMESTAMPTZ, -- Last edit on platform

  -- Status
  published BOOLEAN DEFAULT TRUE,
  deleted_on_platform BOOLEAN DEFAULT FALSE,

  -- Engagement (snapshot at time of sync)
  engagement_stats JSONB DEFAULT '{}',
  -- Example: {"likes": 42, "comments": 5, "shares": 2, "views": 1000}

  -- Platform-specific metadata
  metadata JSONB DEFAULT '{}',
  -- Bluesky: {author_did, author_handle, uri, reply_parent, reply_root}
  -- Strava: {activity_type, sport_type, distance, duration, elevation, stats}
  -- Instagram: {permalink, product_type, is_carousel}

  -- Search
  search_vector TSVECTOR, -- Full-text search

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Constraints
  CONSTRAINT unique_platform_post UNIQUE (platform, platform_post_id)
)

-- Indexes
CREATE INDEX idx_posts_account_id ON posts(account_id)
CREATE INDEX idx_posts_user_id ON posts(user_id)
CREATE INDEX idx_posts_user_created ON posts(user_id, created_at_platform DESC)
CREATE INDEX idx_posts_user_platform_created ON posts(user_id, platform, created_at_platform DESC)
CREATE INDEX idx_posts_deleted ON posts(deleted_on_platform)
CREATE INDEX idx_posts_engagement_stats ON posts USING GIN(engagement_stats)
CREATE INDEX idx_posts_metadata ON posts USING GIN(metadata)
CREATE INDEX idx_posts_search_vector ON posts USING GIN(search_vector)
