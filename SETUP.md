# Trove Setup Guide

## Prerequisites

- Node.js 18+ installed
- Supabase account
- Git installed

## 1. Clone and Install

```bash
git clone https://github.com/yourusername/trove.git
cd trove
npm install
```

## 2. Supabase Project Setup

1. Go to https://supabase.com and create a new project
2. Note your project credentials from **Project Settings → API**:
   - Project URL
   - anon/public key
   - service_role key

## 3. Environment Configuration

1. Copy the example environment file:
```bash
cp .env.example .env
```

2. Edit `.env` and fill in your Supabase credentials:
```bash
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_KEY=your-service-role-key
```

3. Generate an encryption key (32 characters):
```bash
openssl rand -hex 16
```
Add it to `.env`:
```bash
ENCRYPTION_KEY=your-generated-key-here
```

## 4. Database Setup

Run migrations to create the database schema:
```bash
npm run migrate
```

## 5. Storage Configuration

Configure Supabase Storage buckets:
```bash
npm run setup:storage
```

## 6. Platform API Credentials

### Bluesky
1. Set up OAuth client metadata at your domain
2. Add to `.env`:
```bash
BLUESKY_CLIENT_ID=https://your-domain.com/client-metadata.json
```

### Strava
1. Create app at https://www.strava.com/settings/api
2. Add to `.env`:
```bash
STRAVA_CLIENT_ID=your-client-id
STRAVA_CLIENT_SECRET=your-client-secret
STRAVA_WEBHOOK_VERIFY_TOKEN=$(openssl rand -hex 16)
```

### Instagram
1. Create Facebook app at https://developers.facebook.com
2. Add Instagram Basic Display product
3. Add to `.env`:
```bash
INSTAGRAM_APP_ID=your-app-id
INSTAGRAM_APP_SECRET=your-app-secret
```

## 7. Deploy Edge Functions

```bash
npm run deploy
```

## 8. Verify Setup

Run the verification script:
```bash
npm run verify
```

## Development

Start local development:
```bash
npm run dev
```

## Troubleshooting

### Database Connection Issues
- Verify your `SUPABASE_URL` and keys are correct
- Check that your IP is allowed in Supabase project settings

### Migration Failures
- Ensure you're using the service_role key for migrations
- Check migration logs in `supabase/migrations/`

### Storage Bucket Errors
- Verify bucket policies are set correctly
- Check RLS policies allow your user access

## Next Steps

1. Test OAuth flows with each platform
2. Run initial sync to backfill data
3. Access your data via the public API

See [README.md](README.md) for usage examples and API documentation.
