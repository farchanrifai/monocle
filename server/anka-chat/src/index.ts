import Anthropic from '@anthropic-ai/sdk'
import { APPLE_ROOT_G3_SHA256, ReceiptError, sha256, verifyReceipt } from './receipt'
import { PRICES, costMicro, parseUsage } from './usage'

// Anka's chat proxy: the app sends a Messages API request with its App Store transaction, the Worker checks the
// subscription, pins the model, adds the key and streams Claude's reply back. Tools run on the phone; nothing is stored
// here but token counts.

export interface Env {
  DB: D1Database
  ANTHROPIC_API_KEY: string
  /** Lets the owner's debug builds (free team, no StoreKit) through. Unset in production = no bypass. */
  OWNER_KEY?: string
  MODEL: string
  MAX_TOKENS_CEILING: string
  MAX_BODY_BYTES: string
  CAP_MONTHLY_USD_USER: string
  CAP_MONTHLY_USD_GLOBAL: string
  BUNDLE_ID: string
  PRODUCT_IDS: string
  ENVIRONMENTS: string
}

/** Errors in the Messages API shape, so the app reads one format. `anka_*` types carry a message for the user. */
export const fail = (status: number, type: string, message: string) =>
  Response.json({ type: 'error', error: { type, message } }, { status })

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const path = new URL(req.url).pathname
    if (req.method === 'GET' && path === '/health') return Response.json({ ok: true })
    if (req.method !== 'POST' || path !== '/v1/messages') return fail(404, 'not_found_error', 'Not found')

    const user = await identify(req, env)
    if (user instanceof Response) return user
    const capped = await capMessage(env, user)
    if (capped) return fail(429, 'anka_cap_error', capped)

    const raw = await req.text()
    if (raw.length > Number(env.MAX_BODY_BYTES)) return fail(413, 'request_too_large', 'Request body too large')
    let body: any
    try { body = JSON.parse(raw) } catch { return fail(400, 'invalid_request_error', 'Body is not JSON') }
    const problem = clamp(body, env)
    if (problem) return fail(400, 'invalid_request_error', problem)

    let up: Response
    try {
      up = await new Anthropic({ apiKey: env.ANTHROPIC_API_KEY }).messages.create(body).asResponse()
    } catch (e) {
      if (e instanceof Anthropic.APIError && e.status) return Response.json(e.error ?? { type: 'error', error: { type: 'api_error', message: e.message } }, { status: e.status })
      return fail(502, 'api_error', 'Claude is unreachable right now')
    }

    const ctype = up.headers.get('content-type') ?? 'application/json'
    const [toClient, toMeter] = up.body!.tee()
    ctx.waitUntil(meter(toMeter, ctype.includes('event-stream'), env, user, body.model).catch((e) => console.error('meter failed', String(e))))
    return new Response(toClient, { status: up.status, headers: { 'content-type': ctype, 'cache-control': 'no-cache' } })
  },
}

/** Pins what costs money: the model, the output ceiling, and no server tools (they bill outside the token table). */
export function clamp(body: any, env: Pick<Env, 'MODEL' | 'MAX_TOKENS_CEILING'>): string | null {
  if (!body || typeof body !== 'object' || !Array.isArray(body.messages)) return 'messages required'
  if (body.mcp_servers || body.container || body.tools?.some?.((t: any) => t?.type && t.type !== 'custom')) return 'Server tools are not allowed'
  if (!(env.MODEL in PRICES)) return 'Model not priced'
  body.model = env.MODEL
  body.max_tokens = Math.min(Number.isInteger(body.max_tokens) && body.max_tokens > 0 ? body.max_tokens : 4096, Number(env.MAX_TOKENS_CEILING))
  delete body.speed
  return null
}

/** The subscription behind the request (its originalTransactionId), or the error to send back. */
async function identify(req: Request, env: Env): Promise<string | Response> {
  const owner = req.headers.get('x-anka-owner')
  if (owner) return env.OWNER_KEY && (await sha256(owner)) === (await sha256(env.OWNER_KEY)) ? 'owner' : fail(403, 'permission_error', 'Owner key rejected')

  const jws = req.headers.get('x-anka-receipt')
  if (!jws) return fail(401, 'anka_receipt_error', 'Claude chat is part of Anka Pro.')
  const hash = await sha256(jws)
  let row = await env.DB.prepare('SELECT user, expires_ms FROM receipts WHERE hash = ?1').bind(hash).first<{ user: string; expires_ms: number }>()
  if (!row) {
    try {
      const r = await verifyReceipt(jws, {
        bundleId: env.BUNDLE_ID, productIds: env.PRODUCT_IDS.split(','), environments: env.ENVIRONMENTS.split(','), rootSha256: APPLE_ROOT_G3_SHA256,
      })
      row = { user: r.originalTransactionId, expires_ms: r.expiresMs }
      await env.DB.prepare('INSERT OR IGNORE INTO receipts (hash, user, expires_ms, environment, created_at) VALUES (?1,?2,?3,?4,?5)')
        .bind(hash, r.originalTransactionId, r.expiresMs, r.environment, Date.now()).run()
    } catch (e) {
      if (!(e instanceof ReceiptError)) throw e
      console.log(JSON.stringify({ receipt: e.message }))
      return fail(401, 'anka_receipt_error', "Anka Pro couldn't be confirmed. Try Restore Purchases in Settings.")
    }
  }
  if (row.expires_ms <= Date.now()) return fail(401, 'anka_receipt_error', 'Your Anka Pro subscription has ended.')
  return row.user
}

/** A user-facing message when this month's cap is reached, or null. Per subscription, then for the whole app. */
export async function capMessage(env: Env, user: string, now = new Date()): Promise<string | null> {
  const s = await env.DB.prepare(
    'SELECT COALESCE(SUM(CASE WHEN user = ?2 THEN cost_micro END), 0) AS mine, COALESCE(SUM(cost_micro), 0) AS total FROM usage WHERE month = ?1',
  ).bind(now.toISOString().slice(0, 7), user).first<{ mine: number; total: number }>()
  if (user !== 'owner' && s!.mine >= Number(env.CAP_MONTHLY_USD_USER) * 1e6) return "You've reached this month's chat limit. It resets on the 1st."
  if (s!.total >= Number(env.CAP_MONTHLY_USD_GLOBAL) * 1e6) return 'Claude chat is paused until the 1st. On-device chat still works where available.'
  return null
}

async function meter(stream: ReadableStream<Uint8Array>, sse: boolean, env: Env, user: string, model: string, now = new Date()) {
  // Explicit reader loop: Response.text() on a tee branch makes workerd hold back the client branch.
  const reader = stream.getReader()
  const dec = new TextDecoder()
  let text = ''
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    text += dec.decode(value, { stream: true })
  }
  const u = parseUsage(text, sse)
  await env.DB.prepare(
    `INSERT INTO usage (month, user, requests, tokens_in, tokens_out, cost_micro) VALUES (?1,?2,1,?3,?4,?5)
     ON CONFLICT (month, user) DO UPDATE SET requests = requests + 1, tokens_in = tokens_in + ?3, tokens_out = tokens_out + ?4, cost_micro = cost_micro + ?5`,
  ).bind(now.toISOString().slice(0, 7), user, u.input + u.cacheRead + u.cacheWrite, u.output, costMicro(model, u)).run()
}
