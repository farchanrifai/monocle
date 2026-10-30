// Copied from luna-server/src/usage.ts. Prices in USD per million tokens. Haiku/Sonnet in/out from the claude-api skill cache (2026-10-06).
// Cache multipliers from the claude-api docs: read 0.1x input, write 1.25x (5m TTL) or 2x (1h TTL).
// ponytail: Haiku 5.5's own cache prices aren't listed separately (assumed standard multipliers), and its >100K
// "long" prompt tier (5x) is assumed to scale the same way. Verify against the Console bill.
type Price = { in: number; out: number; read: number; write5m: number; write1h: number }
const p = (i: number, o: number): Price => ({ in: i, out: o, read: i / 10, write5m: i * 1.25, write1h: i * 2 })

export const PRICES: Record<string, { std: Price; long?: Price }> = {
  'claude-haiku-5-5': { std: p(0.1, 0.5), long: p(0.5, 2.5) },
}

export type Usage = { input: number; output: number; cacheRead: number; cacheWrite: number; cacheWrite1h: number } // cacheWrite includes the 1h part

/** micro-USD (tokens x $/MTok = micro-dollars), rounded up. */
export function costMicro(model: string, u: Usage): number {
  const m = PRICES[model]
  if (!m) throw new Error(`no price for ${model}`)
  const price = m.long && u.input + u.cacheRead + u.cacheWrite > 100_000 ? m.long : m.std
  return Math.ceil(u.input * price.in + u.output * price.out + u.cacheRead * price.read + (u.cacheWrite - u.cacheWrite1h) * price.write5m + u.cacheWrite1h * price.write1h)
}

const FIELDS = {
  input_tokens: 'input',
  output_tokens: 'output',
  cache_read_input_tokens: 'cacheRead',
  cache_creation_input_tokens: 'cacheWrite',
} as const

export const emptyUsage = (): Usage => ({ input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cacheWrite1h: 0 })

/** Copies the usage fields present in an Anthropic `usage` object onto `u`. */
export function mergeUsage(u: Usage, src: Record<string, unknown> | undefined): void {
  for (const [k, f] of Object.entries(FIELDS)) {
    const v = src?.[k]
    if (typeof v === 'number') u[f] = v
  }
  const h = (src?.cache_creation as Record<string, unknown> | undefined)?.ephemeral_1h_input_tokens
  if (typeof h === 'number') u.cacheWrite1h = h
}

/** Reads usage from a non-streaming JSON body or a full SSE transcript (message_start + message_delta). */
export function parseUsage(text: string, sse: boolean): Usage {
  const u = emptyUsage()
  const merge = (src: Record<string, unknown> | undefined) => mergeUsage(u, src)
  if (!sse) {
    try { merge(JSON.parse(text).usage) } catch { /* unbilled if unparseable */ }
    return u
  }
  for (const line of text.split('\n')) {
    // Only two events carry usage; skipping JSON.parse on the hundreds of deltas keeps CPU low (Workers Free = 10 ms).
    if (!line.startsWith('data:') || !(line.includes('"message_start"') || line.includes('"message_delta"'))) continue
    try {
      const ev = JSON.parse(line.slice(5))
      if (ev.type === 'message_start') merge(ev.message?.usage)
      else if (ev.type === 'message_delta') merge(ev.usage)
    } catch { /* keep going */ }
  }
  return u
}
