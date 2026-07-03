const BASE = process.env.CEREBELUM_API_URL || 'https://cerebelum.zea.cl'
const KEY = process.env.CEREBELUM_API_KEY || ''

const AUTH_BASE = process.env.ZEA_AUTH_URL || 'https://auth.zea.cl'

export interface CerebelumConfig {
  baseUrl: string
  apiKey: string
  refreshToken: string
  authUrl: string
}

export function loadConfig(): CerebelumConfig {
  const configFile = `${process.env.HOME || '~'}/.cerebelum/config.json`
  let fileConfig: Partial<CerebelumConfig> = {}

  try {
    const fs = require('fs')
    if (fs.existsSync(configFile)) {
      fileConfig = JSON.parse(fs.readFileSync(configFile, 'utf-8'))
    }
  } catch {}

  return {
    baseUrl: BASE,
    apiKey: KEY || fileConfig.apiKey || '',
    refreshToken: fileConfig.refreshToken || '',
    authUrl: AUTH_BASE,
  }
}

/**
 * Save the API key (and optionally refresh token) to the local config file.
 */
export function saveTokens(accessToken: string, refreshToken?: string): string {
  const configFile = `${process.env.HOME || '~'}/.cerebelum/config.json`
  const configDir = `${process.env.HOME || '~'}/.cerebelum`
  const fs = require('fs')

  if (!fs.existsSync(configDir)) {
    fs.mkdirSync(configDir, { recursive: true })
  }

  let config: Record<string, unknown> = {}
  try {
    config = JSON.parse(fs.readFileSync(configFile, 'utf-8'))
  } catch {}

  config.apiKey = accessToken
  if (refreshToken) config.refreshToken = refreshToken
  fs.writeFileSync(configFile, JSON.stringify(config, null, 2))

  return configFile
}

export async function api(
  method: string,
  path: string,
  body?: unknown,
  apiKey?: string,
): Promise<{ status: number; data: unknown }> {
  const config = loadConfig()
  const key = apiKey || config.apiKey

  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (key) headers['Authorization'] = `Bearer ${key}`

  const resp = await fetch(`${config.baseUrl}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(30_000),
  })

  const data = await resp.json().catch(() => ({}))
  return { status: resp.status, data }
}

export function printJSON(data: unknown) {
  console.log(JSON.stringify(data, null, 2))
}

export function color(c: string, text: string) {
  const colors: Record<string, string> = {
    reset: '\x1b[0m',
    green: '\x1b[32m',
    red: '\x1b[31m',
    yellow: '\x1b[33m',
    cyan: '\x1b[36m',
    purple: '\x1b[35m',
    gray: '\x1b[90m',
    bold: '\x1b[1m',
  }
  return `${colors[c] || ''}${text}${colors.reset}`
}
