import type { ConsentDescription } from '@cloudflare/workers-oauth-provider'
import { createLocalJWKSet, decodeProtectedHeader, importPKCS8, jwtVerify, SignJWT } from 'jose'
import { developmentUserId, publicOrigin, type ApiBindings } from './config'

const appleOrigin = 'https://appleid.apple.com'
const appleCallback = `${publicOrigin}/auth/apple/callback`
const cookieName = '__Host-lifelify-apple'
const flowTTL = 600
const maximumBodyBytes = 16 * 1024
const maximumAppleResponseBytes = 64 * 1024
const opaquePattern = /^[A-Za-z0-9_-]{43}$/
const securityPolicy = "default-src 'none'; form-action 'self' https://appleid.apple.com https://chatgpt.com; frame-ancestors 'none'; base-uri 'none'"

type AppleFlow = {
    browserHash: string
    handle: string
    details: Pick<ConsentDescription, 'clientName' | 'clientDomain' | 'redirectHost' | 'scope'>
    createdAt: number
    expiresAt: number
    stage: 'pending' | 'started' | 'authenticated'
    stateHash?: string
    nonce?: string
    userId?: string
}

type BoundFlow = { id: string; flow: AppleFlow }

class AppleAuthenticationError extends Error {
    constructor(readonly status: number, readonly publicMessage: string) {
        super('Apple authentication failed')
    }
}

const nowSeconds = () => Math.floor(Date.now() / 1000)
const stages: AppleFlow['stage'][] = ['authenticated', 'started', 'pending']
const flowKey = (id: string, stage: AppleFlow['stage']) => `apple:flow:${id}:${stage}`
const escapeHTML = (value: string) => value.replace(/[&<>"']/g,
    (character) => `&#${character.charCodeAt(0)};`)

function secureHeaders(headers = new Headers()): Headers {
    headers.set('Cache-Control', 'no-store')
    headers.set('Referrer-Policy', 'strict-origin')
    headers.set('Content-Security-Policy', securityPolicy)
    headers.set('X-Frame-Options', 'DENY')
    headers.set('X-Content-Type-Options', 'nosniff')
    return headers
}

function response(message: string, status = 400, headers = new Headers()): Response {
    headers.set('Content-Type', 'text/plain; charset=utf-8')
    return new Response(message, { status, headers: secureHeaders(headers) })
}

function html(body: string, headers = new Headers()): Response {
    headers.set('Content-Type', 'text/html; charset=utf-8')
    return new Response(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Connect lifelify</title></head><body><main>${body}</main></body></html>`,
        { headers: secureHeaders(headers) })
}

function redirect(location: string, headers = new Headers()): Response {
    headers.set('Location', location)
    return new Response(null, { status: 303, headers: secureHeaders(headers) })
}

function expireCookie(headers: Headers) {
    headers.append('Set-Cookie', `${cookieName}=; Path=/; Max-Age=0; Secure; HttpOnly; SameSite=None`)
}

function randomOpaque(): string {
    const bytes = crypto.getRandomValues(new Uint8Array(32))
    return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

async function hash(value: string): Promise<string> {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('')
}

function browserBinding(request: Request): { id: string; secret: string } | null {
    const values = (request.headers.get('Cookie') ?? '').split(';')
        .map((part) => part.trim()).filter((part) => part.startsWith(`${cookieName}=`))
    if (values.length !== 1) return null
    const [id, secret, extra] = values[0].slice(cookieName.length + 1).split('.')
    if (extra !== undefined || !opaquePattern.test(id ?? '') || !opaquePattern.test(secret ?? '')) return null
    return { id, secret }
}

async function boundFlow(request: Request, env: ApiBindings): Promise<BoundFlow | null> {
    const binding = browserBinding(request)
    if (!binding) return null
    const records = await Promise.all(stages.map((stage) => env.OAUTH_KV.get<AppleFlow>(flowKey(binding.id, stage), 'json')))
    const flow = records.find((record) => record !== null)
    if (!flow || flow.expiresAt <= nowSeconds() || flow.browserHash !== await hash(binding.secret)) return null
    return { id: binding.id, flow }
}

async function saveFlow(env: ApiBindings, id: string, flow: AppleFlow): Promise<void> {
    // KV's minimum TTL is 60 seconds; expiresAt remains the actual authorization deadline.
    // Each transition writes a different key: Workers KV limits writes to one
    // per key per second, including otherwise valid fast sign-in transitions.
    await env.OAUTH_KV.put(flowKey(id, flow.stage), JSON.stringify(flow), {
        expirationTtl: Math.max(60, flow.expiresAt - nowSeconds())
    })
}

async function deleteFlow(env: ApiBindings, id: string): Promise<void> {
    await Promise.all(stages.map((stage) => env.OAUTH_KV.delete(flowKey(id, stage))))
}

export function isAppleConfigured(env: ApiBindings): boolean {
    return env.AUTH_MODE === 'apple'
        && typeof env.APPLE_SERVICE_ID === 'string' && /^[A-Za-z0-9][A-Za-z0-9.-]{0,254}$/.test(env.APPLE_SERVICE_ID)
        && typeof env.APPLE_TEAM_ID === 'string' && /^[A-Z0-9]{10}$/.test(env.APPLE_TEAM_ID)
        && typeof env.APPLE_KEY_ID === 'string' && /^[A-Z0-9]{10}$/.test(env.APPLE_KEY_ID)
        && typeof env.APPLE_PRIVATE_KEY === 'string'
        && env.APPLE_PRIVATE_KEY.replace(/\\n/g, '\n').trim().startsWith('-----BEGIN PRIVATE KEY-----')
        && env.APPLE_PRIVATE_KEY.replace(/\\n/g, '\n').trim().endsWith('-----END PRIVATE KEY-----')
        && Boolean(env.OAUTH_KV && env.DB)
}

function clientDescription(details: AppleFlow['details']): string {
    const publisher = details.clientDomain
        ? `<p>Client domain: ${escapeHTML(details.clientDomain)}</p>`
        : '<p>The client name is self-reported.</p>'
    return `<p>Client: ${escapeHTML(details.clientName)}</p>${publisher}<p>Callback host: ${escapeHTML(details.redirectHost)}</p>`
}

export async function beginAppleConsent(
    request: Request, env: ApiBindings, details: ConsentDescription, handle: string, headers: Headers
): Promise<Response> {
    if (!isAppleConfigured(env)) return response('Apple sign-in is not configured.', 503, headers)
    if (new URL(request.url).origin !== publicOrigin || !opaquePattern.test(handle)) {
        return response('Start again from your ChatGPT connection.', 400, headers)
    }
    // One pending Apple sign-in per browser. A new one replaces the prior bound flow.
    const previous = await boundFlow(request, env)
    if (previous) await deleteFlow(env, previous.id)
    const id = randomOpaque()
    const secret = randomOpaque()
    const createdAt = nowSeconds()
    await saveFlow(env, id, {
        browserHash: await hash(secret), handle,
        details: { clientName: details.clientName, clientDomain: details.clientDomain,
            redirectHost: details.redirectHost, scope: [...details.scope] },
        createdAt, expiresAt: createdAt + flowTTL, stage: 'pending'
    })
    headers.append('Set-Cookie', `${cookieName}=${id}.${secret}; Path=/; Max-Age=${flowTTL}; Secure; HttpOnly; SameSite=None`)
    return html(`<h1>Sign in to lifelify</h1>${clientDescription(details)}
<p>Continue with Apple to identify your lifelify account. You will review the requested permissions next.</p>
<p>This development connection accesses cloud shopping data. iPhone synchronization is optional: enable it explicitly in lifelify with the same account. The app retrieves changes when opened or synchronized manually. Signing in or allowing this connection does not upload your existing iPhone shopping list.</p>
<form method="post" action="/auth/apple/start"><input type="hidden" name="flow" value="${id}"><button type="submit">Continue with Apple</button></form>`, headers)
}

async function readLimitedBody(body: ReadableStream<Uint8Array> | null, maximum: number): Promise<string> {
    if (!body) return ''
    const reader = body.getReader()
    const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false })
    let total = 0
    let result = ''
    try {
        while (true) {
            const { done, value } = await reader.read()
            if (done) break
            total += value.byteLength
            if (total > maximum) {
                await reader.cancel()
                throw new AppleAuthenticationError(413, 'The sign-in response is too large. Start again from ChatGPT.')
            }
            result += decoder.decode(value, { stream: true })
        }
        return result + decoder.decode()
    } finally {
        reader.releaseLock()
    }
}

async function formBody(request: Request): Promise<URLSearchParams> {
    if (!/^application\/x-www-form-urlencoded(?:\s*;|\s*$)/i.test(request.headers.get('Content-Type') ?? '')) {
        throw new AppleAuthenticationError(415, 'Submit the sign-in form from this site.')
    }
    const form = new URLSearchParams(await readLimitedBody(request.body, maximumBodyBytes))
    if ([...form.keys()].some((key) => form.getAll(key).length !== 1)) {
        throw new AppleAuthenticationError(400, 'Invalid sign-in response. Start again from ChatGPT.')
    }
    return form
}

async function startApple(request: Request, env: ApiBindings): Promise<Response> {
    if (request.headers.get('Origin') !== publicOrigin) {
        return response('Sign-in must be started from this site.', 403)
    }
    const form = await formBody(request)
    if ([...form.keys()].length !== 1 || !opaquePattern.test(form.get('flow') ?? '')) {
        return response('Invalid sign-in form. Start again from ChatGPT.')
    }
    const bound = await boundFlow(request, env)
    if (!bound || bound.id !== form.get('flow') || bound.flow.stage !== 'pending') {
        return response('Sign-in expired or belongs to another browser. Start again from ChatGPT.', 403)
    }
    const state = randomOpaque()
    const nonce = randomOpaque()
    await env.OAUTH_KV.delete(flowKey(bound.id, 'pending'))
    await saveFlow(env, bound.id, { ...bound.flow, stage: 'started', stateHash: await hash(state), nonce })
    const location = new URL(`${appleOrigin}/auth/authorize`)
    location.search = new URLSearchParams({ client_id: env.APPLE_SERVICE_ID!, redirect_uri: appleCallback,
        response_type: 'code', response_mode: 'form_post', state, nonce }).toString()
    // No email or name scope: only the stable verified Apple subject is needed.
    return redirect(location.toString())
}

async function appleJSON(path: '/auth/token' | '/auth/keys', init: RequestInit = {}): Promise<Record<string, unknown>> {
    const appleResponse = await fetch(`${appleOrigin}${path}`, {
        // Workers does not implement redirect:'error'. Manual + the non-2xx
        // rejection below prevents forwarding the client secret to any redirect.
        ...init, redirect: 'manual', signal: AbortSignal.timeout(5000),
        headers: { Accept: 'application/json', ...init.headers }
    })
    if (!appleResponse.ok) {
        await appleResponse.body?.cancel()
        throw new AppleAuthenticationError(502, 'Apple sign-in could not be verified. Start again from ChatGPT.')
    }
    const value: unknown = JSON.parse(await readLimitedBody(appleResponse.body, maximumAppleResponseBytes))
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
        throw new AppleAuthenticationError(502, 'Apple returned an invalid sign-in response.')
    }
    return value as Record<string, unknown>
}

async function verifiedAppleSubject(env: ApiBindings, code: string, flow: AppleFlow): Promise<string> {
    const issuedAt = nowSeconds()
    const privateKey = await importPKCS8(env.APPLE_PRIVATE_KEY!.replace(/\\n/g, '\n').trim(), 'ES256')
    const clientSecret = await new SignJWT({})
        .setProtectedHeader({ alg: 'ES256', kid: env.APPLE_KEY_ID! })
        .setIssuer(env.APPLE_TEAM_ID!).setSubject(env.APPLE_SERVICE_ID!)
        .setAudience(appleOrigin).setIssuedAt(issuedAt).setExpirationTime(issuedAt + 300).sign(privateKey)
    const tokens = await appleJSON('/auth/token', {
        method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ client_id: env.APPLE_SERVICE_ID!, client_secret: clientSecret,
            code, grant_type: 'authorization_code', redirect_uri: appleCallback }).toString()
    })
    if (typeof tokens.id_token !== 'string' || tokens.id_token.length > 16 * 1024) {
        throw new AppleAuthenticationError(400, 'Apple identity could not be verified.')
    }
    return verifyAppleIdentityToken(tokens.id_token, env.APPLE_SERVICE_ID!, flow.nonce!, flow.createdAt)
}

// Web and native sign-in use different audiences but the same trusted Apple
// issuer, signing keys and claim validation. Callers supply server-owned nonce
// expectations rather than trusting identity fields from the client.
export async function verifyAppleIdentityToken(
    idToken: string, audience: string, nonce: string, createdAt: number
): Promise<string> {
    if (!idToken || idToken.length > 16 * 1024) {
        throw new AppleAuthenticationError(400, 'Apple identity could not be verified.')
    }
    const header = decodeProtectedHeader(idToken)
    if (header.alg !== 'RS256' || typeof header.kid !== 'string' || !header.kid || header.kid.length > 200) {
        throw new AppleAuthenticationError(400, 'Apple identity could not be verified.')
    }
    const jwks = await appleJSON('/auth/keys')
    if (!Array.isArray(jwks.keys) || jwks.keys.length === 0 || jwks.keys.length > 20) {
        throw new AppleAuthenticationError(502, 'Apple signing keys are unavailable.')
    }
    const { payload } = await jwtVerify(idToken, createLocalJWKSet({ keys: jwks.keys }), {
        algorithms: ['RS256'], issuer: appleOrigin, audience,
        requiredClaims: ['iss', 'aud', 'exp', 'iat', 'nonce', 'sub'],
        maxTokenAge: 600, clockTolerance: 5
    })
    if (typeof payload.sub !== 'string' || !payload.sub || payload.sub.length > 255
        || /[\u0000-\u001f\u007f]/.test(payload.sub) || payload.nonce !== nonce
        || payload.aud !== audience || typeof payload.iat !== 'number' || payload.iat < createdAt - 5) {
        throw new AppleAuthenticationError(400, 'Apple identity could not be verified.')
    }
    return payload.sub
}

export async function provisionAppleUser(env: ApiBindings, appleSubject: string): Promise<string | null> {
    const id = crypto.randomUUID()
    const timestamp = Date.now()
    // The unique apple_sub constraint makes concurrent first sign-ins converge.
    // A deleted row is deliberately not revived or updated by this upsert.
    await env.DB.prepare(`INSERT INTO users (id, apple_sub, created_at, updated_at)
        VALUES (?, ?, ?, ?) ON CONFLICT(apple_sub) DO NOTHING`)
        .bind(id, appleSubject, timestamp, timestamp).run()
    const user = await env.DB.prepare('SELECT id, deleted_at FROM users WHERE apple_sub = ?')
        .bind(appleSubject).first<{ id: string; deleted_at: number | null }>()
    return user && user.deleted_at === null && user.id !== developmentUserId ? user.id : null
}

async function finishApple(request: Request, env: ApiBindings): Promise<Response> {
    const form = await formBody(request)
    const state = form.get('state')
    const bound = await boundFlow(request, env)
    if (!state || !opaquePattern.test(state) || !bound || bound.flow.stage !== 'started'
        || bound.flow.stateHash !== await hash(state) || !bound.flow.nonce) {
        return response('Sign-in could not be verified in this browser. Start again from ChatGPT.', 403)
    }
    const headers = new Headers()
    try {
        // Reserve before exchange. KV is not atomic; deployment documentation covers
        // its replay limits. Apple also accepts each authorization code only once.
        await env.OAUTH_KV.delete(flowKey(bound.id, 'started'))
        const code = form.get('code')
        if (form.has('error') || !code || code.length > 2048) {
            throw new AppleAuthenticationError(400, 'Apple sign-in was not completed. Start again from ChatGPT.')
        }
        const subject = await verifiedAppleSubject(env, code, bound.flow)
        const userId = await provisionAppleUser(env, subject)
        if (!userId) throw new AppleAuthenticationError(403, 'This lifelify account is unavailable.')
        if (bound.flow.expiresAt <= nowSeconds()) {
            throw new AppleAuthenticationError(400, 'Sign-in expired. Start again from ChatGPT.')
        }
        await saveFlow(env, bound.id, { ...bound.flow, stage: 'authenticated',
            stateHash: undefined, nonce: undefined, userId })
        // First return to a same-origin GET. The provider's SameSite=Lax consent
        // cookie is then available for the final same-origin permission POST.
        return redirect(`${publicOrigin}/auth/apple/complete`, headers)
    } catch {
        await deleteFlow(env, bound.id)
        expireCookie(headers)
        return response('Apple sign-in could not be completed. Start again from ChatGPT.', 400, headers)
    }
}

async function activeIdentity(env: ApiBindings, flow: AppleFlow): Promise<string | null> {
    if (flow.stage !== 'authenticated' || !flow.userId || flow.userId === developmentUserId) return null
    const user = await env.DB.prepare('SELECT id FROM users WHERE id = ? AND deleted_at IS NULL')
        .bind(flow.userId).first<{ id: string }>()
    return user?.id ?? null
}

async function completeApple(request: Request, env: ApiBindings): Promise<Response> {
    const bound = await boundFlow(request, env)
    if (!bound || !await activeIdentity(env, bound.flow)) {
        return response('Sign-in expired or the account is unavailable. Start again from ChatGPT.', 403)
    }
    const { details, handle } = bound.flow
    const permissions = details.scope.map((scope) => `<li>${escapeHTML(scope)}</li>`).join('')
    return html(`<h1>Allow access to lifelify?</h1>${clientDescription(details)}
<p>You signed in with Apple. No permission has been granted to the client yet.</p>
<p>Requested permissions:</p><ul>${permissions}</ul>
<p>This development connection accesses cloud shopping data. iPhone synchronization is optional: enable it explicitly in lifelify with the same account. The app retrieves changes when opened or synchronized manually. Signing in or allowing this connection does not upload your existing iPhone shopping list.</p>
<p>Access tokens expire after one hour. This connection can renew access for up to seven days.</p>
<form method="post" action="/authorize"><input type="hidden" name="handle" value="${escapeHTML(handle)}">
<button type="submit" name="decision" value="approve">Allow listed access</button>
<button type="submit" name="decision" value="deny">Deny</button></form>`)
}

export async function handleAppleAuthentication(request: Request, env: ApiBindings): Promise<Response> {
    if (!isAppleConfigured(env)) return response('Apple sign-in is not configured.', 503)
    const url = new URL(request.url)
    if (url.origin !== publicOrigin) return response('Use the configured lifelify sign-in page.', 400)
    try {
        if (url.pathname === '/auth/apple/start' && request.method === 'POST') return await startApple(request, env)
        if (url.pathname === '/auth/apple/callback' && request.method === 'POST') return await finishApple(request, env)
        if (url.pathname === '/auth/apple/complete' && request.method === 'GET') return await completeApple(request, env)
        return response('Not found.', 404)
    } catch (error) {
        if (error instanceof AppleAuthenticationError) return response(error.publicMessage, error.status)
        // Do not log Apple responses, codes, credentials, headers or browser handles.
        return response('Apple sign-in is temporarily unavailable. Start again from ChatGPT.', 503)
    }
}

export async function resolveAppleConsentIdentity(
    request: Request, env: ApiBindings, handle: string
): Promise<string | null> {
    if (!isAppleConfigured(env) || !opaquePattern.test(handle)
        || new URL(request.url).origin !== publicOrigin || request.headers.get('Origin') !== publicOrigin) return null
    const bound = await boundFlow(request, env)
    if (!bound || bound.flow.handle !== handle) return null
    const userId = await activeIdentity(env, bound.flow)
    if (!userId) return null
    await deleteFlow(env, bound.id)
    return userId
}

export async function clearAppleConsent(request: Request, env: ApiBindings, headers: Headers): Promise<void> {
    expireCookie(headers)
    if (!env.OAUTH_KV) return
    const bound = await boundFlow(request, env)
    if (bound) await deleteFlow(env, bound.id)
}
