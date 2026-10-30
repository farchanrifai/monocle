import * as x509 from '@peculiar/x509'

x509.cryptoProvider.set(crypto)

/** Apple Root CA - G3 (apple.com/certificateauthority), SHA-256 of its DER. Every App Store transaction chains to it. */
export const APPLE_ROOT_G3_SHA256 = '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179'
/** Marker extensions Apple puts on the App Store receipt-signing leaf and its WWDR intermediate. */
const LEAF_OID = '1.2.840.113635.100.6.11.1'
const INTERMEDIATE_OID = '1.2.840.113635.100.6.2.1'

export type Policy = { bundleId: string; productIds: string[]; environments: string[]; rootSha256: string }
export type Receipt = { originalTransactionId: string; expiresMs: number; environment: string }
export class ReceiptError extends Error {}

const bytes = (b64: string): Uint8Array<ArrayBuffer> => Uint8Array.from(atob(b64.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(b64.length / 4) * 4, '=')), (c) => c.charCodeAt(0))
const json = (b64url: string) => JSON.parse(new TextDecoder().decode(bytes(b64url)))
export const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('')
export const sha256 = async (s: string) => hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)))

/** Checks a StoreKit 2 transaction (`Transaction.jwsRepresentation`) the way Apple's server library does: x5c chain to the
 *  pinned root, Apple's marker extensions, the ES256 signature, then the app, product, environment and expiry. */
export async function verifyReceipt(jws: string, policy: Policy, now = Date.now()): Promise<Receipt> {
  const parts = jws.split('.')
  if (parts.length !== 3) throw new ReceiptError('not a JWS')
  let header: any, payload: any
  try { header = json(parts[0]); payload = json(parts[1]) } catch { throw new ReceiptError('unreadable JWS') }
  if (header.alg !== 'ES256' || !Array.isArray(header.x5c) || header.x5c.length !== 3) throw new ReceiptError('unexpected JWS header')

  const ders = header.x5c.map((c: string) => bytes(c))
  if (hex(await crypto.subtle.digest('SHA-256', ders[2])) !== policy.rootSha256) throw new ReceiptError('untrusted root')
  const [leaf, intermediate, root] = ders.map((d: Uint8Array<ArrayBuffer>) => new x509.X509Certificate(d))
  const at = new Date(now)
  if ([leaf, intermediate, root].some((c) => at < c.notBefore || at > c.notAfter)) throw new ReceiptError('certificate out of date')
  if (!leaf.getExtension(LEAF_OID) || !intermediate.getExtension(INTERMEDIATE_OID)) throw new ReceiptError('not an App Store signing chain')
  if (!(await intermediate.verify({ publicKey: root, signatureOnly: true })) || !(await leaf.verify({ publicKey: intermediate, signatureOnly: true })))
    throw new ReceiptError('broken certificate chain')
  const key = await leaf.publicKey.export({ name: 'ECDSA', namedCurve: 'P-256' } as EcKeyImportParams, ['verify'])
  const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`)
  if (!(await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, bytes(parts[2]), signed))) throw new ReceiptError('bad signature')

  if (payload.bundleId !== policy.bundleId) throw new ReceiptError('other app')
  if (!policy.productIds.includes(payload.productId)) throw new ReceiptError('other product')
  if (!policy.environments.includes(payload.environment)) throw new ReceiptError(`environment ${payload.environment}`)
  if (payload.revocationDate) throw new ReceiptError('refunded')
  if (typeof payload.expiresDate !== 'number' || typeof payload.originalTransactionId !== 'string') throw new ReceiptError('not a subscription')
  return { originalTransactionId: payload.originalTransactionId, expiresMs: payload.expiresDate, environment: payload.environment }
}
