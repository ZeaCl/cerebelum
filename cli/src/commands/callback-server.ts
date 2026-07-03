/**
 * Local callback server for OAuth2 Authorization Code flow.
 *
 * Listens on a random port briefly to capture the authorization code
 * that Thalamus redirects to after user login + auto-approve.
 */

import * as http from 'http'
import { URL } from 'url'

export interface CallbackResult {
  code: string
  state: string
}

/**
 * Start a minimal HTTP server, wait for Thalamus to redirect here,
 * and return the authorization code + state.
 *
 * Times out after 120 seconds.
 */
export function waitForCallback(
  port: number,
  expectedState: string,
): Promise<CallbackResult> {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      const url = new URL(req.url || '/', `http://localhost:${port}`)

      // Handle the callback — any path works
      if (url.pathname === '/callback' || url.pathname === '/') {
        const code = url.searchParams.get('code')
        const state = url.searchParams.get('state')
        const error = url.searchParams.get('error')

        if (error) {
          res.writeHead(400, { 'Content-Type': 'text/html; charset=utf-8' })
          res.end(
            `<html><body style="font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#111;color:#eee"><div style="text-align:center"><h1 style="color:#f87171">❌ Login failed</h1><p>${error}</p><p style="color:#888;font-size:14px">You can close this window.</p></div></body></html>`,
          )
          cleanup()
          reject(new Error(`OAuth error: ${error}`))
          return
        }

        if (code && state === expectedState) {
          res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
          res.end(
            `<html><body style="font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#111;color:#eee"><div style="text-align:center"><h1 style="color:#4ade80">✅ Authenticated</h1><p style="color:#888;font-size:14px">You can close this window and return to your terminal.</p></div></body></html>`,
          )
          cleanup()
          resolve({ code, state })
        } else {
          res.writeHead(400, { 'Content-Type': 'text/plain' })
          res.end('Invalid request')
        }
      } else {
        res.writeHead(404, { 'Content-Type': 'text/plain' })
        res.end('Not found')
      }
    })

    const timer = setTimeout(() => {
      cleanup()
      reject(new Error('Login timed out — please try again'))
    }, 120_000)

    function cleanup() {
      clearTimeout(timer)
      server.close()
    }

    server.on('error', (err: NodeJS.ErrnoException) => {
      clearTimeout(timer)
      if (err.code === 'EADDRINUSE') {
        reject(
          new Error(
            `Port ${port} is already in use. Is another cerebelum login running?`,
          ),
        )
      } else {
        reject(err)
      }
    })

    server.listen(port, '127.0.0.1', () => {
      // Server is ready — caller will open the browser now
    })
  })
}
