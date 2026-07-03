import { color, loadConfig, saveTokens } from '../api'
import { generateCodeVerifier, generateCodeChallenge, generateState } from './pkce'
import { waitForCallback } from './callback-server'
import { exec } from 'child_process'

const THALAMUS_CLIENT_ID = 'thalamus_cli'
const CALLBACK_PORT = 4005
const CALLBACK_URL = `http://localhost:${CALLBACK_PORT}/callback`

const SCOPES = 'openid profile email zea:read zea:write'

/** Open a URL in the user's default browser. */
function openBrowser(url: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const platform = process.platform
    let cmd: string
    if (platform === 'darwin') cmd = `open "${url}"`
    else if (platform === 'win32') cmd = `start "" "${url}"`
    else cmd = `xdg-open "${url}"`

    exec(cmd, (err) => {
      if (err) reject(new Error(`Failed to open browser: ${err.message}`))
      else resolve()
    })
  })
}

/**
 * Exchange authorization code for access token via Thalamus.
 *
 * Since thalamus_cli is a public client with PKCE, we do NOT send
 * client_secret — only client_id + code_verifier.
 */
async function exchangeCode(
  authUrl: string,
  code: string,
  codeVerifier: string,
): Promise<{ access_token: string; refresh_token?: string; token_type: string }> {
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    code,
    redirect_uri: CALLBACK_URL,
    client_id: THALAMUS_CLIENT_ID,
    code_verifier: codeVerifier,
  })

  const resp = await fetch(`${authUrl}/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
    signal: AbortSignal.timeout(15_000),
  })

  const data = (await resp.json()) as Record<string, unknown>

  if (!resp.ok) {
    const errDesc = (data.error_description as string) || (data.error as string) || 'unknown error'
    throw new Error(`Token exchange failed: ${errDesc}`)
  }

  return data as unknown as {
    access_token: string
    refresh_token?: string
    token_type: string
  }
}

/**
 * OAuth2 Authorization Code + PKCE login with Thalamus.
 *
 * Flow:
 * 1. Generate PKCE code_verifier + code_challenge + state
 * 2. Start local HTTP server on port 4005
 * 3. Open browser → Thalamus /oauth/authorize
 * 4. User logs in (or has existing session) → auto-approve
 * 5. Catch redirect → extract authorization code
 * 6. Exchange code for access_token via /oauth/token
 * 7. Save token to ~/.cerebelum/config.json
 */
export async function login() {
  const config = loadConfig()

  console.log(`\n${color('cyan', '🔐 Cerebelum Login')} ${color('gray', '— via Thalamus OAuth2')}`)
  console.log('═'.repeat(55))

  // 1. Generate PKCE + state
  const codeVerifier = generateCodeVerifier()
  const codeChallenge = generateCodeChallenge(codeVerifier)
  const state = generateState()

  // 2. Build authorize URL
  const authorizeParams = new URLSearchParams({
    response_type: 'code',
    client_id: THALAMUS_CLIENT_ID,
    redirect_uri: CALLBACK_URL,
    code_challenge: codeChallenge,
    code_challenge_method: 'S256',
    scope: SCOPES,
    state,
  })

  const authorizeUrl = `${config.authUrl}/oauth/authorize?${authorizeParams.toString()}`

  // 3. Open browser
  console.log(`\n  ${color('bold', '→')} Opening browser for authentication...`)
  console.log(`    ${color('gray', authorizeUrl)}`)
  console.log(`\n  ${color('yellow', 'If the browser does not open, visit:')}`)
  console.log(`    ${color('green', authorizeUrl)}`)

  await openBrowser(authorizeUrl).catch((err) => {
    // Non-fatal: log but continue — the user can manually open the URL
    console.log(`  ${color('yellow', `⚠ ${err.message}`)}`)
    console.log(`  ${color('yellow', 'Copy the URL above and open it manually.')}`)
  })

  // 4. Wait for callback
  console.log(`\n  ${color('bold', '⟳')} Waiting for login... (timeout: 2 min)`)

  let callbackResult
  try {
    callbackResult = await waitForCallback(CALLBACK_PORT, state)
  } catch (err) {
    console.log(`\n${color('red', '✕')} ${(err as Error).message}`)
    process.exit(1)
  }

  // 5. Exchange code for token
  console.log(`\n  ${color('bold', '⟳')} Exchanging authorization code for access token...`)

  let tokens
  try {
    tokens = await exchangeCode(config.authUrl, callbackResult.code, codeVerifier)
  } catch (err) {
    console.log(`\n${color('red', '✕')} ${(err as Error).message}`)
    process.exit(1)
  }

  // 6. Save tokens
  const configFile = saveTokens(tokens.access_token, tokens.refresh_token)

  console.log(`\n  ${color('green', '✅ Login successful')}`)
  console.log(`    ${color('gray', 'Token saved to')} ${configFile}`)
  console.log(`\n  Run ${color('green', 'cerebelum doctor')} to verify your connection.`)
  console.log('')
}

/**
 * Login with a manual token (legacy / headless fallback).
 * This is kept for CI environments or cases where OAuth2 browser flow is not possible.
 */
export async function loginWithToken(token: string) {
  const configFile = saveTokens(token)
  console.log(`${color('green', '✅')} Token saved to ${configFile}`)
  console.log(`   Run ${color('green', 'cerebelum doctor')} to verify`)
}
