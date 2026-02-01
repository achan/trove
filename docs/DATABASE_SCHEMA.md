# Trove Database Schema

## Overview
This document provides a detailed specification of the PostgreSQL database schema for Trove, including all tables, relationships, constraints, indexes, and Row Level Security (RLS) policies.

## Schema Diagram

```
users
  └─< connected_accounts (1:many)
       └─< posts (1:many)
       └─< sync_logs (1:many)
       └─< ingested_items (1:many)
            └─< ingested_posts (1:many)
                 └─< media_downloads (1:many)
       └─< ingested_posts (1:many)
```

## Tables

### `users`
Stores Trove user accounts.

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**Indexes:**
- `PRIMARY KEY` on `id`
- `UNIQUE` index on `email`

**RLS Policies:**
- Users can only read their own record
- Users can update their own email
- New user creation handled via Supabase Auth

**Notes:**
- Can extend with additional fields: `display_name`, `avatar_url`, `timezone`
- Email comes from Supabase Auth initially
- `updated_at` maintained via trigger

---

### `connected_accounts`
Stores OAuth connections to social media platforms.

```sql
CREATE TYPE platform_enum AS ENUM ('bluesky', 'strava', 'instagram');
CREATE TYPE account_status_enum AS ENUM ('active', 'error', 'disconnected', 'token_expired');

CREATE TABLE connected_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform platform_enum NOT NULL,
  platform_user_id TEXT NOT NULL,
  username TEXT NOT NULL,
  display_name TEXT,
  avatar_url TEXT,

  -- OAuth credentials (encrypted at application level)
  access_token TEXT NOT NULL,
  refresh_token TEXT,
  token_expires_at TIMESTAMPTZ,
  scope TEXT, -- Granted OAuth scopes

  -- Webhook status
  webhook_subscribed BOOLEAN DEFAULT FALSE,
  webhook_subscription_id TEXT, -- For platforms like Strava

  -- Sync tracking
  last_sync_at TIMESTAMPTZ,
  last_sync_status TEXT, -- 'success', 'failed', 'partial'
  next_sync_at TIMESTAMPTZ, -- For scheduled polling
  sync_enabled BOOLEAN DEFAULT TRUE,

  -- Account status
  status account_status_enum DEFAULT 'active',
  error_message TEXT,
  error_count INTEGER DEFAULT 0,

  -- Metadata
  metadata JSONB DEFAULT '{}', -- Platform-specific data
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Constraints
  CONSTRAINT unique_platform_account UNIQUE (user_id, platform, platform_user_id)
);
```

**Indexes:**
- `PRIMARY KEY` on `id`
- `UNIQUE` composite on `(user_id, platform, platform_user_id)`
- `INDEX` on `user_id` (foreign key)
- `INDEX` on `platform`
- `INDEX` on `status`
- `INDEX` on `(sync_enabled, next_sync_at)` for sync scheduling
- `INDEX` on `token_expires_at` for token refresh jobs

**RLS Policies:**
- Users can read only their own connected accounts
- Users can insert their own connected accounts
- Users can update their own connected accounts
- Users can delete their own connected accounts

**Notes:**
- Tokens should be encrypted before storage (application-level encryption)
- `metadata` can store platform-specific info (e.g., Strava athlete type, Instagram account type)
- `error_count` increments on sync failures, resets on success
- Consider using Supabase Vault for token encryption in future

---

### `posts`
Stores normalized social media posts/activities from all platforms.

```sql
CREATE TYPE content_type_enum AS ENUM (
  'post',      -- Standard social media post
  'activity',  -- Strava activity
  'story',     -- Instagram story
  'reel',      -- Instagram reel
  'reply',     -- Reply to another post
  'repost',    -- Share/repost
  'article'    -- Long-form content
);

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

  -- Search
  search_vector TSVECTOR, -- Full-text search (populated from ingested_posts.post_data)

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Constraints
  CONSTRAINT unique_platform_post UNIQUE (platform, platform_post_id)
);
```

**Indexes:**
- `PRIMARY KEY` on `id`
- `UNIQUE` composite on `(platform, platform_post_id)`
- `INDEX` on `account_id`
- `INDEX` on `user_id` (for user queries)
- `INDEX` on `(user_id, created_at_platform DESC)` (main query pattern)
- `INDEX` on `(user_id, platform, created_at_platform DESC)`
- `INDEX` on `deleted_on_platform` (to filter out)
- `GIN INDEX` on `search_vector` (for full-text search)

**RLS Policies:**
- Users can read only their own posts
- Service role can insert/update posts (sync jobs)
- Users cannot directly insert/update posts (done via sync)

**Triggers:**
- Update `search_vector` on insert/update (queries `ingested_posts.post_data` for platform-specific fields)
- Update `updated_at` timestamp
- Denormalize `user_id` from `account_id` on insert

**Notes:**
- Platform-specific metadata (engagement, activity stats, etc.) stored in `ingested_posts.post_data`
- Query via JOIN with `ingested_posts` for full data
- Consider partitioning by `created_at_platform` for large datasets

---

### `media_downloads`
Tracks media download status. Storage path derived from URL hash at runtime.

```sql
CREATE TYPE download_status_enum AS ENUM (
  'pending',
  'downloading',
  'downloaded',
  'failed',
  'unavailable'
);

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
);
```

**Indexes:**
- `PRIMARY KEY` on `id`
- `UNIQUE` on `(user_id, original_url)` (natural deduplication)
- `INDEX` on `ingested_post_id`
- `INDEX` on `user_id`
- `INDEX` on `status` (for background jobs)
- `INDEX` on `(status, attempts)` (for retry logic)

**RLS Policies:**
- Users can read only their own media downloads
- Service role can insert/update (download jobs)

**Storage Path (computed at runtime):**
```
{user_id}/{platform}/{sha256(original_url)}.{ext}
```

**Notes:**
- Media metadata (dimensions, alt_text, etc.) available in `ingested_posts.post_data`
- Storage path not stored in DB - derived from URL hash
- Natural deduplication: same URL = same storage location
- Platform-specific renderers use `post_data` for display info

---

### `sync_logs`
Tracks synchronization operations for debugging and monitoring.

```sql
CREATE TYPE sync_type_enum AS ENUM (
  'webhook',
  'manual',
  'scheduled',
  'backfill'
);

CREATE TYPE sync_status_enum AS ENUM (
  'running',
  'success',
  'partial', -- Some items succeeded, some failed
  'failed',
  'cancelled'
);

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
);
```

**Indexes:**
- `PRIMARY KEY` on `id`
- `INDEX` on `account_id`
- `INDEX` on `user_id`
- `INDEX` on `started_at DESC` (recent logs)
- `INDEX` on `(account_id, started_at DESC)`
- `INDEX` on `status`
- `INDEX` on `sync_type`

**RLS Policies:**
- Users can read only their own sync logs
- Service role can insert sync logs

**Triggers:**
- Calculate `duration_ms` on completion
- Update `connected_accounts.last_sync_at` on completion

**Notes:**
- Retention policy: Archive/delete logs older than 90 days
- Use for debugging sync issues
- Metrics useful for monitoring

---

### `ingested_items`
Permanent archive of raw webhook/fetch payloads from platforms.

```sql
CREATE TYPE ingestion_source_enum AS ENUM (
  'webhook',      -- Incoming webhook from platform
  'fetch',        -- Scheduled/manual fetch
  'backfill',     -- Initial backfill operation
  'retry'         -- Retry of failed operation
);

CREATE TYPE processing_status_enum AS ENUM (
  'pending',      -- Waiting to be processed
  'processing',   -- Currently being processed
  'completed',    -- Successfully processed
  'failed',       -- Processing failed
  'dead_letter'   -- Moved to dead letter after max retries
);

CREATE TABLE ingested_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source ingestion_source_enum NOT NULL,
  platform platform_enum NOT NULL,
  account_id UUID REFERENCES connected_accounts(id) ON DELETE SET NULL,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,

  -- Event identification
  event_type TEXT NOT NULL,
  external_id TEXT, -- Platform's event/webhook ID

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
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**Indexes:**
- `INDEX` on `status` (for processing)
- `INDEX` on `platform`
- `INDEX` on `account_id`, `user_id`
- `INDEX` on `received_at DESC`
- `GIN INDEX` on `payload`
- `INDEX` on `(platform, external_id)` for deduplication

**Notes:**
- Retained permanently as audit trail and raw data archive
- Enables reprocessing with updated normalization logic

---

### `ingested_posts`
Permanent archive of individual posts with raw platform data.

```sql
CREATE TABLE ingested_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ingested_item_id UUID REFERENCES ingested_items(id) ON DELETE SET NULL,

  -- Platform information
  platform platform_enum NOT NULL,
  account_id UUID REFERENCES connected_accounts(id) ON DELETE SET NULL,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,

  -- Post identification
  platform_post_id TEXT NOT NULL,

  -- Post data in native format (permanent archive)
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
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**Indexes:**
- `INDEX` on `status` (for processing)
- `INDEX` on `(platform, platform_post_id)` (for lookups from posts)
- `INDEX` on `account_id`, `user_id`
- `INDEX` on `received_at DESC`
- `GIN INDEX` on `post_data` (for querying platform-specific fields)

**Notes:**
- Contains full platform-specific data: engagement stats, metadata, activity details
- Query via JOIN with `posts` table for combined data
- Retained permanently - no deletion policy

---

## Additional Tables (Future)

### `engagement_history`
Track engagement over time (likes, views, etc.)

```sql
CREATE TABLE engagement_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  engagement_stats JSONB NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT unique_post_recording UNIQUE (post_id, recorded_at)
);
```

---

## Enums Reference

```sql
-- Platform types
CREATE TYPE platform_enum AS ENUM ('bluesky', 'strava', 'instagram');

-- Account statuses
CREATE TYPE account_status_enum AS ENUM ('active', 'error', 'disconnected', 'token_expired');

-- Content types
CREATE TYPE content_type_enum AS ENUM ('post', 'activity', 'story', 'reel', 'reply', 'repost', 'article');

-- Media types

-- Download statuses
CREATE TYPE download_status_enum AS ENUM ('pending', 'downloading', 'downloaded', 'failed', 'unavailable');

-- Sync types
CREATE TYPE sync_type_enum AS ENUM ('webhook', 'manual', 'scheduled', 'backfill');

-- Sync statuses
CREATE TYPE sync_status_enum AS ENUM ('running', 'success', 'partial', 'failed', 'cancelled');

-- Ingestion source types
CREATE TYPE ingestion_source_enum AS ENUM ('webhook', 'fetch', 'backfill', 'retry');

-- Processing statuses (for ingested_items and ingested_posts)
CREATE TYPE processing_status_enum AS ENUM ('pending', 'processing', 'completed', 'failed', 'dead_letter');
```

---

## Row Level Security (RLS)

### General Principles
- All tables have RLS enabled
- Users can only access their own data
- Service role bypasses RLS for background jobs
- Public API uses service role with additional auth layer

### Example Policies

```sql
-- users table
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own record"
  ON users FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can update own record"
  ON users FOR UPDATE
  USING (auth.uid() = id);

-- connected_accounts table
ALTER TABLE connected_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own accounts"
  ON connected_accounts FOR ALL
  USING (auth.uid() = user_id);

-- posts table
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own posts"
  ON posts FOR SELECT
  USING (auth.uid() = user_id);

-- media_downloads table
ALTER TABLE media_downloads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own media downloads"
  ON media_downloads FOR SELECT
  USING (auth.uid() = user_id);

-- sync_logs table
ALTER TABLE sync_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own sync logs"
  ON sync_logs FOR SELECT
  USING (auth.uid() = user_id);
```

---

## Database Functions

### Update Timestamps
```sql
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to all tables with updated_at
CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Repeat for other tables...
```

### Update Search Vector
```sql
-- Queries ingested_posts for platform-specific fields (author_handle, activity_type)
CREATE OR REPLACE FUNCTION update_search_vector()
RETURNS TRIGGER AS $$
DECLARE
  post_data JSONB;
BEGIN
  -- Look up the raw post data from ingested_posts
  SELECT ip.post_data INTO post_data
  FROM ingested_posts ip
  WHERE ip.platform = NEW.platform
    AND ip.platform_post_id = NEW.platform_post_id
  ORDER BY ip.created_at DESC
  LIMIT 1;

  NEW.search_vector = to_tsvector('english',
    COALESCE(NEW.text_content, '') || ' ' ||
    COALESCE(post_data->>'author_handle', '') || ' ' ||
    COALESCE(post_data->>'activity_type', '')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_posts_search_vector
  BEFORE INSERT OR UPDATE OF text_content ON posts
  FOR EACH ROW EXECUTE FUNCTION update_search_vector();
```

### Denormalize User ID
```sql
CREATE OR REPLACE FUNCTION denormalize_post_user_id()
RETURNS TRIGGER AS $$
BEGIN
  SELECT user_id INTO NEW.user_id
  FROM connected_accounts
  WHERE id = NEW.account_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER denormalize_posts_user_id
  BEFORE INSERT ON posts
  FOR EACH ROW EXECUTE FUNCTION denormalize_post_user_id();
```

---

## Supabase Storage Buckets

### `media` Bucket
- **Purpose**: Store downloaded media assets
- **Public**: No (authenticated access)
- **File size limit**: 50MB per file
- **Allowed MIME types**: `image/*`, `video/*`, `audio/*`
- **RLS**: Users can only access their own files

### Structure
```
media/
  {user_id}/
    bluesky/
      {post_id}/
        {filename}
    strava/
      {post_id}/
        {filename}
    instagram/
      {post_id}/
        {filename}
```

### RLS Policy
```sql
CREATE POLICY "Users can access own media"
  ON storage.objects FOR ALL
  USING (bucket_id = 'media' AND (storage.foldername(name))[1] = auth.uid()::text);
```

---

## Performance Considerations

### Partitioning
For large datasets (millions of posts), consider partitioning `posts` table by date:
```sql
-- Partition by year
CREATE TABLE posts_2024 PARTITION OF posts
  FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
```

### Materialized Views
For public API performance:
```sql
CREATE MATERIALIZED VIEW public_posts AS
SELECT
  p.id,
  p.platform,
  p.content_type,
  p.text_content,
  p.created_at_platform,
  p.engagement_stats,
  json_agg(json_build_object(
    'id', m.id,
    'type', m.media_type,
    'url', m.storage_path,
    'width', m.width,
    'height', m.height
  )) AS media
FROM posts p
LEFT JOIN media_downloads md ON md.ingested_post_id = ip.id AND md.status = 'downloaded'
LEFT JOIN ingested_posts ip ON ip.platform = p.platform AND ip.platform_post_id = p.platform_post_id
WHERE p.published = TRUE AND p.deleted_on_platform = FALSE
GROUP BY p.id;

CREATE INDEX ON public_posts (created_at_platform DESC);
```

### Archival Strategy
- Move sync_logs older than 90 days to archive table
- Keep engagement snapshots at intervals (daily) in engagement_history
- Consider cold storage for old media

---

## Migration Strategy

1. Create enums first
2. Create tables in order: users, connected_accounts, posts, ingested_items, ingested_posts, media_downloads, sync_logs
3. Create indexes
4. Enable RLS and create policies
5. Create functions and triggers
6. Create storage buckets
7. Test with sample data

## Testing Data Integrity

- Foreign key constraints ensure referential integrity
- Unique constraints prevent duplicate platform posts
- Check constraints validate data ranges
- Triggers maintain denormalized fields
- RLS policies tested with multiple users
