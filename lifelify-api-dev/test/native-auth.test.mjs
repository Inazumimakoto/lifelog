import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { after, before, beforeEach, describe, it } from 'node:test'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'
import { exportJWK, generateKeyPair, SignJWT } from 'jose'
import { convertV4MiniflareOptions, Miniflare } from 'miniflare'

const project = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const origin = 'https://lifelify-api-dev.inazumimakoto.workers.dev'
const appleOrigin = 'https://appleid.apple.com'
const appID = 'test.lifelify.native'
const appleSubject = 'synthetic-native-apple-subject'
const timestamp = () => Math.floor(Date.now() / 1000)
const sha = value => createHash('sha256').update(value).digest('hex')
let temporaryDirectory, script, schema, migration, key, wrongKey, jwks, runtime, database
let externalRequests = [], appleFailure = false
const runtimes = []

async function request(path, { method = 'GET', body, token, headers = {} } = {}, target = runtime) {
    return target.dispatchFetch(`${origin}/auth/native${path}`, { method,
        headers: { ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
            ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
        ...(body !== undefined ? { body: typeof body === 'string' ? body : JSON.stringify(body) } : {}),
        redirect: 'manual' })
}

async function newRuntime(overrides = {}) {
    const name = `native-auth-${runtimes.length}`
    const bindings = { AUTH_MODE: 'apple', APPLE_APP_ID: appID, ...overrides }
    for (const field of Object.keys(bindings)) if (bindings[field] === undefined) delete bindings[field]
    const target = new Miniflare(convertV4MiniflareOptions({ name, modules: true, script,
        compatibilityDate: '2026-10-10', compatibilityFlags: ['nodejs_compat', 'global_fetch_strictly_public'],
        bindings, d1Databases: { DB: name }, resourcePersistencePath: join(temporaryDirectory, name),
        cf: false, telemetry: { enabled: false }, logRequests: false,
        outboundService: async request => {
            externalRequests.push(request.url)
            assert.equal(request.url, `${appleOrigin}/auth/keys`, 'No real network or caller-supplied key URLs are allowed')
            assert.equal(request.method, 'GET')
            return appleFailure ? new Response(null, { status: 302, headers: { Location: 'https://forbidden.invalid/keys' } })
                : Response.json(jwks)
        } }))
    runtimes.push(target)
    const db = await target.getD1Database('DB')
    for (const statement of `${schema}\n${migration}`.split(';').map(value => value.trim()).filter(Boolean)) {
        await db.prepare(statement).run()
    }
    return target
}

async function challenge(target = runtime) {
    const response = await request('/apple/challenge', { method: 'POST', body: {} }, target)
    assert.equal(response.status, 200, await response.clone().text())
    assert.equal(response.headers.get('Cache-Control'), 'no-store')
    return response.json()
}

async function identityToken(flow, { claims = {}, omit = [], signingKey = key.privateKey, header = {} } = {}) {
    const payload = { iss: appleOrigin, aud: appID, sub: appleSubject, iat: timestamp(), exp: timestamp() + 300,
        nonce: sha(flow.nonce), email: 'never-store@example.invalid', ...claims }
    for (const name of omit) delete payload[name]
    return new SignJWT(payload).setProtectedHeader({ alg: 'RS256', kid: 'native-test-key', ...header }).sign(signingKey)
}

async function exchange(flow, token) {
    return request('/apple/session', { method: 'POST', body: { challenge_id: flow.id, id_token: token } })
}

async function signIn(subject = appleSubject) {
    const flow = await challenge()
    const response = await exchange(flow, await identityToken(flow, { claims: { sub: subject } }))
    assert.equal(response.status, 200, await response.clone().text())
    return response.json()
}

async function session(token) { return request('/session', { token }) }
async function refresh(token) { return request('/refresh', { method: 'POST', body: { refresh_token: token } }) }

describe('native Apple authentication and rotating D1 sessions', { concurrency: false }, () => {
    before(async () => {
        temporaryDirectory = await mkdtemp(join(tmpdir(), 'lifelify-native-auth-'))
        ;[key, wrongKey] = await Promise.all([generateKeyPair('RS256'), generateKeyPair('RS256')])
        jwks = { keys: [{ ...await exportJWK(key.publicKey), kid: 'native-test-key', alg: 'RS256', use: 'sig' }] }
        ;[schema, migration] = await Promise.all([
            readFile(join(project, '../docs/cloudflare-shopping/schema.sql'), 'utf8'),
            readFile(join(project, 'migrations/0002_native_auth.sql'), 'utf8')])
        const harness = `import {handleNativeAuthentication} from './src/native-auth';
            export default {fetch(request,env){return handleNativeAuthentication(request,env)}};`
        script = (await build({ stdin: { contents: harness, resolveDir: project, loader: 'ts' },
            bundle: true, format: 'esm', platform: 'browser', conditions: ['workerd'], target: 'es2022',
            external: ['node:*', 'cloudflare:*'], logLevel: 'silent', write: false })).outputFiles[0].text
        runtime = await newRuntime()
        database = await runtime.getD1Database('DB')
    })

    beforeEach(async () => {
        externalRequests = []
        appleFailure = false
        await database.batch(['DELETE FROM native_sessions', 'DELETE FROM native_auth_challenges', 'DELETE FROM users']
            .map(statement => database.prepare(statement)))
    })

    after(async () => {
        await Promise.all(runtimes.map(target => target.dispose()))
        if (temporaryDirectory) await rm(temporaryDirectory, { recursive: true, force: true })
    })

    it('fails closed outside Apple mode or without the native Apple audience, without a private key dependency', async () => {
        for (const overrides of [{ AUTH_MODE: 'development' }, { APPLE_APP_ID: undefined }, { APPLE_APP_ID: '' }]) {
            const target = await newRuntime(overrides)
            assert.equal((await request('/apple/challenge', { method: 'POST', body: {} }, target)).status, 503)
        }
        assert.equal((await request('/apple/challenge', { method: 'POST', body: {} })).status, 200)
        assert.equal(externalRequests.length, 0)
    })

    it('stores only a hashed Apple nonce and hashed access/refresh credentials', async () => {
        const flow = await challenge()
        assert.match(flow.id, /^[A-Za-z0-9_-]{43}$/)
        assert.match(flow.nonce, /^[A-Za-z0-9_-]{43}$/)
        assert.ok(flow.expires_at >= timestamp() + 598 && flow.expires_at <= timestamp() + 600)
        const storedChallenge = await database.prepare('SELECT * FROM native_auth_challenges WHERE id = ?').bind(flow.id).first()
        assert.equal(storedChallenge.nonce_hash, sha(flow.nonce))
        assert.equal(JSON.stringify(storedChallenge).includes(flow.nonce), false)
        const jwt = await identityToken(flow)
        const response = await exchange(flow, jwt)
        assert.equal(response.status, 200, await response.clone().text())
        const credentials = await response.json()
        assert.equal(credentials.expires_in, 3600)
        assert.equal(credentials.refresh_expires_in, 2592000)
        assert.match(credentials.access_token, /^[A-Za-z0-9_-]{43}$/)
        assert.match(credentials.refresh_token, /^[A-Za-z0-9_-]{43}$/)
        const stored = await database.prepare('SELECT * FROM native_sessions').first()
        assert.equal(stored.access_token_hash, sha(credentials.access_token))
        assert.equal(stored.refresh_token_hash, sha(credentials.refresh_token))
        const dump = JSON.stringify(stored)
        for (const secret of [credentials.access_token, credentials.refresh_token, jwt]) assert.equal(dump.includes(secret), false)
        assert.deepEqual(await (await session(credentials.access_token)).json(), { user: credentials.user })
        const user = await database.prepare('SELECT * FROM users').first()
        assert.equal(user.apple_sub, appleSubject)
        assert.equal(JSON.stringify(user).includes('never-store'), false)
    })

    it('rejects JWT signature, issuer, exact native audience, nonce, expiry, freshness and missing claims', async () => {
        const variants = [
            { signingKey: wrongKey.privateKey },
            { claims: { iss: 'https://untrusted.invalid' } },
            { claims: { aud: 'test.lifelify.web' } },
            { claims: { aud: [appID, 'untrusted'] } },
            { claims: { nonce: 'wrong-nonce' } },
            { claims: { exp: timestamp() - 10 } },
            { claims: { iat: timestamp() + 600 } },
            { claims: { iat: timestamp() - 700 } },
            { claims: { sub: '' } },
            { header: { kid: 'untrusted-key' } },
            ...['iss', 'aud', 'exp', 'iat', 'nonce', 'sub'].map(name => ({ omit: [name] }))
        ]
        for (const variant of variants) {
            const flow = await challenge()
            assert.equal((await exchange(flow, await identityToken(flow, variant))).status, 401, JSON.stringify(variant.claims ?? variant.omit ?? variant.header))
        }
        const flow = await challenge()
        assert.equal((await exchange(flow, await identityToken(flow, { claims: { nonce: flow.nonce } }))).status, 401, 'The unhashed native nonce must not match')
        assert.equal((await database.prepare('SELECT count(*) AS count FROM users').first()).count, 0)
        assert.equal((await database.prepare('SELECT count(*) AS count FROM native_sessions').first()).count, 0)
    })

    it('does not follow key redirects or JWT-supplied key URLs', async () => {
        const flow = await challenge()
        const token = await identityToken(flow, { header: { jku: 'https://forbidden.invalid/keys' } })
        appleFailure = true
        assert.equal((await exchange(flow, token)).status, 401)
        assert.deepEqual(externalRequests, [`${appleOrigin}/auth/keys`])
        appleFailure = false
        assert.equal((await exchange(flow, token)).status, 200, 'A transient verifier failure does not consume the challenge')
        assert.ok(externalRequests.every(url => url === `${appleOrigin}/auth/keys`))
    })

    it('permits only one concurrent exchange and rejects consumed, expired or unknown challenges', async () => {
        const flow = await challenge(), token = await identityToken(flow)
        const replies = await Promise.all([exchange(flow, token), exchange(flow, token)])
        assert.deepEqual(replies.map(reply => reply.status).sort(), [200, 401])
        assert.equal((await exchange(flow, token)).status, 401)
        assert.equal((await database.prepare('SELECT count(*) AS count FROM native_sessions').first()).count, 1)
        const expired = await challenge()
        await database.prepare('UPDATE native_auth_challenges SET created_at = ?, expires_at = ? WHERE id = ?')
            .bind(timestamp() - 601, timestamp() - 1, expired.id).run()
        assert.equal((await exchange(expired, await identityToken(expired))).status, 401)
        assert.equal((await exchange({ ...flow, id: 'X'.repeat(43) }, token)).status, 401)
    })

    it('converges concurrent first sign-ins on the stable Apple identity and separates other accounts', async () => {
        const credentials = await Promise.all([signIn(), signIn()])
        assert.equal(credentials[0].user.id, credentials[1].user.id)
        assert.notEqual(credentials[0].access_token, credentials[1].access_token)
        const other = await signIn('another-apple-subject')
        assert.notEqual(credentials[0].user.id, other.user.id)
        assert.equal((await database.prepare('SELECT count(*) AS count FROM users').first()).count, 2)
    })

    it('rotates access and refresh tokens atomically with one winner and no grace replay', async () => {
        const original = await signIn()
        const responses = await Promise.all([refresh(original.refresh_token), refresh(original.refresh_token)])
        assert.deepEqual(responses.map(value => value.status).sort(), [200, 401])
        const current = await responses.find(value => value.status === 200).json()
        assert.equal(current.user.id, original.user.id)
        assert.notEqual(current.access_token, original.access_token)
        assert.notEqual(current.refresh_token, original.refresh_token)
        assert.equal((await session(original.access_token)).status, 401)
        assert.equal((await refresh(original.refresh_token)).status, 401)
        assert.equal((await session(current.access_token)).status, 200)
        assert.equal((await refresh(current.refresh_token)).status, 200)
    })

    it('allows refresh after access expiry but denies expired refresh credentials', async () => {
        const original = await signIn()
        await database.prepare('UPDATE native_sessions SET access_expires_at = ?').bind(timestamp() - 1).run()
        assert.equal((await session(original.access_token)).status, 401)
        const refreshed = await refresh(original.refresh_token)
        assert.equal(refreshed.status, 200)
        const current = await refreshed.json()
        await database.prepare('UPDATE native_sessions SET refresh_expires_at = ?').bind(timestamp() - 1).run()
        assert.equal((await refresh(current.refresh_token)).status, 401)
        assert.equal((await session(current.access_token)).status, 401)
    })

    it('denies deleted identities for sign-in, access and refresh without reviving their account', async () => {
        const original = await signIn()
        await database.prepare('UPDATE users SET deleted_at = ? WHERE id = ?').bind(Date.now(), original.user.id).run()
        assert.equal((await session(original.access_token)).status, 401)
        assert.equal((await refresh(original.refresh_token)).status, 401)
        const flow = await challenge()
        assert.equal((await exchange(flow, await identityToken(flow))).status, 403)
        const user = await database.prepare('SELECT id, deleted_at FROM users WHERE apple_sub = ?').bind(appleSubject).first()
        assert.equal(user.id, original.user.id)
        assert.notEqual(user.deleted_at, null)
    })

    it('logs out only the authenticated session and revokes both of its tokens', async () => {
        const first = await signIn(), second = await signIn(), other = await signIn('other-owner')
        assert.equal((await request('/logout', { method: 'POST', body: {}, token: first.access_token })).status, 200)
        assert.equal((await session(first.access_token)).status, 401)
        assert.equal((await refresh(first.refresh_token)).status, 401)
        assert.equal((await session(second.access_token)).status, 200)
        assert.equal((await session(other.access_token)).status, 200)
        assert.equal((await request('/logout', { method: 'POST', body: {}, token: first.refresh_token })).status, 401)
        assert.equal((await request('/logout', { method: 'POST', body: { user_id: other.user.id }, token: second.access_token })).status, 400)
    })

    it('validates strict bounded JSON and rejects ambient cookies, extra identity fields and cross-origin browser requests', async () => {
        for (const invalid of [[], null, { user_id: 'forged' }, '{', '']) {
            assert.equal((await request('/apple/challenge', { method: 'POST', body: invalid })).status, 400)
        }
        assert.equal((await request('/apple/challenge', { method: 'POST', body: '{}', headers: { 'Content-Type': 'text/plain' } })).status, 415)
        assert.equal((await request('/apple/challenge', { method: 'POST', body: ' '.repeat(25 * 1024) })).status, 413)
        assert.equal((await request('/apple/challenge', { method: 'POST', body: {}, headers: { Origin: 'https://untrusted.invalid' } })).status, 403)
        const credentials = await signIn()
        assert.equal((await request('/session', { headers: { Cookie: `session=${credentials.access_token}` } })).status, 401)
        assert.equal((await session(credentials.refresh_token)).status, 401)
        const flow = await challenge()
        assert.equal((await request('/apple/session', { method: 'POST', body: {
            challenge_id: flow.id, id_token: await identityToken(flow), user_id: credentials.user.id } })).status, 400)
        assert.equal((await request('/refresh', { method: 'POST', body: { refresh_token: 'not-a-token' } })).status, 400)
        for (const duplicate of [
            `{"refresh_token":"${credentials.refresh_token}","refresh_token":"${credentials.refresh_token}"}`,
            `{"refresh_token":"${credentials.refresh_token}","refresh_\\u0074oken":"${credentials.refresh_token}"}`
        ]) {
            assert.equal((await request('/refresh', { method: 'POST', body: duplicate })).status, 400)
        }
    })
})
