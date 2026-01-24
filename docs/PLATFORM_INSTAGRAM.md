# Instagram Graph API Integration

## Overview
- **API**: Instagram Graph API (part of Meta Platform)
- **Account Types Supported**: Business and Creator accounts only
- **Access**: Only for accounts you own or manage
- **Status**: Active and updated in 2025

## Authentication

### OAuth 2.0 via Facebook Login
- Requires Facebook App ID and App Secret
- Users authenticate via Facebook Login
- Must link Instagram Business/Creator account to Facebook Page
- Permissions requested via OAuth scopes

### Required Permissions (Scopes)
- `instagram_basic` - Basic profile access
- `instagram_content_publish` - Publish content (not needed for archival)
- `pages_show_list` - Access to Facebook Pages
- `pages_read_engagement` - Read engagement metrics
- `instagram_manage_insights` - Access to insights/analytics

### Account Requirements
- Instagram account must be Business or Creator type
- Account must be connected to a Facebook Page
- Personal Instagram accounts NOT supported

## API Capabilities

### Media Endpoints
- `GET /{ig-user-id}/media` - Get list of media objects
- `GET /{media-id}` - Get specific media details
- `GET /{media-id}/children` - For carousel posts

### Available Data Per Media Item
- Media ID (unique identifier)
- Media type (IMAGE, VIDEO, CAROUSEL_ALBUM, REELS)
- Caption text
- Media URL (direct link to image/video)
- Permalink (Instagram post URL)
- Timestamp
- Username
- Media product type (FEED, STORY, REELS)

### Engagement Data
- Like count
- Comments count (requires additional call)
- Comments text (with separate endpoint)
- Reach and impressions (via Insights API)

### Limitations
- Cannot access private/personal accounts
- Cannot fetch follower lists of other accounts
- Cannot access public content from accounts you don't own
- Stories available only for 24 hours (same as platform)
- API access requires App Review for production use

## Webhooks

### Limited Webhook Support
- **Not Available**: Real-time webhooks for new media posts
- **Available**: Webhooks for mentions and comments
- **Strategy**: Polling is required for new content detection

### Mentions Webhook
- Notified when account is @mentioned
- Not useful for archiving own content

## Implementation Strategy

### Polling Approach (Required)
1. Authenticate user via Facebook Login
2. Get Instagram Business/Creator account ID
3. Periodically call `/media` endpoint
4. Check for new media since last sync
5. Download media files
6. Store metadata and engagement stats

### Polling Frequency Considerations
- Instagram posts are less frequent than other platforms
- Recommended: Every 1-6 hours depending on user activity
- Rate limits apply

## Media Download

### Image Media
- `media_url` field provides direct link to image
- High resolution available
- Download and store in Supabase Storage

### Video Media
- `media_url` provides direct link to video file
- Can be large files (Stories, Reels)
- Consider storage costs

### Carousel Albums
- Parent media object has `media_type: CAROUSEL_ALBUM`
- Must fetch children via `/{media-id}/children`
- Each child has own `media_url`
- Maintain order (position in carousel)

### Stories
- Available via API only while live (24 hours)
- Same structure as posts
- Expires quickly - need frequent polling if archiving stories

## Rate Limits

### Standard Limits (2025)
- 200 calls per hour per user
- Rate limit headers in response
- Applies per Instagram Business account

### Best Practices
- Batch requests when possible
- Cache results
- Use pagination efficiently
- Monitor rate limit headers

## Insights & Analytics

### Media Insights
- Impressions
- Reach
- Engagement
- Saved
- Video views (for video content)

### Time Limits
- Metrics available for limited time period
- Stories: 24 hours
- Posts: Ongoing (but may have cutoff)

## Data Schema Mapping

```
Instagram Media → Trove Schema
- id → platform_post_id
- media_type → content_type
- caption → text_content
- timestamp → created_at_platform
- like_count, comments_count → engagement_stats
- media_url → media_assets.original_url
- permalink → metadata.permalink
- media_product_type → metadata.product_type
- children (carousel) → multiple media_assets
```

## 2025 Updates

### New Features
- Enhanced endpoints for better access to media and comments
- Privacy-first demographic reporting
- Deprecated legacy metrics (clean up old fields)

### Deprecated
- Old insights metrics (specific fields vary)
- Some legacy API versions

## Special Considerations

### Carousel Posts
- Single post, multiple media items
- All children share same caption/engagement
- Store as one post with multiple media_assets
- Preserve order with `position` field

### Reels
- Special media type
- Video content
- May have cover image separate from video
- Higher engagement typically

### Content Rights
- Only download content you own
- Respect user's own content rights
- Terms of Service compliance

### Facebook Page Dependency
- Instagram Business account must stay linked to Facebook Page
- If unlinked, API access breaks
- Monitor connection status

## Implementation Phases

### Phase 1: Basic Auth & Media List
1. Implement Facebook Login OAuth
2. Get Instagram account ID
3. Fetch media list
4. Display in basic format

### Phase 2: Media Download
1. Download images
2. Download videos
3. Handle carousels
4. Store in Supabase Storage

### Phase 3: Metadata & Engagement
1. Store captions
2. Fetch comments
3. Store engagement stats
4. Update on subsequent polls

### Phase 4: Insights (Optional)
1. Fetch media insights
2. Store analytics data
3. Track over time

## Resources
- Instagram Graph API: https://developers.facebook.com/docs/instagram-api/
- Getting Started: https://developers.facebook.com/docs/instagram-api/getting-started
- Reference: https://developers.facebook.com/docs/instagram-api/reference/
- App Review: https://developers.facebook.com/docs/app-review
