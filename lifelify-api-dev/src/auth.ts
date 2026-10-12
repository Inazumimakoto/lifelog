import OAuthProvider, {
    AuthorizationError,
    CimdFetchError,
    OAuthError,
    type AuthRequest,
    type ConsentDescription,
    type OAuthHelpers
} from '@cloudflare/workers-oauth-provider'
import { Hono } from 'hono'
import { bodyLimit } from 'hono/body-limit'
import { timingSafeEqual } from 'hono/utils/buffer'
import {
    beginAppleConsent,
    clearAppleConsent,
    isAppleConfigured,
    resolveAppleConsentIdentity
} from './apple'
import {
    AppConsentError, beginAppConsent, clearAppConsent, consumeAppConsent,
    hasAppConsent, isAppApprovalEnabled, resolveAppConsentIdentity
} from './app-consent'
import {
    developmentUserId,
    mcpResource,
    publicOrigin,
    shoppingScopes,
    type ApiBindings
} from './config'

export type OAuthEnvironment = ApiBindings & { OAUTH_PROVIDER: OAuthHelpers }
type FetchHandler = Pick<Required<ExportedHandler<ApiBindings>>, 'fetch'>
const supportedScopes: string[] = [...shoppingScopes, 'offline_access']
// Browsers may apply form-action to the final OAuth redirect as well as the POST.
const authorizationCSP = "default-src 'none'; form-action 'self' https://chatgpt.com; frame-ancestors 'none'; base-uri 'none'"
const appleAuthorizationCSP = "default-src 'none'; form-action 'self' https://appleid.apple.com https://chatgpt.com; frame-ancestors 'none'; base-uri 'none'"

export function getAuthenticationMode(env: ApiBindings): 'development' | 'apple' | null {
    if (env.AUTH_MODE === undefined || env.AUTH_MODE === 'development') return 'development'
    if (env.AUTH_MODE === 'apple') return 'apple'
    return null
}

// The provider supplies these grant properties only after token verification.
// Recheck mode and account state at both access and code/refresh exchanges so a
// switch to Apple cannot preserve access granted by the development password.
export async function resolveActiveGrantUser(
    env: ApiBindings,
    props: unknown,
    expectedUserId?: string
): Promise<string | null> {
    if (props === null || typeof props !== 'object' || Array.isArray(props)) return null
    const grant = props as Record<string, unknown>
    const userId = grant.userId
    if (typeof userId !== 'string' || !userId || (expectedUserId !== undefined && userId !== expectedUserId)) {
        return null
    }

    const mode = getAuthenticationMode(env)
    if (mode === 'apple') {
        if (!isAppleConfigured(env) || grant.authMethod !== 'apple' || userId === developmentUserId) return null
    } else if (mode === 'development') {
        if (userId !== developmentUserId
            || (grant.authMethod !== undefined && grant.authMethod !== 'development')) return null
    } else {
        return null
    }

    const user = await env.DB.prepare('SELECT id FROM users WHERE id = ? AND deleted_at IS NULL')
        .bind(userId).first<{ id: string }>()
    return user?.id ?? null
}

// This prototype grants access only to ChatGPT's current MCP OAuth callbacks.
// The provider additionally requires an exact match to the client's registered URI.
export function isChatGPTCallback(value: string): boolean {
    try {
        const url = new URL(value)
        return url.origin === 'https://chatgpt.com'
            && !url.username && !url.password && !url.search && !url.hash
            && (url.pathname === '/connector_platform_oauth_redirect'
                || /^\/connector\/oauth\/[A-Za-z0-9_-]+$/.test(url.pathname))
    } catch {
        return false
    }
}

function isAllowedRequest(request: AuthRequest): boolean {
    return request.responseType === 'code'
        && isChatGPTCallback(request.redirectUri)
        && request.resource === mcpResource
        && request.issuer === publicOrigin
        && request.codeChallengeMethod === 'S256'
        && typeof request.codeChallenge === 'string'
        && /^[A-Za-z0-9_-]{43}$/.test(request.codeChallenge)
        && request.scope.some((scope) => shoppingScopes.some((allowed) => allowed === scope))
        && request.scope.every((scope) => supportedScopes.includes(scope))
}

const escapeHTML = (value: string) => value.replace(/[&<>"']/g,
    (character) => `&#${character.charCodeAt(0)};`)

function consentPage(details: ConsentDescription, handle: string): string {
    const scopes = details.scope.map((scope) => `<li>${escapeHTML(scope)}</li>`).join('')
    const publisher = details.clientDomain
        ? `<p>Client domain: ${escapeHTML(details.clientDomain)}</p>`
        : '<p>The client name is self-reported.</p>'
    return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Connect lifelify development</title></head>
<body><main><h1>Connect lifelify development</h1>
<p>Allow ${escapeHTML(details.clientName)} to access the private development shopping account?</p>
${publisher}<p>Callback host: ${escapeHTML(details.redirectHost)}</p>
<p>Requested permissions:</p><ul>${scopes}</ul>
<p>This is a development account. Data is not synchronized with the iPhone app.</p>
<p>Access tokens expire after one hour. This connection can renew access for up to seven days.</p>
<form method="post" action="/authorize" autocomplete="off">
<input type="hidden" name="handle" value="${escapeHTML(handle)}">
<p><label>Development access token <input type="password" name="credential" autocomplete="off" spellcheck="false" maxlength="64"></label></p>
<p>Enter the development token only on this lifelify page. It is not sent to ChatGPT.</p>
<button type="submit" name="decision" value="approve">Allow listed access</button>
<button type="submit" name="decision" value="deny">Deny</button>
</form></main></body></html>`
}

const authorizationApp = new Hono<{ Bindings: OAuthEnvironment }>()

authorizationApp.use('*', async (c, next) => {
    c.header('Cache-Control', 'no-store')
    // Preserve the form POST's Origin for CSRF validation without sharing query
    // parameters (client ID, state or PKCE) in referrers.
    c.header('Referrer-Policy', 'strict-origin')
    c.header('X-Content-Type-Options', 'nosniff')
    c.header('X-Frame-Options', 'DENY')
    const mode = getAuthenticationMode(c.env)
    c.header('Content-Security-Policy', mode === 'apple' ? appleAuthorizationCSP : authorizationCSP)
    if (new URL(c.req.url).origin !== publicOrigin) {
        return c.text('Open authorization from the configured ChatGPT connection.', 400)
    }
    if (mode === null || (mode === 'apple' && !isAppleConfigured(c.env))) {
        return c.text('Authorization is not configured.', 503)
    }
    await next()
})

authorizationApp.get('/authorize', async (c) => {
    const url = new URL(c.req.url)
    const loginMethods = url.searchParams.getAll('login_method')
    if (loginMethods.length > 1 || (loginMethods.length === 1 && loginMethods[0] !== 'apple')) {
        return c.text('Invalid sign-in method.', 400)
    }
    // Keep the resource explicit even though a single-resource provider also
    // accepts omission for older clients. Do not reconstruct OAuth requests.
    if (url.searchParams.getAll('resource').length !== 1
        || url.searchParams.get('resource') !== mcpResource) {
        return c.text('The authorization request must target this MCP resource.', 400)
    }
    const request = await c.env.OAUTH_PROVIDER.parseAuthRequest(c.req.raw)
    if (!isAllowedRequest(request)) {
        return c.text('This connection requires a ChatGPT callback, shopping scopes, and S256 PKCE.', 400)
    }
    const details = await c.env.OAUTH_PROVIDER.describeConsent(request)
    const consent = await c.env.OAUTH_PROVIDER.beginConsent(request)
    if (getAuthenticationMode(c.env) === 'apple') {
        if (isAppApprovalEnabled(c.env) && loginMethods.length === 0) {
            return beginAppConsent(c.req.raw, c.env, details, consent.handle, consent.headers)
        }
        consent.headers.set('Content-Security-Policy', appleAuthorizationCSP)
        return beginAppleConsent(c.req.raw, c.env, details, consent.handle, consent.headers)
    }
    consent.headers.set('Content-Type', 'text/html; charset=utf-8')
    // Preserve the library's browser-binding cookie and strengthen its CSP.
    consent.headers.set('Content-Security-Policy', authorizationCSP)
    consent.headers.set('Referrer-Policy', 'strict-origin')
    return new Response(consentPage(details, consent.handle), { headers: consent.headers })
})

authorizationApp.post('/authorize', bodyLimit({
    maxSize: 8 * 1024,
    onError: (c) => c.text('Authorization form is too large.', 413)
}), async (c) => {
    if (c.req.header('Origin') !== publicOrigin) {
        return c.text('Authorization must be submitted from this site.', 403)
    }
    if (!/^application\/x-www-form-urlencoded(?:\s*;|\s*$)/i.test(c.req.header('Content-Type') ?? '')) {
        return c.text('Submit the authorization form from this site.', 415)
    }
    let form: FormData
    try {
        form = await c.req.raw.formData()
    } catch {
        return c.text('Invalid authorization form. Start again from ChatGPT.', 400)
    }
    const mode = getAuthenticationMode(c.env)
    if (mode === null) return c.text('Authorization is not configured.', 503)
    const allowedFields = mode === 'apple' ? ['handle', 'decision'] : ['handle', 'decision', 'credential']
    if ([...form.keys()].some((key) => !allowedFields.includes(key))
        || allowedFields.some((key) => form.getAll(key).length !== 1)) {
        return c.text('Invalid authorization form. Start again from ChatGPT.', 400)
    }
    const handle = form.get('handle')
    const decision = form.get('decision')
    const credential = form.get('credential')
    if (typeof handle !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(handle)
        || (decision !== 'approve' && decision !== 'deny')
        || (mode === 'development' && typeof credential !== 'string')) {
        return c.text('Invalid authorization form. Start again from ChatGPT.', 400)
    }
    const oauth = c.env.OAUTH_PROVIDER
    const appFlow = mode === 'apple' && await hasAppConsent(c.req.raw, c.env, handle)
    if (decision === 'deny') {
        const denied = await oauth.denyConsent(c.req.raw, handle)
        if (appFlow) await clearAppConsent(c.req.raw, c.env, handle, denied.headers, true)
        else if (mode === 'apple') await clearAppleConsent(c.req.raw, c.env, denied.headers)
        return new Response(null, { status: 303, headers: denied.headers })
    }
    let userId: string | null = developmentUserId
    if (appFlow) userId = await resolveAppConsentIdentity(c.req.raw, c.env, handle)
    if (mode === 'development') {
        const expectedToken = c.env.DEV_API_TOKEN
        if (typeof expectedToken !== 'string' || !/^[0-9a-f]{64}$/i.test(expectedToken)) {
            return c.text('Development authorization is not configured.', 503)
        }
        if (typeof credential !== 'string' || !/^[0-9a-f]{64}$/i.test(credential)
            || !await timingSafeEqual(expectedToken, credential)) {
            return c.text('Authorization failed. Start again from ChatGPT.', 401)
        }
        userId = await resolveActiveGrantUser(c.env, { userId, authMethod: mode })
        if (!userId) return c.text('The development account is unavailable.', 403)
    }
    const approved = await oauth.approveConsent(c.req.raw, handle)
    if (!isAllowedRequest(approved.request)) {
        return c.text('Invalid authorization request. Start again from ChatGPT.', 400)
    }
    if (mode === 'apple') {
        if (appFlow) await consumeAppConsent(c.req.raw, c.env, handle, userId!)
        else userId = await resolveAppleConsentIdentity(c.req.raw, c.env, handle)
        userId = await resolveActiveGrantUser(c.env, { userId, authMethod: mode })
        if (!userId) {
            if (appFlow) await clearAppConsent(c.req.raw, c.env, handle, approved.headers)
            else await clearAppleConsent(c.req.raw, c.env, approved.headers)
            approved.headers.set('Content-Type', 'text/plain; charset=utf-8')
            return new Response('Apple authorization could not be verified. Start again from ChatGPT.', {
                status: 403, headers: approved.headers
            })
        }
    }
    const { redirectTo } = await oauth.completeAuthorization({
        request: approved.request,
        userId,
        metadata: {},
        scope: approved.request.scope,
        props: { userId, authMethod: mode }
    })
    if (appFlow) await clearAppConsent(c.req.raw, c.env, handle, approved.headers)
    else if (mode === 'apple') await clearAppleConsent(c.req.raw, c.env, approved.headers)
    approved.headers.set('Location', redirectTo)
    return new Response(null, { status: 303, headers: approved.headers })
})

authorizationApp.onError((error, c) => {
    if (error instanceof AppConsentError) {
        return new Response('Approval is unavailable or has expired. Start again from ChatGPT.', {
            status: error.status, headers: { 'Cache-Control': 'no-store', 'Content-Type': 'text/plain; charset=utf-8' }
        })
    }
    if (error instanceof AuthorizationError || error instanceof CimdFetchError) {
        return c.text('Authorization could not be verified or has expired. Start again from ChatGPT.', 400)
    }
    // OAuth URLs, form bodies, handles and credentials never belong in logs.
    console.error(JSON.stringify({ event: 'authorization_failed', name: error.name }))
    return c.text('Authorization is temporarily unavailable.', 500)
})

export async function handleAuthorization(request: Request, env: OAuthEnvironment): Promise<Response> {
    return authorizationApp.fetch(request, env)
}

export function createOAuthProvider(apiHandler: FetchHandler, defaultHandler: FetchHandler): OAuthProvider<ApiBindings> {
    return new OAuthProvider<ApiBindings>({
        apiRoute: '/mcp',
        apiHandler,
        defaultHandler,
        authorizeEndpoint: `${publicOrigin}/authorize`,
        tokenEndpoint: `${publicOrigin}/oauth/token`,
        clientRegistrationEndpoint: `${publicOrigin}/oauth/register`,
        clientRegistrationCallback: ({ clientMetadata }) => {
            const redirects = clientMetadata.redirect_uris
            if (!Array.isArray(redirects) || redirects.length === 0 || redirects.length > 10
                || redirects.some((uri) => typeof uri !== 'string' || !isChatGPTCallback(uri))) {
                return { code: 'invalid_redirect_uri', description: 'Only ChatGPT MCP callback URLs are accepted.' }
            }
        },
        resourceMetadata: {
            resource: mcpResource,
            authorization_servers: [publicOrigin]
        },
        requiredScopes: ['shopping:read'],
        scopesSupported: supportedScopes,
        clientIdMetadataDocumentEnabled: true,
        accessTokenTTL: 3600,
        refreshTokenTTL: 7 * 24 * 60 * 60,
        tokenExchangeCallback: async ({ userId, props, env }) => {
            if (!await resolveActiveGrantUser(env, props, userId)) {
                throw new OAuthError('invalid_grant', { description: 'The authorized account or authentication method is unavailable.' })
            }
        },
        onError: ({ status, code }) => {
            console.warn(JSON.stringify({ event: 'oauth_failed', status, code }))
        }
    })
}
