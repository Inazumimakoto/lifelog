import { Hono } from 'hono'
import { bearerAuth } from 'hono/bearer-auth'
import { bodyLimit } from 'hono/body-limit'
import { HTTPException } from 'hono/http-exception'
import { developmentUserId, type ApiBindings } from './config'
import { createShoppingItem, isShoppingUserActive, listShoppingItems, parseNewShoppingItem } from './shopping'

type AppEnvironment = {
    Bindings: ApiBindings
    Variables: { userId: string }
}

const app = new Hono<AppEnvironment>()

app.onError((error, c) => {
    if (error instanceof HTTPException) {
        return error.getResponse()
    }
    // Never log tokens, request bodies, or SQL errors containing user content.
    console.error(JSON.stringify({ event: 'request_failed', name: error.name }))
    return c.json({ error: 'internal_error' }, 500)
})

app.get('/', (c) => c.text('Hello Hono!'))

app.get('/health', async (c) => {
    const { results } = await c.env.DB.prepare(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('users', 'shopping_places', 'shopping_items') ORDER BY name"
    ).all<{ name: string }>()

    const ok = results.length === 3

    return c.json(
        { ok, tables: results.map((table) => table.name) },
        ok ? 200 : 503
    )
})

app.use('/api/*', async (c, next) => {
    c.header('Cache-Control', 'no-store')
    const token = c.env.DEV_API_TOKEN
    if (typeof token !== 'string' || !/^[0-9a-f]{64}$/i.test(token)) {
        return c.json({ error: 'api_not_configured' }, 503)
    }
    return bearerAuth<AppEnvironment>({ token })(c, next)
})

app.use('/api/*', async (c, next) => {
    // REST retains its original development-account mapping during MCP migration.
    if (!await isShoppingUserActive(c.env.DB, developmentUserId)) {
        return c.json({ error: 'user_unavailable' }, 403)
    }
    c.set('userId', developmentUserId)
    await next()
})

app.get('/api/shopping/items', async (c) => {
    return c.json(await listShoppingItems(c.env.DB, c.get('userId')))
})

app.post('/api/shopping/items', bodyLimit({
    maxSize: 16 * 1024,
    onError: (c) => c.json({ error: 'body_too_large' }, 413)
}), async (c) => {
    const contentType = c.req.header('Content-Type') ?? ''
    if (!/^application\/json(?:\s*;|\s*$)/i.test(contentType)) {
        return c.json({ error: 'json_required' }, 415)
    }

    let body: unknown
    try {
        body = await c.req.json<unknown>()
    } catch {
        return c.json({ error: 'invalid_json' }, 400)
    }
    const input = parseNewShoppingItem(body)
    if (!input) {
        return c.json({ error: 'invalid_item' }, 400)
    }

    const item = await createShoppingItem(c.env.DB, c.get('userId'), input)
    if (!item) {
        return c.json({ error: 'owner_or_place_unavailable' }, 409)
    }

    return c.json({ item }, 201)
})

export default app
