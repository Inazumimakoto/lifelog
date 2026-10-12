import { provisionAppleUser, verifyAppleIdentityToken } from './apple'
import { developmentUserId, publicOrigin, type ApiBindings } from './config'

const challengeTTL = 600
const accessTTL = 3600
const refreshTTL = 30 * 24 * 60 * 60
const maximumBodyBytes = 24 * 1024
const opaquePattern = /^[A-Za-z0-9_-]{43}$/
const nowSeconds = () => Math.floor(Date.now() / 1000)

type NativeIdentity = { userId: string; sessionId: string }
type Challenge = { id: string; nonce_hash: string; created_at: number; expires_at: number }

class NativeAuthenticationError extends Error {
    constructor(readonly status: number, readonly code: string) { super('Native authentication failed') }
}

function json(value: unknown, status = 200): Response {
    return Response.json(value, { status, headers: {
        'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
        'Referrer-Policy': 'no-referrer'
    } })
}

function configured(env: ApiBindings): boolean {
    // Native identity tokens are verified with Apple's public keys. A private
    // key, Web Services ID and the browser's authentication cookies are unused.
    return env.AUTH_MODE === 'apple' && Boolean(env.DB)
        && typeof env.APPLE_APP_ID === 'string'
        && /^[A-Za-z0-9][A-Za-z0-9.-]{0,254}$/.test(env.APPLE_APP_ID)
}

function randomOpaque(): string {
    const bytes = crypto.getRandomValues(new Uint8Array(32))
    return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

async function hash(value: string): Promise<string> {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
    return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('')
}

async function body(request: Request, fields: string[]): Promise<Record<string, unknown>> {
    if (!/^application\/json(?:\s*;|\s*$)/i.test(request.headers.get('Content-Type') ?? '')) {
        throw new NativeAuthenticationError(415, 'json_required')
    }
    const reader = request.body?.getReader()
    if (!reader) throw new NativeAuthenticationError(400, 'invalid_body')
    let total = 0
    let text = ''
    const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false })
    try {
        while (true) {
            const { done, value } = await reader.read()
            if (done) break
            total += value.byteLength
            if (total > maximumBodyBytes) {
                await reader.cancel()
                throw new NativeAuthenticationError(413, 'body_too_large')
            }
            text += decoder.decode(value, { stream: true })
        }
        text += decoder.decode()
    } catch (error) {
        if (error instanceof NativeAuthenticationError) throw error
        throw new NativeAuthenticationError(400, 'invalid_body')
    } finally {
        reader.releaseLock()
    }
    let value: unknown
    try { value = JSON.parse(text) } catch { throw new NativeAuthenticationError(400, 'invalid_body') }
    // JSON.parse otherwise silently keeps the last duplicate key. Scan valid
    // JSON string tokens at the top level, including escaped key spellings.
    const keys = new Set<string>()
    let depth = 0
    for (let index = 0; index < text.length; index++) {
        const character = text[index]
        if (character === '{' || character === '[') depth++
        else if (character === '}' || character === ']') depth--
        else if (character === '"') {
            const start = index
            for (index++; index < text.length; index++) {
                if (text[index] === '\\') index++
                else if (text[index] === '"') break
            }
            if (depth === 1 && /^\s*:/.test(text.slice(index + 1))) {
                const key = JSON.parse(text.slice(start, index + 1)) as string
                if (keys.has(key)) throw new NativeAuthenticationError(400, 'invalid_body')
                keys.add(key)
            }
        }
    }
    if (!value || typeof value !== 'object' || Array.isArray(value)
        || Object.keys(value).length !== fields.length
        || Object.keys(value).some(key => !fields.includes(key))) {
        throw new NativeAuthenticationError(400, 'invalid_body')
    }
    return value as Record<string, unknown>
}

async function createChallenge(request: Request, env: ApiBindings): Promise<Response> {
    await body(request, [])
    const id = randomOpaque(), nonce = randomOpaque(), now = nowSeconds()
    // Bound opportunistic cleanup. Rate limiting is still required before this
    // unauthenticated prototype endpoint is offered to the general public.
    await env.DB.batch([
        env.DB.prepare(`DELETE FROM native_auth_challenges WHERE id IN
            (SELECT id FROM native_auth_challenges WHERE expires_at <= ? ORDER BY expires_at LIMIT 128)`).bind(now),
        env.DB.prepare(`INSERT INTO native_auth_challenges (id, nonce_hash, created_at, expires_at)
            VALUES (?, ?, ?, ?)`).bind(id, await hash(nonce), now, now + challengeTTL)
    ])
    return json({ id, nonce, expires_at: now + challengeTTL })
}

function tokenResponse(accessToken: string, refreshToken: string, userId: string): Response {
    return json({ access_token: accessToken, refresh_token: refreshToken,
        expires_in: accessTTL, refresh_expires_in: refreshTTL, user: { id: userId } })
}

async function createSession(request: Request, env: ApiBindings): Promise<Response> {
    const input = await body(request, ['challenge_id', 'id_token'])
    if (typeof input.challenge_id !== 'string' || !opaquePattern.test(input.challenge_id)
        || typeof input.id_token !== 'string' || !input.id_token || input.id_token.length > 16 * 1024) {
        throw new NativeAuthenticationError(400, 'invalid_body')
    }
    const challenge = await env.DB.prepare(`SELECT id, nonce_hash, created_at, expires_at
        FROM native_auth_challenges WHERE id = ? AND consumed_at IS NULL AND expires_at > ?`)
        .bind(input.challenge_id, nowSeconds()).first<Challenge>()
    if (!challenge) throw new NativeAuthenticationError(401, 'invalid_apple_sign_in')
    let subject: string
    try {
        subject = await verifyAppleIdentityToken(input.id_token, env.APPLE_APP_ID!, challenge.nonce_hash, challenge.created_at)
    } catch {
        throw new NativeAuthenticationError(401, 'invalid_apple_sign_in')
    }
    const now = nowSeconds()
    // The signature may be checked concurrently, but exactly one request may
    // consume this challenge. A lost response requires a new Apple sign-in.
    const consumed = await env.DB.prepare(`UPDATE native_auth_challenges SET consumed_at = ?
        WHERE id = ? AND consumed_at IS NULL AND expires_at > ? RETURNING id`)
        .bind(now, challenge.id, now).first<{ id: string }>()
    if (!consumed) throw new NativeAuthenticationError(401, 'invalid_apple_sign_in')
    const userId = await provisionAppleUser(env, subject)
    if (!userId) throw new NativeAuthenticationError(403, 'account_unavailable')
    const accessToken = randomOpaque(), refreshToken = randomOpaque(), id = randomOpaque()
    const session = await env.DB.prepare(`INSERT INTO native_sessions
        (id, user_id, access_token_hash, refresh_token_hash, created_at, updated_at, access_expires_at, refresh_expires_at)
        SELECT ?, id, ?, ?, ?, ?, ?, ? FROM users WHERE id = ? AND deleted_at IS NULL
        RETURNING id`)
        .bind(id, await hash(accessToken), await hash(refreshToken), now, now, now + accessTTL, now + refreshTTL, userId)
        .first<{ id: string }>()
    if (!session) throw new NativeAuthenticationError(403, 'account_unavailable')
    return tokenResponse(accessToken, refreshToken, userId)
}

export async function resolveNativeSession(request: Request, env: ApiBindings): Promise<NativeIdentity | null> {
    if (!configured(env)) return null
    const token = /^Bearer ([A-Za-z0-9_-]{43})$/i.exec(request.headers.get('Authorization') ?? '')?.[1]
    if (!token) return null
    const session = await env.DB.prepare(`SELECT s.id AS sessionId, s.user_id AS userId
        FROM native_sessions s JOIN users u ON u.id = s.user_id
        WHERE s.access_token_hash = ? AND s.access_expires_at > ? AND s.refresh_expires_at > ? AND s.revoked_at IS NULL
        AND u.deleted_at IS NULL AND u.id <> ?`)
        .bind(await hash(token), nowSeconds(), nowSeconds(), developmentUserId).first<NativeIdentity>()
    return session ?? null
}

async function refreshSession(request: Request, env: ApiBindings): Promise<Response> {
    const input = await body(request, ['refresh_token'])
    if (typeof input.refresh_token !== 'string' || !opaquePattern.test(input.refresh_token)) {
        throw new NativeAuthenticationError(400, 'invalid_body')
    }
    const accessToken = randomOpaque(), refreshToken = randomOpaque(), now = nowSeconds()
    // Atomic rotation: the prior access and refresh tokens both stop working.
    // The replacement refresh token gets a new 30-day lifetime. If its response
    // is lost, the app must sign in again instead of replaying the old token.
    const session = await env.DB.prepare(`UPDATE native_sessions
        SET access_token_hash = ?, refresh_token_hash = ?, updated_at = ?, access_expires_at = ?, refresh_expires_at = ?
        WHERE refresh_token_hash = ? AND refresh_expires_at > ? AND revoked_at IS NULL
        AND user_id <> ? AND EXISTS (SELECT 1 FROM users WHERE users.id = native_sessions.user_id AND users.deleted_at IS NULL)
        RETURNING user_id AS userId`)
        .bind(await hash(accessToken), await hash(refreshToken), now, now + accessTTL, now + refreshTTL,
            await hash(input.refresh_token), now, developmentUserId).first<{ userId: string }>()
    if (!session) throw new NativeAuthenticationError(401, 'invalid_session')
    return tokenResponse(accessToken, refreshToken, session.userId)
}

export async function handleNativeAuthentication(request: Request, env: ApiBindings): Promise<Response> {
    if (!configured(env)) return json({ error: 'native_auth_not_configured' }, 503)
    const url = new URL(request.url)
    if (url.origin !== publicOrigin) return json({ error: 'invalid_origin' }, 400)
    // This interface uses bearer credentials, never ambient browser cookies.
    // Reject browser cross-origin requests even if a caller adds JSON headers.
    const origin = request.headers.get('Origin')
    if (origin !== null && origin !== publicOrigin) return json({ error: 'invalid_origin' }, 403)
    try {
        if (url.pathname === '/auth/native/apple/challenge' && request.method === 'POST') return await createChallenge(request, env)
        if (url.pathname === '/auth/native/apple/session' && request.method === 'POST') return await createSession(request, env)
        if (url.pathname === '/auth/native/refresh' && request.method === 'POST') return await refreshSession(request, env)
        if (url.pathname === '/auth/native/session' && request.method === 'GET') {
            const session = await resolveNativeSession(request, env)
            return session ? json({ user: { id: session.userId } }) : json({ error: 'invalid_session' }, 401)
        }
        if (url.pathname === '/auth/native/logout' && request.method === 'POST') {
            await body(request, [])
            const session = await resolveNativeSession(request, env)
            if (!session) return json({ error: 'invalid_session' }, 401)
            await env.DB.prepare('UPDATE native_sessions SET revoked_at = ? WHERE id = ? AND user_id = ? AND revoked_at IS NULL')
                .bind(nowSeconds(), session.sessionId, session.userId).run()
            return json({ ok: true })
        }
        return json({ error: 'not_found' }, 404)
    } catch (error) {
        if (error instanceof NativeAuthenticationError) return json({ error: error.code }, error.status)
        // Do not log credentials, Apple JWTs, nonce challenges or request bodies.
        return json({ error: 'native_auth_unavailable' }, 503)
    }
}
