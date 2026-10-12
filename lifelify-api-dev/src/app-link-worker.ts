// Link-only Worker: separate origin allows Safari to hand off to the native
// app. It has no DB, OAuth bindings or secrets and never approves a request.
const host = 'lifelify-connect-dev.inazumimakoto.workers.dev'
const appID = 'V7XG8HDQL4.com.inazumimakoto.lifelog'
const securityHeaders = {
    'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
    'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
    'X-Frame-Options': 'DENY'
}

export default {
    async fetch(request: Request): Promise<Response> {
        const url = new URL(request.url)
        if (url.protocol !== 'https:' || url.hostname !== host) return new Response('Not found', { status: 404 })
        if (request.method !== 'GET' && request.method !== 'HEAD') return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } })
        if (url.pathname === '/.well-known/apple-app-site-association' || url.pathname === '/apple-app-site-association') {
            const body = JSON.stringify({ applinks: { details: [{ appIDs: [appID],
                components: [{ '/': '/connect/*', comment: 'Open native shopping connection approval' }] }] } })
            return new Response(request.method === 'HEAD' ? null : body, { headers: {
                ...securityHeaders, 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=300'
            } })
        }
        if (!/^\/connect\/[A-Za-z0-9_-]{43}$/.test(url.pathname)) return new Response('Not found', { status: 404 })
        // No reflected identifiers or arbitrary redirect targets in this page.
        const body = `<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>lifelify</title></head><body><main>
<h1>lifelify開発版を開いてください</h1><p>このページでは連携は承認されません。Universal Linkに対応したlifelify開発版をインストールし、元のChatGPT接続画面からもう一度「lifelifyを開く」を押してください。</p>
<p>アプリが開かない場合は元の接続画面に戻り、WebのAppleログインを選べます。</p>
<p lang="en">Install the lifelify development build that supports this link, then return to your original ChatGPT connection screen and tap Open lifelify. You can also choose Apple sign-in on that screen.</p>
<p lang="ko">이 링크를 지원하는 lifelify 개발 버전을 설치한 뒤 원래 ChatGPT 연결 화면으로 돌아가 lifelify 열기를 누르세요. 해당 화면에서 웹 Apple 로그인을 선택할 수도 있습니다.</p>
<p lang="zh-Hans">请安装支持此链接的 lifelify 开发版本，然后返回原来的 ChatGPT 连接页面，点击打开 lifelify。也可以在该页面选择网页 Apple 登录。</p>
<p lang="zh-Hant">請安裝支援此連結的 lifelify 開發版本，然後返回原來的 ChatGPT 連線頁面，點選開啟 lifelify。也可以在該頁面選擇網頁 Apple 登入。</p>
</main></body></html>`
        return new Response(request.method === 'HEAD' ? null : body, { headers: {
            ...securityHeaders, 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store'
        } })
    }
}
