# Trove Data Flow Documentation

## Overview
This document describes the data flows through the Trove system, covering authentication, synchronization, media processing, and API access patterns.

---

## 1. User Onboarding Flow

```
[User] → [Trove App] → [Supabase Auth] → [users table]
                                        ↓
                                   [Auth Token]
```

### Steps
1. User signs up/logs in via Supabase Auth (email, OAuth, etc.)
2. Supabase creates auth record
3. Trigger creates corresponding record in `users` table
4. User receives authentication token

### Database Operations
```sql
-- Automatic via Supabase Auth trigger
INSERT INTO users (id, email) VALUES (auth.uid(), auth.email());
```

---

## 2. Platform Connection Flow (OAuth)

### High-Level Flow
```
[User] → [Connect Platform Button]
         ↓
[Edge Function: oauth-{platform}]
         ↓
[Redirect to Platform OAuth]
         ↓
[User Authorizes] → [Platform]
         ↓
[Callback with Code]
         ↓
[Exchange Code for Tokens]
         ↓
[Store in connected_accounts]
         ↓
[Trigger Initial Sync]
```

### Detailed Steps

#### 2.1 Initiate OAuth
```
User clicks "Connect Bluesky"
  ↓
POST /functions/v1/oauth-bluesky/start
  Body: { user_id }
  ↓
Generate state parameter (CSRF protection)
  ↓
Store state in session/database
  ↓
Return redirect URL to platform
```

#### 2.2 OAuth Callback
```
Platform redirects to callback URL
  ↓
GET /functions/v1/oauth-bluesky/callback?code=XXX&state=YYY
  ↓
Validate state parameter
  ↓
Exchange authorization code for tokens
  POST to platform OAuth endpoint
  ↓
Receive: access_token, refresh_token, expires_in
  ↓
Fetch user profile from platform
  ↓
Encrypt tokens
  ↓
INSERT INTO connected_accounts
```

#### 2.3 Database Record
```sql
INSERT INTO connected_accounts (
  user_id,
  platform,
  platform_user_id,
  username,
  display_name,
  access_token, -- encrypted
  refresh_token, -- encrypted
  token_expires_at,
  scope,
  status
) VALUES (...);
```

#### 2.4 Post-Connection
```
Trigger backfill sync job
  ↓
Queue: sync-account with sync_type='backfill'
```

---

## 3. Webhook Setup Flow (Strava Example)

```
[Connected Account Created]
         ↓
[Edge Function: setup-webhook]
         ↓
[POST to Strava Webhook API]
  {
    "callback_url": "https://{project}.supabase.co/functions/v1/webhook-strava",
    "verify_token": "{secret}"
  }
         ↓
[Strava Sends Verification Challenge]
         ↓
[GET webhook-strava?hub.challenge=XXX]
         ↓
[Respond with hub.challenge]
         ↓
[Webhook Subscription Confirmed]
         ↓
UPDATE connected_accounts
  SET webhook_subscribed = true,
      webhook_subscription_id = '{id}'
```

### Webhook Verification
```
Strava: GET {callback_url}?hub.mode=subscribe&hub.challenge=XXX&hub.verify_token=YYY
  ↓
Validate verify_token
  ↓
Return hub.challenge in response body
  ↓
Subscription active
```

---

## 4. Sync Flows

### 4.1 Webhook-Triggered Sync (Real-time)

```
[Platform Event Occurs]
  (User posts on Strava)
         ↓
[Platform Sends Webhook]
  POST /functions/v1/webhook-strava
  {
    "object_type": "activity",
    "object_id": 123456,
    "aspect_type": "create",
    "owner_id": 789,
    "event_time": 1234567890
  }
         ↓
[Webhook Receiver Function]
  1. Validate webhook signature
  2. Parse event payload
  3. Queue processing job
         ↓
[Background Job: process-webhook]
  1. Look up connected_account by owner_id
  2. Refresh access token if needed
  3. Fetch full data from platform API
  4. Process and store
```

#### Detailed Webhook Processing
```
Receive webhook event
  ↓
INSERT INTO ingested_items (platform, event_type, payload, source='webhook')
  ↓
Return 200 OK immediately
  ↓
--- Background Processing ---
  ↓
SELECT * FROM ingested_items WHERE status = 'pending'
  ↓
FOR EACH item:
  ↓
  Parse platform, object_id, owner_id
  ↓
  SELECT * FROM connected_accounts
    WHERE platform = item.platform
      AND platform_user_id = item.owner_id
  ↓
  Check token expiration
  ↓
  If expired: refresh_token()
  ↓
  Fetch full data from platform API
    (e.g., GET /activities/{object_id})
  ↓
  INSERT INTO ingested_posts (post_data, platform_post_id, ...)
  ↓
  UPDATE ingested_items SET status = 'completed'
  ↓
--- Post Processing ---
  ↓
  UPSERT INTO posts (normalized fields only)
  ↓
  Queue media downloads
  ↓
  UPDATE ingested_posts SET status = 'completed'
```

### 4.2 Scheduled Polling Sync

```
[Cron Trigger: Every 1 hour]
         ↓
[Edge Function: sync-all-accounts]
         ↓
SELECT * FROM connected_accounts
  WHERE sync_enabled = true
    AND (next_sync_at IS NULL OR next_sync_at <= NOW())
    AND status = 'active'
         ↓
FOR EACH account:
  ↓
  [Call sync-account function]
         ↓
  [Platform-Specific Sync Logic]
```

#### Platform-Specific Sync (Bluesky Example)

```
[sync-bluesky function]
         ↓
CREATE sync_log (status='running')
         ↓
Refresh access token if needed
         ↓
GET last synced post timestamp
  SELECT MAX(created_at_platform)
  FROM posts
  WHERE account_id = {account_id}
         ↓
Call Bluesky API
  GET app.bsky.feed.getAuthorFeed
  {
    actor: {did},
    limit: 100,
    cursor: {last_cursor}
  }
         ↓
Receive paginated results
         ↓
FOR EACH post in results:
  ↓
  Check if post exists
    SELECT id FROM posts WHERE platform_post_id = {uri}
  ↓
  If exists:
    UPDATE posts (updated_at_platform)
    UPDATE ingested_posts (post_data with latest engagement)
  If new:
    INSERT INTO ingested_posts (post_data, ...)
    INSERT INTO posts (normalized fields)
    Extract media from post.embed
    Queue media downloads
  ↓
If has more pages (cursor):
  Continue pagination
         ↓
UPDATE sync_log (status='success', completed_at=NOW())
UPDATE connected_accounts (last_sync_at=NOW(), next_sync_at=NOW() + interval)
```

### 4.3 Manual Sync Flow

```
[User clicks "Sync Now"]
         ↓
POST /api/sync/{account_id}
         ↓
Validate user owns account
         ↓
Call sync-account function
  WITH sync_type='manual'
         ↓
Return sync_log_id to track progress
         ↓
Client polls sync status
  GET /api/sync/{sync_log_id}/status
```

---

## 5. Media Download Flow

```
[Post Created/Updated]
         ↓
Extract media URLs from ingested_posts.post_data
         ↓
FOR EACH media URL:
  ↓
  INSERT INTO media_downloads (
    ingested_post_id,
    user_id,
    original_url,
    status='pending'
  )
  ON CONFLICT (user_id, original_url) DO NOTHING
         ↓
[Background Job: download-media]
         ↓
SELECT * FROM media_downloads
  WHERE status = 'pending'
     OR (status = 'failed'
         AND attempts < 3)
  ORDER BY created_at
  LIMIT 10
         ↓
FOR EACH media:
  ↓
  UPDATE status='downloading'
  ↓
  Fetch file from original_url
  ↓
  Compute storage_path = {user_id}/{platform}/{sha256(original_url)}.{ext}
  ↓
  Upload to Supabase Storage
  ↓
  UPDATE media_downloads
    SET status='downloaded'
  ↓
  If error:
    UPDATE status='failed',
           attempts = attempts + 1,
           error={message}
```

### Media Download with Retry Logic

```
attempt = 1
WHILE attempt <= 3:
  ↓
  TRY:
    Download file
    Upload to storage (path derived from URL hash)
    Update record
    BREAK
  ↓
  CATCH error:
    IF attempt == 3:
      Mark as 'failed'
    ELSE:
      Wait (exponential backoff: 2^attempt seconds)
      attempt++
```

### Natural Deduplication

```
Storage path = sha256(original_url)
  ↓
Same URL always maps to same storage location
  ↓
No explicit dedup check needed
  ↓
Unique constraint on (user_id, original_url) prevents duplicate records
```

---

## 6. Token Refresh Flow

```
[Before API Call]
         ↓
Check token_expires_at
         ↓
IF expires_at < NOW() + 5 minutes:
  ↓
  Call refresh_token()
         ↓
  POST to platform OAuth endpoint
    {
      grant_type: 'refresh_token',
      refresh_token: {encrypted_token},
      client_id: {id},
      client_secret: {secret}
    }
         ↓
  Receive new access_token, refresh_token
         ↓
  UPDATE connected_accounts
    SET access_token = encrypt(new_token),
        refresh_token = encrypt(new_refresh),
        token_expires_at = NOW() + expires_in,
        updated_at = NOW()
         ↓
  Use new access_token for API call
ELSE:
  Use existing access_token
```

### Token Refresh Error Handling

```
TRY refresh_token()
  ↓
CATCH invalid_grant:
  ↓
  UPDATE connected_accounts
    SET status = 'disconnected',
        error_message = 'Token refresh failed. Reauthorization required.'
  ↓
  Notify user to reconnect account
  ↓
  STOP sync for this account
```

---

## 7. Public API Data Flow

### 7.1 Get Posts Request

```
[Client] → GET /api/posts?platforms=bluesky,strava&limit=20&offset=0
         ↓
[Edge Function: api-posts]
         ↓
Validate API key / auth token
         ↓
Parse query parameters
         ↓
Build SQL query with filters
         ↓
SELECT p.*, ip.post_data
FROM posts p
JOIN ingested_posts ip ON ip.platform = p.platform
  AND ip.platform_post_id = p.platform_post_id
WHERE p.user_id = {authenticated_user}
  AND p.platform = ANY({platforms})
  AND p.published = true
  AND p.deleted_on_platform = false
ORDER BY p.created_at_platform DESC
LIMIT {limit} OFFSET {offset}
         ↓
Transform to API response format
         ↓
Extract media URLs from post_data
         ↓
Compute storage paths, generate signed URLs for downloaded media
         ↓
Return JSON response
```

### 7.2 Media URL Resolution

```
[Renderer] receives post + ingested_posts.post_data
         ↓
Extract media URL from post_data
         ↓
Compute storage_path = {user_id}/{platform}/{sha256(url)}.{ext}
         ↓
Check if file exists in storage
         ↓
IF exists:
  Generate signed URL for local copy
ELSE:
  Return original platform URL
```

### 7.3 Signed URL Generation

```
For each media URL in post_data:
  ↓
Compute storage_path from URL hash
  ↓
supabase.storage
  .from('media')
  .createSignedUrl(storage_path, 3600) // 1 hour
  ↓
Return signed URL that bypasses RLS
  ↓
Client can fetch directly from Supabase Storage
```

---

## 8. Error Recovery Flows

### 8.1 Sync Failure Recovery

```
[Sync fails with error]
         ↓
UPDATE connected_accounts
  SET error_count = error_count + 1,
      last_sync_status = 'failed',
      error_message = {message}
         ↓
IF error_count >= 5:
  ↓
  UPDATE status = 'error'
  Send notification to user
         ↓
Log to sync_logs
  ↓
CASE error_type:
  ↓
  WHEN 'rate_limit':
    Calculate backoff: next_sync_at = NOW() + {rate_limit_reset}
  ↓
  WHEN 'auth_error':
    UPDATE status = 'token_expired'
    Request user reauthorization
  ↓
  WHEN 'not_found':
    Account deleted on platform?
    UPDATE status = 'disconnected'
  ↓
  DEFAULT:
    Exponential backoff: next_sync_at = NOW() + (2^error_count * 60 seconds)
```

### 8.2 Media Download Failure Recovery

```
[Media download fails]
         ↓
UPDATE media_downloads
  SET attempts = attempts + 1,
      error = {message},
      last_attempt_at = NOW()
         ↓
IF attempts < 3:
  Keep status = 'pending' or 'failed'
  Will retry in next job run
         ↓
IF attempts >= 3:
  ↓
  CASE error_type:
    ↓
    WHEN '404' OR '410':
      UPDATE status = 'unavailable'
      (Media deleted/expired on platform)
    ↓
    DEFAULT:
      UPDATE status = 'failed'
      Log for manual review
```

---

## 9. Batch Processing Patterns

### 9.1 Batch Post Creation

```
Receive 100 posts from API
         ↓
Transform to database format
         ↓
Batch INSERT raw data into ingested_posts:

INSERT INTO ingested_posts (
  platform, platform_post_id, post_data, ...
)
SELECT * FROM unnest(...)
         ↓
Batch INSERT/UPDATE normalized posts:

INSERT INTO posts (
  account_id, platform, platform_post_id, text_content, ...
)
SELECT * FROM unnest(
  $1::uuid[], $2::platform_enum[], $3::text[], $4::text[], ...
)
ON CONFLICT (platform, platform_post_id)
DO UPDATE SET
  text_content = EXCLUDED.text_content,
  updated_at = NOW()
         ↓
RETURNING id, platform_post_id
         ↓
Map returned IDs to original data
         ↓
Extract all media URLs from post_data
         ↓
Batch INSERT media_downloads
```

### 9.2 Parallel Processing

```
[Large Sync Job]
         ↓
Split into chunks of 100 posts
         ↓
Process chunks in parallel
  Promise.all([
    processChunk(chunk1),
    processChunk(chunk2),
    processChunk(chunk3),
    ...
  ])
         ↓
Aggregate results
         ↓
Update sync_log with totals
```

---

## 10. Caching Strategy

### 10.1 API Response Caching

```
GET /api/posts request
         ↓
Generate cache key:
  posts:{user_id}:{platforms}:{start_date}:{end_date}:{offset}:{limit}
         ↓
Check Redis/Supabase cache:
  ↓
  IF exists AND not expired:
    Return cached response
  ↓
  ELSE:
    Query database
    Transform response
    Store in cache (TTL: 5 minutes)
    Return response
```

### 10.2 Materialized View Refresh

```
[Post created/updated]
         ↓
Mark materialized view as stale
         ↓
[Scheduled job: Every 5 minutes]
         ↓
IF views marked stale:
  REFRESH MATERIALIZED VIEW CONCURRENTLY public_posts
  ↓
  Clear related cache keys
```

---

## 11. Data Consistency Patterns

### 11.1 Transactional Sync

```
BEGIN TRANSACTION;
  ↓
  INSERT INTO sync_logs (...) RETURNING id;
  ↓
  TRY:
    Fetch from platform API
    ↓
    UPSERT posts
    ↓
    INSERT media_downloads (from post_data URLs)
    ↓
    UPDATE connected_accounts (last_sync_at)
    ↓
    UPDATE sync_logs (status='success', completed_at)
    ↓
    COMMIT;
  ↓
  CATCH:
    UPDATE sync_logs (status='failed', error_message)
    ↓
    ROLLBACK;
```

### 11.2 Idempotency

All sync operations designed to be idempotent:

```
UPSERT pattern for posts:
  ↓
INSERT INTO posts (...)
VALUES (...)
ON CONFLICT (platform, platform_post_id)
DO UPDATE SET
  text_content = EXCLUDED.text_content,
  updated_at_platform = EXCLUDED.updated_at_platform,
  updated_at = NOW()
WHERE
  posts.updated_at_platform < EXCLUDED.updated_at_platform

UPSERT pattern for ingested_posts (preserves raw data):
  ↓
INSERT INTO ingested_posts (...)
VALUES (...)
ON CONFLICT (platform, platform_post_id)
DO UPDATE SET
  post_data = EXCLUDED.post_data,
  updated_at = NOW()
```

This ensures:
- Running sync multiple times doesn't create duplicates
- Only updates if data actually changed
- Safe to retry failed operations
- Raw platform data always preserved in ingested_posts

---

## 12. Monitoring & Observability

### 12.1 Metrics Collection

```
Throughout sync process:
  ↓
Record metrics:
  - sync_duration_ms
  - posts_fetched
  - posts_created
  - posts_updated
  - api_calls_made
  - rate_limit_remaining
         ↓
Store in sync_logs.metadata
         ↓
Aggregate for monitoring dashboard
```

### 12.2 Health Checks

```
[Scheduled: Every 5 minutes]
         ↓
Check account health:
  ↓
  SELECT COUNT(*) FROM connected_accounts
    WHERE status = 'error'
      OR (last_sync_at < NOW() - interval '24 hours'
          AND sync_enabled = true)
         ↓
  IF count > threshold:
    Alert admin
         ↓
Check media download queue:
  ↓
  SELECT COUNT(*) FROM media_downloads
    WHERE status = 'pending'
      AND created_at < NOW() - interval '1 hour'
         ↓
  IF count > threshold:
    Alert admin
```

---

## Summary

This data flow architecture provides:

1. **Reliability**: Retry logic, error handling, transactional integrity
2. **Scalability**: Batch processing, parallel execution, caching
3. **Real-time**: Webhook support where available
4. **Flexibility**: Polling fallback for all platforms
5. **Consistency**: Idempotent operations, UPSERT patterns
6. **Observability**: Comprehensive logging and monitoring
7. **Security**: Token encryption, RLS, signed URLs

Each flow is designed to handle failures gracefully and provide clear audit trails for debugging.
