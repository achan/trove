# Bluesky / AT Protocol Integration

## Authentication

### OAuth 2.0 (Recommended)
- **Status**: Primary authentication method as of 2025
- **Replaces**: App Passwords and createSession (legacy)
- **Scope Support**: Granular permissions implemented in 2025
  - Read/write posts on Bluesky
  - Access DMs (separate permission)
  - Email access via `transition:email` scope

### Requirements
- Client metadata JSON document published on public web
- `client_id` = fully-qualified https:// URL to metadata document
- TypeScript SDK: `@atproto/api` (supports OAuth)
  - Browser-specific package available
  - Node.js-specific package available

### Limitations
- Not recommended for "headless" clients (CLI tools, bots)
- OAuth is primary for interactive web applications

## API Capabilities

### Endpoints
- `app.bsky.feed.getAuthorFeed` - Get user's posts (polling)
- `com.atproto.server.getSession` - Get account session info (includes email with proper scope)

### Real-Time Data
- **Firehose**: AT Protocol provides a firehose for real-time data streams
- **Not Traditional Webhooks**: No webhook subscriptions, use firehose for real-time

## Data Available

### Posts
- Text content
- Embedded media (images, videos)
- Replies and threads
- Quote posts
- External embeds (links, etc.)

### Metadata
- Post URI (AT Protocol identifier)
- Timestamps (created, indexed)
- Author DID (decentralized identifier)
- Engagement: likes, reposts, replies count

### Media
- Images (multiple per post)
- Videos
- Alt text for accessibility
- Aspect ratios

## Implementation Strategy

### Initial Approach: Polling
1. Authenticate via OAuth
2. Periodically call `getAuthorFeed` for new posts
3. Store posts with AT Protocol URIs as unique identifiers
4. Download embedded media to Supabase Storage

### Advanced Approach: Firehose
1. Subscribe to AT Protocol firehose
2. Filter events for specific user DID
3. Process create/update/delete events in real-time
4. More complex but truly real-time

## Rate Limits
- Documentation doesn't specify hard limits
- Reasonable use expected
- Firehose is designed for high-volume consumption

## Token Management
- OAuth tokens managed via standard refresh flow
- Granular scopes ensure minimal permissions
- Tokens stored encrypted in database

## Special Considerations
- AT Protocol is decentralized - posts stored on PDS (Personal Data Server)
- DIDs (Decentralized Identifiers) are permanent user identifiers
- Post URIs include DID + timestamp + unique ID
- Bluesky is one application on AT Protocol (could support others)

## Data Schema Mapping

```
AT Protocol Post → Trove Schema
- uri → platform_post_id
- text → text_content
- createdAt → created_at_platform
- likeCount, repostCount, replyCount → engagement_stats
- embed.images[] → media_assets
- author.did → metadata.author_did
- author.handle → metadata.author_handle
```

## Resources
- Official Docs: https://docs.bsky.app/
- TypeScript SDK: https://github.com/bluesky-social/atproto
- OAuth Guide: https://docs.bsky.app/docs/advanced-guides/oauth-client
