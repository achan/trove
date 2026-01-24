# Trove Security & Privacy Architecture

## Overview
This document outlines the security and privacy architecture for Trove, covering authentication, authorization, data protection, compliance, and threat mitigation strategies.

---

## Security Principles

### 1. Defense in Depth
Multiple layers of security controls:
- Application-level authentication
- Database Row Level Security (RLS)
- Network security (HTTPS only)
- Token encryption
- Input validation
- Output encoding

### 2. Least Privilege
- Users access only their own data
- Service roles limited to necessary operations
- API keys scoped to specific permissions
- OAuth scopes minimal for platform needs

### 3. Zero Trust
- Verify every request
- No implicit trust based on network location
- Continuous authentication and authorization

### 4. Privacy by Design
- Minimal data collection
- User control over data
- Transparent data usage
- Secure deletion

---

## Authentication

### User Authentication (Supabase Auth)

#### Supported Methods
1. **Email/Password**
   - Bcrypt password hashing
   - Email verification required
   - Password reset flow

2. **OAuth Social Login**
   - Google, GitHub, etc.
   - Reduces password management risk
   - Faster onboarding

3. **Magic Links**
   - Passwordless authentication
   - Time-limited tokens
   - Email-based verification

#### JWT Token Structure
```json
{
  "sub": "550e8400-e29b-41d4-a716-446655440000",
  "email": "user@example.com",
  "role": "authenticated",
  "iat": 1640000000,
  "exp": 1640003600
}
```

#### Token Management
- **Access Token**: Short-lived (1 hour)
- **Refresh Token**: Long-lived (30 days), stored securely
- **Automatic Refresh**: SDK handles token refresh
- **Revocation**: Tokens can be revoked server-side

### API Key Authentication

#### API Key Structure
```
trove_live_1a2b3c4d5e6f7g8h9i0j
       ^      ^
       |      |
       |      Random 20-character alphanumeric
       |
       Environment (live/test)
```

#### API Key Security
- Stored hashed (SHA-256) in database
- Only first 8 chars + last 4 shown in UI
- Per-key permissions and rate limits
- Revocable by user
- Expiration dates (optional)

#### API Key Management
```sql
CREATE TABLE api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key_hash TEXT NOT NULL UNIQUE,
  key_prefix TEXT NOT NULL, -- First 8 chars for display
  name TEXT NOT NULL, -- User-friendly name
  scopes TEXT[] DEFAULT ARRAY['read'],
  rate_limit INTEGER DEFAULT 200, -- Per minute
  expires_at TIMESTAMPTZ,
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ
);
```

---

## Authorization

### Row Level Security (RLS)

#### Principle
Every database query automatically filtered by user_id:
```sql
-- User can only see their own posts
CREATE POLICY "Users can read own posts"
  ON posts FOR SELECT
  USING (auth.uid() = user_id);
```

#### RLS Policies

**users table**:
```sql
-- Read own record
USING (auth.uid() = id)

-- Update own record
USING (auth.uid() = id)
```

**connected_accounts table**:
```sql
-- Full CRUD on own accounts
USING (auth.uid() = user_id)
```

**posts table**:
```sql
-- Read own posts
USING (auth.uid() = user_id)

-- Service role can insert/update (sync jobs)
-- Users cannot directly modify
```

**media_assets table**:
```sql
-- Read own media
USING (auth.uid() = user_id)
```

#### Service Role Bypass
- Background jobs use service role
- Service role bypasses RLS
- Extra validation in application code
- Audit logging for service role operations

### Supabase Storage RLS

```sql
-- Users can only access their own media folder
CREATE POLICY "Users can access own media"
  ON storage.objects FOR ALL
  USING (
    bucket_id = 'media'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
```

#### Folder Structure
```
media/
  {user_id}/        ← RLS enforces this
    bluesky/
    strava/
    instagram/
```

---

## Data Protection

### Encryption at Rest

#### Database Encryption
- **Supabase**: AES-256 encryption for data at rest
- **Backups**: Encrypted with separate keys
- **Point-in-Time Recovery**: Encrypted

#### Storage Encryption
- **Supabase Storage**: Encrypted at rest
- **Files**: AES-256 encryption
- **Metadata**: Also encrypted

### Encryption in Transit

#### HTTPS Only
```typescript
// Enforce HTTPS in all API calls
if (request.protocol !== 'https') {
  return new Response('HTTPS Required', { status: 403 });
}
```

#### TLS Configuration
- Minimum TLS 1.2
- Strong cipher suites only
- HSTS headers enabled
- Certificate pinning (mobile apps)

### Application-Level Encryption

#### OAuth Token Encryption
Tokens encrypted before storage:

```typescript
import { createCipheriv, createDecipheriv, randomBytes } from 'crypto';

// Encryption
function encryptToken(token: string, key: Buffer): string {
  const iv = randomBytes(16);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([
    cipher.update(token, 'utf8'),
    cipher.final()
  ]);
  const authTag = cipher.getAuthTag();

  return JSON.stringify({
    iv: iv.toString('base64'),
    encrypted: encrypted.toString('base64'),
    authTag: authTag.toString('base64')
  });
}

// Decryption
function decryptToken(encryptedData: string, key: Buffer): string {
  const { iv, encrypted, authTag } = JSON.parse(encryptedData);
  const decipher = createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(iv, 'base64')
  );
  decipher.setAuthTag(Buffer.from(authTag, 'base64'));

  return decipher.update(Buffer.from(encrypted, 'base64'), undefined, 'utf8') +
         decipher.final('utf8');
}
```

#### Encryption Key Management
```typescript
// Stored in Supabase Vault (future) or environment variables
const ENCRYPTION_KEY = process.env.TOKEN_ENCRYPTION_KEY; // 32 bytes

// Key rotation strategy
const KEY_VERSION = '1';
const KEYS = {
  '1': process.env.TOKEN_ENCRYPTION_KEY_V1,
  '2': process.env.TOKEN_ENCRYPTION_KEY_V2  // For rotation
};
```

### Sensitive Data Handling

#### What Gets Encrypted
- OAuth access tokens
- OAuth refresh tokens
- API keys (hashed, not encrypted)
- User email (if needed for marketing)

#### What Doesn't Need Encryption
- Post content (already public on platforms)
- Engagement stats (public data)
- Media files (public content)
- Usernames (public identifiers)

---

## Input Validation & Sanitization

### API Input Validation

```typescript
// Zod schema for validation
import { z } from 'zod';

const GetPostsSchema = z.object({
  platforms: z.array(z.enum(['bluesky', 'strava', 'instagram'])).optional(),
  limit: z.number().int().min(1).max(100).default(20),
  offset: z.number().int().min(0).default(0),
  start_date: z.string().datetime().optional(),
  end_date: z.string().datetime().optional(),
  search: z.string().max(200).optional()
});

// Usage
try {
  const params = GetPostsSchema.parse(request.query);
  // Proceed with validated params
} catch (error) {
  return new Response(JSON.stringify({
    error: {
      code: 'invalid_request',
      message: 'Invalid parameters',
      details: error.errors
    }
  }), { status: 400 });
}
```

### SQL Injection Prevention

#### Parameterized Queries
```typescript
// GOOD: Parameterized
const posts = await supabase
  .from('posts')
  .select('*')
  .eq('user_id', userId)
  .eq('platform', platform);

// BAD: String concatenation (NEVER DO THIS)
const query = `SELECT * FROM posts WHERE user_id = '${userId}'`;
```

#### ORM Usage
- Supabase client handles parameterization
- No raw SQL in application code
- Migrations use parameterized queries

### XSS Prevention

#### Output Encoding
```typescript
// Sanitize HTML content before rendering
import DOMPurify from 'isomorphic-dompurify';

function sanitizeContent(content: string): string {
  return DOMPurify.sanitize(content, {
    ALLOWED_TAGS: ['p', 'br', 'a', 'strong', 'em'],
    ALLOWED_ATTR: ['href', 'target']
  });
}
```

#### Content Security Policy (CSP)
```typescript
// Set CSP headers
const cspHeader = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline'", // Minimize unsafe-inline
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: https://*.supabase.co",
  "media-src 'self' https://*.supabase.co",
  "connect-src 'self' https://*.supabase.co",
  "frame-ancestors 'none'"
].join('; ');

response.headers.set('Content-Security-Policy', cspHeader);
```

---

## Rate Limiting

### Implementation

```typescript
interface RateLimiter {
  checkLimit(key: string, limit: number, window: number): Promise<boolean>;
}

// Redis-based rate limiter
class RedisRateLimiter implements RateLimiter {
  async checkLimit(key: string, limit: number, window: number): Promise<boolean> {
    const current = await redis.incr(key);
    if (current === 1) {
      await redis.expire(key, window);
    }
    return current <= limit;
  }
}

// Usage in Edge Function
const limiter = new RedisRateLimiter();
const key = `ratelimit:${userId}:${endpoint}`;

if (!await limiter.checkLimit(key, 100, 60)) {
  return new Response(JSON.stringify({
    error: {
      code: 'rate_limit_exceeded',
      message: 'Too many requests'
    }
  }), {
    status: 429,
    headers: {
      'Retry-After': '60',
      'X-RateLimit-Limit': '100',
      'X-RateLimit-Remaining': '0',
      'X-RateLimit-Reset': String(Math.floor(Date.now() / 1000) + 60)
    }
  });
}
```

### Rate Limit Tiers

| User Type | Requests/Minute | Requests/Day |
|-----------|----------------|--------------|
| Unauthenticated | 10 | 100 |
| Authenticated User | 100 | 10,000 |
| API Key | 200 | 50,000 |
| Premium User | 500 | 100,000 |

### DDoS Protection
- Cloudflare/CDN layer protection
- Rate limiting at edge
- IP-based throttling
- Geographic restrictions (if needed)

---

## Webhook Security

### Webhook Signature Verification

#### Strava Example
```typescript
function verifyStravaWebhook(request: Request): boolean {
  // Verify token on subscription
  const mode = request.query.get('hub.mode');
  const token = request.query.get('hub.verify_token');
  const challenge = request.query.get('hub.challenge');

  if (mode === 'subscribe' && token === process.env.STRAVA_VERIFY_TOKEN) {
    return { 'hub.challenge': challenge };
  }

  return false;
}
```

#### Instagram/Facebook Example
```typescript
import crypto from 'crypto';

function verifyInstagramWebhook(request: Request): boolean {
  const signature = request.headers.get('X-Hub-Signature-256');
  const body = await request.text();

  const expectedSignature = 'sha256=' + crypto
    .createHmac('sha256', process.env.INSTAGRAM_APP_SECRET)
    .update(body)
    .digest('hex');

  return crypto.timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(expectedSignature)
  );
}
```

### Webhook Request Validation
1. Verify signature
2. Validate payload structure
3. Check timestamp (prevent replay)
4. Verify event type
5. Process asynchronously

---

## Secrets Management

### Environment Variables

```bash
# Supabase
SUPABASE_URL=https://{project}.supabase.co
SUPABASE_ANON_KEY=eyJ... # Public, rate-limited
SUPABASE_SERVICE_KEY=eyJ... # Secret, full access

# Encryption
TOKEN_ENCRYPTION_KEY=32_byte_random_key_here

# Platform OAuth
BLUESKY_CLIENT_ID=https://trove.example.com/client-metadata.json
BLUESKY_CLIENT_SECRET=secret_here

STRAVA_CLIENT_ID=12345
STRAVA_CLIENT_SECRET=secret_here
STRAVA_VERIFY_TOKEN=random_token_here

INSTAGRAM_APP_ID=67890
INSTAGRAM_APP_SECRET=secret_here

# API Keys
INTERNAL_API_KEY=for_cron_jobs_etc
```

### Supabase Vault (Future)

```sql
-- Store secrets in Supabase Vault
SELECT vault.create_secret('token_encryption_key', 'secret_value');

-- Retrieve in Edge Functions
SELECT decrypted_secret FROM vault.decrypted_secrets
WHERE name = 'token_encryption_key';
```

### Key Rotation

#### Rotation Schedule
- Encryption keys: Every 90 days
- API keys: As needed
- OAuth secrets: When compromised
- Service keys: Every 180 days

#### Rotation Process
1. Generate new key
2. Deploy with both old and new keys
3. Re-encrypt data with new key
4. Remove old key after migration
5. Update environment variables

---

## Audit Logging

### What to Log

#### Security Events
```typescript
interface SecurityLog {
  event_type: 'auth_success' | 'auth_failure' | 'permission_denied' | 'token_refresh' | 'api_key_used';
  user_id?: string;
  ip_address: string;
  user_agent: string;
  endpoint: string;
  timestamp: Date;
  metadata?: object;
}
```

#### Data Access Logs
```sql
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL,
  user_id UUID REFERENCES users(id),
  resource_type TEXT, -- 'post', 'media', 'account'
  resource_id UUID,
  action TEXT, -- 'create', 'read', 'update', 'delete'
  ip_address INET,
  user_agent TEXT,
  status TEXT, -- 'success', 'failure'
  error_message TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX ON audit_logs (user_id, created_at DESC);
CREATE INDEX ON audit_logs (event_type, created_at DESC);
CREATE INDEX ON audit_logs (created_at DESC);
```

### Log Retention
- Security logs: 1 year
- Access logs: 90 days
- Error logs: 30 days
- Archived to cold storage after retention period

---

## Privacy

### Data Minimization

#### What We Collect
- **User Account**: Email, name (optional)
- **Connected Accounts**: Platform usernames, OAuth tokens
- **Content**: Posts, media that user already posted publicly
- **Metadata**: Engagement stats, timestamps (already public)

#### What We Don't Collect
- Follower lists
- Direct messages (unless platform provides via API)
- Private/hidden posts (unless user has read_all scope)
- Browsing history
- Analytics beyond basic usage metrics

### User Rights (GDPR/CCPA Compliance)

#### Right to Access
```typescript
// Export all user data
POST /api/user/export

Response:
{
  "export_url": "https://.../export.zip",
  "expires_at": "2024-01-22T12:00:00Z"
}

// Contents: JSON files with all data
- user.json
- accounts.json
- posts.json
- media/ (folder with all media files)
```

#### Right to Deletion
```typescript
// Delete account and all data
DELETE /api/user/account

// Cascade deletes:
- User record
- Connected accounts
- Posts
- Media assets (from storage)
- Sync logs
- API keys
```

#### Right to Rectification
```typescript
// Update user data
PATCH /api/user/profile
{
  "email": "newemail@example.com",
  "name": "New Name"
}
```

#### Right to Data Portability
```typescript
// Same as export, but in machine-readable format
POST /api/user/export?format=json

// Returns structured JSON adhering to standard schema
```

### Data Retention Policy

| Data Type | Retention | Rationale |
|-----------|-----------|-----------|
| User account | Until deletion | Core service |
| Connected accounts | Until disconnected | Core service |
| Posts | Until deletion | Core service |
| Media files | Until deletion | Core service |
| Sync logs | 90 days | Debugging |
| Audit logs | 1 year | Security |
| Deleted data | 30 days backup | Recovery |

#### Soft Delete Implementation
```sql
ALTER TABLE users ADD COLUMN deleted_at TIMESTAMPTZ;

-- Mark as deleted
UPDATE users SET deleted_at = NOW() WHERE id = {user_id};

-- Hard delete after 30 days (cron job)
DELETE FROM users WHERE deleted_at < NOW() - interval '30 days';
```

### Cookie Policy

#### Strictly Necessary
- `sb-access-token`: Authentication (HTTP-only, Secure, SameSite=Lax)
- `sb-refresh-token`: Token refresh (HTTP-only, Secure, SameSite=Lax)

#### No Tracking Cookies
- No third-party analytics
- No advertising cookies
- No social media pixels

---

## Compliance

### GDPR (EU)
- ✅ Legal basis: Consent & Legitimate Interest
- ✅ Data processing agreement with Supabase
- ✅ Data stored in EU region (optional)
- ✅ User rights implemented
- ✅ Privacy policy transparent
- ✅ Breach notification process

### CCPA (California)
- ✅ Do Not Sell disclosure
- ✅ Opt-out mechanism (we don't sell data)
- ✅ Data disclosure on request
- ✅ Deletion on request

### SOC 2 (Future)
For enterprise customers:
- Security controls documented
- Regular audits
- Penetration testing
- Incident response plan

---

## Incident Response

### Security Incident Process

1. **Detection**: Monitor logs, alerts, user reports
2. **Containment**: Isolate affected systems, revoke tokens
3. **Investigation**: Determine scope, root cause
4. **Eradication**: Remove threat, patch vulnerability
5. **Recovery**: Restore services, verify integrity
6. **Communication**: Notify affected users, regulators (if required)
7. **Post-Mortem**: Document lessons, improve processes

### Breach Notification

#### Criteria for Notification
- Unauthorized access to user data
- Data exfiltration
- Account compromise
- Token leakage

#### Notification Timeline
- **GDPR**: Within 72 hours of discovery
- **CCPA**: Without unreasonable delay
- **Users**: As soon as practically possible

#### Notification Template
```
Subject: Security Notification - Trove Account

Dear [User],

We are writing to inform you of a security incident that may have affected your Trove account.

What Happened:
[Description of incident]

What Information Was Involved:
[List of data types]

What We're Doing:
[Mitigation steps]

What You Should Do:
[Recommended user actions]

For More Information:
[Support contact]
```

---

## Security Best Practices for Developers

### 1. Code Review
- All code changes reviewed
- Security-focused review for auth/data access
- Automated security scanning (Snyk, GitHub Security)

### 2. Dependency Management
```json
// package.json
{
  "scripts": {
    "audit": "npm audit",
    "audit:fix": "npm audit fix"
  }
}
```

- Regular dependency updates
- Security patches applied immediately
- Automated alerts for vulnerabilities

### 3. Testing
```typescript
// Security test example
describe('Authorization', () => {
  it('should not allow access to other user posts', async () => {
    const user1Token = await createUser('user1@example.com');
    const user2Token = await createUser('user2@example.com');

    const post = await createPost(user1Token);

    const response = await fetch(`/api/posts/${post.id}`, {
      headers: { Authorization: `Bearer ${user2Token}` }
    });

    expect(response.status).toBe(404); // Not 403, to avoid leaking existence
  });
});
```

### 4. Secure Defaults
- HTTPS only
- RLS enabled by default
- Encryption at rest enabled
- Tokens expire after reasonable time
- Fail closed (deny by default)

---

## Monitoring & Alerting

### Security Monitoring

#### Metrics to Monitor
- Failed authentication attempts
- Unusual API access patterns
- High error rates
- Token refresh failures
- Storage access violations
- Rate limit hits

#### Alerts
```typescript
// Example: Alert on multiple failed auth attempts
if (failedAuthAttempts > 10 in 5 minutes from same IP) {
  alert('Potential brute force attack');
  blockIP(ipAddress, duration: '1 hour');
}

// Example: Alert on unusual data access
if (apiCalls > 1000 in 1 minute for user) {
  alert('Unusual API usage pattern');
  throttleUser(userId);
}
```

### Observability Tools
- **Logs**: Supabase logs + custom application logs
- **Metrics**: Prometheus/Grafana or built-in Supabase metrics
- **Tracing**: OpenTelemetry for distributed tracing
- **Alerts**: PagerDuty, Slack, email

---

## Security Checklist

### Pre-Launch
- [ ] All API endpoints require authentication
- [ ] RLS policies tested for all tables
- [ ] Secrets stored in environment variables
- [ ] OAuth tokens encrypted at rest
- [ ] HTTPS enforced
- [ ] Rate limiting implemented
- [ ] Input validation on all endpoints
- [ ] Error messages don't leak sensitive info
- [ ] Dependency security scan passed
- [ ] Penetration testing completed
- [ ] Privacy policy published
- [ ] Terms of service published
- [ ] Data processing agreement with Supabase
- [ ] Incident response plan documented

### Ongoing
- [ ] Weekly dependency updates
- [ ] Monthly security reviews
- [ ] Quarterly penetration tests
- [ ] Annual compliance audit
- [ ] Regular key rotation
- [ ] Log monitoring active
- [ ] Backup restoration tested
- [ ] Disaster recovery plan updated

---

## Conclusion

Security and privacy are foundational to Trove. This architecture provides:

1. **Strong Authentication**: Multi-factor options, secure token management
2. **Granular Authorization**: RLS ensures data isolation
3. **Data Protection**: Encryption at rest and in transit
4. **Privacy Compliance**: GDPR/CCPA ready
5. **Incident Preparedness**: Clear response procedures
6. **Continuous Improvement**: Regular audits and updates

Regular review and updates to this security architecture are essential as threats evolve and new features are added.
