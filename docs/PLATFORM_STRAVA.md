# Strava API v3 Integration

## Authentication

### OAuth 2.0
- **Required**: All API access requires athlete authorization via OAuth 2.0
- **Token Expiration**: Access tokens expire every 6 hours
- **Refresh Required**: Must implement token refresh flow
- **Scopes**:
  - `activity:read` - Read activities with Followers/Everyone visibility
  - `activity:read_all` - Read all activities including "Only You"
  - `profile:read_all` - Read profile information

### Authorization Flow
1. Redirect athlete to Strava authorization page
2. Athlete grants permissions
3. Receive authorization code
4. Exchange code for access_token + refresh_token
5. Refresh access_token every 6 hours using refresh_token

## Webhooks

### Subscription Model
- **Limit**: ONE webhook subscription per application
- **Covers**: All athletes who have authorized the application
- **Endpoint**: `https://www.strava.com/api/v3/push_subscriptions`

### Events Supported
- **Activity Created**: New activity uploaded
- **Activity Updated**: Activity fields modified
  - Possible updates: `title`, `type`, `private` (visibility)
- **Activity Deleted**: Activity removed
- **Athlete Revoked**: Athlete deauthorized the application

### Webhook Payload
```json
{
  "object_type": "activity",
  "object_id": 123456789,
  "aspect_type": "create|update|delete",
  "updates": {
    "title": true,
    "type": true,
    "private": true
  },
  "owner_id": 987654,
  "subscription_id": 12345,
  "event_time": 1234567890
}
```

### Important Notes
- Webhook does NOT contain activity data
- Only contains `object_id` and `owner_id`
- Must make API call to fetch actual activity data
- Must store athlete tokens to retrieve activity details
- Requires webhook verification on subscription setup

### Visibility Behavior
- `activity:read` scope: Delete event sent if activity changed to "Only You"
- `activity:read_all` scope: Receive all activities regardless of visibility

## API Endpoints

### Activities
- `GET /athlete/activities` - List authenticated athlete's activities
- `GET /activities/:id` - Get detailed activity by ID
- Supports pagination via `page` and `per_page` parameters

### Activity Data Structure
- ID (unique identifier)
- Name/Title
- Type (Run, Ride, Swim, etc.)
- Sport type (more granular)
- Start date
- Distance, moving time, elapsed time
- Total elevation gain
- Location data (start lat/lng, map polyline)
- Photos
- Stats: average speed, max speed, heart rate, power, calories

## Media

### Photos
- Activities can have multiple photos
- Photo objects include:
  - URLs (various sizes)
  - Captions
  - Upload timestamp
- Accessible via activity detail endpoint

### Maps
- Polyline data (encoded)
- Summary polyline for overview
- Can generate static map images
- Not always available (privacy settings)

## Rate Limits

### Standard Limits
- 100 requests every 15 minutes
- 1,000 requests per day
- Rate limit headers provided in responses

### Webhook Considerations
- Webhooks don't count against rate limits
- But fetching activity data after webhook does
- Strategy: Queue webhook events, batch process

## Implementation Strategy

### Initial Setup
1. Register application with Strava
2. Obtain client_id and client_secret
3. Create webhook subscription
4. Implement webhook verification endpoint
5. Implement OAuth flow

### Webhook Flow
1. Receive webhook event
2. Validate event signature
3. Store event in queue
4. Retrieve athlete's tokens from database
5. Refresh access token if expired
6. Fetch activity data via API
7. Download photos
8. Store in Trove database

### Polling Fallback
- For athletes who connected before webhooks
- For backfilling historical data
- Use `GET /athlete/activities` with pagination

## Token Management

### Storage Requirements
- `access_token` (expires 6 hours)
- `refresh_token` (long-lived)
- `expires_at` timestamp
- `scope` granted

### Refresh Flow
```
POST https://www.strava.com/oauth/token
{
  "client_id": "...",
  "client_secret": "...",
  "refresh_token": "...",
  "grant_type": "refresh_token"
}
```

## Data Schema Mapping

```
Strava Activity → Trove Schema
- id → platform_post_id
- name → text_content
- type, sport_type → metadata.activity_type
- start_date → created_at_platform
- distance, moving_time, elevation → metadata.stats
- kudos_count, comment_count → engagement_stats
- photos[] → media_assets
- map.summary_polyline → metadata.map_data
```

## Special Considerations

### Privacy
- Respect athlete visibility settings
- "Only You" activities require special scope
- Some athletes hide map data

### Activity Types
- 50+ activity types supported
- Handle various sports differently
- Some have unique data (cycling power, running pace)

### Deduplication
- Activity IDs are permanent
- Handle updates via webhook
- Track last_updated timestamp

## Resources
- API Documentation: https://developers.strava.com/docs/
- Webhooks Guide: https://developers.strava.com/docs/webhooks/
- API Reference: https://developers.strava.com/docs/reference/
