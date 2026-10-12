import type { ConsentDescription } from '@cloudflare/workers-oauth-provider'
import { timingSafeEqual } from 'hono/utils/buffer'
import { appLinkOrigin, developmentUserId, publicOrigin, shoppingScopes, type ApiBindings } from './config'
import { resolveNativeSession } from './native-auth'

const cookieName = '__Host-lifelify-app'
const opaque = /^[A-Za-z0-9_-]{43}$/
const ttl = 600
const nowSeconds = () => Math.floor(Date.now() / 1000)
type ConsentRow = {
    id: string; consent_handle: string; browser_hash: string; client_name: string
    client_domain: string; scopes: string; expires_at: number
    status: 'pending' | 'approved' | 'denied' | 'consumed'
    approved_user_id: string | null; approved_session_id: string | null
}

export class AppConsentError extends Error {
    constructor(readonly status: number, readonly code: string) { super('App approval could not be verified') }
}

export function isAppApprovalEnabled(env: ApiBindings): boolean {
    return env.AUTH_MODE === 'apple' && env.APP_APPROVAL_ENABLED === 'true'
}

function randomOpaque(): string {
    return btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))))
        .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

async function hash(value: string): Promise<string> {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
    return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('')
}

function json(value: unknown, status = 200): Response {
    return Response.json(value, { status, headers: { 'Cache-Control': 'no-store',
        'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' } })
}

async function browserConsent(request: Request, env: ApiBindings, handle?: string): Promise<ConsentRow | null> {
    const values = (request.headers.get('Cookie') ?? '').split(';').map(part => part.trim())
        .filter(part => part.startsWith(`${cookieName}=`))
    if (values.length !== 1) return null
    const parts = values[0].slice(cookieName.length + 1).split('.')
    if (parts.length !== 2 || !parts.every(value => opaque.test(value))) return null
    const row = await env.DB.prepare('SELECT * FROM shopping_oauth_requests WHERE id = ?')
        .bind(parts[0]).first<ConsentRow>()
    if (!row || (handle !== undefined && row.consent_handle !== handle)
        || !await timingSafeEqual(row.browser_hash, await hash(parts[1]))) return null
    return row
}

export async function hasAppConsent(request: Request, env: ApiBindings, handle: string): Promise<boolean> {
    return isAppApprovalEnabled(env) && await browserConsent(request, env, handle) !== null
}

// A read before provider approval keeps an early/pending POST from consuming
// the library's browser consent. The final mutation still follows its checks.
export async function resolveAppConsentIdentity(request: Request, env: ApiBindings, handle: string): Promise<string> {
    const row = await browserConsent(request, env, handle)
    if (!row) throw new AppConsentError(403, 'invalid_browser')
    if (row.expires_at <= nowSeconds()) throw new AppConsentError(410, 'request_expired')
    if (row.status !== 'approved') throw new AppConsentError(409, 'approval_required')
    const active = await env.DB.prepare(`SELECT u.id FROM users u JOIN native_sessions s ON s.user_id = u.id
        WHERE u.id = ? AND u.deleted_at IS NULL AND u.id <> ? AND s.id = ?
        AND s.revoked_at IS NULL AND s.access_expires_at > ? AND s.refresh_expires_at > ?`)
        .bind(row.approved_user_id, developmentUserId, row.approved_session_id, nowSeconds(), nowSeconds())
        .first<{ id: string }>()
    if (!active) throw new AppConsentError(403, 'account_unavailable')
    return active.id
}

export async function consumeAppConsent(request: Request, env: ApiBindings, handle: string, userId: string): Promise<void> {
    const row = await browserConsent(request, env, handle)
    if (!row) throw new AppConsentError(403, 'invalid_browser')
    const now = nowSeconds()
    const claimed = await env.DB.prepare(`UPDATE shopping_oauth_requests SET status = 'consumed'
        WHERE id = ? AND consent_handle = ? AND status = 'approved' AND expires_at > ?
        AND approved_user_id = ? AND EXISTS (SELECT 1 FROM users u JOIN native_sessions s ON s.user_id = u.id
            WHERE u.id = shopping_oauth_requests.approved_user_id AND u.deleted_at IS NULL AND u.id <> ?
            AND s.id = shopping_oauth_requests.approved_session_id AND s.revoked_at IS NULL
            AND s.access_expires_at > ? AND s.refresh_expires_at > ?) RETURNING id`)
        .bind(row.id, handle, now, userId, developmentUserId, now, now).first<{ id: string }>()
    if (!claimed) throw new AppConsentError(409, 'approval_unavailable')
}

export async function clearAppConsent(request: Request, env: ApiBindings, handle: string, headers: Headers, denied = false): Promise<void> {
    const row = await browserConsent(request, env, handle)
    if (!row) return
    if (denied) {
        await env.DB.prepare(`UPDATE shopping_oauth_requests SET status = 'denied'
            WHERE id = ? AND status IN ('pending', 'approved')`).bind(row.id).run()
    }
    headers.append('Set-Cookie', `${cookieName}=; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=0`)
}

const escapeHTML = (value: string) => value.replace(/[&<>"']/g, char => `&#${char.charCodeAt(0)};`)

function resumePage(message: string, status: number, row?: ConsentRow): Response {
    const nonce = randomOpaque()
    const decision = row?.status === 'approved' ? 'approve' : row?.status === 'denied' ? 'deny' : null
    const form = decision && row ? `<form id="finish" method="post" action="${publicOrigin}/authorize"><input type="hidden" name="handle" value="${escapeHTML(row.consent_handle)}"><input type="hidden" name="decision" value="${decision}"><button type="submit">Continue to ChatGPT</button></form>` : ''
    const script = decision ? `<script nonce="${nonce}">document.getElementById('finish').requestSubmit();</script>` : ''
    return new Response(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Continue the ChatGPT connection</title></head><body><main><h1>Continue the ChatGPT connection</h1><p>${escapeHTML(message)}</p>${form}</main>${script}</body></html>`, {
        status,
        headers: {
            'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store',
            'Referrer-Policy': 'no-referrer', 'X-Frame-Options': 'DENY', 'X-Content-Type-Options': 'nosniff',
            'Content-Security-Policy': `default-src 'none'; script-src 'nonce-${nonce}'; form-action 'self' https://chatgpt.com; frame-ancestors 'none'; base-uri 'none'`
        }
    })
}

async function resumeConsent(request: Request, env: ApiBindings, url: URL): Promise<Response> {
    if (url.searchParams.getAll('id').length !== 1 || !opaque.test(url.searchParams.get('id') ?? '')
        || [...url.searchParams.keys()].some(key => key !== 'id') || url.hash) {
        return resumePage('This connection link is invalid. Return to the original ChatGPT connection page.', 400)
    }
    // The app only knows a public request identifier. Its decision must still
    // finish in the browser that holds the original secret binding cookie.
    const row = await browserConsent(request, env)
    if (!row || row.id !== url.searchParams.get('id')) {
        return resumePage('This browser cannot finish the request. Return to the original ChatGPT connection page in the browser where you started. Your decision in lifelify is unchanged.', 403)
    }
    if (row.expires_at <= nowSeconds()) {
        return resumePage('This connection request expired. Start a new connection from ChatGPT.', 410)
    }
    if (row.status === 'consumed') {
        return resumePage('This request has already been completed. Return to ChatGPT to check the connection.', 200)
    }
    if (row.status === 'pending') {
        return resumePage('Access has not been approved. Return to lifelify to review the request, or to the original ChatGPT connection page.', 409)
    }
    if (!opaque.test(row.consent_handle)) {
        return resumePage('This connection is unavailable. Return to the original ChatGPT connection page.', 503)
    }
    // GET never consumes approval or creates an OAuth grant. The form POST
    // keeps the provider's own browser-cookie, account and replay checks.
    return resumePage('Your decision was received. Finishing this connection in the original browser.', 200, row)
}

export async function beginAppConsent(request: Request, env: ApiBindings, details: ConsentDescription,
    handle: string, headers: Headers): Promise<Response> {
    const id = randomOpaque(), secret = randomOpaque(), expires = nowSeconds() + ttl
    await env.DB.batch([
        env.DB.prepare(`DELETE FROM shopping_oauth_requests WHERE id IN
            (SELECT id FROM shopping_oauth_requests WHERE expires_at <= ? ORDER BY expires_at LIMIT 128)`).bind(nowSeconds()),
        env.DB.prepare(`INSERT INTO shopping_oauth_requests
            (id, consent_handle, browser_hash, client_name, client_domain, scopes, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)`).bind(id, handle, await hash(secret), details.clientName,
                details.clientDomain ?? '', JSON.stringify(details.scope), expires)
    ])
    const fallback = new URL(request.url)
    fallback.searchParams.set('login_method', 'apple')
    const nonce = randomOpaque()
    headers.append('Set-Cookie', `${cookieName}=${id}.${secret}; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=${ttl}`)
    headers.set('Content-Type', 'text/html; charset=utf-8')
    headers.set('Cache-Control', 'no-store')
    headers.set('Referrer-Policy', 'strict-origin')
    headers.set('X-Frame-Options', 'DENY')
    headers.set('X-Content-Type-Options', 'nosniff')
    headers.set('Content-Security-Policy', `default-src 'none'; script-src 'nonce-${nonce}'; connect-src 'self'; form-action 'self' https://chatgpt.com; frame-ancestors 'none'; base-uri 'none'`)
    const permissions = details.scope.map(scope => `<li>${escapeHTML(scope)}</li>`).join('')
    // This page retains the original OAuth browser cookies. The other domain
    // only opens the installed app; it never grants permissions or holds tokens.
    return new Response(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Connect lifelify</title></head><body><main>
<h1>Approve in lifelify</h1><p>Client: ${escapeHTML(details.clientName)}</p><p>${details.clientDomain ? `Client domain: ${escapeHTML(details.clientDomain)}` : 'The client name is self-reported.'}</p><p>Callback host: ${escapeHTML(details.redirectHost)}</p><ul>${permissions}</ul>
<p>Open the lifelify development app and review these permissions. Return to this ChatGPT connection screen after approving. This request expires in 10 minutes.</p>
<p>Shopping synchronization is optional. Enable it explicitly in lifelify with the same account to upload your iPhone shopping list and retrieve cloud changes when opening the app or synchronizing manually. Allowing access here does not start synchronization.</p>
<p><a href="${appLinkOrigin}/connect/${id}">Open lifelify to review access</a></p>
<p id="status" role="status">Waiting for your decision in lifelify.</p>
<form id="finish" method="post" action="/authorize"><input type="hidden" name="handle" value="${escapeHTML(handle)}"><input id="decision" type="hidden" name="decision" value="approve"></form>
<button id="check" type="button">Check approval</button>
<form method="post" action="/authorize"><input type="hidden" name="handle" value="${escapeHTML(handle)}"><button name="decision" value="deny">Cancel connection</button></form>
<p><a href="${escapeHTML(fallback.href)}">Use Apple sign-in on this website instead</a></p>
</main><script nonce="${nonce}">
let busy=false,finished=false;const deadline=${expires}*1000;
async function check(){if(busy||finished)return;if(Date.now()>=deadline){finished=true;document.getElementById('status').textContent='This request expired. Start again from ChatGPT.';return;}busy=true;try{const response=await fetch('/auth/app/status?id=${id}',{cache:'no-store',credentials:'same-origin',redirect:'error'});if(!response.ok){if(response.status===410||response.status===403){finished=true;document.getElementById('status').textContent='This request expired or was replaced. Start again from ChatGPT.';}return;}const result=await response.json();if(result.status==='approved'||result.status==='denied'){finished=true;document.getElementById('decision').value=result.status==='approved'?'approve':'deny';document.getElementById('finish').requestSubmit();}}catch{}finally{busy=false;}}
document.getElementById('check').addEventListener('click',check);document.addEventListener('visibilitychange',()=>{if(!document.hidden)check();});setInterval(()=>{if(!document.hidden)check();},2000);check();
</script></body></html>`, { headers })
}

async function decisionBody(request: Request): Promise<'approve' | 'deny'> {
    if (!/^application\/json(?:\s*;|\s*$)/i.test(request.headers.get('Content-Type') ?? '')) {
        throw new AppConsentError(415, 'json_required')
    }
    const reader = request.body?.getReader()
    if (!reader) throw new AppConsentError(400, 'invalid_body')
    let total = 0, input = ''
    const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false })
    try {
        while (true) {
            const { value, done } = await reader.read()
            if (done) break
            total += value.byteLength
            if (total > 1024) { await reader.cancel(); throw new AppConsentError(413, 'body_too_large') }
            input += decoder.decode(value, { stream: true })
        }
        input += decoder.decode()
    } finally { reader.releaseLock() }
    // There is exactly one string field. This grammar rejects duplicate keys,
    // unknown fields and nested input while allowing JSON's escaped strings.
    if (!/^\s*\{\s*"(?:[^"\\\u0000-\u001f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"\s*:\s*"(?:[^"\\\u0000-\u001f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"\s*\}\s*$/.test(input)) {
        throw new AppConsentError(400, 'invalid_body')
    }
    const value = JSON.parse(input) as Record<string, unknown>
    if (Object.keys(value)[0] !== 'decision' || (value.decision !== 'approve' && value.decision !== 'deny')) {
        throw new AppConsentError(400, 'invalid_body')
    }
    return value.decision
}

export async function handleAppConsent(request: Request, env: ApiBindings): Promise<Response> {
    if (!isAppApprovalEnabled(env)) return json({ error: 'app_approval_not_configured' }, 503)
    const url = new URL(request.url)
    const origin = request.headers.get('Origin')
    if (url.origin !== publicOrigin || (origin !== null && origin !== publicOrigin)) return json({ error: 'invalid_origin' }, 403)
    try {
        if (url.pathname === '/auth/app/resume') {
            if (request.method !== 'GET') return json({ error: 'method_not_allowed' }, 405)
            return await resumeConsent(request, env, url)
        }
        if (url.pathname === '/auth/app/status' && request.method === 'GET') {
            if (url.searchParams.getAll('id').length !== 1 || !opaque.test(url.searchParams.get('id') ?? '')
                || [...url.searchParams.keys()].some(key => key !== 'id')) return json({ error: 'invalid_request' }, 400)
            const row = await browserConsent(request, env)
            if (!row || row.id !== url.searchParams.get('id')) return json({ error: 'invalid_browser' }, 403)
            if (row.expires_at <= nowSeconds()) return json({ error: 'request_expired' }, 410)
            return json({ status: row.status, expires_at: row.expires_at })
        }
        const id = /^\/auth\/app\/requests\/([A-Za-z0-9_-]{43})$/.exec(url.pathname)?.[1]
        if (!id || (request.method !== 'GET' && request.method !== 'POST')) return json({ error: 'not_found' }, 404)
        const session = await resolveNativeSession(request, env)
        if (!session) return json({ error: 'invalid_session' }, 401)
        const row = await env.DB.prepare('SELECT * FROM shopping_oauth_requests WHERE id = ?').bind(id).first<ConsentRow>()
        if (!row) return json({ error: 'not_found' }, 404)
        if (row.expires_at <= nowSeconds()) return json({ error: 'request_expired' }, 410)
        if (row.status !== 'pending') return json({ error: 'request_completed' }, 409)
        if (request.method === 'GET') {
            const scopes: unknown = JSON.parse(row.scopes)
            if (!Array.isArray(scopes) || scopes.some(scope => typeof scope !== 'string'
                || !([...shoppingScopes, 'offline_access'] as string[]).includes(scope))) throw new AppConsentError(400, 'invalid_request')
            return json({ id, client_name: row.client_name, client_domain: row.client_domain,
                callback_host: 'chatgpt.com', scopes, expires_at: row.expires_at })
        }
        const decision = await decisionBody(request)
        const status = decision === 'approve' ? 'approved' : 'denied'
        const now = nowSeconds()
        const result = await env.DB.prepare(`UPDATE shopping_oauth_requests
            SET status = ?, approved_user_id = ?, approved_session_id = ?
            WHERE id = ? AND status = 'pending' AND expires_at > ?
            AND EXISTS (SELECT 1 FROM users u JOIN native_sessions s ON s.user_id = u.id
                WHERE u.id = ? AND u.deleted_at IS NULL AND u.id <> ? AND s.id = ?
                AND s.revoked_at IS NULL AND s.access_expires_at > ? AND s.refresh_expires_at > ?) RETURNING id`)
            .bind(status, session.userId, session.sessionId, id, now, session.userId, developmentUserId, session.sessionId, now, now)
            .first<{ id: string }>()
        if (!result) return json({ error: 'request_completed' }, 409)
        return json({ status })
    } catch (error) {
        if (error instanceof AppConsentError) return json({ error: error.code }, error.status)
        if (error instanceof SyntaxError || error instanceof TypeError) return json({ error: 'invalid_body' }, 400)
        return json({ error: 'approval_unavailable' }, 503)
    }
}
