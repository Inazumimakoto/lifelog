CREATE TABLE IF NOT EXISTS users (
    id TEXT NOT NULL PRIMARY KEY,
    apple_sub TEXT NOT NULL UNIQUE CHECK (length(apple_sub) > 0),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
);

CREATE TABLE IF NOT EXISTS shopping_places (
    id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    order_index INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
    deleted_at INTEGER,
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS shopping_items (
    id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    title TEXT NOT NULL CHECK (length(trim(title)) > 0),
    note TEXT NOT NULL DEFAULT '',
    place_id TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
    deleted_at INTEGER,
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (user_id, place_id)
        REFERENCES shopping_places (user_id, id)
        ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_shopping_places_active_order
    ON shopping_places (user_id, order_index, id)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_shopping_items_active_created
    ON shopping_items (user_id, created_at, id)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_shopping_items_active_place
    ON shopping_items (user_id, place_id, created_at, id)
    WHERE deleted_at IS NULL;
