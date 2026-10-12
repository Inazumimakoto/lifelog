import assert from 'node:assert/strict'
import { createHash, randomUUID } from 'node:crypto'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { after, before, beforeEach, describe, it } from 'node:test'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'
import { convertV4MiniflareOptions, Miniflare } from 'miniflare'

const project = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const origin = 'https://lifelify-api-dev.inazumimakoto.workers.dev'
const user = '10000000-0000-4000-8000-000000000001'
const otherUser = '10000000-0000-4000-8000-000000000002'
const token = 'A'.repeat(43), otherToken = 'B'.repeat(43)
const sha = value => createHash('sha256').update(value).digest('hex')
let temporaryDirectory, runtime, db, syncMigration

async function execute(sql) {
    // D1 exec treats each newline as a statement. Keep multiline triggers intact.
    let remaining = sql.replace(/--[^\n]*/g, '').trim()
    while (remaining) {
        const end = /^CREATE TRIGGER/i.test(remaining)
            ? remaining.indexOf('END;') + 4 : remaining.indexOf(';') + 1
        assert.ok(end > 0, 'Fixture statement must end with a semicolon')
        await db.prepare(remaining.slice(0, end)).run()
        remaining = remaining.slice(end).trim()
    }
}
async function request(path, { method = 'GET', body, bearer = token, headers = {} } = {}) {
    return runtime.dispatchFetch(`${origin}/auth/native/shopping${path}`, { method,
        headers: { Authorization: `Bearer ${bearer}`, ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}), ...headers },
        ...(body !== undefined ? { body: typeof body === 'string' ? body : JSON.stringify(body) } : {}) })
}
async function send(input, options = {}) { return request('/mutations', { method: 'POST', body: input, ...options }) }
function place(name = 'スーパー', options = {}) {
    return { operation_id: randomUUID(), entity: 'place', id: randomUUID(), base_version: 0,
        deleted: false, data: { name, order_index: 0 }, ...options }
}
function item(title = '卵', options = {}) {
    return { operation_id: randomUUID(), entity: 'item', id: randomUUID(), base_version: 0,
        deleted: false, data: { title, note: '6個', place_id: null, created_at: 1000 }, ...options }
}
async function applied(input, options = {}) {
    const response = await send(input, options)
    assert.equal(response.status, 200, await response.clone().text())
    assert.equal(response.headers.get('Cache-Control'), 'no-store')
    return response.json()
}
async function pull(after = 0, limit = 100, options = {}) {
    const response = await request(`/changes?after=${after}&limit=${limit}`, options)
    assert.equal(response.status, 200, await response.clone().text())
    return response.json()
}
async function session(owner, bearer) {
    const now = Math.floor(Date.now() / 1000)
    await db.prepare('INSERT INTO users (id, apple_sub, created_at, updated_at) VALUES (?, ?, 1, 1)')
        .bind(owner, `test-${owner}`).run()
    await db.prepare(`INSERT INTO native_sessions (id, user_id, access_token_hash, refresh_token_hash,
        created_at, updated_at, access_expires_at, refresh_expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`)
        .bind(sha(`session-${owner}`).slice(0, 43), owner, sha(bearer), sha(`refresh-${bearer}`), now, now, now + 3600, now + 7200).run()
}

describe('native shopping synchronization with local D1 only', { concurrency: false }, () => {
    before(async () => {
        temporaryDirectory = await mkdtemp(join(tmpdir(), 'lifelify-shopping-sync-'))
        const harness = `import {handleShoppingSynchronization} from './src/shopping-sync';
            import {createShoppingItem} from './src/shopping';
            export default { async fetch(request, env) {
                if (new URL(request.url).pathname === '/test/mcp-create') {
                    return Response.json(await createShoppingItem(env.DB, '${user}', await request.json()));
                }
                if (request.headers.get('X-Test-Revoke-After-Resolution')
                    || request.headers.get('X-Test-Rotate-After-Resolution')
                    || request.headers.get('X-Test-Delete-User-After-Resolution')) {
                    const database = env.DB;
                    env = {...env, DB: {prepare: database.prepare.bind(database), async batch(statements) {
                        if (request.headers.get('X-Test-Revoke-After-Resolution')) {
                            await database.prepare('UPDATE native_sessions SET revoked_at = 1').run();
                        } else if (request.headers.get('X-Test-Rotate-After-Resolution')) {
                            await database.prepare('UPDATE native_sessions SET access_token_hash = ? WHERE user_id = ?')
                                .bind('${sha('C'.repeat(43))}', '${user}').run();
                        } else {
                            await database.prepare('UPDATE users SET deleted_at = 1 WHERE id = ?').bind('${user}').run();
                        }
                        return database.batch(statements);
                    }}};
                }
                return handleShoppingSynchronization(request, env);
            }};`
        const script = (await build({ stdin: { contents: harness, resolveDir: project, loader: 'ts' },
            bundle: true, format: 'esm', platform: 'browser', target: 'es2022', external: ['node:*', 'cloudflare:*'],
            logLevel: 'silent', write: false })).outputFiles[0].text
        runtime = new Miniflare(convertV4MiniflareOptions({ name: 'shopping-sync', modules: true, script,
            compatibilityDate: '2026-10-10', compatibilityFlags: ['nodejs_compat', 'global_fetch_strictly_public'],
            bindings: { AUTH_MODE: 'apple', APPLE_APP_ID: 'test.lifelify.native' }, d1Databases: { DB: 'shopping-sync' },
            resourcePersistencePath: temporaryDirectory, cf: false, telemetry: { enabled: false }, logRequests: false,
            outboundService() { throw new Error('Real network is forbidden in synchronization tests') } }))
        db = await runtime.getD1Database('DB')
        const schema = await readFile(join(project, '../docs/cloudflare-shopping/schema.sql'), 'utf8')
        const nativeMigration = await readFile(join(project, 'migrations/0002_native_auth.sql'), 'utf8')
        syncMigration = await readFile(join(project, 'migrations/0004_shopping_sync.sql'), 'utf8')
        await execute(schema)
        await execute(nativeMigration)
        await execute(syncMigration)
    })
    beforeEach(async () => {
        await db.batch(['DELETE FROM shopping_items', 'DELETE FROM shopping_places', 'DELETE FROM shopping_changes',
            'DELETE FROM shopping_mutation_receipts', 'DELETE FROM native_sessions', 'DELETE FROM users']
            .map(sql => db.prepare(sql)))
        await session(user, token)
        await session(otherUser, otherToken)
    })
    after(async () => {
        await runtime?.dispose()
        if (temporaryDirectory) await rm(temporaryDirectory, { recursive: true, force: true })
    })

    it('uploads stable local identities and dates, and separates the same UUID across accounts', async () => {
        const localPlace = place(), localItem = item('牛乳')
        await applied(localPlace)
        localItem.data.place_id = localPlace.id
        const first = await applied(localItem)
        assert.equal(first.record.created_at, 1000)
        assert.equal(first.record.place_id, localPlace.id)
        assert.equal(first.record.version, 1)
        const other = item('Private item', { id: localItem.id })
        await applied(other, { bearer: otherToken })
        const page = await pull()
        assert.deepEqual(page.changes.map(value => value.entity), ['place', 'item'])
        assert.equal(JSON.stringify(page).includes('Private item'), false)
        assert.equal((await pull(0, 100, { bearer: otherToken })).changes.length, 1)
        assert.equal((await send({ ...localItem, user_id: otherUser })).status, 400)
        assert.equal((await request('/changes?user_id=' + otherUser)).status, 400)
    })

    it('paginates more than 100 changes using a sequence cursor even when timestamps are identical', async () => {
        const statements = Array.from({ length: 215 }, (_, index) => db.prepare(`INSERT INTO shopping_items
            (id, user_id, title, created_at, updated_at) VALUES (?, ?, ?, 1, 1)`)
            .bind(randomUUID(), user, `Item ${index}`))
        for (let index = 0; index < statements.length; index += 50) await db.batch(statements.slice(index, index + 50))
        let cursor = 0, all = [], hasMore = true
        while (hasMore) {
            const page = await pull(cursor)
            assert.ok(page.changes.length <= 100)
            all.push(...page.changes)
            assert.ok(page.next_cursor > cursor)
            cursor = page.next_cursor
            hasMore = page.has_more
        }
        assert.equal(all.length, 215)
        assert.equal(new Set(all.map(value => value.seq)).size, 215)
        assert.deepEqual(await pull(cursor), { changes: [], next_cursor: cursor, has_more: false })
    })

    it('replays a lost acknowledgement without duplicate rows or changes and rejects payload reuse', async () => {
        const local = item()
        const first = await applied(local), replay = await applied(local)
        assert.deepEqual(replay, first)
        assert.equal((await pull()).changes.length, 1)
        const other = { ...local, data: { ...local.data, note: 'changed' } }
        const response = await send(other)
        assert.equal(response.status, 409)
        assert.deepEqual(await response.json(), { error: 'idempotency_conflict' })
        const sameNewOperation = await applied({ ...local, operation_id: randomUUID() })
        assert.deepEqual(sameNewOperation, first)
        assert.equal((await pull()).changes.length, 1)
    })

    it('permits exactly one concurrent CAS writer and returns the winning version to the loser', async () => {
        const local = item()
        await applied(local)
        const variants = ['first', 'second'].map(note => ({ ...local, operation_id: randomUUID(), base_version: 1,
            data: { ...local.data, note } }))
        const replies = await Promise.all(variants.map(value => send(value)))
        assert.deepEqual(replies.map(value => value.status).sort(), [200, 409])
        const winner = await replies.find(value => value.status === 200).json()
        const loser = await replies.find(value => value.status === 409).json()
        assert.equal(loser.error, 'version_conflict')
        assert.deepEqual(loser.record, winner.record)
        assert.equal(winner.record.version, 2)
        assert.equal((await pull()).changes.length, 2)
    })

    it('retains deletion tombstones and restores the same ID only with its current deleted version', async () => {
        const local = item()
        await applied(local)
        const deletion = { ...local, operation_id: randomUUID(), base_version: 1, deleted: true, data: null }
        const deleted = await applied(deletion)
        assert.ok(deleted.record.deleted_at)
        assert.equal(deleted.record.version, 2)
        assert.equal((await send({ ...local, operation_id: randomUUID(), base_version: 1 })).status, 409)
        const restored = await applied({ ...local, operation_id: randomUUID(), base_version: 2 })
        assert.equal(restored.record.id, local.id)
        assert.equal(restored.record.version, 3)
        assert.equal(restored.record.deleted_at, null)
        assert.deepEqual(await applied(deletion), deleted, 'A delayed duplicate delete returns its old receipt, not a second deletion')
        assert.equal((await pull()).changes.length, 3)
    })

    it('atomically deletes a place, unassigns active items, and emits all affected versions', async () => {
        const localPlace = place(), localItem = item()
        await applied(localPlace)
        localItem.data.place_id = localPlace.id
        await applied(localItem)
        const cursor = (await pull()).next_cursor
        const removal = { ...localPlace, operation_id: randomUUID(), base_version: 1, deleted: true, data: null }
        await applied(removal)
        const page = await pull(cursor)
        assert.deepEqual(page.changes.map(value => value.entity), ['place', 'item'])
        assert.equal(page.changes[0].record.version, 2)
        assert.equal(page.changes[1].record.version, 2)
        assert.equal(page.changes[1].record.place_id, null)
        assert.equal(page.changes[1].record.deleted_at, null)
        await applied(removal)
        assert.equal((await pull(cursor)).changes.length, 2)
        const bad = await send(item('bad', { data: { ...localItem.data, title: 'bad' } }))
        assert.equal(bad.status, 409)
        assert.equal((await bad.json()).error, 'place_unavailable')
    })

    it('rolls back a place deletion and its receipt if an item-cascade trigger fails', async () => {
        const localPlace = place(), localItem = item()
        await applied(localPlace)
        localItem.data.place_id = localPlace.id
        await applied(localItem)
        await execute(`CREATE TRIGGER test_fail_cascade BEFORE UPDATE ON shopping_items
            BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END;`)
        try {
            const input = { ...localPlace, operation_id: randomUUID(), base_version: 1, deleted: true, data: null }
            assert.equal((await send(input)).status, 503)
            const unchanged = await db.prepare('SELECT version, deleted_at FROM shopping_places WHERE id = ?').bind(localPlace.id).first()
            assert.deepEqual(unchanged, { version: 1, deleted_at: null })
            assert.equal((await pull()).changes.length, 2)
            assert.equal((await db.prepare('SELECT count(*) AS n FROM shopping_mutation_receipts WHERE operation_id = ?')
                .bind(input.operation_id).first()).n, 0)
        } finally { await execute('DROP TRIGGER test_fail_cascade;') }
    })

    it('backfills legacy rows once and captures writes from the existing MCP creation function', async () => {
        await execute('DROP TRIGGER shopping_items_sync_insert;')
        const id = randomUUID()
        await db.prepare('INSERT INTO shopping_items (id, user_id, title, created_at, updated_at) VALUES (?, ?, ?, 1, 1)')
            .bind(id, user, 'Existing legacy item').run()
        assert.equal((await pull()).changes.length, 0)
        await execute(syncMigration)
        await execute(syncMigration)
        assert.equal((await pull()).changes.length, 1)
        const response = await runtime.dispatchFetch(`${origin}/test/mcp-create`, { method: 'POST',
            body: JSON.stringify({ title: 'MCP item', note: '3個', place_id: null }) })
        assert.equal(response.status, 200)
        const created = await response.json()
        assert.equal((await pull()).changes.at(-1).record.id, created.id)
    })

    it('normalizes uppercase legacy UUIDs without breaking their existing foreign keys', async () => {
        const placeID = randomUUID().toUpperCase(), itemID = randomUUID().toUpperCase()
        await db.prepare('INSERT INTO shopping_places (id, user_id, name, created_at, updated_at) VALUES (?, ?, ?, 1, 1)')
            .bind(placeID, user, 'Legacy').run()
        const input = item('Upper', { id: itemID, data: { title: 'Upper', note: '', place_id: placeID, created_at: 1 } })
        const created = await applied(input)
        assert.equal(created.record.id, itemID.toLowerCase())
        assert.equal(created.record.place_id, placeID.toLowerCase())
        assert.equal((await db.prepare('SELECT place_id FROM shopping_items WHERE lower(id) = ?').bind(itemID.toLowerCase()).first()).place_id, placeID)
        await applied({ ...input, operation_id: randomUUID(), id: itemID.toLowerCase(), base_version: 1 })
        const updated = await applied(place('Renamed', { id: placeID.toLowerCase(), base_version: 1 }))
        assert.equal(updated.record.id, placeID.toLowerCase())
    })

    it('rejects malformed, oversized, unknown-field and duplicate-key JSON before any writes', async () => {
        const input = item()
        const serialized = JSON.stringify(input)
        const invalid = ['{', serialized.replace('"entity":"item"', '"entity":"place","entity":"item"'),
            serialized.replace('"note":"6個"', '"note":"x","n\\u006fte":"6個"'),
            { ...input, unexpected: 1 }, { ...input, data: { ...input.data, user_id: otherUser } },
            { ...input, base_version: -1 }, { ...input, base_version: 1.5 }, { ...input, deleted: true },
            { ...input, data: { ...input.data, title: ' ' } }, { ...input, data: { ...input.data, place_id: 'bad' } }]
        for (const body of invalid) assert.equal((await send(body)).status, 400, JSON.stringify(body))
        assert.equal((await send(' '.repeat(70_000))).status, 413)
        for (const query of ['after=-1', 'after=1.5', 'after=1&after=2', 'limit=101', 'limit=0']) {
            assert.equal((await request('/changes?' + query)).status, 400)
        }
        assert.equal((await pull()).changes.length, 0)
    })

    it('accepts the documented field limits even when valid JSON needs six-byte character escapes', async () => {
        const input = item('\u0001'.repeat(200), {
            data: { title: '\u0001'.repeat(200), note: '\u0000'.repeat(4000), place_id: null, created_at: 1 }
        })
        assert.ok(Buffer.byteLength(JSON.stringify(input)) > 24 * 1024)
        const result = await applied(input)
        assert.equal(result.record.title, input.data.title)
        assert.equal(result.record.note, input.data.note)
        assert.deepEqual((await pull()).changes[0].record, result.record)
    })

    it('rejects inactive users, revoked sessions and token rotation between resolution and the transaction', async () => {
        const input = item()
        await db.prepare('UPDATE users SET deleted_at = 1 WHERE id = ?').bind(user).run()
        assert.equal((await send(input)).status, 401)
        assert.equal((await request('/changes')).status, 401)
        await db.prepare('UPDATE users SET deleted_at = NULL WHERE id = ?').bind(user).run()
        assert.equal((await send(input, { headers: { 'X-Test-Delete-User-After-Resolution': '1' } })).status, 401)
        assert.equal((await db.prepare('SELECT count(*) AS n FROM shopping_items').first()).n, 0)
        await db.prepare('UPDATE users SET deleted_at = NULL WHERE id = ?').bind(user).run()
        assert.equal((await send(input, { headers: { 'X-Test-Revoke-After-Resolution': '1' } })).status, 401)
        assert.equal((await db.prepare('SELECT count(*) AS n FROM shopping_items').first()).n, 0)
        assert.equal((await db.prepare('SELECT count(*) AS n FROM shopping_mutation_receipts').first()).n, 0)
        await db.prepare('UPDATE native_sessions SET revoked_at = NULL WHERE user_id = ?').bind(user).run()
        assert.equal((await send(input, { headers: { 'X-Test-Rotate-After-Resolution': '1' } })).status, 401)
        assert.equal((await db.prepare('SELECT count(*) AS n FROM shopping_items').first()).n, 0)
        assert.equal((await db.prepare('SELECT count(*) AS n FROM shopping_mutation_receipts').first()).n, 0)
        assert.equal((await send(input)).status, 401)
        assert.equal((await send(input, { bearer: 'C'.repeat(43) })).status, 200)
    })
})
