import assert from 'node:assert/strict'
import { createHash, randomBytes } from 'node:crypto'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { after, before, beforeEach, describe, it } from 'node:test'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'
import { exportJWK, exportPKCS8, generateKeyPair, jwtVerify, SignJWT } from 'jose'
import { convertV4MiniflareOptions, Miniflare } from 'miniflare'

const projectDirectory = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const origin = 'https://lifelify-api-dev.inazumimakoto.workers.dev'
const resource = `${origin}/mcp`
const appleOrigin = 'https://appleid.apple.com'
const appleCallback = `${origin}/auth/apple/callback`
const mcpCallback = 'https://chatgpt.com/connector_platform_oauth_redirect'
const serviceID = 'test.lifelify.web'
const teamID = 'TESTTEAM01'
const keyID = 'TESTKEY001'
const subject = 'synthetic-apple-subject'
const handle = 'H'.repeat(43)
const cookieName = '__Host-lifelify-apple'
let temporaryDirectory, isolatedScript, integratedScript, schema, seed, appleKey, wrongKey, developerKey, jwks, bindings
let runtime, database, kv
let serial = 0
let scenarios = new Map()
let outbound = []
const runtimes = []

function absorbCookies(jar, response) {
    const values = response.headers.getSetCookie?.() ?? (response.headers.get('Set-Cookie') ?? '').split(/,\s*(?=[^;,\s]+=)/)
    for (const value of values) {
        const pair = value.split(';')[0]
        const separator = pair.indexOf('=')
        if (separator < 1) continue
        const name = pair.slice(0, separator), content = pair.slice(separator + 1)
        if (content) jar.set(name, content)
        else jar.delete(name)
    }
}

async function request(path, options = {}, target = runtime, jar) {
    const headers = new Headers(options.headers)
    headers.set('Host', new URL(origin).host)
    if (jar && !headers.has('Cookie')) headers.set('Cookie', [...jar].map(([name, value]) => `${name}=${value}`).join('; '))
    const response = await target.dispatchFetch(`${origin}${path}`, { ...options, headers, redirect: 'manual' })
    if (jar) absorbCookies(jar, response)
    return response
}

function postForm(path, values, target = runtime, jar, extraHeaders = {}) {
    return request(path, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Origin: origin, ...extraHeaders },
        body: new URLSearchParams(values).toString() }, target, jar)
}

async function mockApple(request) {
    outbound.push({ url: request.url, method: request.method })
    if (request.url === `${appleOrigin}/auth/keys` && request.method === 'GET') {
        return Response.json(jwks)
    }
    if (request.url !== `${appleOrigin}/auth/token` || request.method !== 'POST') {
        throw new Error('All external network access is forbidden in Apple tests')
    }
    const form = new URLSearchParams(await request.text())
    assert.equal(form.get('client_id'), serviceID)
    assert.equal(form.get('redirect_uri'), appleCallback)
    assert.equal(form.get('grant_type'), 'authorization_code')
    const secret = await jwtVerify(form.get('client_secret'), developerKey.publicKey, {
        issuer: teamID, subject: serviceID, audience: appleOrigin, algorithms: ['ES256'],
        requiredClaims: ['iss', 'sub', 'aud', 'iat', 'exp']
    })
    assert.equal(secret.protectedHeader.kid, keyID)
    assert.ok(secret.payload.exp - secret.payload.iat <= 300)
    const scenario = scenarios.get(form.get('code'))
    assert.ok(scenario, 'Only a synthetic code registered by the test can be exchanged')
    if (scenario.tokenFailure) return Response.json({ error: 'invalid_grant' }, { status: 400 })
    if (scenario.redirect) return new Response(null, { status: 302, headers: { Location: 'https://forbidden.example/token' } })
    if (scenario.oversized) return Response.json({ id_token: 'x'.repeat(70 * 1024) })
    const timestamp = Math.floor(Date.now() / 1000)
    const claims = { iss: appleOrigin, aud: serviceID, sub: subject, iat: timestamp, exp: timestamp + 300,
        nonce: scenario.nonce, email: 'never-persist@example.invalid', name: 'Never persist me', ...scenario.claims }
    for (const name of scenario.omit ?? []) delete claims[name]
    const token = await new SignJWT(claims)
        .setProtectedHeader({ alg: scenario.symmetric ? 'HS256' : 'RS256', kid: scenario.unknownKey ? 'unknown-key' : 'apple-test-key' })
        .sign(scenario.symmetric ? new TextEncoder().encode('synthetic-test-only-hmac-key-256-bits')
            : scenario.wrongSignature ? wrongKey.privateKey : appleKey.privateKey)
    return Response.json({ id_token: token, access_token: 'synthetic-apple-access', refresh_token: 'synthetic-apple-refresh' })
}

async function newRuntime({ integrated = false, overrides = {} } = {}) {
    const name = `apple-auth-${++serial}`
    const configured = { ...bindings, ...overrides }
    for (const key of Object.keys(configured)) if (configured[key] === undefined) delete configured[key]
    const target = new Miniflare(convertV4MiniflareOptions({ name, modules: true,
        script: integrated ? integratedScript : isolatedScript,
        compatibilityDate: '2026-10-10', compatibilityFlags: ['nodejs_compat', 'global_fetch_strictly_public'],
        bindings: configured, d1Databases: { DB: `${name}-d1` }, kvNamespaces: ['OAUTH_KV'],
        resourcePersistencePath: join(temporaryDirectory, name), cf: false,
        telemetry: { enabled: false }, logRequests: false, outboundService: mockApple }))
    runtimes.push(target)
    const db = await target.getD1Database('DB')
    for (const statement of `${schema}\n${seed}`.split(';').map(value => value.trim()).filter(Boolean)) await db.prepare(statement).run()
    return target
}

async function begin(target = runtime, jar = new Map()) {
    const response = await request('/__begin', {}, target, jar)
    assert.equal(response.status, 200, await response.clone().text())
    const page = await response.text()
    const flow = page.match(/name="flow" value="([^"]+)"/)?.[1]
    assert.ok(flow)
    return { response, page, flow, jar, target }
}

async function start(flow) {
    const response = await postForm('/auth/apple/start', { flow: flow.flow }, flow.target, flow.jar)
    assert.equal(response.status, 303, await response.clone().text())
    const location = new URL(response.headers.get('Location'))
    assert.equal(location.origin + location.pathname, `${appleOrigin}/auth/authorize`)
    assert.equal(location.searchParams.get('redirect_uri'), appleCallback)
    assert.equal(location.searchParams.get('response_type'), 'code')
    assert.equal(location.searchParams.get('response_mode'), 'form_post')
    assert.equal(location.searchParams.has('scope'), false)
    return { ...flow, state: location.searchParams.get('state'), nonce: location.searchParams.get('nonce') }
}

async function callback(flow, scenario = {}) {
    const code = `synthetic-code-${randomBytes(8).toString('hex')}`
    scenarios.set(code, { nonce: flow.nonce, ...scenario })
    return postForm('/auth/apple/callback', { state: flow.state, code }, flow.target, flow.jar, { Origin: appleOrigin })
}

async function authenticate(scenario = {}) {
    const flow = await start(await begin())
    const response = await callback(flow, scenario)
    return { ...flow, response }
}

async function identity(flow, selectedHandle = handle) {
    return postForm('/__resolve', { handle: selectedHandle }, flow.target, flow.jar)
}

describe('isolated Apple authentication and the integrated MCP permission flow', { concurrency: false }, () => {
    before(async () => {
        temporaryDirectory = await mkdtemp(join(tmpdir(), 'lifelify-apple-auth-'))
        ;[appleKey, wrongKey, developerKey] = await Promise.all([
            generateKeyPair('RS256'), generateKeyPair('RS256'), generateKeyPair('ES256', { extractable: true })])
        jwks = { keys: [{ ...await exportJWK(appleKey.publicKey), kid: 'apple-test-key', alg: 'RS256', use: 'sig' }] }
        bindings = { AUTH_MODE: 'apple', APPLE_SERVICE_ID: serviceID, APPLE_TEAM_ID: teamID,
            APPLE_KEY_ID: keyID, APPLE_PRIVATE_KEY: await exportPKCS8(developerKey.privateKey) }
        ;[schema, seed] = await Promise.all([
            readFile(join(projectDirectory, '../docs/cloudflare-shopping/schema.sql'), 'utf8'),
            readFile(join(projectDirectory, '../docs/cloudflare-shopping/seed.dev.sql'), 'utf8')])
        const harness = `import { beginAppleConsent, handleAppleAuthentication, resolveAppleConsentIdentity, clearAppleConsent, isAppleConfigured } from './src/apple';
export default {async fetch(request,env) {
const path=new URL(request.url).pathname;
if(path==='/__configured')return Response.json({configured:isAppleConfigured(env)});
if(path==='/__begin')return beginAppleConsent(request,env,{clientId:'synthetic-client',clientName:'<script>Untrusted client</script>',clientDomain:'chatgpt.com',redirectHost:'chatgpt.com',redirectUri:'${mcpCallback}',redirectIsLoopback:false,scope:['shopping:read','shopping:write']},'${handle}',new Headers({'Set-Cookie':'__Host-existing=preserved; Path=/; Secure; HttpOnly; SameSite=Lax'}));
if(path==='/__resolve'){const body=new URLSearchParams(await request.text());return Response.json({userId:await resolveAppleConsentIdentity(request,env,body.get('handle'))});}
if(path==='/__clear'){const headers=new Headers();await clearAppleConsent(request,env,headers);return new Response('cleared',{headers});}
return handleAppleAuthentication(request,env);
}};`
        const options = { bundle: true, format: 'esm', platform: 'browser', conditions: ['workerd'],
            target: 'es2022', external: ['node:*', 'cloudflare:*'], logLevel: 'silent', write: false }
        isolatedScript = (await build({ ...options, stdin: { contents: harness, resolveDir: projectDirectory, loader: 'ts' } })).outputFiles[0].text
        // dispatchFetch replaces Host with its local proxy address. Restore the
        // URL's public host only in this harness, preserving production checks.
        const integratedHarness = `import worker from './src/index.ts';
export default {fetch(request,env,ctx){const headers=new Headers(request.headers);
headers.set('Host',new URL(request.url).host);return worker.fetch(new Request(request,{headers}),env,ctx)}};`
        integratedScript = (await build({ ...options, stdin: { contents: integratedHarness,
            resolveDir: projectDirectory, loader: 'ts' } })).outputFiles[0].text
        runtime = await newRuntime()
        database = await runtime.getD1Database('DB')
        kv = await runtime.getKVNamespace('OAUTH_KV')
    })

    beforeEach(async () => {
        scenarios = new Map()
        outbound = []
        await database.prepare('DELETE FROM shopping_items').run()
        await database.prepare('DELETE FROM shopping_places').run()
        await database.prepare('DELETE FROM users').run()
        for (const statement of seed.split(';').map(value => value.trim()).filter(Boolean)) await database.prepare(statement).run()
    })

    after(async () => {
        await Promise.all(runtimes.map(target => target.dispose()))
        if (temporaryDirectory) await rm(temporaryDirectory, { recursive: true, force: true })
    })

    it('fails closed for missing or partial configuration and an inactive auth mode', async () => {
        for (const field of Object.keys(bindings)) {
            const target = await newRuntime({ overrides: { [field]: undefined } })
            assert.equal((await (await request('/__configured', {}, target)).json()).configured, false, field)
            assert.equal((await request('/__begin', {}, target)).status, 503, field)
            assert.equal((await request('/auth/apple/complete', {}, target)).status, 503, field)
        }
        const unknown = await newRuntime({ overrides: { AUTH_MODE: 'development' } })
        assert.equal((await (await request('/__configured', {}, unknown)).json()).configured, false)
        assert.equal(outbound.length, 0)
    })

    it('escapes client metadata, preserves provider cookies and binds the Apple form to its browser', async () => {
        const flow = await begin()
        assert.equal(flow.page.includes('<script>Untrusted'), false)
        assert.match(flow.page, /&#60;script&#62;/)
        assert.equal(flow.jar.get('__Host-existing'), 'preserved')
        assert.ok(flow.jar.has(cookieName))
        const cookies = flow.response.headers.get('Set-Cookie')
        assert.match(cookies, /SameSite=None/)
        assert.match(cookies, /HttpOnly/)
        assert.match(cookies, /Secure/)
        assert.equal(flow.response.headers.get('Referrer-Policy'), 'strict-origin')
        assert.match(flow.response.headers.get('Content-Security-Policy'), /https:\/\/appleid\.apple\.com/)
        assert.equal((await identity(flow)).status, 200)
        assert.equal((await (await identity(flow)).json()).userId, null)
        assert.equal((await postForm('/auth/apple/start', { flow: flow.flow }, runtime, new Map())).status, 403)
        assert.equal((await postForm('/auth/apple/start', { flow: flow.flow }, runtime, flow.jar, { Origin: 'https://attacker.invalid' })).status, 403)
        const other = await begin()
        assert.equal((await postForm('/auth/apple/start', { flow: flow.flow }, runtime, other.jar)).status, 403)
        assert.equal(outbound.length, 0)
    })

    it('rejects wrong state, absent or substituted cookies without exchanging an Apple code', async () => {
        const flow = await start(await begin())
        const values = { state: 'X'.repeat(43), code: 'unregistered-code' }
        assert.equal((await postForm('/auth/apple/callback', values, runtime, flow.jar)).status, 403)
        values.state = flow.state
        assert.equal((await postForm('/auth/apple/callback', values, runtime, new Map())).status, 403)
        const tampered = new Map(flow.jar)
        tampered.set(cookieName, `${flow.flow}.${'X'.repeat(43)}`)
        assert.equal((await postForm('/auth/apple/callback', values, runtime, tampered)).status, 403)
        assert.equal(outbound.length, 0)
    })

    it('verifies signed identity, provisions one stable UUID, and grants nothing before final consent', async () => {
        const flow = await authenticate()
        assert.equal(flow.response.status, 303, await flow.response.clone().text())
        assert.equal(flow.response.headers.get('Location'), `${origin}/auth/apple/complete`)
        const complete = await request('/auth/apple/complete', {}, runtime, flow.jar)
        assert.equal(complete.status, 200)
        const page = await complete.text()
        assert.match(page, /No permission has been granted/)
        assert.match(page, /action="\/authorize"/)
        assert.deepEqual([...new Set([...page.matchAll(/name="([^"]+)"/g)].map(match => match[1]).filter(name => name !== 'viewport'))].sort(), ['decision', 'handle'])
        assert.equal(page.includes('credential'), false)
        const records = await kv.list({ prefix: `apple:flow:${flow.flow}:` })
        assert.deepEqual(records.keys.map(key => key.name), [`apple:flow:${flow.flow}:authenticated`])
        const stored = await kv.get(records.keys[0].name)
        for (const privateValue of ['never-persist@example.invalid', 'Never persist me', 'synthetic-apple-access', 'synthetic-apple-refresh']) {
            assert.equal(stored.includes(privateValue), false)
        }
        assert.equal((await (await identity(flow, 'W'.repeat(43))).json()).userId, null)
        const user = (await (await identity(flow)).json()).userId
        assert.match(user, /^[0-9a-f-]{36}$/)
        assert.notEqual(user, 'dev-user')
        assert.equal((await (await identity(flow)).json()).userId, null)
        const again = await authenticate()
        assert.equal(again.response.status, 303)
        assert.equal((await (await identity(again)).json()).userId, user)
        assert.equal((await database.prepare('SELECT COUNT(*) AS count FROM users WHERE apple_sub = ?').bind(subject).first()).count, 1)
    })

    it('uses a distinct immutable KV key for each rapid sign-in stage', async () => {
        const flow = await begin()
        assert.deepEqual((await kv.list({ prefix: `apple:flow:${flow.flow}:` })).keys.map(key => key.name), [`apple:flow:${flow.flow}:pending`])
        const started = await start(flow)
        assert.deepEqual((await kv.list({ prefix: `apple:flow:${flow.flow}:` })).keys.map(key => key.name), [`apple:flow:${flow.flow}:started`])
        assert.equal((await callback(started)).status, 303)
        assert.deepEqual((await kv.list({ prefix: `apple:flow:${flow.flow}:` })).keys.map(key => key.name), [`apple:flow:${flow.flow}:authenticated`])
    })

    it('rejects invalid nonce, audience, issuer, subject, signature, key ID, expiry and issue time', async () => {
        const timestamp = Math.floor(Date.now() / 1000)
        const invalid = [
            { claims: { nonce: 'attacker-nonce' } }, { claims: { aud: 'other-service' } },
            { claims: { iss: 'https://attacker.invalid' } }, { claims: { sub: '' } },
            { wrongSignature: true }, { symmetric: true }, { unknownKey: true }, { claims: { exp: timestamp - 60 } },
            { claims: { iat: timestamp + 120 } }, { claims: { iat: timestamp - 900 } },
            { omit: ['nonce'] }, { omit: ['iat'] }, { omit: ['exp'] }
        ]
        for (const scenario of invalid) {
            const flow = await authenticate(scenario)
            assert.equal(flow.response.status, 400, JSON.stringify(scenario))
            assert.equal((await (await identity(flow)).json()).userId, null)
        }
        assert.equal((await database.prepare('SELECT COUNT(*) AS count FROM users WHERE apple_sub = ?').bind(subject).first()).count, 0)
    })

    it('does not revive soft-deleted accounts or map Apple identity onto the development account', async () => {
        await database.prepare('INSERT INTO users (id, apple_sub, created_at, updated_at, deleted_at) VALUES (?, ?, 1, 1, 1)')
            .bind('deleted-user', subject).run()
        assert.equal((await authenticate()).response.status, 400)
        assert.equal((await database.prepare('SELECT deleted_at FROM users WHERE id = ?').bind('deleted-user').first()).deleted_at, 1)
        const dev = await database.prepare('SELECT apple_sub FROM users WHERE id = ?').bind('dev-user').first()
        assert.equal((await authenticate({ claims: { sub: dev.apple_sub } })).response.status, 400)
        const rows = await database.prepare('SELECT id FROM users WHERE apple_sub = ?').bind(dev.apple_sub).all()
        assert.deepEqual(rows.results, [{ id: 'dev-user' }])
    })

    it('rechecks account deletion before resolving final consent and supports denial cleanup', async () => {
        const flow = await authenticate()
        await database.prepare('UPDATE users SET deleted_at = 1 WHERE apple_sub = ?').bind(subject).run()
        assert.equal((await (await identity(flow)).json()).userId, null)
        const clear = await postForm('/__clear', {}, runtime, flow.jar)
        assert.match(clear.headers.get('Set-Cookie'), /Max-Age=0/)
        assert.equal(flow.jar.has(cookieName), false)
        assert.equal((await kv.list({ prefix: `apple:flow:${flow.flow}:` })).keys.length, 0)
    })

    it('rejects callback replay, expiry, oversized forms and failed or redirected token responses', async () => {
        const flow = await start(await begin())
        const code = 'replay-test-code'
        scenarios.set(code, { nonce: flow.nonce })
        assert.equal((await postForm('/auth/apple/callback', { state: flow.state, code }, runtime, flow.jar)).status, 303)
        const count = outbound.length
        assert.equal((await postForm('/auth/apple/callback', { state: flow.state, code }, runtime, flow.jar)).status, 403)
        assert.equal(outbound.length, count)
        const declined = await start(await begin())
        const declinedResponse = await postForm('/auth/apple/callback', {
            state: declined.state, error: 'access_denied'
        }, runtime, declined.jar)
        assert.equal(declinedResponse.status, 400)
        assert.equal(declinedResponse.headers.has('Location'), false)
        assert.equal(outbound.length, count)
        const expired = await begin()
        const key = `apple:flow:${expired.flow}:pending`
        const saved = await kv.get(key, 'json')
        await kv.put(key, JSON.stringify({ ...saved, expiresAt: 1 }))
        assert.equal((await postForm('/auth/apple/start', { flow: expired.flow }, runtime, expired.jar)).status, 403)
        assert.equal((await postForm('/auth/apple/start', { flow: 'x'.repeat(20 * 1024) }, runtime)).status, 413)
        for (const scenario of [{ tokenFailure: true }, { redirect: true }, { oversized: true }]) {
            assert.equal((await authenticate(scenario)).response.status, 400)
        }
        assert.equal(outbound.some(item => new URL(item.url).origin !== appleOrigin), false)
    })

    it('completes real Worker OAuth after Apple consent and isolates the new Apple user in MCP', async () => {
        const target = await newRuntime({ integrated: true })
        const jar = new Map()
        const registration = await request('/oauth/register', { method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ client_name: 'Synthetic ChatGPT', redirect_uris: [mcpCallback],
                grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'], token_endpoint_auth_method: 'none' }) }, target)
        assert.equal(registration.status, 201, await registration.clone().text())
        const clientID = (await registration.json()).client_id
        const verifier = randomBytes(32).toString('base64url')
        const parameters = new URLSearchParams({ client_id: clientID, redirect_uri: mcpCallback, response_type: 'code', state: 'synthetic-mcp-state',
            scope: 'shopping:read shopping:write offline_access', resource,
            code_challenge: createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256' })
        const consent = await request(`/authorize?${parameters}`, {}, target, jar)
        assert.equal(consent.status, 200, await consent.clone().text())
        const page = await consent.text()
        assert.equal(page.includes('Development access token'), false)
        const flowID = page.match(/name="flow" value="([^"]+)"/)?.[1]
        const flow = await start({ flow: flowID, jar, target })
        const signedIn = await callback(flow)
        assert.equal(signedIn.status, 303, await signedIn.clone().text())
        assert.equal(signedIn.headers.get('Location'), `${origin}/auth/apple/complete`)
        const permission = await request('/auth/apple/complete', {}, target, jar)
        assert.equal(permission.status, 200)
        const integratedKV = await target.getKVNamespace('OAUTH_KV')
        assert.equal((await integratedKV.list({ prefix: 'grant:' })).keys.length, 0,
            'Apple authentication alone must not create an OAuth grant')
        const finalHandle = (await permission.text()).match(/name="handle" value="([^"]+)"/)?.[1]
        assert.ok(finalHandle)
        const final = await postForm('/authorize', { handle: finalHandle, decision: 'approve' }, target, jar)
        assert.equal(final.status, 303, await final.clone().text())
        assert.equal(jar.has(cookieName), false)
        const redirect = new URL(final.headers.get('Location'))
        assert.equal(redirect.origin + redirect.pathname, mcpCallback)
        assert.equal(redirect.searchParams.get('state'), 'synthetic-mcp-state')
        const exchanged = await postForm('/oauth/token', { grant_type: 'authorization_code', client_id: clientID,
            redirect_uri: mcpCallback, code: redirect.searchParams.get('code'), code_verifier: verifier, resource }, target)
        assert.equal(exchanged.status, 200, await exchanged.clone().text())
        const tokens = await exchanged.json()
        async function tool(name, args) {
            const call = await request('/mcp', { method: 'POST', headers: { 'Content-Type': 'application/json',
                Accept: 'application/json, text/event-stream', Authorization: `Bearer ${tokens.access_token}` },
                body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } }) }, target)
            assert.equal(call.status, 200, await call.clone().text())
            const text = await call.text()
            const result = call.headers.get('Content-Type')?.includes('text/event-stream')
                ? JSON.parse(text.split('\n').find(line => line.startsWith('data: ')).slice(6))
                : JSON.parse(text)
            assert.equal(result.result?.isError ?? false, false, JSON.stringify(result))
            return result.result.structuredContent
        }
        assert.deepEqual((await tool('list_shopping_items', {})).items, [])
        const added = await tool('add_shopping_item', { title: 'Apple account item', note: 'Synthetic isolated test', place_id: null })
        assert.ok(added.item.id)
        const db = await target.getD1Database('DB')
        const owner = await db.prepare('SELECT user_id FROM shopping_items WHERE id = ?').bind(added.item.id).first()
        assert.notEqual(owner.user_id, 'dev-user')
        const appleUser = await db.prepare('SELECT id FROM users WHERE apple_sub = ?').bind(subject).first()
        assert.equal(owner.user_id, appleUser.id)
        assert.equal((await tool('list_shopping_items', {})).items.length, 1)
    })
})
