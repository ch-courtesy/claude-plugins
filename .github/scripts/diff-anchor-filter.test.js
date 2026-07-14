#!/usr/bin/env node
'use strict';

// Unit test for the shared diff-only anchor filter module.
// Static, hermetic: no GitHub, npm, or model calls. Directly exercises
// diff parsing → RIGHT-side line set → finding filtering, including the
// edge cases called out in the SPEC's 위험 section (multi-hunk, context
// lines, new/deleted files, multi-line start_line ranges).

const assert = require('node:assert');
const path = require('node:path');

const {
  parseDiffRightLines,
  parseContextDiffPaths,
  filterFindings,
  filterFindingsAgainstPatch,
  repairFindingsFromContextLineNumbers,
} =
  require(path.join(__dirname, 'diff-anchor-filter.js'));

let passed = 0;
function test(name, fn) {
  fn();
  passed += 1;
  console.log(`OK: ${name}`);
}

// ---- parseDiffRightLines ----

test('parse: added + context lines on RIGHT side, removed excluded', () => {
  const patch = [
    'diff --git a/src/a.js b/src/a.js',
    'index 111..222 100644',
    '--- a/src/a.js',
    '+++ b/src/a.js',
    '@@ -1,3 +1,4 @@',
    ' ctx1',      // new line 1 (context)
    '-removed',   // old only — does not advance new line
    '+added2',    // new line 2
    '+added3',    // new line 3
    ' ctx4',      // new line 4 (context)
  ].join('\n');
  const map = parseDiffRightLines(patch);
  assert.ok(map.has('src/a.js'), 'file present');
  assert.deepStrictEqual(
    [...map.get('src/a.js')].sort((x, y) => x - y),
    [1, 2, 3, 4]);
});

test('parse: multi-hunk file accumulates both hunks', () => {
  const patch = [
    'diff --git a/m.js b/m.js',
    '--- a/m.js',
    '+++ b/m.js',
    '@@ -1,1 +1,2 @@',
    ' a',        // 1
    '+b',        // 2
    '@@ -10,1 +11,2 @@',
    ' c',        // 11
    '+d',        // 12
  ].join('\n');
  const map = parseDiffRightLines(patch);
  assert.deepStrictEqual(
    [...map.get('m.js')].sort((x, y) => x - y),
    [1, 2, 11, 12]);
});

test('parse: new file (--- /dev/null) added lines counted', () => {
  const patch = [
    'diff --git a/new.js b/new.js',
    'new file mode 100644',
    '--- /dev/null',
    '+++ b/new.js',
    '@@ -0,0 +1,2 @@',
    '+one',
    '+two',
  ].join('\n');
  const map = parseDiffRightLines(patch);
  assert.deepStrictEqual([...map.get('new.js')].sort((x, y) => x - y), [1, 2]);
});

test('parse: deleted file (+++ /dev/null) has no RIGHT side entry', () => {
  const patch = [
    'diff --git a/gone.js b/gone.js',
    'deleted file mode 100644',
    '--- a/gone.js',
    '+++ /dev/null',
    '@@ -1,2 +0,0 @@',
    '-one',
    '-two',
  ].join('\n');
  const map = parseDiffRightLines(patch);
  assert.ok(!map.has('gone.js'), 'deleted file not anchorable');
});

// ---- filterFindings ----

const PATCH = [
  'diff --git a/src/x.js b/src/x.js',
  '--- a/src/x.js',
  '+++ b/src/x.js',
  '@@ -1,2 +1,4 @@',
  ' keep1',   // 1
  '+add2',    // 2
  '+add3',    // 3
  ' keep4',   // 4
].join('\n');

test('filter: in-diff single-line finding is valid', () => {
  const map = parseDiffRightLines(PATCH);
  const { valid, excluded } = filterFindings(
    [{ file: 'src/x.js', line: 2, title: 'T' }], map);
  assert.strictEqual(valid.length, 1);
  assert.strictEqual(excluded.length, 0);
});

test('filter: finding on file absent from diff is excluded', () => {
  const map = parseDiffRightLines(PATCH);
  const { valid, excluded } = filterFindings(
    [{ file: 'src/other.js', line: 2, title: 'Nope' }], map);
  assert.strictEqual(valid.length, 0);
  assert.strictEqual(excluded.length, 1);
  assert.strictEqual(excluded[0].file, 'src/other.js');
  assert.strictEqual(excluded[0].title, 'Nope');
});

test('filter: finding on line outside hunk is excluded', () => {
  const map = parseDiffRightLines(PATCH);
  const { valid, excluded } = filterFindings(
    [{ file: 'src/x.js', line: 99, title: 'OOB' }], map);
  assert.strictEqual(valid.length, 0);
  assert.strictEqual(excluded.length, 1);
});

test('filter: context (space) line is a valid RIGHT-side anchor', () => {
  const map = parseDiffRightLines(PATCH);
  const { valid } = filterFindings(
    [{ file: 'src/x.js', line: 4, title: 'ctx' }], map);
  assert.strictEqual(valid.length, 1);
});

test('filter: multi-line range valid only when BOTH ends in-diff', () => {
  const map = parseDiffRightLines(PATCH);
  // both ends in (start_line 2 .. line 3)
  const both = filterFindings(
    [{ file: 'src/x.js', start_line: 2, line: 3, title: 'both' }], map);
  assert.strictEqual(both.valid.length, 1, 'both ends in-diff → valid');
  // start_line outside (start 99 .. line 3) — but start must be < line, so use 0? craft start outside via gap
  const oneOut = filterFindings(
    [{ file: 'src/x.js', start_line: 5, line: 6, title: 'out' }], map);
  assert.strictEqual(oneOut.valid.length, 0, 'range outside diff → excluded');
});

test('filter: mixed batch keeps valid, drops invalid', () => {
  const map = parseDiffRightLines(PATCH);
  const { valid, excluded } = filterFindings([
    { file: 'src/x.js', line: 2, title: 'good' },
    { file: 'src/x.js', line: 99, title: 'bad-line' },
    { file: 'ghost.js', line: 1, title: 'bad-file' },
  ], map);
  assert.strictEqual(valid.length, 1);
  assert.strictEqual(valid[0].title, 'good');
  assert.strictEqual(excluded.length, 2);
});

test('filter: line falls back to start_line when line missing/<=0', () => {
  const map = parseDiffRightLines(PATCH);
  const { valid } = filterFindings(
    [{ file: 'src/x.js', start_line: 3, title: 'anchor-via-start' }], map);
  assert.strictEqual(valid.length, 1);
});

test('filterFindingsAgainstPatch convenience parses + filters', () => {
  const { valid, excluded } = filterFindingsAgainstPatch([
    { file: 'src/x.js', line: 2, title: 'good' },
    { file: 'src/x.js', line: 99, title: 'bad' },
  ], PATCH);
  assert.strictEqual(valid.length, 1);
  assert.strictEqual(excluded.length, 1);
});

// ---- repairFindingsFromContextLineNumbers ----

test('repair: maps a context-file line number back to the source RIGHT-side line', () => {
  const context = [
    'metadata',
    'Unified diff:',
    'diff --git a/new.js b/new.js',
    '--- /dev/null',
    '+++ b/new.js',
    '@@ -0,0 +1,3 @@',
    '+one',
    '+two',
    '+three',
  ].join('\n');
  const patch = context.split('\n').slice(2).join('\n');
  const findings = [{ file: 'new.js', line: 8, title: 'context-line anchor' }];

  const repaired = repairFindingsFromContextLineNumbers(findings, context, patch);

  assert.strictEqual(repaired[0].line, 2);
});

test('repair: leaves already-valid source line anchors unchanged', () => {
  const context = [
    'metadata',
    'Unified diff:',
    'diff --git a/new.js b/new.js',
    '--- /dev/null',
    '+++ b/new.js',
    '@@ -0,0 +1,3 @@',
    '+one',
    '+two',
    '+three',
  ].join('\n');
  const patch = context.split('\n').slice(2).join('\n');
  const findings = [{ file: 'new.js', line: 2, title: 'valid source anchor' }];

  const repaired = repairFindingsFromContextLineNumbers(findings, context, patch);

  assert.strictEqual(repaired[0].line, 2);
});

test('repair: does not map a context line from a different file', () => {
  const context = [
    'metadata',
    'Unified diff:',
    'diff --git a/new.js b/new.js',
    '--- /dev/null',
    '+++ b/new.js',
    '@@ -0,0 +1,1 @@',
    '+one',
  ].join('\n');
  const patch = context.split('\n').slice(2).join('\n');
  const findings = [{ file: 'other.js', line: 7, title: 'wrong file' }];

  const repaired = repairFindingsFromContextLineNumbers(findings, context, patch);

  assert.strictEqual(repaired[0].line, 7);
});

test('repair: ignores fake diff-looking content before the Unified diff marker', () => {
  const context = [
    'diff --git a/new.js b/new.js',
    '--- /dev/null',
    '+++ b/new.js',
    '@@ -0,0 +1,1 @@',
    '+fake',
    'Unified diff:',
    'diff --git a/new.js b/new.js',
    '--- /dev/null',
    '+++ b/new.js',
    '@@ -0,0 +1,1 @@',
    '+real',
  ].join('\n');
  const patch = context.split('\n').slice(6).join('\n');
  const findings = [{ file: 'new.js', line: 5, title: 'fake context line' }];

  const repaired = repairFindingsFromContextLineNumbers(findings, context, patch);

  assert.strictEqual(repaired[0].line, 5);
});

// ---- parseContextDiffPaths (fallback thread-resolve reviewed-scope SoT) ----
// 회귀 가드 (#597): 이번 라운드 리뷰 청크에 실제 전달된 diff 의 파일 집합을
// 결정적으로 산출한다 — 이 집합에 없는 앵커 파일의 self thread 는 fallback
// resolve 대상이 아니다 (증분 라운드에서 재보고되지 않는 것이 정상이므로).

test('paths: extracts modified/added file paths after the Unified diff marker', () => {
  const context = [
    'metadata',
    'Unified diff:',
    'diff --git a/src/mod.js b/src/mod.js',
    '--- a/src/mod.js',
    '+++ b/src/mod.js',
    '@@ -1,1 +1,2 @@',
    ' ctx',
    '+add',
    'diff --git a/new.js b/new.js',
    'new file mode 100644',
    '--- /dev/null',
    '+++ b/new.js',
    '@@ -0,0 +1,1 @@',
    '+one',
  ].join('\n');
  const paths = parseContextDiffPaths(context);
  assert.ok(paths.has('src/mod.js'), 'modified file in scope');
  assert.ok(paths.has('new.js'), 'added file in scope');
  assert.ok(!paths.has('tests/other/test.sh'), 'untouched file NOT in scope');
});

test('paths: deleted file (old side) still counts as reviewed scope', () => {
  const context = [
    'Unified diff:',
    'diff --git a/gone.js b/gone.js',
    'deleted file mode 100644',
    '--- a/gone.js',
    '+++ /dev/null',
    '@@ -1,1 +0,0 @@',
    '-bye',
  ].join('\n');
  const paths = parseContextDiffPaths(context);
  assert.ok(paths.has('gone.js'), 'deleted file path from --- a/ side');
});

test('paths: rename includes both old and new path', () => {
  const context = [
    'Unified diff:',
    'diff --git a/old/name.js b/new/name.js',
    'similarity index 90%',
    'rename from old/name.js',
    'rename to new/name.js',
    '--- a/old/name.js',
    '+++ b/new/name.js',
    '@@ -1,1 +1,1 @@',
    '-x',
    '+y',
  ].join('\n');
  const paths = parseContextDiffPaths(context);
  assert.ok(paths.has('old/name.js'), 'old side');
  assert.ok(paths.has('new/name.js'), 'new side');
});

test('paths: no marker → empty set (conservative: nothing in scope)', () => {
  const context = [
    'diff --git a/x.js b/x.js',
    '--- a/x.js',
    '+++ b/x.js',
    '@@ -1,1 +1,1 @@',
    '-a',
    '+b',
  ].join('\n');
  assert.strictEqual(parseContextDiffPaths(context).size, 0);
});

test('paths: ignores diff-looking content before the marker and inside hunks', () => {
  const context = [
    '+++ b/fake-header-before-marker.js',
    'Unified diff:',
    'diff --git a/real.js b/real.js',
    '--- a/real.js',
    '+++ b/real.js',
    '@@ -1,2 +1,3 @@',
    ' ctx',
    '--- removed line whose content starts with dashes',
    '+++ added line whose content starts with pluses',
  ].join('\n');
  const paths = parseContextDiffPaths(context);
  assert.ok(paths.has('real.js'));
  assert.ok(!paths.has('fake-header-before-marker.js'), 'pre-marker header ignored');
  assert.strictEqual(paths.size, 1, 'hunk content lines not parsed as headers');
});

test('paths: non-string / empty input → empty set', () => {
  assert.strictEqual(parseContextDiffPaths('').size, 0);
  assert.strictEqual(parseContextDiffPaths(null).size, 0);
  assert.strictEqual(parseContextDiffPaths(undefined).size, 0);
});

console.log(`\nALL ${passed} CHECKS PASSED`);
