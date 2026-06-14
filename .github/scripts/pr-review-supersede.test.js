#!/usr/bin/env node
'use strict';

// Unit test for the deterministic supersede-resolve module used by the codex
// PR review workflow to prevent stale [blocking] finding accumulation.
//
// Background: when the review model re-emits a finding with the SAME
// fingerprint on a new head, the workflow posts a fresh inline thread while the
// previous run's open thread for that fingerprint stays open — two open threads
// per fingerprint pile up, and a stale/contradicted [blocking] thread can keep
// the auto-merge gate falsely blocked. The supersede rule resolves the OLDER
// duplicate(s) so at most one open thread (the newest) survives per fingerprint
// that was newly posted this round. It NEVER suppresses posting (resolve-only).
//
// Static, hermetic: no GitHub, npm, or model calls. Pure function over the
// fingerprints posted this round and the currently-open self threads.

const assert = require('node:assert');
const path = require('node:path');

const M = require(path.join(__dirname, 'pr-review-supersede.js'));

let passed = 0;
function test(name, fn) {
  fn();
  passed += 1;
  console.log(`OK: ${name}`);
}

// ---- contract: only resolve-only output (array of thread ids) ----

test('exports selectSupersededThreads', () => {
  assert.strictEqual(typeof M.selectSupersededThreads, 'function');
});

test('returns an array (resolve-only contract — never a suppression signal)', () => {
  const out = M.selectSupersededThreads({ postedFingerprints: [], openThreads: [] });
  assert.ok(Array.isArray(out));
  assert.strictEqual(out.length, 0);
});

// ---- core: same fingerprint, an older open thread is superseded ----

test('same fingerprint existing open thread → older resolved, newest kept', () => {
  // old thread (order 10) from a prior head + new thread (order 20) just posted.
  const out = M.selectSupersededThreads({
    postedFingerprints: ['fpA'],
    openThreads: [
      { id: 'OLD', fingerprint: 'fpA', order: 10 },
      { id: 'NEW', fingerprint: 'fpA', order: 20 },
    ],
  });
  assert.deepStrictEqual(out, ['OLD']);
});

test('accepts postedFingerprints as a Set', () => {
  const out = M.selectSupersededThreads({
    postedFingerprints: new Set(['fpA']),
    openThreads: [
      { id: 'OLD', fingerprint: 'fpA', order: 10 },
      { id: 'NEW', fingerprint: 'fpA', order: 20 },
    ],
  });
  assert.deepStrictEqual(out, ['OLD']);
});

// ---- multiple older duplicates: keep only newest ----

test('multiple older duplicates of a posted fingerprint → all but newest resolved', () => {
  const out = M.selectSupersededThreads({
    postedFingerprints: ['fpA'],
    openThreads: [
      { id: 'T1', fingerprint: 'fpA', order: 1 },
      { id: 'T2', fingerprint: 'fpA', order: 2 },
      { id: 'T3', fingerprint: 'fpA', order: 3 },
    ],
  });
  assert.deepStrictEqual(out.sort(), ['T1', 'T2']);
});

// ---- safety: do not touch fingerprints NOT posted this round ----

test('fingerprint not posted this round → untouched even if duplicated', () => {
  const out = M.selectSupersededThreads({
    postedFingerprints: ['fpA'],
    openThreads: [
      { id: 'B1', fingerprint: 'fpB', order: 1 },
      { id: 'B2', fingerprint: 'fpB', order: 2 },
    ],
  });
  assert.deepStrictEqual(out, []);
});

// ---- safety: a single open thread for a posted fingerprint is the newest → keep ----

test('single open thread for a posted fingerprint → nothing to supersede', () => {
  const out = M.selectSupersededThreads({
    postedFingerprints: ['fpA'],
    openThreads: [{ id: 'ONLY', fingerprint: 'fpA', order: 5 }],
  });
  assert.deepStrictEqual(out, []);
});

// ---- safety: nothing posted this round (suppressed/skipped) → nothing touched ----

test('empty postedFingerprints (no new post) → never resolves anything', () => {
  const out = M.selectSupersededThreads({
    postedFingerprints: [],
    openThreads: [
      { id: 'OLD', fingerprint: 'fpA', order: 10 },
      { id: 'NEWER', fingerprint: 'fpA', order: 20 },
    ],
  });
  assert.deepStrictEqual(out, []);
});

// ---- mixed: only the posted fingerprint's older dup is resolved ----

test('mixed fingerprints → only posted-fp older dup resolved, others untouched', () => {
  const out = M.selectSupersededThreads({
    postedFingerprints: ['fpA'],
    openThreads: [
      { id: 'A_OLD', fingerprint: 'fpA', order: 1 },
      { id: 'A_NEW', fingerprint: 'fpA', order: 9 },
      { id: 'B_OLD', fingerprint: 'fpB', order: 2 },
      { id: 'B_NEW', fingerprint: 'fpB', order: 8 },
    ],
  });
  assert.deepStrictEqual(out, ['A_OLD']);
});

// ---- robustness: threads with no fingerprint are ignored ----

test('threads missing a fingerprint are ignored', () => {
  const out = M.selectSupersededThreads({
    postedFingerprints: ['fpA'],
    openThreads: [
      { id: 'NOFP', order: 1 },
      { id: 'A_OLD', fingerprint: 'fpA', order: 2 },
      { id: 'A_NEW', fingerprint: 'fpA', order: 3 },
    ],
  });
  assert.deepStrictEqual(out, ['A_OLD']);
});

// ---- robustness: tie/missing order is deterministic (array order breaks ties,
//      later-in-array treated as newer) ----

test('equal/missing order falls back to array position (later = newer)', () => {
  const out = M.selectSupersededThreads({
    postedFingerprints: ['fpA'],
    openThreads: [
      { id: 'FIRST', fingerprint: 'fpA' },
      { id: 'SECOND', fingerprint: 'fpA' },
    ],
  });
  // SECOND appears later → treated as newest → FIRST superseded.
  assert.deepStrictEqual(out, ['FIRST']);
});

// ---- robustness: empty/garbage input never throws ----

test('garbage/empty input is handled without throwing', () => {
  assert.deepStrictEqual(M.selectSupersededThreads({}), []);
  assert.deepStrictEqual(M.selectSupersededThreads({ postedFingerprints: null, openThreads: null }), []);
  assert.deepStrictEqual(M.selectSupersededThreads(), []);
});

console.log(`\nALL ${passed} CHECKS PASSED`);
