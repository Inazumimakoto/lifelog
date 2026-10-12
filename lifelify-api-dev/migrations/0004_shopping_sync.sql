-- Every shopping write, including an MCP insert, creates its sync event in the
-- same SQLite transaction. Sequence IDs, rather than clocks, define the cursor.
CREATE TABLE IF NOT EXISTS shopping_changes (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    entity TEXT NOT NULL CHECK (entity IN ('place', 'item')),
    entity_id TEXT NOT NULL,
    version INTEGER NOT NULL,
    record_json TEXT NOT NULL,
    UNIQUE (user_id, entity, entity_id, version),
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_shopping_changes_owner_cursor
    ON shopping_changes (user_id, seq);

CREATE TABLE IF NOT EXISTS shopping_mutation_receipts (
    user_id TEXT NOT NULL,
    operation_id TEXT NOT NULL,
    payload_hash TEXT NOT NULL,
    attempt_id TEXT NOT NULL,
    status TEXT NOT NULL,
    entity TEXT NOT NULL,
    record_json TEXT,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, operation_id),
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT
);

-- Existing Swift UUID spellings may use uppercase. Resolve identifiers without
-- case sensitivity while preserving their actual spelling for existing FKs.
CREATE UNIQUE INDEX IF NOT EXISTS idx_shopping_places_owner_uuid
    ON shopping_places (user_id, lower(id));
CREATE UNIQUE INDEX IF NOT EXISTS idx_shopping_items_owner_uuid
    ON shopping_items (user_id, lower(id));

CREATE TRIGGER IF NOT EXISTS shopping_places_sync_insert AFTER INSERT ON shopping_places
BEGIN
    INSERT INTO shopping_changes (user_id, entity, entity_id, version, record_json)
    VALUES (NEW.user_id, 'place', lower(NEW.id), NEW.version,
        json_object('id', lower(NEW.id), 'name', NEW.name, 'order_index', NEW.order_index,
            'created_at', NEW.created_at, 'updated_at', NEW.updated_at,
            'version', NEW.version, 'deleted_at', NEW.deleted_at));
END;
CREATE TRIGGER IF NOT EXISTS shopping_places_sync_update AFTER UPDATE ON shopping_places
WHEN NEW.version <> OLD.version
BEGIN
    INSERT INTO shopping_changes (user_id, entity, entity_id, version, record_json)
    VALUES (NEW.user_id, 'place', lower(NEW.id), NEW.version,
        json_object('id', lower(NEW.id), 'name', NEW.name, 'order_index', NEW.order_index,
            'created_at', NEW.created_at, 'updated_at', NEW.updated_at,
            'version', NEW.version, 'deleted_at', NEW.deleted_at));
END;
CREATE TRIGGER IF NOT EXISTS shopping_items_sync_insert AFTER INSERT ON shopping_items
BEGIN
    INSERT INTO shopping_changes (user_id, entity, entity_id, version, record_json)
    VALUES (NEW.user_id, 'item', lower(NEW.id), NEW.version,
        json_object('id', lower(NEW.id), 'title', NEW.title, 'note', NEW.note,
            'place_id', lower(NEW.place_id), 'created_at', NEW.created_at,
            'updated_at', NEW.updated_at, 'version', NEW.version, 'deleted_at', NEW.deleted_at));
END;
CREATE TRIGGER IF NOT EXISTS shopping_items_sync_update AFTER UPDATE ON shopping_items
WHEN NEW.version <> OLD.version
BEGIN
    INSERT INTO shopping_changes (user_id, entity, entity_id, version, record_json)
    VALUES (NEW.user_id, 'item', lower(NEW.id), NEW.version,
        json_object('id', lower(NEW.id), 'title', NEW.title, 'note', NEW.note,
            'place_id', lower(NEW.place_id), 'created_at', NEW.created_at,
            'updated_at', NEW.updated_at, 'version', NEW.version, 'deleted_at', NEW.deleted_at));
END;

-- Idempotent backfill includes tombstones and places before their items.
INSERT OR IGNORE INTO shopping_changes (user_id, entity, entity_id, version, record_json)
SELECT user_id, 'place', lower(id), version,
    json_object('id', lower(id), 'name', name, 'order_index', order_index,
        'created_at', created_at, 'updated_at', updated_at, 'version', version, 'deleted_at', deleted_at)
FROM shopping_places ORDER BY user_id, order_index, id;
INSERT OR IGNORE INTO shopping_changes (user_id, entity, entity_id, version, record_json)
SELECT user_id, 'item', lower(id), version,
    json_object('id', lower(id), 'title', title, 'note', note, 'place_id', lower(place_id),
        'created_at', created_at, 'updated_at', updated_at, 'version', version, 'deleted_at', deleted_at)
FROM shopping_items ORDER BY user_id, created_at, id;
