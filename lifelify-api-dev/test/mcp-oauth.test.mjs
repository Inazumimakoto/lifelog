import assert from 'node:assert/strict'
import { createHash, generateKeyPairSync, randomBytes } from 'node:crypto'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { after, before, beforeEach, describe, it } from 'node:test'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'
import { convertV4MiniflareOptions, Miniflare } from 'miniflare'

const projectDirectory = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const fixtureDirectory = resolve(projectDirectory, '../docs/cloudflare-shopping')
const origin = 'https://lifelify-api-dev.inazumimakoto.workers.dev'
const resource = `${origin}/mcp`
const callback = 'https://chatgpt.com/connector_platform_oauth_redirect'
const developmentToken = '0123456789abcdef'.repeat(4) // Never reads .dev.vars.
const cimdURL = 'https://chatgpt.com/oauth/client.json'
const allScopes = ['shopping:read', 'shopping:write', 'offline_access']
const seedPlaceId = '10000000-0000-4000-8000-000000000001'
const appleUserId = '30000000-0000-4000-8000-000000000001'
const appleBindings = {
    AUTH_MODE: 'apple',
    APPLE_SERVICE_ID: 'me.inazu.lifelify.web.test',
    APPLE_TEAM_ID: 'TESTTEAM01',
    APPLE_KEY_ID: 'TESTKEY001',
    // Fresh test-only key: this file never reads a developer's Apple credentials.
    APPLE_PRIVATE_KEY: generateKeyPairSync('ec', {
        namedCurve: 'prime256v1',
        privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
        publicKeyEncoding: { type: 'spki', format: 'pem' },
    }).privateKey,
}
let temporaryDirectory
let miniflare
let database
let seedSQL
let bundledScript

function runtimeOptions(name, bindings = { DEV_API_TOKEN: developmentToken }) {
    return convertV4MiniflareOptions({
        name,
        modules: true,
        script: bundledScript,
        compatibilityDate: '2026-10-10',
        compatibilityFlags: ['nodejs_compat', 'global_fetch_strictly_public'],
        bindings,
        d1Databases: { DB: `${name}-d1` },
        kvNamespaces: ['OAUTH_KV'],
        resourcePersistencePath: join(temporaryDirectory, name),
        cf: false,
        telemetry: { enabled: false },
        logRequests: false,
        outboundService(request) {
            // Simulate ChatGPT CIMD without making any outbound network request.
            if (request.url === cimdURL) {
                return Response.json({
                    client_id: cimdURL,
                    client_name: 'ChatGPT test client',
                    redirect_uris: [callback],
                    token_endpoint_auth_method: 'none',
                }, { headers: { 'Cache-Control': 'public, max-age=300' } })
            }
            throw new Error('Outbound network is forbidden in MCP OAuth tests')
        },
    })
}

function runtime(name, bindings = { DEV_API_TOKEN: developmentToken }) {
    return new Miniflare(runtimeOptions(name, bindings))
}

async function fixture(sql) {
    for (const statement of sql.split(';').map(value => value.trim()).filter(Boolean)) {
        await database.prepare(statement).run()
    }
}

function request(path, options = {}, target = miniflare) {
    // dispatchFetch's host-side fetch also follows redirects unless overridden.
    // Inspect the OAuth callback locally; never navigate to the real ChatGPT site.
    const headers = new Headers(options.headers)
    headers.set('Host', new URL(origin).host)
    return target.dispatchFetch(`${origin}${path}`, { redirect: 'manual', ...options, headers })
}

async function register(redirect = callback, name = 'Shopping test client') {
    return request('/oauth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            client_name: name,
            redirect_uris: [redirect],
            grant_types: ['authorization_code', 'refresh_token'],
            response_types: ['code'],
            token_endpoint_auth_method: 'none',
        }),
    })
}

async function startConsent({ scopes = allScopes, clientId, name, overrides = {} } = {}) {
    if (!clientId) {
        const registered = await register(callback, name)
        assert.equal(registered.status, 201)
        clientId = (await registered.json()).client_id
    }
    const verifier = randomBytes(32).toString('base64url')
    const parameters = new URLSearchParams({
        client_id: clientId,
        redirect_uri: callback,
        response_type: 'code',
        state: 'local-test-state',
        scope: scopes.join(' '),
        resource,
        code_challenge: createHash('sha256').update(verifier).digest('base64url'),
        code_challenge_method: 'S256',
        ...overrides,
    })
    const response = await request(`/authorize?${parameters}`)
    const html = await response.text()
    const cookie = response.headers.get('Set-Cookie')?.split(';')[0]
    const handle = html.match(/name="handle"\s+value="([^"]+)"/)?.[1]
    return { response, html, cookie, handle, verifier, clientId, scopes }
}

function submitConsent(consent, { token = developmentToken, decision = 'approve',
    cookie = consent.cookie, browserOrigin = origin } = {}) {
    const body = new URLSearchParams({ handle: consent.handle ?? '', decision, credential: token })
    const headers = { 'Content-Type': 'application/x-www-form-urlencoded', Origin: browserOrigin }
    if (cookie) headers.Cookie = cookie
    return request('/authorize', { method: 'POST', headers, body: body.toString() })
}

async function tokenRequest(parameters) {
    return request('/oauth/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams(parameters).toString(),
    })
}

async function authorize(options = {}) {
    const consent = await startConsent(options)
    assert.equal(consent.response.status, 200, consent.html)
    assert.ok(consent.handle)
    const response = await submitConsent(consent)
    assert.equal(response.status, 303, await response.clone().text())
    const redirect = new URL(response.headers.get('Location'))
    assert.equal(redirect.origin + redirect.pathname, callback)
    assert.equal(redirect.searchParams.get('state'), 'local-test-state')
    assert.equal(redirect.searchParams.get('iss'), origin)
    const code = redirect.searchParams.get('code')
    assert.ok(code)
    const exchanged = await tokenRequest({ grant_type: 'authorization_code', client_id: consent.clientId,
        code, code_verifier: consent.verifier, redirect_uri: callback, resource })
    assert.equal(exchanged.status, 200, await exchanged.clone().text())
    return { ...await exchanged.json(), clientId: consent.clientId, consent, code }
}

async function rpc(method, params, accessToken, options = {}) {
    const headers = { 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream' }
    if (accessToken) headers.Authorization = `Bearer ${accessToken}`
    return request('/mcp', {
        method: 'POST',
        headers: { ...headers, ...options.headers },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, ...(params ? { params } : {}) }),
    })
}

async function rpcResult(response) {
    assert.equal(response.status, 200, await response.clone().text())
    const text = await response.text()
    const data = response.headers.get('Content-Type')?.includes('text/event-stream')
        ? JSON.parse(text.split('\n').find(line => line.startsWith('data: ')).slice(6))
        : JSON.parse(text)
    return data
}

async function countItems() {
    return (await database.prepare('SELECT COUNT(*) AS count FROM shopping_items').first()).count
}

async function withBindings(bindings, operation) {
    await miniflare.setOptions(runtimeOptions('mcp-oauth-test', bindings))
    database = await miniflare.getD1Database('DB')
    try { return await operation() }
    finally {
        await miniflare.setOptions(runtimeOptions('mcp-oauth-test'))
        database = await miniflare.getD1Database('DB')
    }
}

async function activeGrant(props, expectedUserId) {
    const response = await request('/__test/resolve-active-grant', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ props, expectedUserId }),
    })
    assert.equal(response.status, 200, await response.clone().text())
    return response.json()
}

describe('private MCP OAuth with isolated D1 and KV', { concurrency: false }, () => {
    before(async () => {
        temporaryDirectory = await mkdtemp(join(tmpdir(), 'lifelify-mcp-oauth-'))
        const bundlePath = join(temporaryDirectory, 'worker.mjs')
        // Miniflare 5's dispatchFetch preserves the original URL but replaces Host
        // with its local proxy socket. Restore the host Cloudflare would provide,
        // in the test entrypoint only; keep production DNS-rebinding checks strict.
        const testEntrypoint = `import worker from './src/index.ts';
            import { getAuthenticationMode, resolveActiveGrantUser } from './src/auth.ts';
            export default { async fetch(request, env, ctx) {
                const headers = new Headers(request.headers);
                headers.set('Host', new URL(request.url).host);
                if (new URL(request.url).pathname === '/__test/resolve-active-grant') {
                    const { props, expectedUserId } = await request.json();
                    return Response.json({ mode: getAuthenticationMode(env),
                        userId: await resolveActiveGrantUser(env, props, expectedUserId) });
                }
                return worker.fetch(new Request(request, { headers }), env, ctx);
            }};`
        await build({ stdin: { contents: testEntrypoint, resolveDir: projectDirectory, loader: 'ts' }, outfile: bundlePath,
            bundle: true, format: 'esm', platform: 'browser', conditions: ['workerd'], target: 'es2022',
            external: ['node:*', 'cloudflare:*'], logLevel: 'silent' })
        bundledScript = await readFile(bundlePath, 'utf8')
        const [schema, seed] = await Promise.all([
            readFile(join(fixtureDirectory, 'schema.sql'), 'utf8'),
            readFile(join(fixtureDirectory, 'seed.dev.sql'), 'utf8'),
        ])
        seedSQL = seed
        miniflare = runtime('mcp-oauth-test')
        database = await miniflare.getD1Database('DB')
        await fixture(schema)
    })

    beforeEach(async () => {
        await database.prepare('DELETE FROM shopping_items').run()
        await database.prepare('DELETE FROM shopping_places').run()
        await database.prepare('DELETE FROM users').run()
        await fixture(seedSQL)
    })

    after(async () => {
        try { await miniflare?.dispose() }
        finally { if (temporaryDirectory) await rm(temporaryDirectory, { recursive: true, force: true }) }
    })

    it('advertises OAuth discovery and challenges unauthenticated MCP without exposing data', async () => {
        const response = await rpc('tools/list')
        assert.equal(response.status, 401)
        const challenge = response.headers.get('WWW-Authenticate')
        assert.match(challenge, /resource_metadata="([^"]+)"/)
        const metadataURL = challenge.match(/resource_metadata="([^"]+)"/)[1]
        const metadata = await (await miniflare.dispatchFetch(metadataURL)).json()
        assert.equal(metadata.resource, resource)
        assert.deepEqual(metadata.authorization_servers, [origin])
        const authorization = await (await request('/.well-known/oauth-authorization-server')).json()
        assert.equal(authorization.issuer, origin)
        assert.equal(authorization.authorization_response_iss_parameter_supported, true)
        assert.equal(authorization.client_id_metadata_document_supported, true)
        assert.deepEqual(authorization.code_challenge_methods_supported, ['S256'])
        assert.equal(await countItems(), 1)
    })

    it('does not accept the development REST token as an MCP access token', async () => {
        const response = await rpc('tools/call', { name: 'add_shopping_item', arguments: { title: 'Denied' } }, developmentToken)
        assert.equal(response.status, 401)
        await response.text()
        assert.equal(await countItems(), 1)
    })

    it('rejects registrations outside the permitted ChatGPT redirect URLs', async () => {
        for (const redirect of ['https://evil.example/callback', 'https://chatgpt.com.evil.example/connector_platform_oauth_redirect',
            'https://chatgpt.com/connector_platform_oauth_redirect?next=evil', 'https://chatgpt.com/other']) {
            const response = await register(redirect)
            assert.equal(response.status, 400, redirect)
            await response.text()
        }
    })

    it('escapes client metadata and binds consent to a secure browser cookie', async () => {
        const consent = await startConsent({ name: '<script>alert(1)</script>' })
        assert.equal(consent.response.status, 200)
        assert.equal(consent.html.includes('<script>alert(1)</script>'), false)
        assert.match(consent.html, /(?:&lt;|&#60;)script/)
        assert.equal(consent.html.includes(developmentToken), false)
        const cookie = consent.response.headers.get('Set-Cookie')
        assert.match(cookie, /__Host-/)
        assert.match(cookie, /HttpOnly/i)
        assert.match(cookie, /Secure/i)
        assert.match(cookie, /SameSite=Lax/i)
        assert.match(consent.response.headers.get('Content-Security-Policy'), /frame-ancestors 'none'/)
        assert.equal(consent.response.headers.get('Referrer-Policy'), 'strict-origin')
        for (const parameters of [{ cookie: null }, { browserOrigin: 'https://evil.example' }]) {
            const denied = await submitConsent(consent, parameters)
            assert.ok([400, 403].includes(denied.status))
            assert.equal(denied.headers.has('Location'), false)
            await denied.text()
        }
    })

    it('rejects missing or plain PKCE, and another resource audience', async () => {
        for (const overrides of [{ code_challenge: '', code_challenge_method: '' },
            { code_challenge_method: 'plain' }, { resource: 'https://other.example/mcp' }]) {
            const consent = await startConsent({ overrides })
            assert.ok([400, 302].includes(consent.response.status))
            if (consent.response.status === 302) {
                assert.ok(new URL(consent.response.headers.get('Location')).searchParams.get('error'))
            }
            assert.equal(consent.html.includes('name="handle"'), false)
        }
    })

    it('rejects wrong login credentials and prevents consent-handle replay', async () => {
        const consent = await startConsent()
        const wrong = await submitConsent(consent, { token: 'wrong' })
        assert.ok([400, 401, 403].includes(wrong.status))
        assert.equal(wrong.headers.has('Location'), false)
        await wrong.text()
        // Open a fresh consent transaction after a failed password attempt.
        const fresh = await startConsent()
        const approved = await submitConsent(fresh)
        assert.equal(approved.status, 303)
        const replay = await submitConsent(fresh)
        assert.ok([400, 403].includes(replay.status))
        assert.equal(replay.headers.has('Location'), false)
        await replay.text()
    })

    it('returns a valid issuer-bound denial without requiring a login token', async () => {
        const consent = await startConsent()
        const denied = await submitConsent(consent, { token: '', decision: 'deny' })
        assert.equal(denied.status, 303)
        const location = new URL(denied.headers.get('Location'))
        assert.equal(location.searchParams.get('error'), 'access_denied')
        assert.equal(location.searchParams.get('iss'), origin)
        assert.equal(location.searchParams.get('state'), 'local-test-state')
        assert.equal(location.searchParams.has('code'), false)
    })

    it('issues resource-bound tokens, lists metadata and creates a shopping item via MCP', async () => {
        const auth = await authorize()
        assert.equal(auth.token_type.toLowerCase(), 'bearer')
        assert.equal(auth.resource, resource)
        assert.ok(auth.refresh_token)
        const initialize = await rpcResult(await rpc('initialize', {
            protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'Local test', version: '1.0' },
        }, auth.access_token))
        assert.ok(initialize.result.serverInfo)
        const listing = await rpcResult(await rpc('tools/list', {}, auth.access_token))
        assert.deepEqual(listing.result.tools.map(tool => tool.name).sort(), ['add_shopping_item', 'list_shopping_items', 'list_shopping_places'])
        const addTool = listing.result.tools.find(tool => tool.name === 'add_shopping_item')
        assert.equal(addTool.annotations.readOnlyHint, false)
        assert.equal(addTool.annotations.idempotentHint, false)
        assert.ok(addTool.inputSchema.required.includes('place_id'))
        const placesTool = listing.result.tools.find(tool => tool.name === 'list_shopping_places')
        assert.equal(placesTool.annotations.readOnlyHint, true)
        assert.equal(placesTool.annotations.idempotentHint, true)
        assert.deepEqual(placesTool._meta.securitySchemes, [{ type: 'oauth2', scopes: ['shopping:read'] }])
        const added = await rpcResult(await rpc('tools/call', {
            name: 'add_shopping_item', arguments: { title: '  牛乳  ', note: '  1リットルを1本\n', place_id: null },
        }, auth.access_token))
        assert.equal(added.result.isError ?? false, false)
        const saved = added.result.structuredContent
        assert.equal(saved.item.title, '牛乳')
        assert.equal(saved.item.note, '  1リットルを1本\n')
        assert.equal(saved.item.place_id, null)
        const rows = await rpcResult(await rpc('tools/call', { name: 'list_shopping_items', arguments: {} }, auth.access_token))
        assert.ok(rows.result.structuredContent.items.some(item => item.id === saved.item.id))
        assert.equal(await countItems(), 2)
    })

    it('protects tool writes from read-only grants and supplies an OAuth scope challenge', async () => {
        const auth = await authorize({ scopes: ['shopping:read'] })
        const result = await rpcResult(await rpc('tools/call', {
            name: 'add_shopping_item', arguments: { title: 'Denied write', place_id: null },
        }, auth.access_token))
        assert.equal(result.result.isError, true)
        const challenge = result.result._meta['mcp/www_authenticate'][0]
        assert.match(challenge, /scope="shopping:read shopping:write"/)
        const metadataURL = challenge.match(/resource_metadata="([^"]+)"/)[1]
        const metadataResponse = await miniflare.dispatchFetch(metadataURL, { redirect: 'manual' })
        assert.equal(metadataResponse.status, 200)
        assert.equal((await metadataResponse.json()).resource, resource)
        assert.equal(await countItems(), 1)
    })

    it('rejects unknown tool arguments and rechecks active user after token issuance', async () => {
        const auth = await authorize()
        for (const argumentsValue of [{ title: 'Bad', user_id: 'other-user', place_id: null },
            { title: '\u0000', place_id: null }, { title: '   ', place_id: null },
            { title: 'Too long', note: 'x'.repeat(4001), place_id: null }]) {
            const result = await rpcResult(await rpc('tools/call', { name: 'add_shopping_item', arguments: argumentsValue }, auth.access_token))
            assert.ok(result.error || result.result?.isError)
        }
        assert.equal(await countItems(), 1)
        await database.prepare('UPDATE users SET deleted_at = 1000 WHERE id = ?').bind('dev-user').run()
        for (const name of ['list_shopping_items', 'list_shopping_places', 'add_shopping_item']) {
            const response = await rpc('tools/call', { name, arguments: name === 'add_shopping_item' ? { title: 'Denied', place_id: null } : {} }, auth.access_token)
            assert.equal(response.status, 403)
            assert.deepEqual(await response.json(), { error: 'user_unavailable' })
        }
        assert.equal(await countItems(), 1)
    })

    it('lists only the active account\'s purchase places in stable display order with a read-only grant', async () => {
        const firstId = '10000000-0000-4000-8000-000000000031'
        const secondId = '10000000-0000-4000-8000-000000000032'
        await database.prepare('INSERT INTO users (id, apple_sub, created_at, updated_at) VALUES (?, ?, 1, 1)')
            .bind('other-user', 'other-sub').run()
        for (const [id, userId, name, orderIndex, deletedAt] of [
            [secondId, 'dev-user', 'Second tied place', -1, null],
            [firstId, 'dev-user', 'First tied place', -1, null],
            ['10000000-0000-4000-8000-000000000033', 'dev-user', 'Deleted place', -2, 1000],
            [firstId, 'other-user', 'Private other-account place', -3, null],
        ]) {
            await database.prepare('INSERT INTO shopping_places (id, user_id, name, order_index, created_at, updated_at, deleted_at) VALUES (?, ?, ?, ?, 1, 1, ?)')
                .bind(id, userId, name, orderIndex, deletedAt).run()
        }
        const auth = await authorize({ scopes: ['shopping:read'] })
        const response = await rpcResult(await rpc('tools/call', { name: 'list_shopping_places', arguments: {} }, auth.access_token))
        assert.equal(response.result.isError ?? false, false)
        assert.deepEqual(response.result.structuredContent, {
            places: [
                { id: firstId, name: 'First tied place', order_index: -1 },
                { id: secondId, name: 'Second tied place', order_index: -1 },
                { id: seedPlaceId, name: 'スーパー', order_index: 0 },
            ],
            has_more: false,
        })
        assert.equal(await countItems(), 1)
    })

    it('caps purchase-place discovery at 100 and reports that more candidates exist', async () => {
        await database.batch(Array.from({ length: 100 }, (_, index) => database.prepare(
            'INSERT INTO shopping_places (id, user_id, name, order_index, created_at, updated_at) VALUES (?, ?, ?, ?, 1, 1)'
        ).bind(`10000000-0000-4000-8000-${String(index + 100).padStart(12, '0')}`, 'dev-user', `Place ${index}`, index + 1)))
        const auth = await authorize({ scopes: ['shopping:read'] })
        const response = await rpcResult(await rpc('tools/call', { name: 'list_shopping_places', arguments: {} }, auth.access_token))
        assert.equal(response.result.isError ?? false, false)
        assert.equal(response.result.structuredContent.places.length, 100)
        assert.equal(response.result.structuredContent.has_more, true)
        assert.equal(response.result.structuredContent.places[0].id, seedPlaceId)
        assert.equal(response.result.structuredContent.places.at(-1).name, 'Place 98')
    })

    it('requires an explicit valid purchase-place selection before creating an item', async () => {
        const auth = await authorize()
        for (const argumentsValue of [
            { title: 'No selection' },
            { title: 'Bad selection', place_id: '' },
            { title: 'Bad selection', place_id: 'スーパー' },
            { title: 'Bad selection', place_id: 123 },
        ]) {
            const response = await rpcResult(await rpc('tools/call', { name: 'add_shopping_item', arguments: argumentsValue }, auth.access_token))
            assert.ok(response.error || response.result?.isError)
            assert.equal(await countItems(), 1)
        }
    })

    it('accepts an owned purchase place and atomically rejects other-account, deleted and nonexistent selections', async () => {
        const otherId = '10000000-0000-4000-8000-000000000041'
        const deletedId = '10000000-0000-4000-8000-000000000042'
        const missingId = '10000000-0000-4000-8000-000000000043'
        await database.prepare('INSERT INTO users (id, apple_sub, created_at, updated_at) VALUES (?, ?, 1, 1)')
            .bind('other-user', 'other-sub').run()
        for (const [id, userId, name, deletedAt] of [
            [otherId, 'other-user', 'Private other-account place', null],
            [seedPlaceId, 'other-user', 'Same ID in another account', null],
            [deletedId, 'dev-user', 'Deleted place', 1000],
        ]) {
            await database.prepare('INSERT INTO shopping_places (id, user_id, name, created_at, updated_at, deleted_at) VALUES (?, ?, ?, 1, 1, ?)')
                .bind(id, userId, name, deletedAt).run()
        }
        const auth = await authorize()
        for (const placeId of [otherId, deletedId, missingId]) {
            const response = await rpcResult(await rpc('tools/call', {
                name: 'add_shopping_item', arguments: { title: 'Denied place', place_id: placeId },
            }, auth.access_token))
            assert.equal(response.result.isError, true)
            assert.equal(await countItems(), 1)
        }
        const response = await rpcResult(await rpc('tools/call', {
            name: 'add_shopping_item', arguments: { title: 'リンゴ', note: '3つ', place_id: seedPlaceId },
        }, auth.access_token))
        assert.equal(response.result.isError ?? false, false)
        const item = response.result.structuredContent.item
        assert.equal(item.place_id, seedPlaceId)
        const saved = await database.prepare('SELECT user_id, place_id FROM shopping_items WHERE id = ?').bind(item.id).first()
        assert.deepEqual(saved, { user_id: 'dev-user', place_id: seedPlaceId })
        assert.equal(await countItems(), 2)
        const listing = await rpcResult(await rpc('tools/call', { name: 'list_shopping_items', arguments: {} }, auth.access_token))
        assert.equal(listing.result.structuredContent.items.find(row => row.id === item.id).place_name, 'スーパー')
    })

    it('does not leak another account through shopping tools', async () => {
        await database.prepare('INSERT INTO users (id, apple_sub, created_at, updated_at) VALUES (?, ?, 1, 1)')
            .bind('other-user', 'other-sub').run()
        await database.prepare('INSERT INTO shopping_items (id, user_id, title, created_at, updated_at) VALUES (?, ?, ?, 1, 1)')
            .bind('other-item', 'other-user', 'Private other-account item').run()
        const auth = await authorize()
        const result = await rpcResult(await rpc('tools/call', { name: 'list_shopping_items', arguments: {} }, auth.access_token))
        assert.equal(JSON.stringify(result).includes('Private other-account item'), false)
    })

    it('refreshes and revokes access without allowing token audience or scope escalation', async () => {
        const auth = await authorize({ scopes: ['shopping:read', 'offline_access'] })
        for (const extra of [{ resource: 'https://other.example/mcp' }, { scope: 'shopping:read shopping:write' }]) {
            const response = await tokenRequest({ grant_type: 'refresh_token', client_id: auth.clientId,
                refresh_token: auth.refresh_token, resource, ...extra })
            if ('resource' in extra) {
                assert.equal(response.status, 400)
                await response.text()
            } else {
                // The provider ignores attempts to expand a refresh's granted scopes.
                assert.equal(response.status, 200)
                const limited = await response.json()
                assert.equal(limited.scope.split(' ').includes('shopping:write'), false)
            }
        }
        const response = await tokenRequest({ grant_type: 'refresh_token', client_id: auth.clientId,
            refresh_token: auth.refresh_token, resource })
        assert.equal(response.status, 200, await response.clone().text())
        const renewed = await response.json()
        assert.notEqual(renewed.access_token, auth.access_token)
        assert.notEqual(renewed.refresh_token, auth.refresh_token)
        const usable = await rpc('tools/list', {}, renewed.access_token)
        assert.equal(usable.status, 200)
        await usable.text()
        const metadata = await (await request('/.well-known/oauth-authorization-server')).json()
        const revoked = await miniflare.dispatchFetch(metadata.revocation_endpoint, {
            method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ client_id: auth.clientId, token: renewed.refresh_token, token_type_hint: 'refresh_token' }).toString(),
        })
        assert.equal(revoked.status, 200)
        await revoked.text()
        const afterRevocation = await rpc('tools/list', {}, renewed.access_token)
        assert.equal(afterRevocation.status, 401)
        await afterRevocation.text()
    })

    it('rejects incorrect PKCE verifier and authorization-code reuse', async () => {
        const auth = await authorize()
        const replay = await tokenRequest({ grant_type: 'authorization_code', client_id: auth.clientId,
            code: auth.code, code_verifier: auth.consent.verifier, redirect_uri: callback, resource })
        assert.equal(replay.status, 400)
        await replay.text()
        const consent = await startConsent()
        const approved = await submitConsent(consent)
        const code = new URL(approved.headers.get('Location')).searchParams.get('code')
        const wrong = await tokenRequest({ grant_type: 'authorization_code', client_id: consent.clientId,
            code, code_verifier: randomBytes(32).toString('base64url'), redirect_uri: callback, resource })
        assert.equal(wrong.status, 400)
        await wrong.text()
    })

    it('uses ChatGPT Client ID Metadata Documents for the authorization flow', async () => {
        const auth = await authorize({ clientId: cimdURL })
        assert.ok(auth.access_token)
        const response = await rpc('tools/list', {}, auth.access_token)
        assert.equal(response.status, 200)
        await response.text()
    })

    it('fails closed when development login is unconfigured', async () => {
        const unconfigured = runtime('mcp-oauth-no-token', {})
        try {
            const response = await request('/authorize', {}, unconfigured)
            assert.equal(response.status, 503)
            await response.text()
        } finally { await unconfigured.dispose() }
    })

    it('preserves explicit development authentication as well as the unset default', async () => {
        await withBindings({ AUTH_MODE: 'development', DEV_API_TOKEN: developmentToken }, async () => {
            const auth = await authorize()
            const response = await rpcResult(await rpc('tools/call', { name: 'list_shopping_places', arguments: {} }, auth.access_token))
            assert.equal(response.result.isError ?? false, false)
            assert.equal(response.result.structuredContent.places[0].id, seedPlaceId)
        })
    })

    it('fails closed on an unknown mode or incomplete Apple setup despite a valid development secret', async () => {
        for (const mode of ['unknown', 'apple']) {
            const unconfigured = runtime(`mcp-oauth-mode-${mode}`, { AUTH_MODE: mode, DEV_API_TOKEN: developmentToken })
            try {
                for (const path of ['/authorize', '/oauth/register', '/oauth/token', '/mcp', '/auth/apple/start']) {
                    const response = await request(path, {}, unconfigured)
                    assert.equal(response.status, 503, `${mode}: ${path}`)
                    assert.deepEqual(await response.json(), { error: 'oauth_not_configured' })
                }
            } finally { await unconfigured.dispose() }
        }
    })

    it('rejects existing development access and refresh grants after switching the same D1 and KV to Apple mode', async () => {
        const auth = await authorize()
        await withBindings(appleBindings, async () => {
            const metadata = await request('/.well-known/oauth-authorization-server')
            assert.equal(metadata.status, 200, await metadata.clone().text())
            await metadata.text()
            const access = await rpc('tools/list', {}, auth.access_token)
            assert.equal(access.status, 403, await access.clone().text())
            assert.deepEqual(await access.json(), { error: 'user_unavailable' })
            const refresh = await tokenRequest({ grant_type: 'refresh_token', client_id: auth.clientId,
                refresh_token: auth.refresh_token, resource })
            assert.equal(refresh.status, 400, await refresh.clone().text())
            assert.equal((await refresh.json()).error, 'invalid_grant')
            assert.equal(await countItems(), 1)
        })
    })

    it('accepts legacy development grant properties only in development mode and checks the provider identity', async () => {
        for (const props of [{ userId: 'dev-user' }, { userId: 'dev-user', authMethod: 'development' }]) {
            assert.deepEqual(await activeGrant(props, 'dev-user'), { mode: 'development', userId: 'dev-user' })
        }
        for (const [props, expectedUserId] of [
            [{ userId: 'dev-user', authMethod: 'apple' }, 'dev-user'],
            [{ userId: 'dev-user' }, appleUserId],
            [{ userId: appleUserId, authMethod: 'development' }, appleUserId],
            [null, 'dev-user'], [[], 'dev-user'], [{}, 'dev-user'],
        ]) {
            assert.deepEqual(await activeGrant(props, expectedUserId), { mode: 'development', userId: null })
        }
        await database.prepare('UPDATE users SET deleted_at = 1000 WHERE id = ?').bind('dev-user').run()
        assert.deepEqual(await activeGrant({ userId: 'dev-user' }, 'dev-user'), { mode: 'development', userId: null })
    })

    it('accepts only matching active Apple identities and rejects legacy, development, unknown and deleted users', async () => {
        await database.prepare('INSERT INTO users (id, apple_sub, created_at, updated_at) VALUES (?, ?, 1, 1)')
            .bind(appleUserId, 'test-verified-apple-subject').run()
        await withBindings(appleBindings, async () => {
            assert.deepEqual(await activeGrant({ userId: appleUserId, authMethod: 'apple' }, appleUserId),
                { mode: 'apple', userId: appleUserId })
            for (const [props, expectedUserId] of [
                [{ userId: 'dev-user' }, 'dev-user'],
                [{ userId: 'dev-user', authMethod: 'development' }, 'dev-user'],
                [{ userId: 'dev-user', authMethod: 'apple' }, 'dev-user'],
                [{ userId: appleUserId }, appleUserId],
                [{ userId: appleUserId, authMethod: 'development' }, appleUserId],
                [{ userId: appleUserId, authMethod: 'apple' }, 'dev-user'],
                [{ userId: '30000000-0000-4000-8000-000000000099', authMethod: 'apple' }, '30000000-0000-4000-8000-000000000099'],
            ]) {
                assert.deepEqual(await activeGrant(props, expectedUserId), { mode: 'apple', userId: null })
            }
            await database.prepare('UPDATE users SET deleted_at = 1000 WHERE id = ?').bind(appleUserId).run()
            assert.deepEqual(await activeGrant({ userId: appleUserId, authMethod: 'apple' }, appleUserId),
                { mode: 'apple', userId: null })
        })
    })
})
