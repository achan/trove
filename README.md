# Trove

> A unified social media archive system that downloads and stores your content from multiple platforms, providing an API for displaying on your personal page.

## Overview

Trove automatically syncs your social media posts, activities, and media from platforms like Bluesky, Strava, and Instagram into a personal archive. It provides a secure API to access your archived content for display on your personal website or other applications.

### Key Features

- **Multi-Platform Support**: Bluesky, Strava, Instagram (with more platforms planned)
- **Automatic Sync**: Hybrid approach using webhooks (real-time) and polling (fallback)
- **Media Archival**: Downloads and stores all images, videos, and other media
- **RESTful API**: Clean, well-documented API for accessing your archived content
- **Privacy-First**: You own your data, fully GDPR/CCPA compliant
- **Supabase-Powered**: Built on Supabase (PostgreSQL + Edge Functions + Storage)

## Architecture

### Tech Stack

- **Backend**: Supabase
  - PostgreSQL Database
  - Edge Functions (Deno)
  - Storage (S3-compatible)
  - Authentication
- **Platforms**: Bluesky (AT Protocol), Strava API v3, Instagram Graph API
- **Sync Strategy**: Webhooks + scheduled polling
- **Security**: RLS, token encryption, HTTPS-only

### System Components

```
┌─────────────┐
│   User      │
└─────┬───────┘
      │
      ▼
┌─────────────────────────────────────┐
│   Trove API (Edge Functions)         │
│  - Authentication                    │
│  - Public API Endpoints              │
│  - Webhook Receivers                 │
└──────────┬──────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│   PostgreSQL Database                 │
│  - Users & Connected Accounts         │
│  - Posts & Media Assets               │
│  - Sync Logs & Audit Trails          │
└──────────┬───────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│   Supabase Storage                    │
│  - Images, Videos, Documents          │
│  - Organized by user/platform         │
└───────────────────────────────────────┘

           │
           ▼
┌──────────────────────────────────────┐
│   External Platforms                  │
│  - Bluesky (AT Protocol)             │
│  - Strava API                        │
│  - Instagram Graph API               │
└───────────────────────────────────────┘
```

## Documentation

### Getting Started
- [**PLAN.md**](PLAN.md) - High-level project plan and implementation roadmap
- [**SETUP.md**](SETUP.md) - Setup guide for local development

### Technical Documentation
- [**docs/ARCHITECTURE.md**](docs/ARCHITECTURE.md) - System architecture and design decisions
- [**docs/schema.mmd**](docs/schema.mmd) - Visual database schema diagram (Mermaid)
- [**docs/DATABASE_SCHEMA.md**](docs/DATABASE_SCHEMA.md) - Complete database schema with tables, relationships, indexes, and RLS policies
- [**docs/DATA_FLOWS.md**](docs/DATA_FLOWS.md) - Detailed data flow diagrams for all system processes
- [**docs/API_SPECIFICATION.md**](docs/API_SPECIFICATION.md) - Full REST API documentation with examples
- [**docs/SECURITY_PRIVACY.md**](docs/SECURITY_PRIVACY.md) - Security architecture and privacy compliance

### Platform Integration Guides
- [**docs/PLATFORM_BLUESKY.md**](docs/PLATFORM_BLUESKY.md) - Bluesky/AT Protocol integration details
- [**docs/PLATFORM_STRAVA.md**](docs/PLATFORM_STRAVA.md) - Strava API v3 integration details
- [**docs/PLATFORM_INSTAGRAM.md**](docs/PLATFORM_INSTAGRAM.md) - Instagram Graph API integration details

## Project Status

**Current Phase**: Planning & Architecture ✅

- [x] Research platform APIs and capabilities
- [x] Design database schema
- [x] Document data flows
- [x] Plan security architecture
- [x] Specify public API
- [ ] Set up Supabase project
- [ ] Implement database migrations
- [ ] Build OAuth flows
- [ ] Implement sync functions
- [ ] Create public API endpoints
- [ ] Test with real data

## Quick Start (Coming Soon)

### Prerequisites
- Supabase account
- Platform developer accounts:
  - Bluesky (OAuth credentials)
  - Strava API application
  - Instagram/Facebook app (for Business/Creator accounts)

### Installation
```bash
# Clone repository
git clone https://github.com/yourusername/trove.git
cd trove

# Install dependencies
npm install

# Set up environment variables
cp .env.example .env
# Edit .env with your credentials

# Run database migrations
npm run migrate

# Deploy Edge Functions
npm run deploy

# Start development server
npm run dev
```

### Configuration
```bash
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_KEY=your-service-key

# Bluesky
BLUESKY_CLIENT_ID=https://your-domain.com/client-metadata.json

# Strava
STRAVA_CLIENT_ID=your-client-id
STRAVA_CLIENT_SECRET=your-client-secret

# Instagram
INSTAGRAM_APP_ID=your-app-id
INSTAGRAM_APP_SECRET=your-app-secret
```

## Usage Examples

### Connect a Platform
```typescript
// User clicks "Connect Bluesky"
// Redirected to OAuth flow
// Returns with connected account
```

### Access Your Archive
```bash
# Get recent posts
curl https://your-project.supabase.co/functions/v1/api/posts \
  -H "Authorization: Bearer YOUR_API_KEY"

# Search your content
curl "https://your-project.supabase.co/functions/v1/api/search?q=morning+run" \
  -H "Authorization: Bearer YOUR_API_KEY"

# Get unified timeline
curl https://your-project.supabase.co/functions/v1/api/timeline \
  -H "Authorization: Bearer YOUR_API_KEY"
```

### Display on Your Website
```typescript
import { TroveClient } from '@trove/sdk';

const client = new TroveClient({
  apiKey: process.env.TROVE_API_KEY
});

// Get latest posts for homepage
const posts = await client.posts.list({
  limit: 10,
  includeMedia: true
});

// Render posts
posts.data.forEach(post => {
  console.log(`${post.platform}: ${post.text_content}`);
  post.media.forEach(media => {
    console.log(`  - ${media.type}: ${media.url}`);
  });
});
```

## Database Schema Highlights

### Core Tables
- **users** - Trove user accounts
- **connected_accounts** - OAuth connections to social platforms
- **posts** - Archived social media posts/activities
- **media_assets** - Downloaded images, videos, etc.
- **sync_logs** - Synchronization history and debugging

### Key Features
- **Row Level Security (RLS)** - Multi-tenant data isolation
- **Full-text search** - Search across all your content
- **Engagement tracking** - Historical stats from platforms
- **Soft deletes** - 30-day recovery period

See [DATABASE_SCHEMA.md](docs/DATABASE_SCHEMA.md) for complete details.

## API Endpoints

### Public API
- `GET /api/posts` - List posts with filtering/pagination
- `GET /api/posts/:id` - Get single post details
- `GET /api/media/:id` - Access media files
- `GET /api/timeline` - Unified chronological timeline
- `GET /api/search` - Full-text search
- `GET /api/stats` - Aggregated statistics

### Internal Endpoints (Edge Functions)
- OAuth flows: `/oauth-{platform}/start`, `/oauth-{platform}/callback`
- Webhooks: `/webhook-{platform}`
- Sync jobs: `/sync-account`, `/sync-all-accounts`
- Media processing: `/download-media`

See [API_SPECIFICATION.md](docs/API_SPECIFICATION.md) for complete details.

## Security

### Key Security Features
- **Authentication**: Supabase Auth + API Keys
- **Authorization**: Row Level Security (RLS) on all tables
- **Encryption**: Tokens encrypted at rest, TLS in transit
- **Rate Limiting**: Per-user and per-API-key limits
- **Audit Logging**: All access logged for security
- **GDPR/CCPA Compliant**: Full user data control

See [SECURITY_PRIVACY.md](docs/SECURITY_PRIVACY.md) for complete details.

## Platform Support

### Currently Planned

#### Bluesky
- ✅ OAuth 2.0 authentication
- ✅ Real-time firehose for instant sync
- ✅ Post content, images, videos
- ✅ Engagement stats (likes, reposts, replies)

#### Strava
- ✅ OAuth 2.0 authentication
- ✅ Webhook support for real-time activity sync
- ✅ Activities (runs, rides, swims, etc.)
- ✅ Photos, maps, stats
- ✅ Engagement (kudos, comments)

#### Instagram
- ✅ OAuth 2.0 via Facebook Login
- ✅ Business/Creator accounts only
- ✅ Posts, Reels, Stories (while available)
- ✅ Images, videos, carousels
- ⚠️ Polling required (no real-time webhooks)

### Future Platforms
- Twitter/X
- YouTube
- TikTok
- LinkedIn
- Mastodon
- GitHub (activity feed)

## Data Flows

### Sync Process
1. **OAuth Connection**: User authorizes platform access
2. **Initial Backfill**: Download all historical content
3. **Real-time Sync**: Webhooks notify of new content (where available)
4. **Scheduled Polling**: Periodic checks for platforms without webhooks
5. **Media Download**: Queue and download all media assets
6. **Data Storage**: Store in PostgreSQL + Supabase Storage

### Data Retention
- **User data**: Until account deletion
- **Posts & media**: Until deletion or account removal
- **Sync logs**: 90 days
- **Audit logs**: 1 year
- **Deleted data**: 30-day soft delete period

See [DATA_FLOWS.md](docs/DATA_FLOWS.md) for detailed flow diagrams.

## Development Roadmap

### Phase 1: Foundation ✅
- [x] Project planning
- [x] Architecture design
- [x] Database schema
- [x] API specification
- [x] Security planning

### Phase 2: Core Infrastructure (Next)
- [ ] Supabase project setup
- [ ] Database migrations
- [ ] RLS policies implementation
- [ ] Storage buckets configuration
- [ ] Environment setup

### Phase 3: Authentication
- [ ] Supabase Auth integration
- [ ] OAuth flow implementations
- [ ] Token management
- [ ] API key system

### Phase 4: Bluesky Integration
- [ ] OAuth client
- [ ] Polling sync
- [ ] Firehose integration (optional)
- [ ] Media download

### Phase 5: Strava Integration
- [ ] OAuth client
- [ ] Webhook subscription
- [ ] Activity sync
- [ ] Photo/map download

### Phase 6: Instagram Integration
- [ ] Facebook Login OAuth
- [ ] Polling sync
- [ ] Media download
- [ ] Carousel handling

### Phase 7: Public API
- [ ] API endpoint implementations
- [ ] Rate limiting
- [ ] Caching layer
- [ ] Documentation site

### Phase 8: Polish & Launch
- [ ] Error handling & monitoring
- [ ] Performance optimization
- [ ] Security audit
- [ ] Documentation completion
- [ ] Beta testing
- [ ] Public launch

## Contributing

(Coming soon - contribution guidelines will be added once core functionality is implemented)

## License

(To be determined)

## Support

- **Documentation**: See [docs/](docs/) folder
- **Issues**: GitHub Issues (coming soon)
- **Discussions**: GitHub Discussions (coming soon)

## Acknowledgments

Built with:
- [Supabase](https://supabase.com/) - Backend infrastructure
- [AT Protocol](https://atproto.com/) - Bluesky integration
- [Strava API](https://developers.strava.com/) - Activity data
- [Instagram Graph API](https://developers.facebook.com/docs/instagram-api/) - Social media content

---

**Status**: Planning & Architecture Phase
**Last Updated**: 2024-01-24
**Version**: 0.1.0 (Pre-release)
