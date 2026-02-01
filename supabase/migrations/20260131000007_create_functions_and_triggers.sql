-- Create database functions and triggers

-- Function: Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW()
  RETURN NEW
END
$$ LANGUAGE plpgsql

-- Function: Update search vector for full-text search
-- Queries ingested_posts for platform-specific fields (author_handle, activity_type)
CREATE OR REPLACE FUNCTION update_search_vector()
RETURNS TRIGGER AS $$
DECLARE
  post_data JSONB;
BEGIN
  -- Look up the raw post data from ingested_posts
  SELECT ip.post_data INTO post_data
  FROM ingested_posts ip
  WHERE ip.platform = NEW.platform
    AND ip.platform_post_id = NEW.platform_post_id
  ORDER BY ip.created_at DESC
  LIMIT 1;

  NEW.search_vector = to_tsvector('english',
    COALESCE(NEW.text_content, '') || ' ' ||
    COALESCE(post_data->>'author_handle', '') || ' ' ||
    COALESCE(post_data->>'activity_type', '')
  );
  RETURN NEW;
END
$$ LANGUAGE plpgsql

-- Function: Denormalize user_id in posts
CREATE OR REPLACE FUNCTION denormalize_post_user_id()
RETURNS TRIGGER AS $$
BEGIN
  SELECT user_id INTO NEW.user_id
  FROM connected_accounts
  WHERE id = NEW.account_id
  RETURN NEW
END
$$ LANGUAGE plpgsql

-- Function: Denormalize user_id in media_assets
CREATE OR REPLACE FUNCTION denormalize_media_user_id()
RETURNS TRIGGER AS $$
BEGIN
  SELECT user_id INTO NEW.user_id
  FROM posts
  WHERE id = NEW.post_id
  RETURN NEW
END
$$ LANGUAGE plpgsql

-- Function: Calculate aspect ratio
CREATE OR REPLACE FUNCTION calculate_aspect_ratio()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.width IS NOT NULL AND NEW.height IS NOT NULL AND NEW.height > 0 THEN
    NEW.aspect_ratio = NEW.width::DECIMAL / NEW.height::DECIMAL
  END IF
  RETURN NEW
END
$$ LANGUAGE plpgsql

-- Function: Calculate sync duration
CREATE OR REPLACE FUNCTION calculate_sync_duration()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.completed_at IS NOT NULL THEN
    NEW.duration_ms = EXTRACT(EPOCH FROM (NEW.completed_at - NEW.started_at)) * 1000
  END IF
  RETURN NEW
END
$$ LANGUAGE plpgsql

-- Triggers for users table
CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at()

-- Triggers for connected_accounts table
CREATE TRIGGER update_connected_accounts_updated_at
  BEFORE UPDATE ON connected_accounts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at()

-- Triggers for posts table
CREATE TRIGGER update_posts_updated_at
  BEFORE UPDATE ON posts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at()

CREATE TRIGGER update_posts_search_vector
  BEFORE INSERT OR UPDATE OF text_content ON posts
  FOR EACH ROW EXECUTE FUNCTION update_search_vector()

CREATE TRIGGER denormalize_posts_user_id
  BEFORE INSERT ON posts
  FOR EACH ROW EXECUTE FUNCTION denormalize_post_user_id()

-- Triggers for media_assets table
CREATE TRIGGER update_media_assets_updated_at
  BEFORE UPDATE ON media_assets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at()

CREATE TRIGGER denormalize_media_assets_user_id
  BEFORE INSERT ON media_assets
  FOR EACH ROW EXECUTE FUNCTION denormalize_media_user_id()

CREATE TRIGGER calculate_media_aspect_ratio
  BEFORE INSERT OR UPDATE OF width, height ON media_assets
  FOR EACH ROW EXECUTE FUNCTION calculate_aspect_ratio()

-- Triggers for sync_logs table
CREATE TRIGGER calculate_sync_logs_duration
  BEFORE UPDATE OF completed_at ON sync_logs
  FOR EACH ROW EXECUTE FUNCTION calculate_sync_duration()
