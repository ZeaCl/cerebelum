/**
 * PKCE (Proof Key for Code Exchange) utilities — RFC 7636.
 *
 * Generates code_verifier and code_challenge for OAuth2 Authorization Code
 * flow with public clients (no client_secret).
 */

import * as crypto from 'crypto'

/** Generate a cryptographically random code verifier (43-128 chars). */
export function generateCodeVerifier(): string {
  return crypto.randomBytes(32).toString('base64url')
}

/** Derive the S256 code challenge from a code verifier. */
export function generateCodeChallenge(verifier: string): string {
  return crypto
    .createHash('sha256')
    .update(verifier)
    .digest('base64url')
}

/** Generate a random state parameter for CSRF protection. */
export function generateState(): string {
  return crypto.randomBytes(16).toString('hex')
}
