import { expect, test } from 'vitest'
import { parseRoadmapVote, parseVote } from '../src/index'

test('parseVote takes a version and a thumb, nothing else', () => {
  expect(parseVote({ version: '0.9.9', up: true })).toEqual({ version: '0.9.9', up: true })
  expect(parseVote({ version: '1', up: false })).toEqual({ version: '1', up: false })
  expect(parseVote({ version: '1.0', up: 1 })).toBeNull()
  expect(parseVote({ version: "1.0'; DROP TABLE votes", up: true })).toBeNull()
  expect(parseVote({ version: '1.2.3.4', up: true })).toBeNull()
  expect(parseVote({ version: 'x'.repeat(5000), up: true })).toBeNull()
  expect(parseVote(null)).toBeNull()
})

test('parseRoadmapVote takes a slug and a real change of thumb', () => {
  expect(parseRoadmapVote({ id: 'icloud-sync', vote: 1, previous: 0 })).toEqual({ id: 'icloud-sync', vote: 1, previous: 0 })
  expect(parseRoadmapVote({ id: 'icloud-sync', vote: -1, previous: 1 })).toEqual({ id: 'icloud-sync', vote: -1, previous: 1 })
  expect(parseRoadmapVote({ id: 'icloud-sync', vote: 0, previous: -1 })).toEqual({ id: 'icloud-sync', vote: 0, previous: -1 })
  expect(parseRoadmapVote({ id: 'icloud-sync', vote: 1, previous: 1 })).toBeNull()
  expect(parseRoadmapVote({ id: 'icloud-sync', vote: 2, previous: 0 })).toBeNull()
  expect(parseRoadmapVote({ id: 'icloud-sync', vote: '1', previous: 0 })).toBeNull()
  expect(parseRoadmapVote({ id: "x'; DROP TABLE roadmap", vote: 1, previous: 0 })).toBeNull()
  expect(parseRoadmapVote({ id: 'a'.repeat(41), vote: 1, previous: 0 })).toBeNull()
})
