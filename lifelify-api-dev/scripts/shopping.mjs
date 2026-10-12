import { readFileSync } from 'node:fs'

// This helper targets the local development server. Credentials stay out of
// command arguments and output; the API's D1 binding can still be remote.
async function main() {
    const contents = readFileSync(new URL('../.dev.vars', import.meta.url), 'utf8')
    const token = contents.match(/^DEV_API_TOKEN=([0-9a-f]{64})\s*$/im)?.[1]
    if (!token) {
        throw new Error('npm run setup:dev を先に実行してください。')
    }

    const [command = 'list', title, note = '', placeId] = process.argv.slice(2)
    if (!['list', 'add'].includes(command) || (command === 'add' && !title)) {
        throw new Error('使用例: npm run shopping:list / npm run shopping:add -- 牛乳 "1リットルを1本"')
    }

    const headers = { Authorization: `Bearer ${token}` }
    const options = { headers, redirect: 'error' }
    if (command === 'add') {
        console.log('開発用 D1 に商品を1件追加します。')
        options.method = 'POST'
        headers['Content-Type'] = 'application/json'
        options.body = JSON.stringify({ title, note, ...(placeId ? { place_id: placeId } : {}) })
    }

    const response = await fetch('http://localhost:8787/api/shopping/items', options)
    console.log(`HTTP ${response.status}`)
    const text = await response.text()
    try {
        console.log(JSON.stringify(JSON.parse(text), null, 2))
    } catch {
        console.log(text)
    }
    if (!response.ok) {
        process.exitCode = 1
    }
}

main().catch((error) => {
    console.error(error.message)
    process.exitCode = 1
})
