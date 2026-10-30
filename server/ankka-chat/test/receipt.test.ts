import * as x509 from '@peculiar/x509'
import { beforeAll, expect, test } from 'vitest'
import { hex, verifyReceipt, type Policy } from '../src/receipt'
import { clamp } from '../src/index'

// A stand-in for Apple's chain: same shape (root → intermediate → leaf, marker extensions, ES256), our own keys.
const alg = { name: 'ECDSA', namedCurve: 'P-256', hash: 'SHA-256' }
const day = 86_400_000
const now = Date.UTC(2026, 9, 30)
let chain: { leaf: x509.X509Certificate; intermediate: x509.X509Certificate; root: x509.X509Certificate; key: CryptoKey }
let policy: Policy

const marker = (oid: string) => new x509.Extension(oid, false, new Uint8Array([5, 0]))
async function cert(name: string, issuer: string, keys: CryptoKeyPair, signer: CryptoKey, ext: x509.Extension[]) {
  return x509.X509CertificateGenerator.create({
    serialNumber: '01', subject: `CN=${name}`, issuer: `CN=${issuer}`, notBefore: new Date(now - day), notAfter: new Date(now + 365 * day),
    signingAlgorithm: alg, publicKey: keys.publicKey, signingKey: signer, extensions: ext,
  })
}

beforeAll(async () => {
  const gen = () => crypto.subtle.generateKey(alg, true, ['sign', 'verify']) as Promise<CryptoKeyPair>
  const [r, i, l] = await Promise.all([gen(), gen(), gen()])
  const root = await cert('Root', 'Root', r, r.privateKey, [])
  const intermediate = await cert('WWDR', 'Root', i, r.privateKey, [marker('1.2.840.113635.100.6.2.1')])
  const leaf = await cert('Leaf', 'WWDR', l, i.privateKey, [marker('1.2.840.113635.100.6.11.1')])
  chain = { leaf, intermediate, root, key: l.privateKey }
  policy = { bundleId: 'com.farchan.ankka', productIds: ['com.farchan.ankka.pro.yearly'], environments: ['Production', 'Sandbox'],
             rootSha256: hex(await crypto.subtle.digest('SHA-256', root.rawData)) }
})

const b64 = (b: ArrayBuffer | Uint8Array) => btoa(String.fromCharCode(...new Uint8Array(b)))
const b64url = (b: ArrayBuffer | Uint8Array) => b64(b).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
const text = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)))

async function jws(payload: Record<string, unknown>, key = chain.key) {
  const head = text({ alg: 'ES256', x5c: [chain.leaf, chain.intermediate, chain.root].map((c) => b64(c.rawData)) })
  const body = text({ bundleId: 'com.farchan.ankka', productId: 'com.farchan.ankka.pro.yearly', environment: 'Production',
                      originalTransactionId: '2000000123', expiresDate: now + 30 * day, ...payload })
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(`${head}.${body}`))
  return `${head}.${body}.${b64url(sig)}`
}

test('a signed Pro transaction gives its original transaction id and expiry', async () => {
  expect(await verifyReceipt(await jws({}), policy, now)).toEqual({ originalTransactionId: '2000000123', expiresMs: now + 30 * day, environment: 'Production' })
})

test('rejects another app, product, environment, a refund, and an unknown root', async () => {
  await expect(verifyReceipt(await jws({ bundleId: 'com.other' }), policy, now)).rejects.toThrow('other app')
  await expect(verifyReceipt(await jws({ productId: 'x' }), policy, now)).rejects.toThrow('other product')
  await expect(verifyReceipt(await jws({ environment: 'Xcode' }), policy, now)).rejects.toThrow('environment')
  await expect(verifyReceipt(await jws({ revocationDate: now }), policy, now)).rejects.toThrow('refunded')
  await expect(verifyReceipt(await jws({}), { ...policy, rootSha256: '00' }, now)).rejects.toThrow('untrusted root')
})

test('rejects a tampered payload or a signature from another key', async () => {
  const [h, , s] = (await jws({})).split('.')
  await expect(verifyReceipt(`${h}.${text({ bundleId: 'com.farchan.ankka', productId: 'com.farchan.ankka.pro.yearly', environment: 'Production', originalTransactionId: '1', expiresDate: now + day })}.${s}`, policy, now)).rejects.toThrow('bad signature')
  const other = (await crypto.subtle.generateKey(alg, true, ['sign', 'verify']) as CryptoKeyPair).privateKey
  await expect(verifyReceipt(await jws({}, other), policy, now)).rejects.toThrow('bad signature')
})

test('rejects certificates outside their validity', async () => {
  await expect(verifyReceipt(await jws({}), policy, now + 400 * day)).rejects.toThrow('out of date')
})

test('clamp pins the model and output ceiling and refuses server tools', () => {
  const env = { MODEL: 'claude-haiku-5-5', MAX_TOKENS_CEILING: '16000' }
  const body: any = { model: 'claude-opus-5-5', max_tokens: 64000, messages: [], speed: 'fast' }
  expect(clamp(body, env)).toBeNull()
  expect(body).toEqual({ model: 'claude-haiku-5-5', max_tokens: 16000, messages: [] })
  expect(clamp({ messages: [], tools: [{ type: 'web_search_20260209', name: 'web_search' }] }, env)).toBe('Server tools are not allowed')
  expect(clamp({ max_tokens: 10 }, env)).toBe('messages required')
})
