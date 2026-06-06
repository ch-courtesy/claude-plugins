#!/usr/bin/env node
'use strict';

// Unit test for the incremental-base marker extractor.
// Static, hermetic: no GitHub, git, npm, or model calls. Exercises marker
// parsing, prefix scoping, submitted_at ordering, and malformed-marker
// handling — the pure logic behind the synchronize incremental base. The
// git-ancestry selection over these candidates is thin shell glue in
// pr-review-context.sh, verified post-merge on a real PR.

const assert = require('node:assert');
const path = require('node:path');

const { extractMarkerShas } =
  require(path.join(__dirname, 'pr-review-incremental-base.js'));

let passed = 0;
function test(name, fn) {
  fn();
  passed += 1;
  console.log(`OK: ${name}`);
}

const CLAUDE = 'claude-formal-review';
const CODEX = 'codex-formal-review';

// COMMENT-style review body: marker only, no prose.
const commentBody = (prefix, sha) => `<!-- ${prefix} head_sha=${sha} verdict=comment -->`;
// APPROVE-style review body: multi-line prose then the marker.
const approveBody = (prefix, sha) =>
  ['## Claude PR 리뷰', '', '승인되었습니다.', '', `<!-- ${prefix} head_sha=${sha} verdict=approve -->`].join('\n');

test('no reviews → []', () => {
  assert.deepStrictEqual(extractMarkerShas([], CLAUDE), []);
});

test('reviews without this prefix marker → []', () => {
  const reviews = [
    { body: 'plain human review, looks good', submitted_at: '2026-06-06T04:00:00Z' },
    { body: '<!-- claude-review-inline fingerprint=abc -->', submitted_at: '2026-06-06T04:01:00Z' },
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), []);
});

test('single comment marker → [sha]', () => {
  const reviews = [{ body: commentBody(CLAUDE, 'e512b9c4d0'), submitted_at: '2026-06-06T04:05:31Z' }];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), ['e512b9c4d0']);
});

test('multiple markers ordered by submitted_at DESC (latest first)', () => {
  const reviews = [
    { body: commentBody(CLAUDE, 'aaa111'), submitted_at: '2026-06-06T04:05:00Z' },
    { body: approveBody(CLAUDE, 'ccc333'), submitted_at: '2026-06-06T04:25:00Z' },
    { body: commentBody(CLAUDE, 'bbb222'), submitted_at: '2026-06-06T04:15:00Z' },
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), ['ccc333', 'bbb222', 'aaa111']);
});

test('prefix scoping: codex markers ignored when asking for claude (PR #334 case)', () => {
  // #334: claude has markers, codex has none. Asking for codex → [].
  const reviews = [
    { body: commentBody(CLAUDE, 'e512b9c4d0'), submitted_at: '2026-06-06T04:05:31Z' },
    { body: approveBody(CLAUDE, '9a7c059868'), submitted_at: '2026-06-06T04:25:18Z' },
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CODEX), []);
  // And asking for claude returns both, latest first.
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), ['9a7c059868', 'e512b9c4d0']);
});

test('APPROVE multi-line body parsed', () => {
  const reviews = [{ body: approveBody(CLAUDE, '9a7c059868'), submitted_at: '2026-06-06T04:25:18Z' }];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), ['9a7c059868']);
});

test('COMMENT marker-only body parsed', () => {
  const reviews = [{ body: commentBody(CODEX, 'deadbeef01'), submitted_at: '2026-06-06T04:05:31Z' }];
  assert.deepStrictEqual(extractMarkerShas(reviews, CODEX), ['deadbeef01']);
});

test('malformed/partial marker skipped gracefully', () => {
  const reviews = [
    { body: '<!-- claude-formal-review head_sha= verdict=comment -->', submitted_at: '2026-06-06T04:05:00Z' }, // empty sha
    { body: '<!-- claude-formal-review head_sha=', submitted_at: '2026-06-06T04:06:00Z' }, // truncated, no sha
    { body: '<!-- claude-formal-review head_sha=zzz999 -->', submitted_at: '2026-06-06T04:07:00Z' }, // non-hex
    { body: commentBody(CLAUDE, 'cafe01'), submitted_at: '2026-06-06T04:08:00Z' }, // the one good one
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), ['cafe01']);
});

test('duplicate sha de-duped, most-recent kept', () => {
  const reviews = [
    { body: commentBody(CLAUDE, 'aaa111'), submitted_at: '2026-06-06T04:05:00Z' },
    { body: approveBody(CLAUDE, 'aaa111'), submitted_at: '2026-06-06T04:25:00Z' },
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), ['aaa111']);
});

test('non-array / bad input → []', () => {
  assert.deepStrictEqual(extractMarkerShas(null, CLAUDE), []);
  assert.deepStrictEqual(extractMarkerShas([{ body: commentBody(CLAUDE, 'aaa') }], ''), []);
});

console.log(`\nALL ${passed} CHECKS PASSED`);
