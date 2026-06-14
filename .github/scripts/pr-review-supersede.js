'use strict';

// Deterministic supersede-resolve for the codex PR review workflow.
//
// Problem this guards against: the review model can re-emit a finding with the
// SAME deterministic fingerprint on a new head (e.g. it re-flags an already
// fixed hunk surfaced by the incremental diff). The workflow then posts a fresh
// inline thread for that fingerprint while the PREVIOUS run's open thread for
// the same fingerprint stays open — open threads pile up two-per-fingerprint,
// and a stale (current-code-contradicting) [blocking] thread can keep the
// auto-merge gate falsely blocked forever.
//
// Rule (additive to the existing resolved_threads/fallback resolve tiers — it
// does NOT weaken them): whenever a fingerprint is NEWLY posted this round and
// more than one open self thread carries that fingerprint, keep only the newest
// open thread and mark the older one(s) to be resolved (superseded). At most one
// open thread (the newest) survives per posted fingerprint.
//
// This is resolve-only: the function returns thread ids to resolve and NEVER a
// suppression signal — the new finding is always posted (no false-green). It is
// scoped strictly to fingerprints posted this round, so it never touches a
// finding that wasn't re-reported (those are handled by the existing fallback
// tier) and never touches another reviewer's or a different fingerprint's
// thread.
//
// CommonJS, pure function, no I/O or network: it operates only on the
// fingerprints the workflow posted and the open self threads it already
// fetched.

// Resolve order key for a thread. A larger key means newer. Threads are created
// in id/databaseId-monotonic order, so the freshly posted thread (this round)
// has the largest key and is the one kept. When `order` is absent or not a
// finite number, fall back to the thread's position in the input array (passed
// as `idx`) so ties are still deterministic and the later-listed thread is
// treated as newer.
function orderOf(thread, idx) {
  const o = thread && thread.order;
  return (typeof o === 'number' && Number.isFinite(o)) ? o : idx;
}

// selectSupersededThreads({ postedFingerprints, openThreads }) -> string[]
//   postedFingerprints: iterable (Array | Set) of fingerprints newly posted
//                       this round. Empty when nothing was posted (skipped /
//                       failed submit) — then nothing is ever superseded.
//   openThreads: [{ id, fingerprint, order? }] for currently-open self-owned
//                threads. Already-resolved threads must NOT be included by the
//                caller; threads without a fingerprint are ignored here.
// Returns the ids of older duplicate threads to resolve (newest kept).
function selectSupersededThreads(input) {
  const arg = input || {};
  const posted = arg.postedFingerprints instanceof Set
    ? arg.postedFingerprints
    : new Set(Array.isArray(arg.postedFingerprints) ? arg.postedFingerprints : []);
  const openThreads = Array.isArray(arg.openThreads) ? arg.openThreads : [];

  if (posted.size === 0) return [];

  // Group open threads (with a fingerprint that was posted this round) by
  // fingerprint, preserving each thread's input index for tie-breaking.
  const groups = new Map();
  openThreads.forEach((t, idx) => {
    if (!t || typeof t.fingerprint !== 'string' || t.fingerprint.length === 0) return;
    if (!posted.has(t.fingerprint)) return;
    if (!groups.has(t.fingerprint)) groups.set(t.fingerprint, []);
    groups.get(t.fingerprint).push({ id: t.id, key: orderOf(t, idx) });
  });

  const superseded = [];
  for (const group of groups.values()) {
    if (group.length <= 1) continue; // only the newest exists — nothing to do
    // Keep the single newest (largest key); resolve every other.
    let newestIdx = 0;
    for (let i = 1; i < group.length; i += 1) {
      // `>=` so a later-in-array tie wins (treated as newer).
      if (group[i].key >= group[newestIdx].key) newestIdx = i;
    }
    group.forEach((g, i) => { if (i !== newestIdx) superseded.push(g.id); });
  }
  return superseded;
}

module.exports = { selectSupersededThreads };
