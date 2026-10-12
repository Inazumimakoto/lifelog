import type { OAuthResourceContext } from '@cloudflare/workers-oauth-provider'
import {
    createOAuthProvider,
    getAuthenticationMode,
    handleAuthorization,
    resolveActiveGrantUser,
    type OAuthEnvironment
} from './auth'
import { handleAppleAuthentication, isAppleConfigured } from './apple'
import { type ApiBindings } from './config'
import { handleNativeAuthentication } from './native-auth'
import { handleShoppingSynchronization } from './shopping-sync'
import { handleAppConsent } from './app-consent'
import { handleMcp } from './mcp'
import rest from './rest'

const provider = createOAuthProvider({
    async fetch(request, env, ctx) {
        // Only the OAuth provider creates this context after validating the token,
        // its expiry and audience. Client-supplied user IDs are never identities.
        const verified = ctx as OAuthResourceContext<unknown>
        const userId = await resolveActiveGrantUser(env, verified.props, verified.auth?.userId)
        if (!userId || !Array.isArray(verified.auth?.scope)
            || !verified.auth.scope.every((scope) => typeof scope === 'string')) {
            return Response.json({ error: 'user_unavailable' }, { status: 403 })
        }
        return handleMcp(request, env, ctx, { userId, scopes: verified.auth.scope })
    }
}, {
    fetch(request, env, ctx) {
        const path = new URL(request.url).pathname
        if (path.startsWith('/auth/apple/')) {
            if (getAuthenticationMode(env) !== 'apple') {
                return new Response('Not found', { status: 404 })
            }
            return handleAppleAuthentication(request, env)
        }
        if (path === '/authorize') {
            return handleAuthorization(request, env as OAuthEnvironment)
        }
        return rest.fetch(request, env, ctx)
    }
})

export default {
    async fetch(request, env, ctx) {
        const path = new URL(request.url).pathname
        // Keep the existing REST interface available without OAuth state. MCP,
        // registration and authorization routes stay closed without their binding.
        if (path === '/' || path === '/health' || path.startsWith('/api/')) {
            return rest.fetch(request, env, ctx)
        }
        // Native bearer sessions are separate from OAuth's browser cookies and
        // can be configured before the optional app approval flow is enabled.
        if (path.startsWith('/auth/native/shopping/')) return handleShoppingSynchronization(request, env)
        if (path.startsWith('/auth/native/')) return handleNativeAuthentication(request, env)
        if (path.startsWith('/auth/app/')) return handleAppConsent(request, env)
        const mode = getAuthenticationMode(env)
        const configured = mode === 'apple'
            ? isAppleConfigured(env)
            : mode === 'development' && typeof env.DEV_API_TOKEN === 'string'
                && /^[0-9a-f]{64}$/i.test(env.DEV_API_TOKEN)
        if (!env.OAUTH_KV || !configured) {
            return Response.json({ error: 'oauth_not_configured' }, {
                status: 503, headers: { 'Cache-Control': 'no-store' }
            })
        }
        try {
            const response = await provider.fetch(request, env, ctx)
            const headers = new Headers(response.headers)
            headers.set('Cache-Control', 'no-store')
            return new Response(response.body, { status: response.status, statusText: response.statusText, headers })
        } catch (error) {
            console.error(JSON.stringify({ event: 'oauth_request_failed',
                name: error instanceof Error ? error.name : 'UnknownError' }))
            return Response.json({ error: 'internal_error' }, { status: 500,
                headers: { 'Cache-Control': 'no-store' } })
        }
    }
} satisfies ExportedHandler<ApiBindings>
