# Trove Architecture

## Overview

Trove is a unified social media archive system built on Supabase that downloads and stores
content from multiple platforms (Bluesky, Strava, Instagram) and provides an API for accessing
your archived data.

## Core Architecture Principles

### 1. Two-Stage Ingestion Architecture
All incoming data flows through a two-stage ingestion architecture that decouples raw data capture from processing:

```
External Platform → ingested_items → ingested_posts → Database (posts, media_downloads)
```

**Benefits:**
- Fast webhook responses (no processing during ingestion)
- Granular retry logic
- Complete audit trail with permanent raw data storage
- Ability to reprocess at any level
- Platform-specific data preserved in original format

### 2. Platform-Agnostic Storage
Data is stored in a normalized schema with platform-specific details in JSONB columns:
- `connected_accounts.platform_profile` - Profile info
- `connected_accounts.connection` - Auth & webhook details
- `ingested_posts.post_data` - Raw platform-specific post data (permanent archive, includes media URLs)

### 3. Multi-Tenant Isolation
Row Level Security (RLS) on all tables ensures users can only access their own data, with
service role bypassing RLS for background processing.

## System Components

### Database Schema

#### Core Tables
- **users** - Trove user accounts
- **connected_accounts** - OAuth connections to platforms
- **posts** - Archived social media posts/activities
- **media_downloads** - Media download tracking (storage path derived from URL hash)
- **sync_logs** - Sync operation audit trail

#### Ingestion Tables
- **ingested_items** - Raw webhook/fetch payloads (permanent archive)
- **ingested_posts** - Individual posts with raw platform data (permanent archive)

See [schema.mmd](schema.mmd) for visual diagram.

### Ingestion Architecture

#### Ingested Items
**Purpose:** Receive and permanently store raw data from platforms

**Sources:**
- `webhook` - Real-time platform webhooks (Strava)
- `fetch` - Scheduled polling (Instagram, fallback for all)
- `backfill` - Initial historical import
- `retry` - Retry of failed ingestion

**Processing:**
1. Webhook/fetch arrives
2. Insert raw payload into `ingested_items`
3. Return success immediately
4. Background worker picks up pending items
5. Extract individual posts from payload
6. Create entries in `ingested_posts`
7. Mark item as completed

**Fields:**
- `payload` - Complete raw response from platform
- `event_type` - Application-defined event classification
- `external_id` - Platform's webhook/event ID (for deduplication)

#### Ingested Posts
**Purpose:** Process individual posts and preserve raw platform data

**Processing:**
1. Worker picks up pending post
2. Parse `post_data` JSONB
3. Create/update `posts` record (normalized fields only)
4. Extract media URLs and queue in `media_downloads`
5. Mark post as completed

**Fields:**
- `ingested_item_id` - FK to source item (audit trail)
- `platform_post_id` - Platform's unique post ID
- `post_data` - Raw post data in platform's native format (permanent archive)

**Retention:**
Both tables are retained permanently:
- Serves as audit trail and raw data archive
- Enables reprocessing with updated normalization logic
- Platform-specific fields (engagement, metadata) queried via JOIN

**Retry Logic:**
Both tables use the same retry pattern:
- Hardcoded 3 attempts
- After 3 failures → status = `dead_letter`
- Dead letter items require manual investigation

### Connected Accounts

**Platform Profile** (`platform_profile` JSONB):
Platform determines structure based on available fields:
```json
// Strava
{
  "username": "runner_john",
  "display_name": "John Doe",
  "avatar_url": "https://...",
  "athlete_type": "runner"
}

// Bluesky
{
  "username": "@john.bsky.social",
  "display_name": "John",
  "avatar_url": "https://...",
  "did": "did:plc:abc123"
}
```

**Connection Details** (`connection` JSONB):
Platform determines auth structure:
```json
// Strava (OAuth2 + webhooks)
{
  "access_token": "encrypted...",
  "refresh_token": "encrypted...",
  "token_expires_at": "2026-02-15T14:30:00Z",
  "scope": "activity:read_all",
  "webhook_subscription_id": "12345"
}

// Bluesky (OAuth2 with DPoP)
{
  "access_token": "encrypted...",
  "refresh_token": "encrypted...",
  "token_expires_at": "2026-02-01T12:00:00Z",
  "dpop_key": "encrypted_jwk...",
  "scope": "atproto"
}

// Instagram (long-lived tokens)
{
  "access_token": "encrypted...",
  "token_expires_at": "2026-03-01T00:00:00Z",
  "scope": "instagram_basic"
}
```

### Sync System

#### Sync Logs
Track all synchronization operations for monitoring and debugging.

**Purpose:**
- Audit trail of all sync operations
- Performance monitoring
- Error analysis
- User-facing sync history

**One log per sync operation:**
- Webhook triggered → 1 log
- Scheduled poll → 1 log
- Manual sync → 1 log
- Initial backfill → 1 log

**Metrics tracked:**
- `posts_fetched` - Retrieved from platform
- `posts_created` - New in database
- `posts_updated` - Updated existing
- `posts_deleted` - Marked as deleted
- `media_downloaded` - Successfully downloaded
- `media_failed` - Failed downloads
- `duration_ms` - Total sync time

#### Sync Scheduling
No `next_sync_at` field - scheduler queries based on `last_sync_at`:

```sql
-- Find accounts that need syncing (1 hour interval example)
SELECT * FROM connected_accounts
WHERE sync_enabled = true
  AND (last_sync_at IS NULL OR last_sync_at < NOW() - INTERVAL '1 hour')
ORDER BY last_sync_at NULLS FIRST
```

### Platform Integration Patterns

#### Bluesky
- **Auth:** OAuth2 with DPoP (Demonstration of Proof of Possession)
- **Sync:** Firehose (real-time event stream) or polling
- **Webhooks:** No (uses firehose instead)
- **Refresh:** Yes, refresh tokens available

#### Strava
- **Auth:** OAuth2
- **Sync:** Webhooks (primary) + polling (fallback)
- **Webhooks:** Yes, subscription-based
- **Refresh:** Yes, short-lived access tokens

#### Instagram
- **Auth:** OAuth2 via Facebook Login
- **Sync:** Polling only (no webhooks for content)
- **Webhooks:** No
- **Refresh:** Long-lived tokens (60 days), no refresh token

## Data Flow Examples

### Webhook Flow (Strava Activity)
```
1. Strava sends webhook: "new activity created"
2. Webhook endpoint inserts to ingested_items
   - source: 'webhook'
   - event_type: 'activity.create'
   - payload: {full webhook body}
3. Return 200 OK immediately
4. Ingestion worker processes:
   - Extracts activity data
   - Creates ingested_posts entry (preserves raw post_data)
   - Marks item complete
5. Post worker processes:
   - Creates posts record (normalized fields)
   - Extracts media URLs, creates media_downloads records
   - Marks ingested_posts complete
6. Media download worker:
   - Downloads each URL to storage (path = hash of URL)
   - Updates media_downloads status
```

### Polling Flow (Instagram)
```
1. Scheduler identifies account needs sync
2. Fetch worker calls Instagram API
3. Inserts to ingested_items
   - source: 'fetch'
   - event_type: 'posts.fetch'
   - payload: {API response with 50 posts}
4. Ingestion worker processes:
   - Iterates through 50 posts
   - Creates 50 ingested_posts entries
   - Marks item complete
5. Post workers process each post in parallel
6. Media workers download all media
```

### Backfill Flow (New Account Connection)
```
1. User connects Instagram account
2. Backfill job created
3. Paginate through all historical posts
4. Each API page → ingested_items entry
   - source: 'backfill'
   - Cursor stored in payload
5. Process as normal through ingested_posts
6. Continue until all historical data fetched
```

## Security

### Authentication
- **User auth:** Supabase Auth (email, social login, etc.)
- **Platform auth:** OAuth2 tokens encrypted at application level
- **API access:** API keys for public API endpoints

### Authorization
- **RLS policies:** All tables have row-level security
- **Multi-tenant:** Users can only access their own data
- **Service role:** Background workers use service_role key (bypasses RLS)

### Data Protection
- **Tokens:** Encrypted before storage in `connection` JSONB
- **Transit:** All connections over HTTPS/TLS
- **Storage:** Supabase Storage with RLS policies

## Storage

### Media Bucket
```
media/
  {user_id}/
    {platform}/
      {sha256(original_url)}.jpg
      {sha256(original_url)}.mp4
```

**Configuration:**
- Size limit: 50MB per file
- Allowed types: image/*, video/*, audio/*
- RLS: Users can only access their own files
- Path format: `{user_id}/{platform}/{sha256(original_url)}.{ext}`
- Storage path derived at download time from URL hash (not stored in DB)

## Performance Considerations

### Indexes
- **Composite indexes:** `(user_id, created_at_platform DESC)` for timeline queries
- **GIN indexes:** JSONB columns for flexible queries
- **Full-text search:** `search_vector` on posts
- **Queue processing:** Status-based indexes for worker queries

### Denormalization
- `posts.user_id` - Denormalized from connected_accounts for performance
- Maintained via database triggers

### Caching Strategy
- API responses cached based on freshness requirements
- Media served via CDN (future enhancement)
- Materialized views for public timeline (future enhancement)

## Monitoring & Observability

### Sync Logs
- Track all sync operations
- Monitor success/failure rates
- Identify problematic accounts
- Performance metrics

### Ingestion Metrics
- Pending items depth
- Processing rate
- Error rate by platform
- Dead letter count

### Error Handling
- Automatic retries (3 attempts)
- Dead letter queue for manual review
- Error details stored in JSONB for debugging
- Error counts tracked on connected_accounts

## Future Enhancements

### Planned
- Real-time API via WebSockets
- Engagement history tracking over time
- Additional platforms (Twitter/X, YouTube, etc.)
- Advanced search with filters
- Data export functionality

### Under Consideration
- Webhook queue table for raw webhook storage
- Engagement history table for time-series data
- Materialized views for performance
- CDN integration for media serving
- Partitioning for large datasets
