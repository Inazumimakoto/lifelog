import { publicOrigin, type ApiBindings } from './config'
import { resolveNativeSession } from './native-auth'

type Entity = 'place' | 'item'
type PlaceData = { name: string; order_index: number }
type ItemData = { title: string; note: string; place_id: string | null; created_at: number }
type Mutation = { operation_id: string; entity: Entity; id: string; base_version: number; deleted: boolean; data: PlaceData | ItemData | null }
type Identity = { userId: string; sessionId: string; tokenHash: string }
type Receipt = { payload_hash: string; status: string; entity: Entity; record_json: string | null }
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
// Allow the stated field limits even when JSON escapes each character as six bytes.
const maximumBodyBytes = 64 * 1024

class SyncError extends Error {
    constructor(readonly status: number, readonly code: string) { super('Shopping synchronization failed') }
}

function json(value: unknown, status = 200): Response {
    return Response.json(value, { status, headers: { 'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' } })
}

async function hash(value: string): Promise<string> {
    return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))),
        byte => byte.toString(16).padStart(2, '0')).join('')
}

function integer(value: unknown): value is number {
    return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0
}

function object(value: unknown, keys: string[]): value is Record<string, unknown> {
    return value !== null && typeof value === 'object' && !Array.isArray(value)
        && Object.keys(value).length === keys.length && Object.keys(value).every(key => keys.includes(key))
}

function identifier(value: unknown): value is string { return typeof value === 'string' && uuid.test(value) }

async function parseMutation(request: Request): Promise<Mutation> {
    if (!/^application\/json(?:\s*;|\s*$)/i.test(request.headers.get('Content-Type') ?? '')) throw new SyncError(400, 'json_required')
    const reader = request.body?.getReader()
    if (!reader) throw new SyncError(400, 'invalid_body')
    let bytes = 0, text = ''
    const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false })
    try {
        while (true) {
            const { done, value } = await reader.read()
            if (done) break
            bytes += value.byteLength
            if (bytes > maximumBodyBytes) { await reader.cancel(); throw new SyncError(413, 'body_too_large') }
            text += decoder.decode(value, { stream: true })
        }
        text += decoder.decode()
    } catch (error) {
        if (error instanceof SyncError) throw error
        throw new SyncError(400, 'invalid_body')
    } finally { reader.releaseLock() }
    let input: unknown
    try { input = JSON.parse(text) } catch { throw new SyncError(400, 'invalid_body') }
    // Reject duplicate keys in every nested object, including escaped spellings.
    const stack: (Set<string> | null)[] = []
    for (let index = 0; index < text.length; index++) {
        const character = text[index]
        if (character === '{') stack.push(new Set())
        else if (character === '[') stack.push(null)
        else if (character === '}' || character === ']') stack.pop()
        else if (character === '"') {
            const start = index
            for (index++; index < text.length; index++) {
                if (text[index] === '\\') index++
                else if (text[index] === '"') break
            }
            const keys = stack.at(-1)
            if (keys && /^\s*:/.test(text.slice(index + 1))) {
                const key = JSON.parse(text.slice(start, index + 1)) as string
                if (keys.has(key)) throw new SyncError(400, 'invalid_body')
                keys.add(key)
            }
        }
    }
    if (!object(input, ['operation_id', 'entity', 'id', 'base_version', 'deleted', 'data'])
        || !identifier(input.operation_id) || !identifier(input.id)
        || !['place', 'item'].includes(String(input.entity)) || !integer(input.base_version)
        || input.base_version >= Number.MAX_SAFE_INTEGER || typeof input.deleted !== 'boolean') throw new SyncError(400, 'invalid_body')
    const common = { operation_id: input.operation_id.toLowerCase(), id: input.id.toLowerCase(),
        entity: input.entity as Entity, base_version: input.base_version, deleted: input.deleted }
    if (input.deleted) {
        if (input.data !== null || input.base_version === 0) throw new SyncError(400, 'invalid_body')
        return { ...common, data: null }
    }
    if (input.entity === 'place') {
        if (!object(input.data, ['name', 'order_index']) || typeof input.data.name !== 'string'
            || !input.data.name.trim() || input.data.name.includes('\u0000') || input.data.name.length > 200
            || !integer(input.data.order_index)) throw new SyncError(400, 'invalid_body')
        return { ...common, data: { name: input.data.name.trim(), order_index: input.data.order_index } }
    }
    if (!object(input.data, ['title', 'note', 'place_id', 'created_at']) || typeof input.data.title !== 'string'
        || !input.data.title.trim() || input.data.title.includes('\u0000') || input.data.title.length > 200
        || typeof input.data.note !== 'string' || input.data.note.length > 4000
        || (input.data.place_id !== null && !identifier(input.data.place_id)) || !integer(input.data.created_at)) throw new SyncError(400, 'invalid_body')
    return { ...common, data: { title: input.data.title.trim(), note: input.data.note,
        place_id: typeof input.data.place_id === 'string' ? input.data.place_id.toLowerCase() : null,
        created_at: input.data.created_at } }
}

const activeSession = `EXISTS (SELECT 1 FROM native_sessions AS s JOIN users AS u ON u.id = s.user_id
    WHERE s.id = ? AND s.user_id = ? AND s.access_token_hash = ? AND s.revoked_at IS NULL
      AND s.access_expires_at > unixepoch() AND s.refresh_expires_at > unixepoch() AND u.deleted_at IS NULL)`
const authValues = (identity: Identity) => [identity.sessionId, identity.userId, identity.tokenHash]
const recordSQL = (entity: Entity) => entity === 'place'
    ? `json_object('id', lower(id), 'name', name, 'order_index', order_index, 'created_at', created_at,
        'updated_at', updated_at, 'version', version, 'deleted_at', deleted_at)`
    : `json_object('id', lower(id), 'title', title, 'note', note, 'place_id', lower(place_id),
        'created_at', created_at, 'updated_at', updated_at, 'version', version, 'deleted_at', deleted_at)`

async function changes(request: Request, env: ApiBindings, identity: Identity): Promise<Response> {
    const search = new URL(request.url).searchParams
    if ([...search.keys()].some(key => !['after', 'limit'].includes(key))
        || search.getAll('after').length > 1 || search.getAll('limit').length > 1) throw new SyncError(400, 'invalid_cursor')
    const afterText = search.get('after') ?? '0', limitText = search.get('limit') ?? '100'
    if (!/^(0|[1-9]\d*)$/.test(afterText) || !/^[1-9]\d*$/.test(limitText)) throw new SyncError(400, 'invalid_cursor')
    const after = Number(afterText), limit = Number(limitText)
    if (!integer(after) || !integer(limit) || limit < 1 || limit > 100) throw new SyncError(400, 'invalid_cursor')
    const replies = await env.DB.batch([
        env.DB.prepare(`SELECT 1 AS valid WHERE ${activeSession}`).bind(...authValues(identity)),
        env.DB.prepare(`SELECT seq, entity, record_json FROM shopping_changes
            WHERE user_id = ? AND seq > ? AND ${activeSession} ORDER BY seq LIMIT ?`)
            .bind(identity.userId, after, ...authValues(identity), limit + 1)
    ])
    if (!replies[0].results.length) throw new SyncError(401, 'invalid_session')
    const rows = replies[1].results as unknown as { seq: number; entity: Entity; record_json: string }[]
    const page = rows.slice(0, limit)
    return json({ changes: page.map(row => ({ seq: row.seq, entity: row.entity, record: JSON.parse(row.record_json) })),
        next_cursor: page.at(-1)?.seq ?? after, has_more: rows.length > limit })
}

async function mutate(request: Request, env: ApiBindings, identity: Identity): Promise<Response> {
    const input = await parseMutation(request)
    const payloadHash = await hash(JSON.stringify(input)), attempt = crypto.randomUUID(), now = Date.now()
    const table = input.entity === 'place' ? 'shopping_places' : 'shopping_items'
    const receipt = `EXISTS (SELECT 1 FROM shopping_mutation_receipts WHERE user_id = ?
        AND operation_id = ? AND attempt_id = ? AND status = 'pending')`
    const receiptValues = [identity.userId, input.operation_id, attempt]
    const current = `(SELECT ${recordSQL(input.entity)} FROM ${table} WHERE user_id = ? AND lower(id) = ?)`
    const currentValues = [identity.userId, input.id]
    const statements: D1PreparedStatement[] = [env.DB.prepare(`
        INSERT OR IGNORE INTO shopping_mutation_receipts
            (user_id, operation_id, payload_hash, attempt_id, status, entity, created_at)
        SELECT ?, ?, ?, ?, 'pending', ?, ? WHERE ${activeSession}`)
        .bind(identity.userId, input.operation_id, payloadHash, attempt, input.entity, now, ...authValues(identity))]
    let identical = '0', identicalValues: (string | number | null)[] = []
    let placeValid = '1', placeValidValues: (string | null)[] = []
    if (input.entity === 'item' && input.data) {
        const data = input.data as ItemData
        placeValid = `(? IS NULL OR EXISTS (SELECT 1 FROM shopping_places
            WHERE user_id = ? AND lower(id) = ? AND deleted_at IS NULL))`
        placeValidValues = [data.place_id, identity.userId, data.place_id]
    }
    if (input.base_version === 0 && input.data) {
        if (input.entity === 'place') {
            const data = input.data as PlaceData
            statements.push(env.DB.prepare(`INSERT INTO shopping_places
                (id, user_id, name, order_index, created_at, updated_at, version, deleted_at)
                SELECT ?, ?, ?, ?, ?, ?, 1, NULL WHERE ${receipt} AND ${activeSession}
                AND NOT EXISTS (SELECT 1 FROM shopping_places WHERE user_id = ? AND lower(id) = ?)`)
                .bind(input.id, identity.userId, data.name, data.order_index, now, now, ...receiptValues,
                    ...authValues(identity), ...currentValues))
            identical = `EXISTS (SELECT 1 FROM shopping_places WHERE user_id = ? AND lower(id) = ?
                AND deleted_at IS NULL AND name = ? AND order_index = ?)`
            identicalValues = [...currentValues, data.name, data.order_index]
        } else {
            const data = input.data as ItemData
            statements.push(env.DB.prepare(`INSERT INTO shopping_items
                (id, user_id, title, note, place_id, created_at, updated_at, version, deleted_at)
                SELECT ?, ?, ?, ?, (SELECT id FROM shopping_places WHERE user_id = ? AND lower(id) = ? AND deleted_at IS NULL),
                    ?, ?, 1, NULL WHERE ${receipt} AND ${activeSession} AND ${placeValid}
                AND NOT EXISTS (SELECT 1 FROM shopping_items WHERE user_id = ? AND lower(id) = ?)`)
                .bind(input.id, identity.userId, data.title, data.note, identity.userId, data.place_id,
                    data.created_at, now, ...receiptValues, ...authValues(identity), ...placeValidValues, ...currentValues))
            identical = `EXISTS (SELECT 1 FROM shopping_items WHERE user_id = ? AND lower(id) = ?
                AND deleted_at IS NULL AND title = ? AND note = ? AND lower(place_id) IS ? AND created_at = ?)`
            identicalValues = [...currentValues, data.title, data.note, data.place_id, data.created_at]
        }
    } else {
        let fields: string, values: (string | number | null)[]
        if (input.deleted) { fields = 'deleted_at = ?'; values = [now] }
        else if (input.entity === 'place') {
            const data = input.data as PlaceData
            fields = 'name = ?, order_index = ?, deleted_at = NULL'; values = [data.name, data.order_index]
        } else {
            const data = input.data as ItemData
            fields = `title = ?, note = ?, place_id = (SELECT id FROM shopping_places
                WHERE user_id = ? AND lower(id) = ? AND deleted_at IS NULL), deleted_at = NULL`
            values = [data.title, data.note, identity.userId, data.place_id]
        }
        statements.push(env.DB.prepare(`UPDATE ${table} SET ${fields}, version = version + 1, updated_at = ?
            WHERE user_id = ? AND lower(id) = ? AND version = ? AND ${receipt} AND ${activeSession} AND ${placeValid}`)
            .bind(...values, now, ...currentValues, input.base_version, ...receiptValues, ...authValues(identity), ...placeValidValues))
    }
    // changes() refers to the preceding outer INSERT/UPDATE, excluding trigger
    // inserts. The result is persisted before a place's dependent-item update.
    statements.push(env.DB.prepare(`UPDATE shopping_mutation_receipts SET
        status = CASE WHEN changes() = 1 OR (${identical}) THEN 'applied'
            WHEN NOT (${placeValid}) THEN 'place_unavailable' ELSE 'version_conflict' END,
        record_json = ${current}
        WHERE user_id = ? AND operation_id = ? AND attempt_id = ? AND status = 'pending' AND ${activeSession}`)
        .bind(...identicalValues, ...placeValidValues, ...currentValues, ...receiptValues, ...authValues(identity)))
    if (input.entity === 'place' && input.deleted) {
        statements.push(env.DB.prepare(`UPDATE shopping_items SET place_id = NULL, version = version + 1, updated_at = ?
            WHERE user_id = ? AND lower(place_id) = ? AND deleted_at IS NULL AND ${activeSession}
            AND EXISTS (SELECT 1 FROM shopping_mutation_receipts WHERE user_id = ? AND operation_id = ?
                AND attempt_id = ? AND status = 'applied')`)
            .bind(now, identity.userId, input.id, ...authValues(identity), ...receiptValues))
    }
    statements.push(env.DB.prepare(`SELECT payload_hash, status, entity, record_json FROM shopping_mutation_receipts
        WHERE user_id = ? AND operation_id = ? AND ${activeSession}`)
        .bind(identity.userId, input.operation_id, ...authValues(identity)))
    const replies = await env.DB.batch(statements)
    const saved = replies.at(-1)?.results[0] as unknown as Receipt | undefined
    if (!saved || saved.status === 'pending') throw new SyncError(401, 'invalid_session')
    if (saved.payload_hash !== payloadHash) throw new SyncError(409, 'idempotency_conflict')
    const result = { entity: saved.entity, record: saved.record_json ? JSON.parse(saved.record_json) : null }
    return saved.status === 'applied' ? json(result) : json({ error: saved.status, ...result }, 409)
}

export async function handleShoppingSynchronization(request: Request, env: ApiBindings): Promise<Response> {
    try {
        const url = new URL(request.url), origin = request.headers.get('Origin')
        if (url.origin !== publicOrigin || (origin !== null && origin !== publicOrigin)) throw new SyncError(400, 'invalid_origin')
        const resolved = await resolveNativeSession(request, env)
        if (!resolved) throw new SyncError(401, 'invalid_session')
        const token = /^Bearer ([A-Za-z0-9_-]{43})$/i.exec(request.headers.get('Authorization') ?? '')![1]
        const identity = { ...resolved, tokenHash: await hash(token) }
        if (url.pathname === '/auth/native/shopping/changes' && request.method === 'GET') return await changes(request, env, identity)
        if (url.pathname === '/auth/native/shopping/mutations' && request.method === 'POST' && !url.search) return await mutate(request, env, identity)
        return json({ error: 'not_found' }, 404)
    } catch (error) {
        if (error instanceof SyncError) return json({ error: error.code }, error.status)
        // Never log shopping contents, bearer tokens, operation payloads or SQL.
        return json({ error: 'shopping_sync_unavailable' }, 503)
    }
}
