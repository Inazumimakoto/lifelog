import { randomBytes } from 'node:crypto'
import { appendFileSync, chmodSync, existsSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const secretsPath = fileURLToPath(new URL('../.dev.vars', import.meta.url))
const contents = existsSync(secretsPath) ? readFileSync(secretsPath, 'utf8') : ''
const existing = contents.match(/^DEV_API_TOKEN=(.*)$/m)

if (existing) {
    if (!/^[0-9a-f]{64}$/i.test(existing[1].trim())) {
        console.error('.dev.vars の DEV_API_TOKEN の設定を確認してください。値は表示しません。')
        process.exitCode = 1
    } else {
        chmodSync(secretsPath, 0o600)
        console.log('開発用トークンは設定済みです。')
    }
} else {
    const prefix = contents && !contents.endsWith('\n') ? '\n' : ''
    appendFileSync(secretsPath, `${prefix}DEV_API_TOKEN=${randomBytes(32).toString('hex')}\n`, {
        mode: 0o600
    })
    chmodSync(secretsPath, 0o600)
    console.log('開発用トークンを .dev.vars に保存しました。値は表示しません。')
}
