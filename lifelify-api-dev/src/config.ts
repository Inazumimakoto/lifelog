export const publicOrigin = 'https://lifelify-api-dev.inazumimakoto.workers.dev'
export const appLinkOrigin = 'https://lifelify-connect-dev.inazumimakoto.workers.dev'
export const mcpResource = `${publicOrigin}/mcp`
export const shoppingScopes = ['shopping:read', 'shopping:write'] as const
export const developmentUserId = 'dev-user'

export type ApiBindings = Omit<CloudflareBindings, 'AUTH_MODE' | 'APPLE_APP_ID' | 'APP_APPROVAL_ENABLED'> & {
    AUTH_MODE?: string
    APPLE_APP_ID?: string
    APP_APPROVAL_ENABLED?: string
    APPLE_SERVICE_ID?: string
    APPLE_TEAM_ID?: string
    APPLE_KEY_ID?: string
    APPLE_PRIVATE_KEY?: string
}
