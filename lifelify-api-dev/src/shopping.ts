export type ShoppingItem = {
    id: string
    title: string
    note: string
    place_id: string | null
    created_at: number
    updated_at: number
    version: number
}

export type ListedShoppingItem = ShoppingItem & {
    place_name: string | null
}

export type ShoppingPlace = {
    id: string
    name: string
    order_index: number
}

export type NewShoppingItem = {
    title: string
    note: string
    place_id: string | null
}

export function parseNewShoppingItem(value: unknown): NewShoppingItem | null {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
        return null
    }

    const fields = value as Record<string, unknown>
    if (Object.keys(fields).some((key) => !['title', 'note', 'place_id'].includes(key))) {
        return null
    }
    if (typeof fields.title !== 'string') {
        return null
    }

    const title = fields.title.trim()
    const note = fields.note === undefined ? '' : fields.note
    const placeId = fields.place_id === undefined ? null : fields.place_id
    if (!title || title.includes('\u0000') || title.length > 200 || typeof note !== 'string' || note.length > 4000) {
        return null
    }
    if (placeId !== null && (
        typeof placeId !== 'string'
        || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(placeId)
    )) {
        return null
    }

    return { title, note, place_id: placeId }
}

export async function isShoppingUserActive(database: D1Database, userId: string): Promise<boolean> {
    const user = await database.prepare(
        'SELECT id FROM users WHERE id = ? AND deleted_at IS NULL'
    ).bind(userId).first<{ id: string }>()
    return user !== null
}

export async function listShoppingPlaces(database: D1Database, userId: string) {
    const pageSize = 100
    const { results } = await database.prepare(`
        SELECT p.id, p.name, p.order_index
        FROM shopping_places AS p
        JOIN users AS u ON u.id = p.user_id AND u.deleted_at IS NULL
        WHERE p.user_id = ? AND p.deleted_at IS NULL
        ORDER BY p.order_index, p.id
        LIMIT ?
    `).bind(userId, pageSize + 1).all<ShoppingPlace>()

    return {
        places: results.slice(0, pageSize),
        has_more: results.length > pageSize
    }
}

export async function listShoppingItems(database: D1Database, userId: string) {
    const pageSize = 100
    const { results } = await database.prepare(`
        SELECT i.id, i.title, i.note, i.place_id,
               i.created_at, i.updated_at, i.version, p.name AS place_name
        FROM shopping_items AS i
        JOIN users AS u ON u.id = i.user_id AND u.deleted_at IS NULL
        LEFT JOIN shopping_places AS p
          ON p.user_id = i.user_id AND p.id = i.place_id AND p.deleted_at IS NULL
        WHERE i.user_id = ? AND i.deleted_at IS NULL
        ORDER BY i.created_at DESC, i.id DESC
        LIMIT ?
    `).bind(userId, pageSize + 1).all<ListedShoppingItem>()

    return {
        items: results.slice(0, pageSize),
        has_more: results.length > pageSize
    }
}

export async function createShoppingItem(
    database: D1Database,
    userId: string,
    input: NewShoppingItem
): Promise<ShoppingItem | null> {
    const id = crypto.randomUUID()
    const now = Date.now()
    // docs/cloudflare-shopping/README.md: owner/place validity and the insert
    // share one statement, including checks not enforced by foreign keys.
    const result = await database.prepare(`
        INSERT INTO shopping_items (
            id, user_id, title, note, place_id,
            created_at, updated_at, version, deleted_at
        )
        SELECT ?, ?, ?, ?, ?, ?, ?, 1, NULL
        WHERE EXISTS (SELECT 1 FROM users WHERE id = ? AND deleted_at IS NULL)
          AND (? IS NULL OR EXISTS (
              SELECT 1 FROM shopping_places
              WHERE user_id = ? AND id = ? AND deleted_at IS NULL
          ))
        RETURNING id
    `).bind(
        id, userId, input.title, input.note, input.place_id, now, now,
        userId, input.place_id, userId, input.place_id
    ).first<{ id: string }>()

    // Sync triggers also write change-log rows; D1 meta.changes includes those.
    // RETURNING identifies the actual inserted shopping row instead.
    if (!result) {
        return null
    }

    return {
        id,
        ...input,
        created_at: now,
        updated_at: now,
        version: 1
    }
}
