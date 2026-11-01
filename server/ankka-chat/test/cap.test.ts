import { expect, test } from 'vitest'
import { capMessage, type Env } from '../src/index'

// D1 stand-in: records the bound values and returns the given sums.
const env = (mine: number, total: number, seen: unknown[][] = []) => ({
  DB: { prepare: () => ({ bind: (...values: unknown[]) => { seen.push(values); return { first: async () => ({ mine, total }) } } }) },
  CAP_MONTHLY_USD_USER: '1', CAP_MONTHLY_USD_GLOBAL: '25', CAP_MONTHLY_USD_SANDBOX: '5',
}) as unknown as Env

test('sandbox purchases draw on their own pool, paying users on the global one', async () => {
  const seen: unknown[][] = []
  expect(await capMessage(env(0, 6e6, seen), 'sandbox:2000000123')).toMatch(/test purchases/)
  expect(seen[0][2]).toBe(1)
  expect(await capMessage(env(0, 6e6), '2000000123')).toBeNull()
  expect(await capMessage(env(0, 25e6), '2000000123')).toMatch(/^Claude chat is paused/)
  expect(await capMessage(env(1e6, 0), '2000000123')).toMatch(/this month's chat limit/)
  expect(await capMessage(env(5e6, 0), 'owner')).toBeNull()
})
