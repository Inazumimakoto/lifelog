import assert from 'node:assert/strict'
import { dirname, resolve } from 'node:path'
import { before, describe, it } from 'node:test'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'

const projectDirectory = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const origin = 'https://lifelify-connect-dev.inazumimakoto.workers.dev'
const appID = 'V7XG8HDQL4.com.inazumimakoto.lifelog'
const firstId = 'A'.repeat(43), secondId = 'B'.repeat(43)
let worker

function request(path, options = {}) {
    return worker.fetch(new Request(`${origin}${path}`, options))
}

describe('link-only Worker without OAuth credentials or database access', () => {
    before(async () => {
        const bundled = await build({ entryPoints: [resolve(projectDirectory, 'src/app-link-worker.ts')],
            bundle: true, format: 'esm', platform: 'browser', target: 'es2022', logLevel: 'silent', write: false })
        worker = (await import(`data:text/javascript;base64,${Buffer.from(bundled.outputFiles[0].text).toString('base64')}`)).default
    })

    it('serves only the exact app association and purchase-consent path on both supported AASA URLs', async () => {
        for (const path of ['/.well-known/apple-app-site-association', '/apple-app-site-association']) {
            const response = await request(path)
            assert.equal(response.status, 200)
            assert.match(response.headers.get('Content-Type'), /^application\/json/)
            const association = await response.json()
            assert.deepEqual(Object.keys(association), ['applinks'])
            assert.equal(association.applinks.details.length, 1)
            const details = association.applinks.details[0]
            assert.deepEqual(details.appIDs, [appID])
            assert.equal(details.components.length, 1)
            assert.equal(details.components[0]['/'], '/connect/*')
            assert.equal(response.headers.has('Location'), false)
        }
    })

    it('rejects insecure URLs, other domains and paths outside the link service', async () => {
        for (const url of [`http://${new URL(origin).host}/connect/${firstId}`,
            `https://evil.example/connect/${firstId}`,
            `https://${new URL(origin).host}.evil.example/.well-known/apple-app-site-association`,
            `${origin}/authorize`, `${origin}/oauth/token`, `${origin}/connect`,
            `${origin}/connect/short`, `${origin}/connect/${firstId}/extra`,
        ]) {
            const response = await worker.fetch(new Request(url))
            assert.equal(response.status, 404, url)
            assert.equal(response.headers.has('Location'), false)
            await response.text()
        }
    })

    it('does not authorize, redirect or reflect request IDs, credentials and arbitrary return targets', async () => {
        let environmentAccesses = 0
        const environment = new Proxy({}, { get() { environmentAccesses++; throw new Error('The link Worker must not access a binding') } })
        const credential = 'synthetic-never-reflected-bearer-token'
        const response = await worker.fetch(new Request(`${origin}/connect/${firstId}?return_url=https%3A%2F%2Fevil.example&access_token=${credential}`, {
            headers: { Authorization: `Bearer ${credential}`, Cookie: `synthetic=${credential}` },
        }), environment)
        assert.equal(response.status, 200)
        assert.equal(environmentAccesses, 0)
        assert.equal(response.headers.has('Location'), false)
        assert.equal(response.headers.has('Set-Cookie'), false)
        assert.equal(response.headers.get('Cache-Control'), 'no-store')
        assert.equal(response.headers.get('Referrer-Policy'), 'no-referrer')
        assert.match(response.headers.get('Content-Security-Policy'), /default-src 'none'/)
        assert.match(response.headers.get('Content-Security-Policy'), /frame-ancestors 'none'/)
        const html = await response.text()
        assert.equal(html.includes(firstId), false)
        assert.equal(html.includes(credential), false)
        assert.equal(html.includes('evil.example'), false)
        assert.equal(html.includes('<form'), false)
        assert.equal(html.includes('<script'), false)
        assert.equal(html, await (await request(`/connect/${secondId}`)).text())
    })

    it('serves bodyless HEAD responses and rejects every write method', async () => {
        for (const path of ['/.well-known/apple-app-site-association', `/connect/${firstId}`]) {
            const head = await request(path, { method: 'HEAD' })
            assert.equal(head.status, 200)
            assert.equal(await head.text(), '')
            for (const method of ['POST', 'PUT', 'DELETE', 'PATCH']) {
                const response = await request(path, { method })
                assert.equal(response.status, 405)
                assert.equal(response.headers.get('Allow'), 'GET, HEAD')
                assert.equal(response.headers.has('Location'), false)
            }
        }
    })
})
