# Trove - Social Media Archive Project

## Overview
Trove is a unified content archive system that downloads and stores social media posts and assets from multiple platforms, providing an API for displaying content on a personal page.

## Tech Stack
- **Backend**: Supabase (PostgreSQL + Edge Functions)
- **Storage**: Supabase Storage
- **Initial Platforms**: Bluesky, Strava, Instagram (Creator API)
- **Sync Strategy**: Hybrid (webhooks + polling)

## Architecture

### Database Schema

#### `users`
- `id` (uuid, primary key)
- `email` (text, unique)
- `created_at` (timestamp)
- `updated_at` (timestamp)

#### `connected_accounts`
- `id` (uuid, primary key)
- `user_id` (uuid, foreign key)
- `platform` (enum: 'bluesky', 'strava', 'instagram')
- `platform_user_id` (text)
- `username` (text)
- `access_token` (encrypted text)
- `refresh_token` (encrypted text)
- `token_expires_at` (timestamp)
- `webhook_subscribed` (boolean)
- `last_sync_at` (timestamp)
- `status` (enum: 'active', 'error', 'disconnected')
- `created_at` (timestamp)
- `updated_at` (timestamp)
- Unique constraint: (user_id, platform, platform_user_id)

#### `posts`
- `id` (uuid, primary key)
- `account_id` (uuid, foreign key)
- `platform` (enum: 'bluesky', 'strava', 'instagram')
- `platform_post_id` (text)
- `content_type` (enum: 'post', 'activity', 'story', 'reel')
- `text_content` (text)
- `metadata` (jsonb) - platform-specific data
- `created_at_platform` (timestamp) - when posted on platform
- `published` (boolean)
- `engagement_stats` (jsonb) - likes, comments, shares
- `created_at` (timestamp)
- `updated_at` (timestamp)
- Unique constraint: (platform, platform_post_id)
- Index: (account_id, created_at_platform)

#### `media_assets`
- `id` (uuid, primary key)
- `post_id` (uuid, foreign key)
- `media_type` (enum: 'image', 'video', 'audio', 'document')
- `original_url` (text)
- `storage_path` (text) - path in Supabase Storage
- `width` (integer)
- `height` (integer)
- `duration` (integer) - for videos/audio
- `file_size` (bigint)
- `mime_type` (text)
- `alt_text` (text)
- `position` (integer) - order in post
- `download_status` (enum: 'pending', 'downloaded', 'failed')
- `created_at` (timestamp)
- Index: (post_id, position)

#### `sync_logs`
- `id` (uuid, primary key)
- `account_id` (uuid, foreign key)
- `sync_type` (enum: 'webhook', 'manual', 'scheduled')
- `status` (enum: 'success', 'partial', 'failed')
- `posts_fetched` (integer)
- `posts_created` (integer)
- `posts_updated` (integer)
- `error_message` (text)
- `started_at` (timestamp)
- `completed_at` (timestamp)

## Platform-Specific Implementation

### Bluesky (AT Protocol)
- **API**: AT Protocol / Bluesky API
- **Auth**: OAuth 2.0
- **Webhooks**: Firehose subscription (real-time)
- **Polling Fallback**: `app.bsky.feed.getAuthorFeed` endpoint
- **Data to Store**:
  - Posts (text, embeds, replies)
  - Images, videos
  - Metadata: likes, reposts, replies count, timestamps

### Strava
- **API**: Strava API v3
- **Auth**: OAuth 2.0
- **Webhooks**: Activity events (create, update, delete)
- **Polling Fallback**: `athlete/activities` endpoint
- **Data to Store**:
  - Activities (runs, rides, swims, etc.)
  - Photos, maps (static images)
  - Metadata: distance, duration, elevation, heart rate, kudos

### Instagram (Creator/Business Account)
- **API**: Instagram Graph API
- **Auth**: OAuth 2.0 (Facebook Login)
- **Webhooks**: Limited (mentions, comments)
- **Polling**: `/{user-id}/media` endpoint
- **Data to Store**:
  - Posts, Reels, Stories (if available)
  - Images, videos, carousels
  - Metadata: likes, comments, caption, hashtags, location

## Supabase Edge Functions

### Authentication Functions
- `oauth-bluesky` - Handle Bluesky OAuth flow
- `oauth-strava` - Handle Strava OAuth flow
- `oauth-instagram` - Handle Instagram OAuth flow
- `disconnect-account` - Revoke tokens and disconnect account

### Webhook Receivers
- `webhook-bluesky` - Receive Bluesky firehose events
- `webhook-strava` - Receive Strava activity webhooks
- `webhook-instagram` - Receive Instagram webhooks (if applicable)

### Sync Functions
- `sync-account` - Manual trigger for single account sync
- `sync-all-accounts` - Scheduled sync for all active accounts
- `sync-bluesky` - Platform-specific sync logic
- `sync-strava` - Platform-specific sync logic
- `sync-instagram` - Platform-specific sync logic

### Media Functions
- `download-media` - Queue and download media assets
- `process-media-queue` - Background worker for media downloads

### Public API Functions
- `api-posts` - Get posts with filtering/pagination
- `api-post-detail` - Get single post with all media
- `api-media` - Proxy media files with auth

## Public API Design

### Endpoints

#### `GET /api/posts`
Query parameters:
- `platforms` - Filter by platform(s)
- `start_date` - ISO timestamp
- `end_date` - ISO timestamp
- `limit` - Default 20, max 100
- `offset` - Pagination offset
- `include_media` - Include media URLs

Response:
```json
{
  "posts": [
    {
      "id": "uuid",
      "platform": "bluesky",
      "type": "post",
      "content": "...",
      "created_at": "2024-01-20T10:00:00Z",
      "media": [
        {
          "id": "uuid",
          "type": "image",
          "url": "/api/media/uuid",
          "width": 1200,
          "height": 800
        }
      ],
      "metadata": {...}
    }
  ],
  "total": 150,
  "limit": 20,
  "offset": 0
}
```

#### `GET /api/posts/:id`
Get single post with full details

#### `GET /api/media/:id`
Serve media file (authenticated)

## Implementation Phases

### Phase 1: Foundation
- Set up Supabase project
- Create database schema with migrations
- Set up Supabase Storage buckets
- Configure RLS policies

### Phase 2: Authentication
- Implement OAuth flows for all platforms
- Store and encrypt tokens securely
- Build account connection UI (basic)

### Phase 3: Bluesky Integration
- Implement Bluesky sync (polling first)
- Media download pipeline
- Test with real data

### Phase 4: Strava Integration
- Implement Strava webhooks + polling
- Handle activity data and photos
- Map/route image generation

### Phase 5: Instagram Integration
- Implement Instagram polling
- Handle media carousels
- Rate limiting considerations

### Phase 6: Webhook Infrastructure
- Set up webhook receivers
- Implement webhook verification
- Add Bluesky firehose integration
- Add Strava webhook subscriptions

### Phase 7: Public API
- Build public-facing API endpoints
- Implement caching strategy
- Rate limiting
- API documentation

### Phase 8: Optimization
- Background job queue for media
- Incremental sync optimization
- Search and filtering improvements
- Analytics and monitoring

## Security Considerations

- Encrypt OAuth tokens at rest
- Use Supabase RLS for multi-tenant isolation
- Validate webhook signatures
- Rate limit public API
- Secure media access (signed URLs or auth)
- Handle token refresh automatically
- Log all sync operations for debugging

## Configuration Needs

### Environment Variables
- Bluesky OAuth client ID/secret
- Strava OAuth client ID/secret
- Instagram/Facebook app ID/secret
- Webhook verification tokens
- Supabase anon/service keys

## Detailed Documentation

This is a high-level overview. For comprehensive details, see:

- **[DATABASE_SCHEMA.md](docs/DATABASE_SCHEMA.md)** - Complete database schema with RLS policies, indexes, triggers, and functions
- **[DATA_FLOWS.md](docs/DATA_FLOWS.md)** - Detailed flow diagrams for OAuth, sync, webhooks, media downloads, and error recovery
- **[API_SPECIFICATION.md](docs/API_SPECIFICATION.md)** - Full REST API documentation with request/response examples, rate limiting, and caching
- **[SECURITY_PRIVACY.md](docs/SECURITY_PRIVACY.md)** - Security architecture, encryption, compliance (GDPR/CCPA), and incident response
- **[PLATFORM_BLUESKY.md](docs/PLATFORM_BLUESKY.md)** - Bluesky/AT Protocol API details, OAuth, firehose, and implementation strategy
- **[PLATFORM_STRAVA.md](docs/PLATFORM_STRAVA.md)** - Strava API v3 details, webhooks, token management, and rate limits
- **[PLATFORM_INSTAGRAM.md](docs/PLATFORM_INSTAGRAM.md)** - Instagram Graph API details, requirements, limitations, and polling strategy

## Next Steps

### Immediate (Phase 1: Foundation)
1. Set up Supabase project
2. Create database migrations from schema documentation
3. Configure RLS policies
4. Set up Supabase Storage buckets

### Short Term (Phase 2-3: First Platform)
4. Implement OAuth flow for Bluesky (simplest to start)
5. Build polling sync for Bluesky
6. Implement media download pipeline
7. Test with real data

### Medium Term (Phase 4-6: Expand Platforms)
8. Add Strava integration with webhooks
9. Add Instagram integration with polling
10. Build webhook infrastructure

### Long Term (Phase 7-8: Polish)
11. Build public API endpoints
12. Optimize performance and caching
13. Security audit and testing
14. Launch beta
