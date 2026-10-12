-- Additive migration: existing users and shopping data are not changed.
-- Native-auth timestamps are Unix seconds (users timestamps remain milliseconds).
CREATE TABLE IF NOT EXISTS native_auth_challenges (
    id TEXT NOT NULL PRIMARY KEY CHECK (length(id) = 43),
    nonce_hash TEXT NOT NULL CHECK (length(nonce_hash) = 64),
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL CHECK (expires_at > created_at),
    consumed_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_native_auth_challenges_expiry
    ON native_auth_challenges (expires_at);

CREATE TABLE IF NOT EXISTS native_sessions (
    id TEXT NOT NULL PRIMARY KEY CHECK (length(id) = 43),
    user_id TEXT NOT NULL,
    access_token_hash TEXT NOT NULL UNIQUE CHECK (length(access_token_hash) = 64),
    refresh_token_hash TEXT NOT NULL UNIQUE CHECK (length(refresh_token_hash) = 64),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    access_expires_at INTEGER NOT NULL,
    refresh_expires_at INTEGER NOT NULL,
    revoked_at INTEGER,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_native_sessions_user
    ON native_sessions (user_id);

CREATE INDEX IF NOT EXISTS idx_native_sessions_expiry
    ON native_sessions (refresh_expires_at);
