INSERT INTO users (id, apple_sub, created_at, updated_at)
VALUES (
    'dev-user', 'dev-only-apple-sub-not-for-login',
    CAST(strftime('%s', 'now') AS INTEGER) * 1000,
    CAST(strftime('%s', 'now') AS INTEGER) * 1000
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO shopping_places (
    id, user_id, name, order_index, created_at, updated_at
) VALUES (
    '10000000-0000-4000-8000-000000000001',
    'dev-user', 'スーパー', 0,
    CAST(strftime('%s', 'now') AS INTEGER) * 1000,
    CAST(strftime('%s', 'now') AS INTEGER) * 1000
)
ON CONFLICT (user_id, id) DO NOTHING;

INSERT INTO shopping_items (
    id, user_id, title, note, place_id, created_at, updated_at
) VALUES (
    '20000000-0000-4000-8000-000000000001',
    'dev-user', '卵', '6個入りを1パック',
    '10000000-0000-4000-8000-000000000001',
    CAST(strftime('%s', 'now') AS INTEGER) * 1000,
    CAST(strftime('%s', 'now') AS INTEGER) * 1000
)
ON CONFLICT (user_id, id) DO NOTHING;
