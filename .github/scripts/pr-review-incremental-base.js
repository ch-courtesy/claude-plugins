'use strict';

// Shared incremental-base resolver for the codex / claude PR review workflows.
//
// On a `synchronize` event the workflows must diff the PR head against the
// commit this reviewer LAST SUCCESSFULLY REVIEWED — not against the webhook's
// `event.before` (the previous push head). `event.before` advances on every
// push regardless of whether the prior review actually ran, so a failed review
// (e.g. usage-limit → no review posted) leaves its commits silently skipped by
// the next incremental diff while the check still goes green.
//
// The success-gated, per-reviewer source of truth already exists: each workflow
// posts a formal-review marker `<!-- <prefix> head_sha=<sha> verdict=<v> -->`
// (prefix `claude-formal-review` / `codex-formal-review`) via createReview ONLY
// when a review is actually submitted (approve/comment) — never on failure,
// unavailable, or skipped. So this reviewer's most recent marker head_sha is the
// last SHA it truly reviewed. This module extracts those SHAs (latest first);
// the shell glue then picks the most recent one that is an ancestor of the
// current head as the incremental base (falling back to a full diff otherwise).
//
// CommonJS + a stdin CLI entry so the bash script (pr-review-context.sh) can pipe
// `gh api .../pulls/{n}/reviews` JSON in and read newline-separated SHAs out.
// Pure: no I/O, git, or network in the exported logic. Like the sibling
// diff-anchor-filter.js / pr-review-chunking.js, a PR that introduces or
// modifies this module is reviewed by the base checkout, so it only takes
// effect post-merge.

// extractMarkerShas(reviews, markerPrefix) → [sha, ...]
//   reviews: array of GitHub review objects (each may have .body, .submitted_at).
//   markerPrefix: e.g. 'claude-formal-review' — only this reviewer's markers
//     are considered (codex and claude share one bot identity, so the prefix
//     scopes WHICH reviewer; the author check below scopes that the marker is
//     genuinely bot-posted).
//   SECURITY: only reviews authored by a Bot account (`user.type === 'Bot'`) are
//     trusted. Formal-review markers are posted by the App bot (`<slug>[bot]`) or
//     the default `github-actions[bot]` — both type Bot. A human (e.g. the PR
//     author, type 'User') could otherwise submit a COMMENT review carrying the
//     marker to FORGE a "last reviewed" SHA at an un-reviewed head, making the
//     next incremental diff skip their unreviewed changes.
//   allowedLogins: optional array of the EXACT trusted reviewer-bot logins (e.g.
//     ['courtesy-bot[bot]', 'github-actions[bot]']). The workflow derives these
//     dynamically from the review App slug (`<app-slug>[bot]`) plus the default
//     `github-actions[bot]`. When provided, a marker is trusted ONLY if its
//     review author login is in this set — so a DIFFERENT bot account that also
//     has PR-review-write cannot forge a marker (the residual gap that bare
//     `type === 'Bot'` left open). When empty/omitted, falls back to requiring
//     `type === 'Bot'` (blocks human forgery; used by unconfigured deployments).
//   Returns the marker head_sha values ordered by submitted_at DESCENDING
//   (latest review first), de-duplicated (first/most-recent occurrence kept).
//   Bodies without a well-formed marker for this prefix are ignored.
function extractMarkerShas(reviews, markerPrefix, allowedLogins) {
  if (!Array.isArray(reviews) || typeof markerPrefix !== 'string' || !markerPrefix) {
    return [];
  }
  const allow = Array.isArray(allowedLogins)
    ? allowedLogins.filter((l) => typeof l === 'string' && l).map((l) => l.toLowerCase())
    : [];
  const needle = `<!-- ${markerPrefix} head_sha=`;
  const hits = [];
  for (const r of reviews) {
    // Trust only bot-authored reviews — a human/non-bot marker is a forgery.
    if (!r || !r.user || r.user.type !== 'Bot') continue;
    // When an explicit trusted-login set is configured, the marker author must
    // be one of them — a different review-writing bot cannot forge the base.
    if (allow.length && !allow.includes(String(r.user.login || '').toLowerCase())) continue;
    const body = typeof r.body === 'string' ? r.body : '';
    const at = body.indexOf(needle);
    if (at === -1) continue;
    // SHA runs from just after the needle up to the next whitespace.
    const rest = body.slice(at + needle.length);
    const sha = rest.split(/\s/, 1)[0];
    if (!/^[0-9a-f]+$/i.test(sha)) continue; // malformed/partial marker → skip
    hits.push({ sha, at: (r && typeof r.submitted_at === 'string') ? r.submitted_at : '' });
  }
  // ISO-8601 submitted_at sorts chronologically as a string; empty (missing)
  // sorts last under a descending order. Stable enough — distinct SHAs differ.
  hits.sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0));
  const seen = new Set();
  const out = [];
  for (const h of hits) {
    if (seen.has(h.sha)) continue;
    seen.add(h.sha);
    out.push(h.sha);
  }
  return out;
}

module.exports = { extractMarkerShas };

// ---- CLI: `node pr-review-incremental-base.js <markerPrefix> [allowedLogins]` ----
// Reads the reviews JSON array on stdin, prints candidate SHAs (latest first),
// one per line. allowedLogins is an optional comma-separated trusted-bot login
// list. On any parse error prints nothing (exit 0) so the caller safely degrades
// to a full review.
if (require.main === module) {
  const markerPrefix = process.argv[2] || '';
  const allowedLogins = (process.argv[3] || '')
    .split(',').map((s) => s.trim()).filter(Boolean);
  let buf = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (d) => { buf += d; });
  process.stdin.on('end', () => {
    let reviews = [];
    try {
      const parsed = JSON.parse(buf || '[]');
      if (Array.isArray(parsed)) reviews = parsed;
    } catch (_e) {
      // Malformed/empty input → no candidates → caller does a full review.
      return;
    }
    const shas = extractMarkerShas(reviews, markerPrefix, allowedLogins);
    if (shas.length) process.stdout.write(shas.join('\n') + '\n');
  });
}
