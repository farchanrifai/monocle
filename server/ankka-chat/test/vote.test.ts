import { expect, test } from 'vitest'
import { parseVote } from '../src/index'

test('parseVote takes a version and a thumb, nothing else', () => {
  expect(parseVote({ version: '0.9.9', up: true })).toEqual({ version: '0.9.9', up: true })
  expect(parseVote({ version: '1', up: false })).toEqual({ version: '1', up: false })
  expect(parseVote({ version: '1.0', up: 1 })).toBeNull()
  expect(parseVote({ version: "1.0'; DROP TABLE votes", up: true })).toBeNull()
  expect(parseVote({ version: '1.2.3.4', up: true })).toBeNull()
  expect(parseVote({ version: 'x'.repeat(5000), up: true })).toBeNull()
  expect(parseVote(null)).toBeNull()
})
