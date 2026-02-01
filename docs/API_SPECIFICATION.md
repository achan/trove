# Trove Public API Specification

## Overview
The Trove Public API provides authenticated access to archived social media content for display on personal pages and applications.

**Base URL**: `https://{project-id}.supabase.co/functions/v1`

**Version**: v1

**Authentication**: API Key or JWT Token

---

## Authentication

### API Key Authentication
```http
GET /api/posts
Authorization: Bearer {api_key}
```

### User JWT Authentication
```http
GET /api/posts
Authorization: Bearer {jwt_token}
```

### API Key Management
Users can generate API keys via dashboard:
- Multiple keys per user
- Scoped permissions (read-only for public API)
- Revocable
- Rate limited per key

---

## Common Headers

### Request Headers
```
Authorization: Bearer {token}
Content-Type: application/json
Accept: application/json
```

### Response Headers
```
Content-Type: application/json
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1640000000
```

---

## Endpoints

### 1. List Posts

Get a paginated list of posts with optional filtering.

#### Request
```http
GET /api/posts
```

#### Query Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `platforms` | string[] | No | all | Comma-separated platform filter: `bluesky,strava,instagram` |
| `content_types` | string[] | No | all | Filter by content type: `post,activity,reel` |
| `start_date` | ISO8601 | No | - | Filter posts after this date |
| `end_date` | ISO8601 | No | - | Filter posts before this date |
| `limit` | integer | No | 20 | Number of results (max 100) |
| `offset` | integer | No | 0 | Pagination offset |
| `include_media` | boolean | No | true | Include media assets in response |
| `include_engagement` | boolean | No | false | Include engagement stats (from ingested_posts) |
| `sort` | string | No | `desc` | Sort order: `asc` or `desc` |
| `search` | string | No | - | Full-text search in content |

#### Example Request
```http
GET /api/posts?platforms=bluesky,strava&limit=10&include_media=true&start_date=2024-01-01
Authorization: Bearer {token}
```

#### Response
```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "platform": "bluesky",
      "content_type": "post",
      "text_content": "Just finished a great morning run!",
      "created_at": "2024-01-15T08:30:00Z",
      "updated_at": "2024-01-15T08:30:00Z",
      "published": true,
      "engagement": {
        "likes": 42,
        "comments": 5,
        "shares": 2
      },
      "media": [
        {
          "id": "660e8400-e29b-41d4-a716-446655440001",
          "type": "image",
          "url": "https://{project}.supabase.co/storage/v1/object/sign/media/{path}?token=...",
          "thumbnail_url": "https://{project}.supabase.co/storage/v1/object/sign/media/{path}?token=...",
          "width": 1200,
          "height": 800,
          "alt_text": "Sunrise over the city",
          "position": 0
        }
      ],
      "metadata": {
        "author_handle": "@username",
        "permalink": "https://bsky.app/profile/..."
      }
      // Note: engagement and metadata sourced from ingested_posts.post_data via JOIN
    }
  ],
  "pagination": {
    "total": 150,
    "limit": 10,
    "offset": 0,
    "has_more": true
  }
}
```

#### Response Codes
- `200 OK` - Success
- `400 Bad Request` - Invalid parameters
- `401 Unauthorized` - Invalid or missing auth token
- `429 Too Many Requests` - Rate limit exceeded
- `500 Internal Server Error` - Server error

---

### 2. Get Single Post

Retrieve detailed information about a specific post.

#### Request
```http
GET /api/posts/{post_id}
```

#### Path Parameters
- `post_id` (UUID, required) - The post identifier

#### Query Parameters
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `include_media` | boolean | No | true | Include media assets |
| `include_engagement` | boolean | No | true | Include engagement stats |

#### Example Request
```http
GET /api/posts/550e8400-e29b-41d4-a716-446655440000?include_media=true
Authorization: Bearer {token}
```

#### Response
```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "platform": "strava",
    "content_type": "activity",
    "text_content": "Morning Run",
    "created_at": "2024-01-15T06:00:00Z",
    "updated_at": "2024-01-15T10:30:00Z",
    "published": true,
    "engagement": {
      "kudos": 28,
      "comments": 3
    },
    "media": [
      {
        "id": "770e8400-e29b-41d4-a716-446655440002",
        "type": "map_image",
        "url": "https://{project}.supabase.co/storage/v1/object/sign/media/{path}?token=...",
        "width": 600,
        "height": 400
      }
    ],
    "metadata": {
      "activity_type": "Run",
      "sport_type": "running",
      "distance": 5000,
      "duration": 1800,
      "elevation": 50,
      "stats": {
        "average_speed": 2.78,
        "max_speed": 3.5,
        "average_heartrate": 145
      }
    }
  }
}
```

#### Response Codes
- `200 OK` - Success
- `401 Unauthorized` - Invalid auth
- `404 Not Found` - Post not found or not accessible
- `500 Internal Server Error` - Server error

---

### 3. Get Media Asset

Retrieve or proxy a media file.

#### Request
```http
GET /api/media/{media_id}
```

#### Path Parameters
- `media_id` (UUID, required) - The media asset identifier

#### Query Parameters
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `size` | string | No | `original` | Size variant: `thumbnail`, `medium`, `original` |
| `download` | boolean | No | false | Force download with Content-Disposition header |

#### Example Request
```http
GET /api/media/660e8400-e29b-41d4-a716-446655440001?size=medium
Authorization: Bearer {token}
```

#### Response
- Binary file content OR
- Redirect (302) to signed Supabase Storage URL

#### Response Headers
```
Content-Type: image/jpeg
Content-Length: 245678
Cache-Control: public, max-age=31536000
ETag: "abc123def456"
```

#### Response Codes
- `200 OK` - File content returned
- `302 Found` - Redirect to storage URL
- `401 Unauthorized` - Invalid auth
- `404 Not Found` - Media not found or download failed
- `500 Internal Server Error` - Server error

---

### 4. Get Platform Stats

Get aggregated statistics for connected platforms.

#### Request
```http
GET /api/stats
```

#### Query Parameters
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `platforms` | string[] | No | all | Filter by platforms |
| `start_date` | ISO8601 | No | - | Stats from this date |
| `end_date` | ISO8601 | No | - | Stats until this date |

#### Example Request
```http
GET /api/stats?platforms=bluesky,strava&start_date=2024-01-01
Authorization: Bearer {token}
```

#### Response
```json
{
  "data": {
    "total_posts": 450,
    "total_media": 1250,
    "platforms": {
      "bluesky": {
        "posts": 200,
        "media": 350,
        "content_types": {
          "post": 180,
          "reply": 20
        },
        "total_engagement": {
          "likes": 5000,
          "reposts": 250,
          "replies": 180
        }
      },
      "strava": {
        "posts": 150,
        "media": 600,
        "content_types": {
          "activity": 150
        },
        "total_engagement": {
          "kudos": 4200,
          "comments": 120
        },
        "stats": {
          "total_distance": 750000,
          "total_duration": 180000,
          "total_elevation": 15000
        }
      },
      "instagram": {
        "posts": 100,
        "media": 300,
        "content_types": {
          "post": 80,
          "reel": 20
        },
        "total_engagement": {
          "likes": 12000,
          "comments": 450
        }
      }
    },
    "date_range": {
      "start": "2024-01-01T00:00:00Z",
      "end": "2024-12-31T23:59:59Z"
    }
  }
}
```

#### Response Codes
- `200 OK` - Success
- `401 Unauthorized` - Invalid auth
- `500 Internal Server Error` - Server error

---

### 5. Search Posts

Full-text search across all posts.

#### Request
```http
GET /api/search
```

#### Query Parameters
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `q` | string | Yes | - | Search query |
| `platforms` | string[] | No | all | Filter by platforms |
| `content_types` | string[] | No | all | Filter by content types |
| `limit` | integer | No | 20 | Results per page (max 100) |
| `offset` | integer | No | 0 | Pagination offset |

#### Example Request
```http
GET /api/search?q=morning+run&platforms=strava&limit=10
Authorization: Bearer {token}
```

#### Response
```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "platform": "strava",
      "content_type": "activity",
      "text_content": "Morning Run through Central Park",
      "created_at": "2024-01-15T06:00:00Z",
      "relevance_score": 0.95,
      "highlight": "...Great <mark>morning run</mark> through...",
      "media_count": 2
    }
  ],
  "pagination": {
    "total": 25,
    "limit": 10,
    "offset": 0,
    "has_more": true
  },
  "search": {
    "query": "morning run",
    "took_ms": 45
  }
}
```

#### Response Codes
- `200 OK` - Success
- `400 Bad Request` - Missing or invalid query
- `401 Unauthorized` - Invalid auth
- `500 Internal Server Error` - Server error

---

### 6. Get Timeline

Get a unified chronological timeline across all platforms.

#### Request
```http
GET /api/timeline
```

#### Query Parameters
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `cursor` | string | No | - | Pagination cursor (opaque string) |
| `limit` | integer | No | 20 | Results per page (max 100) |
| `platforms` | string[] | No | all | Filter by platforms |

#### Example Request
```http
GET /api/timeline?limit=20
Authorization: Bearer {token}
```

#### Response
```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "platform": "bluesky",
      "content_type": "post",
      "text_content": "Beautiful sunset today",
      "created_at": "2024-01-15T18:30:00Z",
      "media": [...],
      "engagement": {...}
    },
    {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "platform": "strava",
      "content_type": "activity",
      "text_content": "Evening Ride",
      "created_at": "2024-01-15T17:00:00Z",
      "media": [...],
      "engagement": {...}
    }
  ],
  "pagination": {
    "next_cursor": "eyJjcmVhdGVkX2F0IjoiMjAyNC0wMS0xNVQxNjowMDowMFoiLCJpZCI6Ijc3MGU4NDAwLWUyOWItNDFkNC1hNzE2LTQ0NjY1NTQ0MDAwMyJ9",
    "has_more": true
  }
}
```

#### Cursor-Based Pagination
Cursors are opaque strings. To get next page:
```http
GET /api/timeline?cursor={next_cursor}
```

#### Response Codes
- `200 OK` - Success
- `400 Bad Request` - Invalid cursor
- `401 Unauthorized` - Invalid auth
- `500 Internal Server Error` - Server error

---

## Error Responses

### Error Format
```json
{
  "error": {
    "code": "invalid_request",
    "message": "The 'platforms' parameter contains invalid values",
    "details": {
      "invalid_platforms": ["fakebook"]
    }
  }
}
```

### Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `invalid_request` | 400 | Malformed request or invalid parameters |
| `unauthorized` | 401 | Missing or invalid authentication |
| `forbidden` | 403 | Authenticated but lacks permissions |
| `not_found` | 404 | Resource not found |
| `rate_limit_exceeded` | 429 | Too many requests |
| `internal_error` | 500 | Server error |
| `service_unavailable` | 503 | Temporary service outage |

---

## Rate Limiting

### Limits
- **Authenticated Users**: 100 requests per minute
- **API Keys**: 200 requests per minute
- **Burst**: 20 requests per second

### Headers
Every response includes rate limit headers:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1640000000
```

### Rate Limit Response
```http
HTTP/1.1 429 Too Many Requests
Retry-After: 30

{
  "error": {
    "code": "rate_limit_exceeded",
    "message": "Rate limit exceeded. Please retry after 30 seconds.",
    "details": {
      "limit": 100,
      "reset_at": "2024-01-15T12:35:00Z"
    }
  }
}
```

---

## Caching

### ETags
Responses include ETags for efficient caching:
```http
GET /api/posts/550e8400-e29b-41d4-a716-446655440000
```

Response:
```http
HTTP/1.1 200 OK
ETag: "33a64df551425fcc55e4d42a148795d9f25f89d4"
Cache-Control: private, max-age=300
```

Conditional request:
```http
GET /api/posts/550e8400-e29b-41d4-a716-446655440000
If-None-Match: "33a64df551425fcc55e4d42a148795d9f25f89d4"
```

Response if unchanged:
```http
HTTP/1.1 304 Not Modified
```

### Cache-Control
- Posts list: `private, max-age=300` (5 minutes)
- Single post: `private, max-age=600` (10 minutes)
- Media files: `public, max-age=31536000` (1 year, immutable)
- Stats: `private, max-age=3600` (1 hour)

---

## Pagination

### Offset-Based Pagination
Used for most list endpoints:

```http
GET /api/posts?limit=20&offset=0   # Page 1
GET /api/posts?limit=20&offset=20  # Page 2
GET /api/posts?limit=20&offset=40  # Page 3
```

Response includes pagination metadata:
```json
{
  "data": [...],
  "pagination": {
    "total": 150,
    "limit": 20,
    "offset": 0,
    "has_more": true
  }
}
```

### Cursor-Based Pagination
Used for timeline endpoint (better for real-time feeds):

```http
GET /api/timeline?limit=20
```

Response includes opaque cursor:
```json
{
  "data": [...],
  "pagination": {
    "next_cursor": "eyJ...",
    "has_more": true
  }
}
```

Next page:
```http
GET /api/timeline?cursor=eyJ...&limit=20
```

---

## Filtering & Sorting

### Platform Filter
```http
GET /api/posts?platforms=bluesky,strava
```

### Date Range Filter
```http
GET /api/posts?start_date=2024-01-01&end_date=2024-12-31
```

### Content Type Filter
```http
GET /api/posts?content_types=post,activity
```

### Sorting
```http
GET /api/posts?sort=asc   # Oldest first
GET /api/posts?sort=desc  # Newest first (default)
```

### Combining Filters
```http
GET /api/posts?platforms=strava&content_types=activity&start_date=2024-06-01&sort=desc&limit=50
```

---

## Media URLs

### Signed URLs
Media URLs are temporary signed URLs from Supabase Storage:
- Valid for 1 hour
- Include authentication token in URL
- No additional auth header needed

### URL Format
```
https://{project}.supabase.co/storage/v1/object/sign/media/{user_id}/{platform}/{post_id}/{filename}?token={signature}
```

### Size Variants (Future)
```http
GET /api/media/{id}?size=thumbnail  # 200x200
GET /api/media/{id}?size=medium     # 800x800
GET /api/media/{id}?size=original   # Original size
```

---

## Webhooks (Future Feature)

### Webhook Events
Subscribe to events in your Trove archive:

- `post.created` - New post synced
- `post.updated` - Post updated (engagement, edits)
- `post.deleted` - Post deleted on platform
- `media.downloaded` - Media successfully downloaded
- `account.connected` - New account connected
- `account.disconnected` - Account disconnected
- `sync.completed` - Sync job completed

### Webhook Payload Example
```json
{
  "event": "post.created",
  "timestamp": "2024-01-15T12:00:00Z",
  "data": {
    "post_id": "550e8400-e29b-41d4-a716-446655440000",
    "platform": "bluesky",
    "content_type": "post",
    "created_at": "2024-01-15T11:30:00Z"
  }
}
```

---

## SDK Examples

### JavaScript/TypeScript
```typescript
import { TroveClient } from '@trove/sdk';

const client = new TroveClient({
  apiKey: process.env.TROVE_API_KEY
});

// Get posts
const posts = await client.posts.list({
  platforms: ['bluesky', 'strava'],
  limit: 20,
  includeMedia: true
});

// Get single post
const post = await client.posts.get('550e8400-e29b-41d4-a716-446655440000');

// Search
const results = await client.search('morning run', {
  platforms: ['strava']
});

// Get timeline
const timeline = await client.timeline.list({ limit: 20 });
```

### Python
```python
from trove import TroveClient

client = TroveClient(api_key=os.getenv('TROVE_API_KEY'))

# Get posts
posts = client.posts.list(
    platforms=['bluesky', 'strava'],
    limit=20,
    include_media=True
)

# Get single post
post = client.posts.get('550e8400-e29b-41d4-a716-446655440000')

# Search
results = client.search('morning run', platforms=['strava'])
```

### cURL
```bash
# List posts
curl -X GET "https://{project}.supabase.co/functions/v1/api/posts?platforms=bluesky&limit=10" \
  -H "Authorization: Bearer {api_key}"

# Get post
curl -X GET "https://{project}.supabase.co/functions/v1/api/posts/{id}" \
  -H "Authorization: Bearer {api_key}"

# Search
curl -X GET "https://{project}.supabase.co/functions/v1/api/search?q=running&platforms=strava" \
  -H "Authorization: Bearer {api_key}"
```

---

## Best Practices

### 1. Use Appropriate Pagination
- **Large datasets**: Cursor-based pagination (timeline)
- **Random access needed**: Offset-based pagination
- **Never** fetch all data at once

### 2. Implement Caching
- Respect `Cache-Control` headers
- Use ETags for conditional requests
- Cache media URLs (but regenerate when expired)

### 3. Handle Rate Limits
- Monitor `X-RateLimit-*` headers
- Implement exponential backoff
- Queue requests if approaching limits

### 4. Error Handling
```typescript
try {
  const posts = await client.posts.list();
} catch (error) {
  if (error.code === 'rate_limit_exceeded') {
    // Wait and retry
    await sleep(error.retryAfter * 1000);
    return retry();
  }
  // Handle other errors
}
```

### 5. Media Optimization
- Request appropriate size variants
- Lazy load images
- Use responsive images
- Cache aggressively (immutable URLs)

### 6. Security
- Never expose API keys in client-side code
- Use environment variables
- Rotate keys periodically
- Monitor for unauthorized usage

---

## Versioning

### API Version Header
```http
GET /api/posts
API-Version: 2024-01-15
```

### Version Support
- Current: v1 (default)
- Deprecated versions supported for 12 months
- Breaking changes require new version
- Backward-compatible changes don't

### Deprecation Notice
Deprecated endpoints return header:
```http
Deprecation: true
Sunset: Wed, 15 Jan 2025 23:59:59 GMT
Link: <https://docs.trove.dev/api/migration>; rel="sunset"
```

---

## Support & Resources

- **Documentation**: https://docs.trove.dev
- **API Status**: https://status.trove.dev
- **Changelog**: https://docs.trove.dev/changelog
- **Support**: support@trove.dev
