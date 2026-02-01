# Instagram API Setup Guide

## Step 1: Connect Instagram to Facebook Page

Your Instagram Business/Creator account must be linked to a Facebook Page.

### Option A: Create New Facebook Page
1. Go to https://www.facebook.com/pages/create
2. Create a page (any category, can be simple)
3. Name it anything (e.g., "My Personal Page")

### Option B: Use Existing Page
1. Go to your Facebook Pages
2. Select the page you want to use

### Link Instagram to Facebook Page
1. Go to your Facebook Page settings
2. Click "Instagram" in left sidebar
3. Click "Connect Account"
4. Log in to your Instagram Business/Creator account
5. Authorize the connection

**Verify**: You should see your Instagram account connected to the Facebook Page

---

## Step 2: Create Meta/Facebook App

1. Go to https://developers.facebook.com/
2. Click "My Apps" (top right)
3. Click "Create App"

### App Setup:

#### Choose Use Case:
Select one of these options:
- **"Authenticate and request data from users"** (Recommended for Trove)
  - This is for apps that need user data via OAuth
- **OR "Other"** if available

#### Then select App Type:
- **App type**: Select "Business" or "Consumer" (Business is fine)
- **App name**: "Trove" (or whatever you prefer)
- **App contact email**: Your email
- Click "Create App" or "Next"

#### Add Products:
You may be asked to add products immediately:
- Look for **"Instagram"** and click "Set Up"
- This adds Instagram Graph API to your app

---

## Step 3: Add Instagram Product

In your app dashboard:
1. Find "Instagram" in the products list
2. Click "Set Up" on Instagram Graph API
3. This adds Instagram capabilities to your app

---

## Step 4: Configure App Settings

### Basic Settings
1. Go to "Settings" → "Basic" in left sidebar
2. Note your **App ID** and **App Secret** (you'll need these)
3. Add **App Domains**: Your domain (e.g., `localhost` for testing)
4. Save changes

### Configure App Roles (IMPORTANT!)

You need to add yourself with the right permissions:

#### Option 1: Add as Administrator (Recommended)
1. Go to "App Roles" → "Roles" in left sidebar
2. Click "Add Administrators"
3. Enter your Facebook name or user ID
4. Click "Submit"
5. Accept the request in your Facebook notifications

#### Option 2: Add as Developer
1. Go to "App Roles" → "Roles"
2. Click "Add Developers"
3. Add yourself
4. This also gives you access to generate tokens

#### Option 3: Use Test Users (For Testing)
1. Go to "App Roles" → "Test Users"
2. Create a test user OR
3. Add your account as a test user
4. This allows testing without App Review

**After adding yourself**, refresh the Graph API Explorer and try again.

---

## Step 5: Get Access Token (Quick Method)

### Using Graph API Explorer (Easiest for Testing)

1. Go to https://developers.facebook.com/tools/explorer/
2. Select your app from the dropdown (top right)
3. Click "Generate Access Token"
4. Select permissions:
   - `instagram_basic`
   - `pages_show_list`
   - `pages_read_engagement`
   - `instagram_manage_insights`
5. Click "Generate Access Token"
6. Authorize the app

### Get Instagram Business Account ID

In the Graph API Explorer:
```
GET /me/accounts
```
This returns your Facebook Pages.

Copy the Page ID, then:
```
GET /{page-id}?fields=instagram_business_account
```

This returns your Instagram Business Account ID.

### Get Long-Lived Token

The token from Graph API Explorer expires in 1 hour. To get a long-lived token (60 days):

```bash
curl -X GET "https://graph.facebook.com/v18.0/oauth/access_token?\
grant_type=fb_exchange_token&\
client_id={APP_ID}&\
client_secret={APP_SECRET}&\
fb_exchange_token={SHORT_LIVED_TOKEN}"
```

Response:
```json
{
  "access_token": "long_lived_token_here",
  "token_type": "bearer",
  "expires_in": 5183944
}
```

---

## Step 6: Test Your Access

Test that everything works:

```bash
# Get your media
curl -X GET "https://graph.facebook.com/v18.0/{IG_USER_ID}/media?\
fields=id,caption,media_type,media_url,permalink,timestamp&\
access_token={ACCESS_TOKEN}"
```

You should see your Instagram posts!

---

## Step 7: For Production (Later)

For production use, you need App Review:
1. Go to "App Review" → "Permissions and Features"
2. Request these permissions:
   - `instagram_basic`
   - `pages_show_list`
   - `pages_read_engagement`
   - `instagram_manage_insights`
3. Provide screencast showing how you use each permission
4. Submit for review (usually takes a few days)

**Note**: For personal use/testing, you can skip App Review by using Test Users.

---

## Environment Variables to Save

Once you have everything:

```bash
# Add to your .env file
INSTAGRAM_APP_ID=your_app_id
INSTAGRAM_APP_SECRET=your_app_secret
INSTAGRAM_ACCESS_TOKEN=your_long_lived_token
INSTAGRAM_IG_USER_ID=your_instagram_business_account_id
INSTAGRAM_PAGE_ID=your_facebook_page_id
```

---

## Token Refresh

Long-lived tokens expire after 60 days. Refresh before expiration:

```bash
curl -X GET "https://graph.facebook.com/v18.0/oauth/access_token?\
grant_type=fb_exchange_token&\
client_id={APP_ID}&\
client_secret={APP_SECRET}&\
fb_exchange_token={CURRENT_LONG_LIVED_TOKEN}"
```

This gives you a new 60-day token.

---

## Troubleshooting

### Error: "Instagram account is not a business account"
- Convert your Instagram to Business/Creator in Instagram app settings

### Error: "The Instagram account is not linked to the page"
- Complete Step 1 again, ensure connection is established

### Error: "Invalid OAuth access token"
- Token expired, get a new one
- Check you're using the correct App ID/Secret

### Can't see media
- Make sure you're using Instagram Business Account ID, not Facebook Page ID
- Verify permissions are granted
- Check the token has `instagram_basic` scope

---

## Quick Test Script

Save as `test-instagram.sh`:

```bash
#!/bin/bash

APP_ID="your_app_id"
IG_USER_ID="your_ig_user_id"
ACCESS_TOKEN="your_access_token"

echo "Fetching Instagram media..."
curl -s "https://graph.facebook.com/v18.0/${IG_USER_ID}/media?fields=id,caption,media_type,media_url,permalink,timestamp&access_token=${ACCESS_TOKEN}" | jq .

echo "\nFetching account info..."
curl -s "https://graph.facebook.com/v18.0/${IG_USER_ID}?fields=username,media_count&access_token=${ACCESS_TOKEN}" | jq .
```

Run: `chmod +x test-instagram.sh && ./test-instagram.sh`

---

## Next Steps

Once you have your tokens:
1. Add them to `.env` file (don't commit!)
2. Test the API endpoints
3. Implement OAuth flow in Trove for automatic token management
4. Set up polling sync for media

---

**Important**:
- Keep App Secret and Access Tokens secure
- Don't commit tokens to git
- Tokens are sensitive - treat like passwords
- Long-lived tokens expire in 60 days, implement refresh
