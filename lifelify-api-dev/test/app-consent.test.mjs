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
const linkOrigin = 'https://lifelify-connect-dev.inazumimakoto.workers.dev'
const resource = `${origin}/mcp`
const callback = 'https://chatgpt.com/connector_platform_oauth_redirect'
const userId = '30000000-0000-4000-8000-000000000001'
const secondUserId = '30000000-0000-4000-8000-000000000002'
const requestedScopes = ['shopping:read', 'shopping:write']
const bindings = {
    AUTH_MODE: 'apple', APP_APPROVAL_ENABLED: 'true',
    APPLE_APP_ID: 'com.inazumimakoto.lifelog',
    APPLE_SERVICE_ID: 'test.lifelify.web', APPLE_TEAM_ID: 'TESTTEAM01', APPLE_KEY_ID: 'TESTKEY001',
    APPLE_PRIVATE_KEY: generateKeyPairSync('ec', {
        namedCurve: 'prime256v1',
        privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
        publicKeyEncoding: { type: 'spki', format: 'pem' },
    }).privateKey,
}
let temporaryDirectory, miniflare, database, kv, script, schema, seed, nativeMigration, appMigration

const opaque = () => randomBytes(32).toString('base64url')
const sha256 = value => createHash('sha256').update(value).digest('hex')
const now = () => Math.floor(Date.now() / 1000)

function absorbCookies(jar, response) {
    for (const value of response.headers.getSetCookie?.() ?? []) {
        const pair = value.split(';')[0], separator = pair.indexOf('=')
        if (separator < 1) continue
        const name = pair.slice(0, separator), content = pair.slice(separator + 1)
        if (content) jar.set(name, content)
        else jar.delete(name)
    }
}

async function request(path, options = {}, jar, target = miniflare) {
    const headers = new Headers(options.headers)
    headers.set('Host', new URL(origin).host)
    if (jar && !headers.has('Cookie')) headers.set('Cookie', [...jar].map(([name, value]) => `${name}=${value}`).join('; '))
    const response = await target.dispatchFetch(`${origin}${path}`, { ...options, headers, redirect: 'manual' })
    if (jar) absorbCookies(jar, response)
    return response
}

async function fixture(sql, targetDatabase = database) {
    for (const statement of sql.split(';').map(value => value.trim()).filter(Boolean)) await targetDatabase.prepare(statement).run()
}

function runtime(name, overrides = {}) {
    const configured = { ...bindings, ...overrides }
    for (const key of Object.keys(configured)) if (configured[key] === undefined) delete configured[key]
    return new Miniflare(convertV4MiniflareOptions({
        name, modules: true, script,
        compatibilityDate: '2026-10-10', compatibilityFlags: ['nodejs_compat', 'global_fetch_strictly_public'],
        bindings: configured, d1Databases: { DB: `${name}-d1` }, kvNamespaces: ['OAUTH_KV'],
        resourcePersistencePath: join(temporaryDirectory, name), cf: false,
        telemetry: { enabled: false }, logRequests: false,
        outboundService() { throw new Error('All external network access is forbidden in app-consent tests') },
    }))
}

async function nativeSession(selectedUserId = userId) {
    const sessionId = opaque(), token = opaque(), timestamp = now()
    await database.prepare(`INSERT INTO native_sessions (
        id, user_id, access_token_hash, refresh_token_hash, created_at, updated_at,
        access_expires_at, refresh_expires_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`).bind(
        sessionId, selectedUserId, sha256(token), sha256(opaque()), timestamp, timestamp, timestamp + 3600, timestamp + 86400,
    ).run()
    return { id: sessionId, token, userId: selectedUserId }
}

async function beginConsent({ name = 'ChatGPT test client', jar = new Map(), target = miniflare } = {}) {
    const registered = await request('/oauth/register', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ client_name: name, redirect_uris: [callback],
            grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'], token_endpoint_auth_method: 'none' }),
    }, undefined, target)
    assert.equal(registered.status, 201, await registered.clone().text())
    const { client_id: clientId } = await registered.json()
    const verifier = opaque()
    const query = new URLSearchParams({ client_id: clientId, redirect_uri: callback, response_type: 'code',
        state: 'synthetic-app-consent-state', scope: requestedScopes.join(' '), resource,
        code_challenge: createHash('sha256').update(verifier).digest('base64url'),
        code_challenge_method: 'S256' })
    const response = await request(`/authorize?${query}`, {}, jar, target)
    assert.equal(response.status, 200, await response.clone().text())
    const html = await response.text()
    const match = html.match(/https:\/\/lifelify-connect-dev\.inazumimakoto\.workers\.dev\/connect\/([A-Za-z0-9_-]{43})/)
    return { response, html, id: match?.[1], jar, verifier, clientId, target }
}

async function pendingConsent(options = {}) {
    const flow = await beginConsent(options)
    assert.ok(flow.id, 'The browser page must link to a fresh opaque app-approval request')
    const row = await database.prepare('SELECT * FROM shopping_oauth_requests WHERE id = ?').bind(flow.id).first()
    assert.ok(row)
    assert.equal(row.status, 'pending')
    return { ...flow, handle: row.consent_handle }
}

function nativeRequest(flow, session, { method = 'GET', body, token = session?.token, contentType = 'application/json' } = {}) {
    const headers = {}
    if (token) headers.Authorization = `Bearer ${token}`
    if (body !== undefined) headers['Content-Type'] = contentType
    return request(`/auth/app/requests/${flow.id}`, { method, headers, ...(body !== undefined ? { body } : {}) })
}

function decide(flow, session, decision) {
    return nativeRequest(flow, session, { method: 'POST', body: JSON.stringify({ decision }) })
}

function finish(flow, { decision = 'approve', jar = flow.jar, handle = flow.handle, browserOrigin = origin, extra = [] } = {}) {
    const body = new URLSearchParams({ handle, decision })
    for (const [name, value] of extra) body.append(name, value)
    return request('/authorize', { method: 'POST', headers: {
        'Content-Type': 'application/x-www-form-urlencoded', Origin: browserOrigin,
    }, body: body.toString() }, jar)
}

async function grants() { return (await kv.list({ prefix: 'grant:' })).keys.length }

async function storedStatus(id) {
    return (await database.prepare('SELECT status, approved_user_id FROM shopping_oauth_requests WHERE id = ?').bind(id).first())
}

async function assertRejected(response, allowed = [400, 401, 403, 404, 409, 410]) {
    assert.ok(allowed.includes(response.status), `${response.status}: ${await response.clone().text()}`)
    assert.equal(response.headers.has('Location'), false)
    await response.text()
}

describe('app approval with isolated native sessions, D1 and OAuth KV', { concurrency: false }, () => {
    before(async () => {
        temporaryDirectory = await mkdtemp(join(tmpdir(), 'lifelify-app-consent-'))
        const harness = `import worker from './src/index.ts';
            export default {fetch(request,env,ctx){const headers=new Headers(request.headers);
                headers.set('Host',new URL(request.url).host);
                return worker.fetch(new Request(request,{headers}),env,ctx);}};`
        script = (await build({ stdin: { contents: harness, resolveDir: projectDirectory, loader: 'ts' },
            bundle: true, format: 'esm', platform: 'browser', conditions: ['workerd'], target: 'es2022',
            external: ['node:*', 'cloudflare:*'], logLevel: 'silent', write: false })).outputFiles[0].text
        ;[schema, seed, nativeMigration, appMigration] = await Promise.all([
            readFile(join(fixtureDirectory, 'schema.sql'), 'utf8'), readFile(join(fixtureDirectory, 'seed.dev.sql'), 'utf8'),
            readFile(join(projectDirectory, 'migrations/0002_native_auth.sql'), 'utf8'),
            readFile(join(projectDirectory, 'migrations/0003_app_consent.sql'), 'utf8'),
        ])
        miniflare = runtime('app-consent-test')
        database = await miniflare.getD1Database('DB')
        kv = await miniflare.getKVNamespace('OAUTH_KV')
        await fixture(`${schema}\n${nativeMigration}\n${appMigration}`)
    })

    beforeEach(async () => {
        for (const table of ['shopping_oauth_requests', 'native_sessions', 'native_auth_challenges', 'shopping_items', 'shopping_places', 'users']) {
            await database.prepare(`DELETE FROM ${table}`).run()
        }
        for (const key of (await kv.list()).keys) await kv.delete(key.name)
        await fixture(seed)
        for (const id of [userId, secondUserId]) await database.prepare(
            'INSERT INTO users (id, apple_sub, created_at, updated_at) VALUES (?, ?, 1, 1)'
        ).bind(id, `synthetic-apple-sub-${id}`).run()
    })

    after(async () => {
        try { await miniflare?.dispose() }
        finally { if (temporaryDirectory) await rm(temporaryDirectory, { recursive: true, force: true }) }
    })

    it('creates only a pending browser-bound request and safely renders untrusted client metadata', async () => {
        const name = '<img src=x onerror=alert(1)>'
        const flow = await pendingConsent({ name })
        assert.equal(flow.html.includes(name), false)
        assert.ok(flow.html.includes(linkOrigin))
        assert.match(flow.response.headers.get('Cache-Control'), /no-store/)
        assert.match(flow.response.headers.get('Content-Security-Policy'), /frame-ancestors 'none'/)
        const cookies = flow.response.headers.getSetCookie()
        assert.ok(cookies.some(value => /__Host-/.test(value) && /Secure/i.test(value) && /HttpOnly/i.test(value) && /SameSite=Lax/i.test(value)))
        assert.equal(await grants(), 0)
        assert.deepEqual(await storedStatus(flow.id), { status: 'pending', approved_user_id: null })
        const status = await request(`/auth/app/status?id=${flow.id}`, {}, flow.jar)
        assert.equal(status.status, 200)
        const body = await status.json()
        assert.deepEqual(Object.keys(body).sort(), ['expires_at', 'status'])
        assert.equal(body.status, 'pending')
        const session = await nativeSession()
        const native = await nativeRequest(flow, session)
        assert.equal(native.status, 200)
        const details = await native.json()
        assert.deepEqual(Object.keys(details).sort(), ['callback_host', 'client_domain', 'client_name', 'expires_at', 'id', 'scopes'])
        assert.equal(details.client_name, name)
        assert.equal(details.callback_host, 'chatgpt.com')
        assert.deepEqual(details.scopes, requestedScopes)
        assert.equal(await grants(), 0)
        assert.equal((await storedStatus(flow.id)).status, 'pending')
    })

    it('requires a valid native bearer token and never approves through a GET', async () => {
        const flow = await pendingConsent()
        for (const token of [undefined, 'invalid', opaque()]) {
            await assertRejected(await nativeRequest(flow, null, { token }), [401])
            await assertRejected(await nativeRequest(flow, null, { method: 'POST', token, body: '{"decision":"approve"}' }), [401])
        }
        const session = await nativeSession()
        const response = await nativeRequest(flow, session)
        assert.equal(response.status, 200)
        await response.text()
        assert.equal((await storedStatus(flow.id)).status, 'pending')
        assert.equal(await grants(), 0)
    })

    it('requires exactly one request identifier for browser polling and binds it to the cookie', async () => {
        const flow = await pendingConsent()
        for (const path of ['/auth/app/status', '/auth/app/status?id=invalid',
            `/auth/app/status?id=${flow.id}&id=${flow.id}`, `/auth/app/status?id=${flow.id}&other=value`]) {
            await assertRejected(await request(path, {}, flow.jar), [400])
        }
        await assertRejected(await request(`/auth/app/status?id=${opaque()}`, {}, flow.jar), [403])
        const status = await request(`/auth/app/status?id=${flow.id}`, {}, flow.jar)
        assert.equal(status.status, 200)
        assert.equal((await status.json()).status, 'pending')
        assert.equal(await grants(), 0)
    })

    it('resumes approved consent with a nonce-protected form but never grants or consumes through GET', async () => {
        const flow = await pendingConsent(), session = await nativeSession()
        assert.equal((await decide(flow, session, 'approve')).status, 200)
        const before = await database.prepare('SELECT * FROM shopping_oauth_requests WHERE id = ?').bind(flow.id).first()
        const response = await request(`/auth/app/resume?id=${flow.id}`, {}, flow.jar)
        assert.equal(response.status, 200)
        assert.equal(response.headers.has('Location'), false)
        assert.equal(response.headers.get('Cache-Control'), 'no-store')
        assert.equal(response.headers.get('Referrer-Policy'), 'no-referrer')
        assert.equal(response.headers.get('X-Frame-Options'), 'DENY')
        const html = await response.text()
        assert.match(html, new RegExp(`method="post" action="${origin}/authorize"`))
        assert.ok(html.includes(`name="handle" value="${flow.handle}"`))
        assert.ok(html.includes('name="decision" value="approve"'))
        const nonce = html.match(/<script nonce="([A-Za-z0-9_-]{43})">/)[1]
        assert.ok(response.headers.get('Content-Security-Policy').includes(`script-src 'nonce-${nonce}'`))
        assert.match(response.headers.get('Content-Security-Policy'), /form-action 'self' https:\/\/chatgpt\.com/)
        assert.ok(html.includes("document.getElementById('finish').requestSubmit()"))
        assert.equal(html.includes(callback), false, 'The app resume page must not reconstruct the OAuth callback')
        assert.equal(html.includes(session.token), false)
        assert.equal(response.headers.has('Set-Cookie'), false)
        assert.deepEqual(await database.prepare('SELECT * FROM shopping_oauth_requests WHERE id = ?').bind(flow.id).first(), before)
        assert.equal(await grants(), 0)
        const completed = await finish(flow)
        assert.equal(completed.status, 303, await completed.clone().text())
        assert.equal(new URL(completed.headers.get('Location')).origin + new URL(completed.headers.get('Location')).pathname, callback)
        assert.equal((await storedStatus(flow.id)).status, 'consumed')
        assert.equal(await grants(), 1)
    })

    it('keeps an approved decision intact when resume opens another browser or request', async () => {
        const flow = await pendingConsent(), other = await pendingConsent(), session = await nativeSession()
        assert.equal((await decide(flow, session, 'approve')).status, 200)
        const forged = new Map(flow.jar)
        forged.set('__Host-lifelify-app', `${flow.id}.${opaque()}`)
        const cookie = flow.jar.get('__Host-lifelify-app')
        for (const [jar, headers] of [
            [undefined, {}], [new Map(), {}], [other.jar, {}], [forged, {}],
            [undefined, { Authorization: `Bearer ${session.token}` }],
            [undefined, { Cookie: `__Host-lifelify-app=${cookie}; __Host-lifelify-app=${cookie}` }],
        ]) {
            const response = await request(`/auth/app/resume?id=${flow.id}`, { headers }, jar)
            assert.equal(response.status, 403)
            const html = await response.text()
            assert.ok(html.includes('Return to the original ChatGPT connection page'))
            assert.ok(html.includes('Your decision in lifelify is unchanged'))
            assert.equal(html.includes('<form'), false)
            assert.equal(html.includes('<script'), false)
            assert.equal(html.includes(flow.handle), false)
            assert.equal(response.headers.has('Location'), false)
        }
        const mismatch = await request(`/auth/app/resume?id=${other.id}`, {}, flow.jar)
        assert.equal(mismatch.status, 403)
        assert.equal((await storedStatus(flow.id)).status, 'approved')
        assert.equal((await storedStatus(other.id)).status, 'pending')
        assert.equal(await grants(), 0)
    })

    it('rejects malformed resume routes, query injection and foreign origins without mutating approval', async () => {
        const flow = await pendingConsent(), session = await nativeSession()
        assert.equal((await decide(flow, session, 'approve')).status, 200)
        for (const path of ['/auth/app/resume', '/auth/app/resume?id=invalid',
            `/auth/app/resume?id=${flow.id}&id=${flow.id}`,
            `/auth/app/resume?id=${flow.id}&redirect_uri=https%3A%2F%2Fevil.example`,
            `/auth/app/resume?id=${flow.id}&decision=deny`]) {
            const response = await request(path, {}, flow.jar)
            assert.equal(response.status, 400)
            const html = await response.text()
            assert.equal(html.includes('<form'), false)
            assert.equal(html.includes('<script'), false)
            assert.equal(html.includes('evil.example'), false)
        }
        await assertRejected(await request(`/auth/app/resume?id=${flow.id}`, {
            headers: { Origin: 'https://evil.example' },
        }, flow.jar), [403])
        for (const method of ['POST', 'HEAD']) {
            await assertRejected(await request(`/auth/app/resume?id=${flow.id}`, { method }, flow.jar), [405])
        }
        assert.equal((await storedStatus(flow.id)).status, 'approved')
        assert.equal(await grants(), 0)
    })

    it('never auto-approves pending or expired consent when resuming', async () => {
        const flow = await pendingConsent(), session = await nativeSession()
        const pending = await request(`/auth/app/resume?id=${flow.id}`, {}, flow.jar)
        assert.equal(pending.status, 409)
        assert.equal((await pending.text()).includes('<form'), false)
        assert.equal((await storedStatus(flow.id)).status, 'pending')
        assert.equal((await decide(flow, session, 'approve')).status, 200)
        await database.prepare('UPDATE shopping_oauth_requests SET expires_at = ? WHERE id = ?').bind(now() - 1, flow.id).run()
        const expired = await request(`/auth/app/resume?id=${flow.id}`, {}, flow.jar)
        assert.equal(expired.status, 410)
        const html = await expired.text()
        assert.ok(html.includes('Start a new connection from ChatGPT'))
        assert.equal(html.includes('<form'), false)
        assert.equal(html.includes('<script'), false)
        assert.equal((await storedStatus(flow.id)).status, 'approved')
        assert.equal(await grants(), 0)
    })

    it('resumes a native denial only as the original OAuth denial', async () => {
        const flow = await pendingConsent(), session = await nativeSession()
        assert.equal((await decide(flow, session, 'deny')).status, 200)
        const response = await request(`/auth/app/resume?id=${flow.id}`, {}, flow.jar)
        assert.equal(response.status, 200)
        const html = await response.text()
        assert.ok(html.includes('name="decision" value="deny"'))
        assert.equal(html.includes('name="decision" value="approve"'), false)
        assert.equal((await storedStatus(flow.id)).status, 'denied')
        assert.equal(await grants(), 0)
        const completed = await finish(flow, { decision: 'deny' })
        assert.equal(completed.status, 303)
        const redirect = new URL(completed.headers.get('Location'))
        assert.equal(redirect.origin + redirect.pathname, callback)
        assert.equal(redirect.searchParams.get('error'), 'access_denied')
        assert.equal(redirect.searchParams.has('code'), false)
        assert.equal(await grants(), 0)
    })

    it('does not mint another grant when a completed consent is resumed or its cookie was cleared', async () => {
        const flow = await pendingConsent(), session = await nativeSession()
        assert.equal((await decide(flow, session, 'approve')).status, 200)
        const originalCookies = new Map(flow.jar)
        const completed = await finish(flow)
        assert.equal(completed.status, 303)
        const resumed = await request(`/auth/app/resume?id=${flow.id}`, {}, originalCookies)
        assert.equal(resumed.status, 200)
        const html = await resumed.text()
        assert.ok(html.includes('This request has already been completed'))
        assert.equal(html.includes('<form'), false)
        assert.equal(html.includes('<script'), false)
        const cleared = await request(`/auth/app/resume?id=${flow.id}`, {}, flow.jar)
        assert.equal(cleared.status, 403)
        assert.equal((await storedStatus(flow.id)).status, 'consumed')
        assert.equal(await grants(), 1)
    })

    it('requires the OAuth provider cookie after a resumed form and preserves the native approval if it is absent', async () => {
        const flow = await pendingConsent(), session = await nativeSession()
        assert.equal((await decide(flow, session, 'approve')).status, 200)
        const appOnly = new Map([['__Host-lifelify-app', flow.jar.get('__Host-lifelify-app')]])
        const resumed = await request(`/auth/app/resume?id=${flow.id}`, {}, appOnly)
        assert.equal(resumed.status, 200)
        assert.ok((await resumed.text()).includes(`name="handle" value="${flow.handle}"`))
        await assertRejected(await finish(flow, { jar: appOnly }), [400, 403])
        assert.equal((await storedStatus(flow.id)).status, 'approved')
        assert.equal(await grants(), 0)
        const completed = await finish(flow)
        assert.equal(completed.status, 303)
        assert.equal(await grants(), 1)
    })

    it('never lets an old tab poll the newer request after the same browser replaces its cookie', async () => {
        const first = await pendingConsent()
        const originalCookie = new Map(first.jar)
        const second = await pendingConsent({ jar: first.jar })
        const session = await nativeSession()
        assert.equal((await decide(second, session, 'approve')).status, 200)
        await assertRejected(await request(`/auth/app/status?id=${first.id}`, {}, second.jar), [403])
        const original = await request(`/auth/app/status?id=${first.id}`, {}, originalCookie)
        assert.equal(original.status, 200)
        assert.equal((await original.json()).status, 'pending')
        const current = await request(`/auth/app/status?id=${second.id}`, {}, second.jar)
        assert.equal(current.status, 200)
        assert.equal((await current.json()).status, 'approved')
        assert.equal((await storedStatus(first.id)).status, 'pending')
        assert.equal(await grants(), 0)
    })

    it('rejects missing or expired requests and malformed approval bodies without changing state', async () => {
        const flow = await pendingConsent(), session = await nativeSession()
        for (const id of ['invalid', opaque()]) {
            await assertRejected(await nativeRequest({ id }, session), [400, 404, 410])
            await assertRejected(await decide({ id }, session, 'approve'), [400, 404, 410])
        }
        for (const body of ['not-json', 'null', '[]', '{}', '{"decision":"maybe"}',
            '{"decision":"approve","user_id":"dev-user"}', '{"decision":"deny","decision":"approve"}',
            '{"decision":"approve","decision":"approve"}']) {
            await assertRejected(await nativeRequest(flow, session, { method: 'POST', body }), [400])
            assert.equal((await storedStatus(flow.id)).status, 'pending')
        }
        await assertRejected(await nativeRequest(flow, session, { method: 'POST', body: '{"decision":"approve"}', contentType: 'text/plain' }), [400, 415])
        await database.prepare('UPDATE shopping_oauth_requests SET expires_at = ? WHERE id = ?').bind(now() - 1, flow.id).run()
        await assertRejected(await nativeRequest(flow, session), [404, 410])
        await assertRejected(await decide(flow, session, 'approve'), [404, 409, 410])
        assert.equal((await storedStatus(flow.id)).status, 'pending')
        assert.equal(await grants(), 0)
    })

    it('rejects expired, revoked and deleted-account native sessions for read and approval', async () => {
        const flow = await pendingConsent()
        for (const condition of ['expired', 'revoked', 'deleted']) {
            const session = await nativeSession(condition === 'deleted' ? secondUserId : userId)
            if (condition === 'expired') await database.prepare('UPDATE native_sessions SET access_expires_at = ? WHERE id = ?').bind(now() - 1, session.id).run()
            if (condition === 'revoked') await database.prepare('UPDATE native_sessions SET revoked_at = ? WHERE id = ?').bind(now(), session.id).run()
            if (condition === 'deleted') await database.prepare('UPDATE users SET deleted_at = 1 WHERE id = ?').bind(session.userId).run()
            await assertRejected(await nativeRequest(flow, session), [401])
            await assertRejected(await decide(flow, session, 'approve'), [401])
        }
        assert.equal((await storedStatus(flow.id)).status, 'pending')
        assert.equal(await grants(), 0)
    })

    it('allows exactly one parallel decision and makes the final native decision immutable', async () => {
        const flow = await pendingConsent(), first = await nativeSession(), second = await nativeSession(secondUserId)
        const responses = await Promise.all([decide(flow, first, 'approve'), decide(flow, second, 'approve')])
        assert.equal(responses.filter(response => response.status === 200).length, 1)
        assert.equal(responses.filter(response => response.status === 409).length, 1)
        for (const response of responses) await response.text()
        const stored = await storedStatus(flow.id)
        assert.equal(stored.status, 'approved')
        assert.ok([first.userId, second.userId].includes(stored.approved_user_id))
        await assertRejected(await decide(flow, first, 'deny'), [409])
        assert.deepEqual(await storedStatus(flow.id), stored)
        assert.equal(await grants(), 0)
    })

    it('requires the original browser cookie, exact handle and origin before consuming an app approval', async () => {
        const flow = await pendingConsent(), other = await pendingConsent(), session = await nativeSession()
        assert.equal((await decide(flow, session, 'approve')).status, 200)
        for (const options of [
            { jar: new Map() }, { jar: other.jar }, { handle: other.handle },
            { browserOrigin: 'https://evil.example' }, { extra: [['handle', flow.handle]] },
            { extra: [['user_id', userId]] },
        ]) {
            await assertRejected(await finish(flow, options))
            assert.equal((await storedStatus(flow.id)).status, 'approved')
            assert.equal(await grants(), 0)
        }
        await assertRejected(await request(`/auth/app/status?id=${flow.id}`), [401, 403, 404])
        const forged = new Map(flow.jar)
        const pair = [...forged].find(([, value]) => value.startsWith(`${flow.id}.`))
        assert.ok(pair, 'The app cookie must contain request id plus its browser secret')
        forged.set(pair[0], `${flow.id}.${opaque()}`)
        await assertRejected(await request(`/auth/app/status?id=${flow.id}`, {}, forged), [401, 403, 404])
        await assertRejected(await finish(flow, { jar: forged }))
        assert.equal((await storedStatus(flow.id)).status, 'approved')
    })

    it('preserves the approved app request when the OAuth library browser cookie is missing', async () => {
        const flow = await pendingConsent(), session = await nativeSession()
        assert.equal((await decide(flow, session, 'approve')).status, 200)
        const appOnly = new Map([...flow.jar].filter(([, value]) => value.startsWith(`${flow.id}.`)))
        assert.equal(appOnly.size, 1)
        await assertRejected(await finish(flow, { jar: appOnly }), [400, 403])
        assert.equal((await storedStatus(flow.id)).status, 'approved')
        assert.equal(await grants(), 0)
        const completed = await finish(flow)
        assert.equal(completed.status, 303, await completed.clone().text())
        assert.equal((await storedStatus(flow.id)).status, 'consumed')
    })

    it('issues a user-bound OAuth grant only after app approval and original browser completion', async () => {
        const flow = await pendingConsent(), session = await nativeSession()
        await assertRejected(await finish(flow), [400, 403, 409])
        assert.equal(await grants(), 0)
        assert.equal((await storedStatus(flow.id)).status, 'pending')
        const approved = await decide(flow, session, 'approve')
        assert.equal(approved.status, 200, await approved.clone().text())
        assert.deepEqual(await approved.json(), { status: 'approved' })
        const status = await request(`/auth/app/status?id=${flow.id}`, {}, flow.jar)
        assert.equal(status.status, 200)
        assert.equal((await status.json()).status, 'approved')
        assert.equal(await grants(), 0)
        const completed = await finish(flow)
        assert.equal(completed.status, 303, await completed.clone().text())
        const redirect = new URL(completed.headers.get('Location'))
        assert.equal(redirect.origin + redirect.pathname, callback)
        assert.equal(redirect.searchParams.get('state'), 'synthetic-app-consent-state')
        assert.equal(redirect.searchParams.get('iss'), origin)
        assert.ok(redirect.searchParams.get('code'))
        assert.equal((await storedStatus(flow.id)).status, 'consumed')
        assert.equal(await grants(), 1)
        const exchanged = await request('/oauth/token', {
            method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ grant_type: 'authorization_code', client_id: flow.clientId,
                code: redirect.searchParams.get('code'), code_verifier: flow.verifier, redirect_uri: callback, resource }).toString(),
        })
        assert.equal(exchanged.status, 200, await exchanged.clone().text())
        const token = await exchanged.json()
        const listed = await request('/mcp', { method: 'POST', headers: {
            Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream',
        }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'list_shopping_items', arguments: {} } }) })
        assert.equal(listed.status, 200)
        const result = await listed.text()
        assert.equal(result.includes('卵'), false, 'Apple app grants must not read the development user\'s shopping data')
        await assertRejected(await finish(flow), [400, 403, 409, 410])
        await assertRejected(await decide(flow, session, 'approve'), [409, 410])
        assert.equal(await grants(), 1)
    })

    it('creates at most one OAuth grant when the approved browser submits completion concurrently', async () => {
        const flow = await pendingConsent(), session = await nativeSession()
        assert.equal((await decide(flow, session, 'approve')).status, 200)
        const responses = await Promise.all([finish(flow), finish(flow)])
        assert.equal(responses.filter(response => response.status === 303).length, 1)
        for (const response of responses) {
            if (response.status === 303) {
                assert.ok(new URL(response.headers.get('Location')).searchParams.get('code'))
                await response.text()
            } else await assertRejected(response, [400, 403, 409])
        }
        assert.equal((await storedStatus(flow.id)).status, 'consumed')
        assert.equal(await grants(), 1)
    })

    it('never completes an approved request after its linked account is deleted', async () => {
        const flow = await pendingConsent(), session = await nativeSession()
        assert.equal((await decide(flow, session, 'approve')).status, 200)
        await database.prepare('UPDATE users SET deleted_at = 1 WHERE id = ?').bind(userId).run()
        await assertRejected(await finish(flow), [400, 403, 409, 410])
        assert.equal(await grants(), 0)
    })

    it('rechecks the approving native session at browser completion', async () => {
        for (const condition of ['revoked', 'access-expired', 'refresh-expired']) {
            const flow = await pendingConsent(), session = await nativeSession()
            assert.equal((await decide(flow, session, 'approve')).status, 200)
            const column = condition === 'revoked' ? 'revoked_at'
                : condition === 'access-expired' ? 'access_expires_at' : 'refresh_expires_at'
            await database.prepare(`UPDATE native_sessions SET ${column} = ? WHERE id = ?`).bind(now() - 1, session.id).run()
            await assertRejected(await finish(flow), [400, 403, 409, 410])
            assert.equal(await grants(), 0)
        }
    })

    it('never completes an expired app request even after native approval', async () => {
        const flow = await pendingConsent(), session = await nativeSession()
        assert.equal((await decide(flow, session, 'approve')).status, 200)
        await database.prepare('UPDATE shopping_oauth_requests SET expires_at = ? WHERE id = ?').bind(now() - 1, flow.id).run()
        await assertRejected(await finish(flow), [409, 410])
        assert.equal(await grants(), 0)
    })

    it('keeps native denial immutable and returns only an OAuth denial to the original browser', async () => {
        const flow = await pendingConsent(), session = await nativeSession()
        const denied = await decide(flow, session, 'deny')
        assert.equal(denied.status, 200)
        assert.deepEqual(await denied.json(), { status: 'denied' })
        await assertRejected(await decide(flow, session, 'approve'), [409])
        await assertRejected(await finish(flow), [400, 403, 409])
        assert.equal(await grants(), 0)
        const completed = await finish(flow, { decision: 'deny' })
        assert.equal(completed.status, 303, await completed.clone().text())
        const redirect = new URL(completed.headers.get('Location'))
        assert.equal(redirect.searchParams.get('error'), 'access_denied')
        assert.equal(redirect.searchParams.has('code'), false)
        assert.equal(redirect.searchParams.get('iss'), origin)
        assert.equal(await grants(), 0)
    })

    it('preserves the existing Apple web path when app approval is disabled by default', async () => {
        const disabled = runtime('app-consent-disabled', { APP_APPROVAL_ENABLED: undefined })
        try {
            const db = await disabled.getD1Database('DB')
            await fixture(schema, db)
            const flow = await beginConsent({ target: disabled })
            assert.equal(flow.id, undefined)
            assert.ok(flow.html.includes('/auth/apple/start'))
            const status = await request('/auth/app/status', {}, undefined, disabled)
            assert.equal(status.status, 503)
            assert.deepEqual(await status.json(), { error: 'app_approval_not_configured' })
        } finally { await disabled.dispose() }
    })
})
