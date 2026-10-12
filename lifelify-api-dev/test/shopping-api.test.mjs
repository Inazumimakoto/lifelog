import assert from 'node:assert/strict'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { after, before, beforeEach, describe, it } from 'node:test'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'
import { convertV4MiniflareOptions, Miniflare } from 'miniflare'

const projectDirectory = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const fixtureDirectory = resolve(projectDirectory, '../docs/cloudflare-shopping')
const token = '0123456789abcdef'.repeat(4) // Test-only: never reads .dev.vars.
const path = '/api/shopping/items'
const placeID = '10000000-0000-4000-8000-000000000001'
const itemID = '20000000-0000-4000-8000-000000000001'
const otherPlaceID = '10000000-0000-4000-8000-000000000002'
const missingPlaceID = '10000000-0000-4000-8000-000000000099'
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

let temporaryDirectory
let bundlePath
let bundledScript
let miniflare
let database
let seedSQL

function createRuntime(name, bindings = { DEV_API_TOKEN: token }) {
  // Standalone Miniflare deliberately never loads wrangler.jsonc or remote D1.
  return new Miniflare(convertV4MiniflareOptions({
    name,
    modules: true,
    // Miniflare 5's legacy adapter fails to start this file-backed ESM bundle;
    // passing the identical built source avoids that adapter path.
    script: bundledScript,
    compatibilityDate: '2026-10-10',
    compatibilityFlags: ['nodejs_compat', 'global_fetch_strictly_public'],
    bindings,
    d1Databases: { DB: `${name}-local-d1` },
    resourcePersistencePath: join(temporaryDirectory, name),
    cf: false,
    telemetry: { enabled: false },
    logRequests: false,
    outboundService() {
      throw new Error('Network access is forbidden in shopping API tests')
    },
  }))
}

async function executeFixture(sql) {
  // These repository fixtures contain ordinary statements with no semicolons
  // inside string literals. Prepare separately to support their multiline SQL.
  for (const statement of sql.split(';').map(value => value.trim()).filter(Boolean)) {
    await database.prepare(statement).run()
  }
}

async function request(suffix = '', options = {}, runtime = miniflare) {
  const headers = new Headers(options.headers)
  if (!headers.has('Authorization')) headers.set('Authorization', `Bearer ${token}`)
  return runtime.dispatchFetch(`http://localhost${path}${suffix}`, { ...options, headers })
}

async function post(body, options = {}) {
  return request('', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    ...options,
  })
}

async function countItems() {
  const row = await database.prepare('SELECT COUNT(*) AS count FROM shopping_items').first()
  return row.count
}

async function addOtherUser() {
  await database.prepare(
    'INSERT INTO users (id, apple_sub, created_at, updated_at) VALUES (?, ?, ?, ?)'
  ).bind('other-user', 'test-other-apple-sub', 1000, 1000).run()
  await database.prepare(
    'INSERT INTO shopping_places (id, user_id, name, created_at, updated_at) VALUES (?, ?, ?, ?, ?)'
  ).bind(otherPlaceID, 'other-user', 'Private other-user place', 1000, 1000).run()
}

describe('shopping API with an isolated local D1 database', { concurrency: false }, () => {
  before(async () => {
    temporaryDirectory = await mkdtemp(join(tmpdir(), 'lifelify-shopping-api-'))
    bundlePath = join(temporaryDirectory, 'worker.mjs')
    await build({
      entryPoints: [join(projectDirectory, 'src/index.ts')],
      outfile: bundlePath,
      bundle: true,
      format: 'esm',
      platform: 'browser',
      target: 'es2022',
      external: ['node:*', 'cloudflare:*'],
      logLevel: 'silent',
    })
    bundledScript = await readFile(bundlePath, 'utf8')
    const [schemaSQL, seed] = await Promise.all([
      readFile(join(fixtureDirectory, 'schema.sql'), 'utf8'),
      readFile(join(fixtureDirectory, 'seed.dev.sql'), 'utf8'),
    ])
    seedSQL = seed
    miniflare = createRuntime('shopping-api-test')
    database = await miniflare.getD1Database('DB')
    await executeFixture(schemaSQL)
  })

  beforeEach(async () => {
    await database.prepare('DELETE FROM shopping_items').run()
    await database.prepare('DELETE FROM shopping_places').run()
    await database.prepare('DELETE FROM users').run()
    await executeFixture(seedSQL)
  })

  after(async () => {
    try {
      await miniflare?.dispose()
    } finally {
      if (temporaryDirectory) await rm(temporaryDirectory, { recursive: true, force: true })
    }
  })

  it('rejects missing or incorrect bearer tokens for reading and writing', async () => {
    for (const method of ['GET', 'POST']) {
      for (const [authorization, expectedStatus] of [[null, 401], ['Bearer wrong-token', 401], ['Basic invalid', 400]]) {
        const response = await miniflare.dispatchFetch(`http://localhost${path}`, {
          method,
          headers: authorization ? { Authorization: authorization } : {},
          ...(method === 'POST' ? { body: JSON.stringify({ title: 'Unauthorized' }) } : {}),
        })
        assert.equal(response.status, expectedStatus, `${method} with ${authorization}`)
        await response.text()
      }
    }
    assert.equal(await countItems(), 1)
  })

  it('fails closed when the development token binding is absent', async () => {
    const unconfigured = createRuntime('shopping-api-no-token', {})
    try {
      const response = await request('', {}, unconfigured)
      assert.equal(response.status, 503)
      await response.text()
    } finally {
      await unconfigured.dispose()
    }
  })

  it('lists only active owned items and does not allow request parameters to switch users', async () => {
    await addOtherUser()
    // The same item UUID in two accounts also exercises composite ownership.
    await database.prepare(
      'INSERT INTO shopping_items (id, user_id, title, place_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)'
    ).bind(itemID, 'other-user', 'Private other-user item', otherPlaceID, 1000, 1000).run()
    await database.prepare(
      'INSERT INTO shopping_items (id, user_id, title, created_at, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?)'
    ).bind('20000000-0000-4000-8000-000000000003', 'dev-user', 'Deleted item', 1000, 1000, 2000).run()

    const response = await request('?user_id=other-user', { headers: { 'X-User-ID': 'other-user' } })
    assert.equal(response.status, 200)
    const body = await response.json()
    assert.equal(body.has_more, false)
    assert.equal(body.items.length, 1)
    assert.equal(body.items[0].id, itemID)
    assert.equal(body.items[0].title, '卵')
    assert.equal(body.items[0].place_name, 'スーパー')
    assert.equal(JSON.stringify(body).includes('Private other-user'), false)
  })

  it('keeps owned items visible with a null place name after a place is soft-deleted', async () => {
    await database.prepare('UPDATE shopping_places SET deleted_at = ? WHERE user_id = ? AND id = ?')
      .bind(2000, 'dev-user', placeID).run()
    const response = await request()
    assert.equal(response.status, 200)
    const body = await response.json()
    assert.equal(body.items.length, 1)
    assert.equal(body.items[0].place_name, null)
  })

  it('creates a server-owned versioned UUID item, trims its title, and preserves memo whitespace', async () => {
    const note = '  2パック\n  500gずつ\n'
    const startedAt = Date.now()
    const response = await post({ title: '  牛乳  ', note, place_id: placeID })
    const finishedAt = Date.now()
    assert.equal(response.status, 201)
    const { item } = await response.json()
    assert.match(item.id, uuidPattern)
    assert.equal(item.title, '牛乳')
    assert.equal(item.note, note)
    assert.equal(item.place_id, placeID)
    assert.equal(item.version, 1)
    assert.equal(Number.isInteger(item.created_at), true)
    assert.ok(item.created_at >= startedAt && item.created_at <= finishedAt)
    assert.equal(item.updated_at, item.created_at)

    const saved = await database.prepare('SELECT * FROM shopping_items WHERE user_id = ? AND id = ?')
      .bind('dev-user', item.id).first()
    assert.equal(saved.user_id, 'dev-user')
    for (const key of ['id', 'title', 'note', 'place_id', 'created_at', 'updated_at', 'version']) {
      assert.equal(saved[key], item[key], `persisted ${key}`)
    }
    assert.equal(saved.deleted_at, null)
  })

  it('defaults an omitted memo and place, accepts an explicit null place, and permits duplicate titles', async () => {
    const ids = []
    for (const body of [{ title: 'パン' }, { title: 'パン', place_id: null }]) {
      const response = await post(body)
      assert.equal(response.status, 201)
      const { item } = await response.json()
      assert.equal(item.note, '')
      assert.equal(item.place_id, null)
      ids.push(item.id)
    }
    assert.notEqual(ids[0], ids[1])
    assert.equal(await countItems(), 3)
    const list = await (await request()).json()
    for (const id of ids) assert.equal(list.items.find(item => item.id === id).place_name, null)
  })

  it('stores SQL-looking text literally without changing other records', async () => {
    const title = "eggs'); DELETE FROM shopping_items; --"
    const response = await post({ title })
    assert.equal(response.status, 201)
    const { item } = await response.json()
    assert.equal(item.title, title)
    assert.equal(await countItems(), 2)
    const existing = await database.prepare('SELECT title FROM shopping_items WHERE user_id = ? AND id = ?')
      .bind('dev-user', itemID).first()
    assert.equal(existing.title, '卵')
  })

  it('rejects invalid JSON shapes, field types, lengths, and client-controlled fields without writes', async () => {
    const invalidBodies = [
      null, [], 'not an object', 123, {},
      { title: '' }, { title: ' \n\t ' }, { title: 7 }, { title: null },
      { title: '\u0000x' },
      { title: 'x'.repeat(201) },
      { title: 'Valid', note: null }, { title: 'Valid', note: 7 },
      { title: 'Valid', note: 'x'.repeat(4001) },
      { title: 'Valid', place_id: '' }, { title: 'Valid', place_id: 'not-a-uuid' },
      { title: 'Valid', place_id: 7 },
      { title: 'Valid', user_id: 'other-user' },
      { title: 'Valid', id: itemID },
      { title: 'Valid', created_at: 0 },
      { title: 'Valid', version: 99 },
      { title: 'Valid', quantity: '2' },
    ]
    for (const body of invalidBodies) {
      const response = await post(body)
      assert.equal(response.status, 400, `invalid body: ${JSON.stringify(body).slice(0, 100)}`)
      await response.text()
    }
    for (const body of ['{', '']) {
      const response = await post(undefined, { body })
      assert.equal(response.status, 400, `malformed JSON: ${body}`)
      await response.text()
    }
    assert.equal(await countItems(), 1)
  })

  it('accepts title and memo at the stated maximum lengths', async () => {
    const response = await post({ title: 't'.repeat(200), note: 'n'.repeat(4000) })
    assert.equal(response.status, 201)
    const { item } = await response.json()
    assert.equal(item.title.length, 200)
    assert.equal(item.note.length, 4000)
  })

  it('rejects a body over 16 KiB before inserting an item', async () => {
    const response = await post({ title: 'Too large', note: 'x'.repeat(16 * 1024 + 1) })
    assert.equal(response.status, 413)
    await response.text()
    assert.equal(await countItems(), 1)
  })

  it('rejects missing, deleted, and other-user places without leaking their ownership', async () => {
    await addOtherUser()
    await database.prepare('UPDATE shopping_places SET deleted_at = ? WHERE user_id = ? AND id = ?')
      .bind(2000, 'dev-user', placeID).run()
    for (const unavailableID of [missingPlaceID, placeID, otherPlaceID]) {
      const response = await post({ title: 'Invalid place', place_id: unavailableID })
      assert.equal(response.status, 409, unavailableID)
      assert.equal((await response.json()).error, 'owner_or_place_unavailable')
    }
    assert.equal(await countItems(), 1)
  })

  it('rejects reads and writes for a soft-deleted or missing owner', async () => {
    await database.prepare('UPDATE users SET deleted_at = ? WHERE id = ?').bind(2000, 'dev-user').run()
    for (const response of [await request(), await post({ title: 'Deleted owner' })]) {
      assert.equal(response.status, 403)
      await response.text()
    }
    assert.equal(await countItems(), 1)

    await database.prepare('DELETE FROM shopping_items').run()
    await database.prepare('DELETE FROM shopping_places').run()
    await database.prepare('DELETE FROM users').run()
    for (const response of [await request(), await post({ title: 'Missing owner' })]) {
      assert.equal(response.status, 403)
      await response.text()
    }
    assert.equal(await countItems(), 0)
  })

  it('caps lists at 100 items and reports whether additional active owned items exist', async () => {
    const statements = Array.from({ length: 99 }, (_, index) => database.prepare(
      'INSERT INTO shopping_items (id, user_id, title, created_at, updated_at) VALUES (?, ?, ?, ?, ?)'
    ).bind(`30000000-0000-4000-8000-${String(index).padStart(12, '0')}`, 'dev-user', `Item ${index}`, 1000, 1000))
    await database.batch(statements)

    const exactly100Response = await request()
    assert.equal(exactly100Response.status, 200)
    const exactly100 = await exactly100Response.json()
    assert.equal(exactly100.items.length, 100)
    assert.equal(exactly100.has_more, false)

    const created = await post({ title: 'Item 101' })
    assert.equal(created.status, 201)
    await created.text()
    const moreResponse = await request()
    assert.equal(moreResponse.status, 200)
    const more = await moreResponse.json()
    assert.equal(more.items.length, 100)
    assert.equal(new Set(more.items.map(item => item.id)).size, 100)
    assert.equal(more.has_more, true)
  })
})
