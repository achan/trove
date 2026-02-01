-- Create all enum types for Trove

-- Platform types
CREATE TYPE platform_enum AS ENUM ('bluesky', 'strava', 'instagram')

-- Account statuses
CREATE TYPE account_status_enum AS ENUM ('active', 'error', 'disconnected', 'token_expired')

-- Content types
CREATE TYPE content_type_enum AS ENUM (
  'post',      -- Standard social media post
  'activity',  -- Strava activity
  'story',     -- Instagram story
  'reel',      -- Instagram reel
  'reply',     -- Reply to another post
  'repost',    -- Share/repost
  'article'    -- Long-form content
)

-- Download statuses
CREATE TYPE download_status_enum AS ENUM (
  'pending',
  'downloading',
  'downloaded',
  'failed',
  'unavailable'
)

-- Sync types
CREATE TYPE sync_type_enum AS ENUM (
  'webhook',
  'manual',
  'scheduled',
  'backfill'
)

-- Sync statuses
CREATE TYPE sync_status_enum AS ENUM (
  'running',
  'success',
  'partial', -- Some items succeeded, some failed
  'failed',
  'cancelled'
)
