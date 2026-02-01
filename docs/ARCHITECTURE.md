# Trove Architecture

## Overview

Trove is a unified social media archive system built on Supabase that downloads and stores
content from multiple platforms (Bluesky, Strava, Instagram) and provides an API for accessing
your archived data.

## Core Architecture Principles

### 1. Queue-Based Processing
All incoming data flows through a two-queue architecture that decouples ingestion from processing:

```
External Platform → ingestion_queue → post_queue → Database (posts, media_assets)
```

**Benefits:**
- Fast webhook responses (no processing during ingestion)
- Granular retry logic
- Complete audit trail
- Ability to reprocess at any level

### 2. Platform-Agnostic Storage
Data is stored in a normalized schema with platform-specific details in JSONB columns:
- `connected_accounts.platform_profile` - Profile info
- `connected_accounts.connection` - Auth & webhook details
- `posts.metadata` - Platform-specific post data
- `media_assets.metadata` - Platform-specific media data

### 3. Multi-Tenant Isolation
Row Level Security (RLS) on all tables ensures users can only access their own data, with
service role bypassing RLS for background processing.

## System Components

### Database Schema

#### Core Tables
- **users** - Trove user accounts
- **connected_accounts** - OAuth connections to platforms
- **posts** - Archived social media posts/activities
- **media_assets** - Downloaded media files
- **sync_logs** - Sync operation audit trail

#### Queue Tables
- **ingestion_queue** - Raw webhook/fetch payloads
- **post_queue** - Individual posts extracted for processing

See [schema.mmd](schema.mmd) for visual diagram.

### Queue Processing Architecture

#### Ingestion Queue
**Purpose:** Receive and store raw data from platforms

**Sources:**
- `webhook` - Real-time platform webhooks (Strava)
- `fetch` - Scheduled polling (Instagram, fallback for all)
- `backfill` - Initial historical import
- `retry` - Retry of failed ingestion

**Processing:**
1. Webhook/fetch arrives
2. Insert raw payload into `ingestion_queue`
3. Return success immediately
4. Background worker picks up pending items
5. Extract individual posts from payload
6. Create entries in `post_queue`
7. Mark ingestion as completed

**Fields:**
- `payload` - Complete raw response from platform
- `event_type` - Application-defined event classification
- `external_id` - Platform's webhook/event ID (for deduplication)

#### Post Queue
**Purpose:** Process individual posts one at a time

**Processing:**
1. Worker picks up pending post
2. Parse `post_data` JSONB
3. Create/update `posts` record
4. Queue media downloads in `media_assets`
5. Mark post as completed

**Fields:**
- `ingestion_queue_id` - FK to source ingestion (audit trail)
- `platform_post_id` - Platform's unique post ID
- `post_data` - Normalized post structure in JSONB

**Retry Logic:**
Both queues use the same retry pattern:
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
2. Webhook endpoint inserts to ingestion_queue
   - source: 'webhook'
   - event_type: 'activity.create'
   - payload: {full webhook body}
3. Return 200 OK immediately
4. Ingestion worker processes:
   - Extracts activity data
   - Creates post_queue entry
   - Marks ingestion complete
5. Post worker processes:
   - Creates posts record
   - Creates media_assets records for photos
   - Marks post_queue complete
6. Media download worker:
   - Downloads each photo
   - Updates media_assets records
```

### Polling Flow (Instagram)
```
1. Scheduler identifies account needs sync
2. Fetch worker calls Instagram API
3. Inserts to ingestion_queue
   - source: 'fetch'
   - event_type: 'posts.fetch'
   - payload: {API response with 50 posts}
4. Ingestion worker processes:
   - Iterates through 50 posts
   - Creates 50 post_queue entries
   - Marks ingestion complete
5. Post workers process each post in parallel
6. Media workers download all media
```

### Backfill Flow (New Account Connection)
```
1. User connects Instagram account
2. Backfill job created
3. Paginate through all historical posts
4. Each API page → ingestion_queue entry
   - source: 'backfill'
   - Cursor stored in metadata
5. Process as normal through post_queue
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
    bluesky/
      {post_id}/
        image1.jpg
        image2.jpg
    strava/
      {post_id}/
        activity_photo.jpg
        map.png
    instagram/
      {post_id}/
        post_image.jpg
```

**Configuration:**
- Size limit: 50MB per file
- Allowed types: image/*, video/*, audio/*
- RLS: Users can only access their own files
- Path format: `{user_id}/{platform}/{post_id}/{filename}`

## Performance Considerations

### Indexes
- **Composite indexes:** `(user_id, created_at_platform DESC)` for timeline queries
- **GIN indexes:** JSONB columns for flexible queries
- **Full-text search:** `search_vector` on posts
- **Queue processing:** Status-based indexes for worker queries

### Denormalization
- `posts.user_id` - Denormalized from connected_accounts for performance
- `media_assets.user_id` - Denormalized from posts for performance
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

### Queue Metrics
- Pending queue depth
- Processing rate
- Error rate by platform
- Dead letter queue size

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
