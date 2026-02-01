-- Enable Row Level Security on all tables

ALTER TABLE users ENABLE ROW LEVEL SECURITY
ALTER TABLE connected_accounts ENABLE ROW LEVEL SECURITY
ALTER TABLE posts ENABLE ROW LEVEL SECURITY
ALTER TABLE media_assets ENABLE ROW LEVEL SECURITY
ALTER TABLE sync_logs ENABLE ROW LEVEL SECURITY

-- RLS Policies for users table
CREATE POLICY "Users can read own record"
  ON users FOR SELECT
  USING (auth.uid() = id)

CREATE POLICY "Users can update own record"
  ON users FOR UPDATE
  USING (auth.uid() = id)

-- RLS Policies for connected_accounts table
CREATE POLICY "Users can manage own accounts"
  ON connected_accounts FOR ALL
  USING (auth.uid() = user_id)

-- RLS Policies for posts table
CREATE POLICY "Users can read own posts"
  ON posts FOR SELECT
  USING (auth.uid() = user_id)

-- RLS Policies for media_assets table
CREATE POLICY "Users can read own media"
  ON media_assets FOR SELECT
  USING (auth.uid() = user_id)

-- RLS Policies for sync_logs table
CREATE POLICY "Users can read own sync logs"
  ON sync_logs FOR SELECT
  USING (auth.uid() = user_id)
