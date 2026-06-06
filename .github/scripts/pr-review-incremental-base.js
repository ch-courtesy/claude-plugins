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
//     are considered (codex and claude share one bot identity, so the prefix,
//     not the author, scopes ownership).
//   Returns the marker head_sha values ordered by submitted_at DESCENDING
//   (latest review first), de-duplicated (first/most-recent occurrence kept).
//   Bodies without a well-formed marker for this prefix are ignored.
function extractMarkerShas(reviews, markerPrefix) {
  if (!Array.isArray(reviews) || typeof markerPrefix !== 'string' || !markerPrefix) {
    return [];
  }
  const needle = `<!-- ${markerPrefix} head_sha=`;
  const hits = [];
  for (const r of reviews) {
    const body = r && typeof r.body === 'string' ? r.body : '';
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

// ---- CLI: `node pr-review-incremental-base.js <markerPrefix>` ----
// Reads the reviews JSON array on stdin, prints candidate SHAs (latest first),
// one per line. On any parse error prints nothing (exit 0) so the caller safely
// degrades to a full review.
if (require.main === module) {
  const markerPrefix = process.argv[2] || '';
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
    const shas = extractMarkerShas(reviews, markerPrefix);
    if (shas.length) process.stdout.write(shas.join('\n') + '\n');
  });
}
