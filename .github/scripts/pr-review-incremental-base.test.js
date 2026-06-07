#!/usr/bin/env node
'use strict';

// Unit test for the incremental-base marker extractor.
// Static, hermetic: no GitHub, git, npm, or model calls. Exercises marker
// parsing, prefix scoping, bot-author trust (forgery rejection), submitted_at
// ordering, and malformed-marker handling — the pure logic behind the
// synchronize incremental base. The git-ancestry selection over these
// candidates is thin shell glue in pr-review-context.sh, verified post-merge
// on a real PR.

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
const BOT = { type: 'Bot' };   // trusted formal-review author (no login pin)
const HUMAN = { type: 'User' }; // untrusted — forged markers must be ignored
const TRUSTED = ['courtesy-bot[bot]', 'github-actions[bot]']; // pinned trusted logins
const bot = (login) => ({ type: 'Bot', login }); // bot with a specific login

// COMMENT-style review body: marker only, no prose.
const commentBody = (prefix, sha) => `<!-- ${prefix} head_sha=${sha} verdict=comment -->`;
// APPROVE-style review body: multi-line prose then the marker.
const approveBody = (prefix, sha) =>
  ['## Claude PR 리뷰', '', '승인되었습니다.', '', `<!-- ${prefix} head_sha=${sha} verdict=approve -->`].join('\n');
// Build a bot-authored review (the trusted, real case).
const rev = (body, submitted_at, user = BOT) => ({ body, submitted_at, user });

test('no reviews → []', () => {
  assert.deepStrictEqual(extractMarkerShas([], CLAUDE), []);
});

test('reviews without this prefix marker → []', () => {
  const reviews = [
    rev('plain human review, looks good', '2026-06-06T04:00:00Z'),
    rev('<!-- claude-review-inline fingerprint=abc -->', '2026-06-06T04:01:00Z'),
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), []);
});

test('single comment marker → [sha]', () => {
  const reviews = [rev(commentBody(CLAUDE, 'e512b9c4d0'), '2026-06-06T04:05:31Z')];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), ['e512b9c4d0']);
});

test('multiple markers ordered by submitted_at DESC (latest first)', () => {
  const reviews = [
    rev(commentBody(CLAUDE, 'aaa111'), '2026-06-06T04:05:00Z'),
    rev(approveBody(CLAUDE, 'ccc333'), '2026-06-06T04:25:00Z'),
    rev(commentBody(CLAUDE, 'bbb222'), '2026-06-06T04:15:00Z'),
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), ['ccc333', 'bbb222', 'aaa111']);
});

test('prefix scoping: codex markers ignored when asking for claude (PR #334 case)', () => {
  // #334: claude has markers, codex has none. Asking for codex → [].
  const reviews = [
    rev(commentBody(CLAUDE, 'e512b9c4d0'), '2026-06-06T04:05:31Z'),
    rev(approveBody(CLAUDE, '9a7c059868'), '2026-06-06T04:25:18Z'),
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CODEX), []);
  // And asking for claude returns both, latest first.
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), ['9a7c059868', 'e512b9c4d0']);
});

test('SECURITY: human-authored (type User) forged marker is ignored', () => {
  // An attacker posts a COMMENT review carrying the marker to forge a base.
  const reviews = [
    rev(commentBody(CODEX, 'forged9999'), '2026-06-06T09:00:00Z', HUMAN),
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CODEX), []);
});

test('SECURITY: bot marker accepted, concurrent human forgery for same prefix dropped', () => {
  const reviews = [
    rev(commentBody(CODEX, 'ff0099'), '2026-06-06T09:00:00Z', HUMAN), // latest, forged → drop
    rev(approveBody(CODEX, 'dead00aa11'), '2026-06-06T08:00:00Z', BOT), // genuine
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CODEX), ['dead00aa11']);
});

test('SECURITY: allowedLogins pins to trusted bot; a DIFFERENT bot is rejected', () => {
  const reviews = [
    rev(commentBody(CODEX, 'ffaa00'), '2026-06-06T09:00:00Z', bot('rogue-bot[bot]')),  // other bot → drop
    rev(approveBody(CODEX, 'bbcc11'), '2026-06-06T08:00:00Z', bot('courtesy-bot[bot]')), // trusted → keep
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CODEX, TRUSTED), ['bbcc11']);
});

test('allowedLogins accepts each trusted login (app bot + github-actions), case-insensitive', () => {
  const reviews = [
    rev(commentBody(CLAUDE, 'aa11'), '2026-06-06T08:00:00Z', bot('github-actions[bot]')),
    rev(approveBody(CLAUDE, 'bb22'), '2026-06-06T09:00:00Z', bot('Courtesy-Bot[bot]')), // case differs
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE, TRUSTED), ['bb22', 'aa11']);
});

test('empty allowedLogins falls back to type===Bot only (unconfigured deployment)', () => {
  const reviews = [rev(commentBody(CLAUDE, 'cc33'), '2026-06-06T08:00:00Z', bot('any-bot[bot]'))];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE, []), ['cc33']);
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), ['cc33']);
});

test('review with missing user is ignored', () => {
  const reviews = [{ body: commentBody(CLAUDE, 'aaa111'), submitted_at: '2026-06-06T04:05:00Z' }];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), []);
});

test('APPROVE multi-line body parsed', () => {
  const reviews = [rev(approveBody(CLAUDE, '9a7c059868'), '2026-06-06T04:25:18Z')];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), ['9a7c059868']);
});

test('COMMENT marker-only body parsed', () => {
  const reviews = [rev(commentBody(CODEX, 'deadbeef01'), '2026-06-06T04:05:31Z')];
  assert.deepStrictEqual(extractMarkerShas(reviews, CODEX), ['deadbeef01']);
});

test('malformed/partial marker skipped gracefully', () => {
  const reviews = [
    rev('<!-- claude-formal-review head_sha= verdict=comment -->', '2026-06-06T04:05:00Z'), // empty sha
    rev('<!-- claude-formal-review head_sha=', '2026-06-06T04:06:00Z'), // truncated, no sha
    rev('<!-- claude-formal-review head_sha=zzz999 -->', '2026-06-06T04:07:00Z'), // non-hex
    rev(commentBody(CLAUDE, 'cafe01'), '2026-06-06T04:08:00Z'), // the one good one
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), ['cafe01']);
});

test('duplicate sha de-duped, most-recent kept', () => {
  const reviews = [
    rev(commentBody(CLAUDE, 'aaa111'), '2026-06-06T04:05:00Z'),
    rev(approveBody(CLAUDE, 'aaa111'), '2026-06-06T04:25:00Z'),
  ];
  assert.deepStrictEqual(extractMarkerShas(reviews, CLAUDE), ['aaa111']);
});

test('non-array / bad input → []', () => {
  assert.deepStrictEqual(extractMarkerShas(null, CLAUDE), []);
  assert.deepStrictEqual(extractMarkerShas([rev(commentBody(CLAUDE, 'aaa'), '2026-06-06T04:00:00Z')], ''), []);
});

console.log(`\nALL ${passed} CHECKS PASSED`);
