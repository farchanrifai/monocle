import Anthropic from '@anthropic-ai/sdk'
import { APPLE_ROOT_G3_SHA256, ReceiptError, sha256, verifyReceipt } from './receipt'
import { PRICES, costMicro, parseUsage } from './usage'

// Ankka's chat proxy: the app sends a Messages API request with its App Store transaction, the Worker checks the
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
  /** TestFlight and App Review buy in the sandbox; they get their own pool so they can't use up paying users' cap. */
  CAP_MONTHLY_USD_SANDBOX?: string
  /** Workers rate limiting binding (wrangler.toml [[ratelimits]]); the vote routes are open, so cap them per IP. */
  VOTE_LIMITER?: { limit(options: { key: string }): Promise<{ success: boolean }> }
  BUNDLE_ID: string
  PRODUCT_IDS: string
  ENVIRONMENTS: string
}

/** Errors in the Messages API shape, so the app reads one format. `ankka_*` types carry a message for the user. */
export const fail = (status: number, type: string, message: string) =>
  Response.json({ type: 'error', error: { type, message } }, { status })

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const path = new URL(req.url).pathname
    if (req.method === 'GET' && path === '/health') return Response.json({ ok: true })
    if (req.method === 'POST' && path === '/v1/vote') return vote(req, env)
    if (req.method === 'GET' && path === '/v1/roadmap') return roadmap(env)
    if (req.method === 'POST' && path === '/v1/roadmap/vote') return roadmapVote(req, env)
    if (req.method !== 'POST' || path !== '/v1/messages') return fail(404, 'not_found_error', 'Not found')

    const user = await identify(req, env)
    if (user instanceof Response) return user
    const capped = await capMessage(env, user)
    if (capped) return fail(429, 'ankka_cap_error', capped)

    const raw = await req.text()
    if (new TextEncoder().encode(raw).length > Number(env.MAX_BODY_BYTES)) return fail(413, 'request_too_large', 'Request body too large')
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

/** `{version, up}` from a What's New vote body, or null when it isn't one. */
export function parseVote(body: any): { version: string; up: boolean } | null {
  if (!body || typeof body.version !== 'string' || typeof body.up !== 'boolean') return null
  return /^\d{1,3}(\.\d{1,3}){0,2}$/.test(body.version) ? { version: body.version, up: body.up } : null
}

// ponytail: open and anonymous, so anyone can inflate a count with curl; the app sends one vote per version. Add a
// per-install id (and a privacy label change) if the numbers ever look gamed.
/** True when this IP has voted too often in the last minute. D1 writes are shared with chat metering. */
async function limited(req: Request, env: Env): Promise<boolean> {
  if (!env.VOTE_LIMITER) return false
  const { success } = await env.VOTE_LIMITER.limit({ key: req.headers.get('cf-connecting-ip') ?? 'unknown' })
  return !success
}

async function vote(req: Request, env: Env): Promise<Response> {
  if (await limited(req, env)) return fail(429, 'rate_limit_error', 'Too many votes')
  let v: ReturnType<typeof parseVote> = null
  try { v = parseVote(await req.json()) } catch {}
  if (!v) return fail(400, 'invalid_request_error', 'Expected {version, up}')
  await env.DB.prepare(
    `INSERT INTO votes (version, up, down) VALUES (?1, ?2, ?3)
     ON CONFLICT (version) DO UPDATE SET up = up + ?2, down = down + ?3`,
  ).bind(v.version, v.up ? 1 : 0, v.up ? 0 : 1).run()
  return Response.json({ ok: true })
}

/** Coming items first, then shipped; never the counts (seeing them makes people follow the crowd). */
async function roadmap(env: Env): Promise<Response> {
  const { results } = await env.DB.prepare(
    'SELECT id, title, detail, shipped_in FROM roadmap ORDER BY shipped_in IS NOT NULL, sort, title',
  ).all()
  return Response.json({ items: results }, { headers: { 'cache-control': 'max-age=300' } })
}

const thumbs = [1, 0, -1]

/** `{id, vote, previous}` (1 up, -1 down, 0 none) from a roadmap vote body, or null. `previous` lets a phone change
 *  or take back its vote without the server knowing who it is. */
export function parseRoadmapVote(body: any): { id: string; vote: number; previous: number } | null {
  if (!body || typeof body.id !== 'string' || !/^[a-z0-9-]{1,40}$/.test(body.id)) return null
  if (!thumbs.includes(body.vote) || !thumbs.includes(body.previous) || body.vote === body.previous) return null
  return { id: body.id, vote: body.vote, previous: body.previous }
}

// ponytail: same open, anonymous counters as `vote`; MAX(0, …) only stops a forged undo from going negative.
async function roadmapVote(req: Request, env: Env): Promise<Response> {
  if (await limited(req, env)) return fail(429, 'rate_limit_error', 'Too many votes')
  let v: ReturnType<typeof parseRoadmapVote> = null
  try { v = parseRoadmapVote(await req.json()) } catch {}
  if (!v) return fail(400, 'invalid_request_error', 'Expected {id, vote, previous}')
  const up = Number(v.vote === 1) - Number(v.previous === 1)
  const down = Number(v.vote === -1) - Number(v.previous === -1)
  await env.DB.prepare('UPDATE roadmap SET up = MAX(0, up + ?2), down = MAX(0, down + ?3) WHERE id = ?1 AND shipped_in IS NULL')
    .bind(v.id, up, down).run()
  return Response.json({ ok: true })
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

/** The subscription behind the request (its originalTransactionId, `sandbox:`-prefixed for test purchases), or the error to send back. */
async function identify(req: Request, env: Env): Promise<string | Response> {
  const owner = req.headers.get('x-ankka-owner')
  if (owner) return env.OWNER_KEY && (await sha256(owner)) === (await sha256(env.OWNER_KEY)) ? 'owner' : fail(403, 'permission_error', 'Owner key rejected')

  const jws = req.headers.get('x-ankka-receipt')
  if (!jws) return fail(401, 'ankka_receipt_error', 'Claude chat is part of Ankka Pro.')
  const hash = await sha256(jws)
  let row = await env.DB.prepare('SELECT user, expires_ms, environment FROM receipts WHERE hash = ?1').bind(hash).first<{ user: string; expires_ms: number; environment: string }>()
  if (!row) {
    try {
      const r = await verifyReceipt(jws, {
        bundleId: env.BUNDLE_ID, productIds: env.PRODUCT_IDS.split(','), environments: env.ENVIRONMENTS.split(','), rootSha256: APPLE_ROOT_G3_SHA256,
      })
      row = { user: r.originalTransactionId, expires_ms: r.expiresMs, environment: r.environment }
      await env.DB.prepare('INSERT OR IGNORE INTO receipts (hash, user, expires_ms, environment, created_at) VALUES (?1,?2,?3,?4,?5)')
        .bind(hash, r.originalTransactionId, r.expiresMs, r.environment, Date.now()).run()
    } catch (e) {
      if (!(e instanceof ReceiptError)) throw e
      console.log(JSON.stringify({ receipt: e.message }))
      return fail(401, 'ankka_receipt_error', "Ankka Pro couldn't be confirmed. Try Restore Purchases in Settings.")
    }
  }
  if (row.expires_ms <= Date.now()) return fail(401, 'ankka_receipt_error', 'Your Ankka Pro subscription has ended.')
  return row.environment === 'Sandbox' ? `sandbox:${row.user}` : row.user
}

/** A user-facing message when this month's cap is reached, or null. Per subscription, then for its pool: paying users
 *  (and the owner) share the global cap, sandbox (TestFlight, App Review) users share their own. */
export async function capMessage(env: Env, user: string, now = new Date()): Promise<string | null> {
  const sandbox = user.startsWith('sandbox:')
  const s = await env.DB.prepare(
    "SELECT COALESCE(SUM(CASE WHEN user = ?2 THEN cost_micro END), 0) AS mine, COALESCE(SUM(CASE WHEN (user LIKE 'sandbox:%') = ?3 THEN cost_micro END), 0) AS total FROM usage WHERE month = ?1",
  ).bind(now.toISOString().slice(0, 7), user, sandbox ? 1 : 0).first<{ mine: number; total: number }>()
  if (user !== 'owner' && s!.mine >= Number(env.CAP_MONTHLY_USD_USER) * 1e6) return "You've reached this month's chat limit. It resets on the 1st."
  const pool = Number(sandbox ? env.CAP_MONTHLY_USD_SANDBOX ?? '5' : env.CAP_MONTHLY_USD_GLOBAL)
  if (s!.total >= pool * 1e6) return sandbox
    ? 'Claude chat for test purchases is paused until the 1st. On-device chat still works where available.'
    : 'Claude chat is paused until the 1st. On-device chat still works where available.'
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
