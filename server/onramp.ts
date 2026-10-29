/**
 * Tiny API for the Circle Onramp widget. It mints widget sessions with the secret Circle API key, which
 * never reaches the browser. Run with `bun run dev:api`; Vite proxies /api to this server.
 *
 * A session is only minted for the wallet that signed a fresh message, and the purchased USDC is always
 * delivered to that same wallet.
 */
import { createAppServerKit, createSessionRouteHandler } from '@circle-fin/app-kit/server'
import { isAddress, verifyMessage, type Hex } from 'viem'
import {
  ONRAMP_ASSETS,
  ONRAMP_AUTH_HEADER,
  ONRAMP_AUTH_MAX_AGE_MS,
  onrampAppUserId,
  onrampAuthMessage,
  type OnrampAuthProof,
} from '../src/lib/onrampAuth'

const apiKey = process.env.CIRCLE_API_KEY
if (!apiKey) {
  console.error('CIRCLE_API_KEY is missing. Add it to .env and restart.')
  process.exit(1)
}

const server = createAppServerKit({
  onramp: {
    apiKey,
    // Sandbox values by default; production needs a mainnet API key plus its matching URLs.
    baseUrl: process.env.ONRAMP_API_BASE_URL,
    widgetBaseUrl: process.env.VITE_ONRAMP_WIDGET_BASE_URL,
    referrerDomain: process.env.ONRAMP_REFERRER_DOMAIN,
  },
})

// Light per-wallet rate limit: 8 sessions per minute.
const hits = new Map<string, number[]>()
function rateLimited(key: string): boolean {
  const now = Date.now()
  const recent = (hits.get(key) ?? []).filter((t) => now - t < 60_000)
  recent.push(now)
  hits.set(key, recent)
  return recent.length > 8
}

function parseProof(raw: string | null): OnrampAuthProof | null {
  if (!raw) return null
  try {
    const value: unknown = JSON.parse(raw)
    if (typeof value !== 'object' || value === null) return null
    const { address, issuedAt, signature } = value as Record<string, unknown>
    if (typeof address !== 'string' || typeof issuedAt !== 'string' || typeof signature !== 'string') return null
    return { address, issuedAt, signature }
  } catch {
    return null
  }
}

const handler = createSessionRouteHandler(server.onramp, {
  authorize: async (request) => {
    const proof = parseProof(request.headers.get(ONRAMP_AUTH_HEADER))
    if (!proof || !isAddress(proof.address)) return false

    const age = Date.now() - Date.parse(proof.issuedAt)
    if (!Number.isFinite(age) || age < -10_000 || age > ONRAMP_AUTH_MAX_AGE_MS) return false

    const valid = await verifyMessage({
      address: proof.address,
      message: onrampAuthMessage(proof.address, proof.issuedAt),
      signature: proof.signature as Hex,
    }).catch(() => false)
    if (valid !== true) return false

    const body: unknown = await request
      .clone()
      .json()
      .catch(() => null)
    if (typeof body !== 'object' || body === null || Array.isArray(body)) return false
    const { appUserId, destinationAddress, assets } = body as Record<string, unknown>
    if (appUserId !== onrampAppUserId(proof.address)) return false
    if (typeof destinationAddress !== 'string' || destinationAddress.toLowerCase() !== proof.address.toLowerCase()) {
      return false
    }
    if (assets !== undefined && JSON.stringify(assets) !== JSON.stringify(ONRAMP_ASSETS)) return false

    return !rateLimited(proof.address.toLowerCase())
  },
  onError: (error) => {
    console.error('onramp session mint failed:', error instanceof Error ? error.message : 'unknown error')
  },
})

const port = Number(process.env.ONRAMP_API_PORT ?? 8787)

Bun.serve({
  port,
  hostname: '127.0.0.1',
  fetch(request) {
    const url = new URL(request.url)
    if (url.pathname === '/api/onramp/sessions') return handler(request)
    if (url.pathname === '/api/health') return Response.json({ ok: true })
    return new Response('Not found', { status: 404 })
  },
})

console.log(`Onramp API listening on http://127.0.0.1:${port}`)
