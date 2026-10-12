CREATE TABLE IF NOT EXISTS shopping_oauth_requests (
    id TEXT NOT NULL PRIMARY KEY CHECK (length(id) = 43),
    consent_handle TEXT NOT NULL UNIQUE,
    browser_hash TEXT NOT NULL CHECK (length(browser_hash) = 64),
    client_name TEXT NOT NULL,
    client_domain TEXT NOT NULL,
    scopes TEXT NOT NULL,
    expires_at INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'denied', 'consumed')),
    approved_user_id TEXT,
    approved_session_id TEXT,
    FOREIGN KEY (approved_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (approved_session_id) REFERENCES native_sessions (id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_shopping_oauth_requests_expiry
    ON shopping_oauth_requests (expires_at);
