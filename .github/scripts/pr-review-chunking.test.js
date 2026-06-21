#!/usr/bin/env node
'use strict';

// Unit test for the shared token-budget chunking module used by the codex /
// claude PR review workflows (Phase 4 Token Optimized Review).
// Static, hermetic: no GitHub, npm, or model calls. Exercises token estimation,
// low-priority file classification, budget-based file selection, greedy chunk
// grouping (incl. single-file-over-threshold truncation), fingerprint-based
// partial findings merge, and the cross-chunk review-event decision.

const assert = require('node:assert');
const path = require('node:path');
const crypto = require('node:crypto');

const M = require(path.join(__dirname, 'pr-review-chunking.js'));

let passed = 0;
function test(name, fn) {
  fn();
  passed += 1;
  console.log(`OK: ${name}`);
}

// ---- LIMITS constants (SPEC 권장 기본값) ----

test('LIMITS exposes the SPEC recommended defaults', () => {
  assert.strictEqual(M.LIMITS.maxTotalInput, 250000);
  assert.strictEqual(M.LIMITS.maxDiffBeforeChunking, 80000);
  assert.strictEqual(M.LIMITS.maxSingleFileContent, 30000);
  assert.strictEqual(M.LIMITS.maxRelatedFilesPerChangedFile, 5);
  assert.strictEqual(M.LIMITS.maxUnchangedContextExpansionDepth, 2);
  assert.strictEqual(M.LIMITS.maxOutputTokens, 16000);
});

// ---- estimateTokens (chars / 4 heuristic) ----

test('estimateTokens uses chars/4 heuristic, ceil', () => {
  assert.strictEqual(M.estimateTokens(''), 0);
  assert.strictEqual(M.estimateTokens('abcd'), 1);
  assert.strictEqual(M.estimateTokens('abcde'), 2); // ceil(5/4)
  assert.strictEqual(M.estimateTokens('a'.repeat(400)), 100);
});

test('estimateTokens tolerates non-string', () => {
  assert.strictEqual(M.estimateTokens(null), 0);
  assert.strictEqual(M.estimateTokens(undefined), 0);
});

// ---- classifyFilePriority ----

test('classify: doc-only is low priority', () => {
  assert.strictEqual(M.classifyFilePriority('README.md'), 'low');
  assert.strictEqual(M.classifyFilePriority('docs/codex/pr-review-workflow.md'), 'low');
  assert.strictEqual(M.classifyFilePriority('docs/anything.txt'), 'low');
});

test('classify: lockfiles are low priority', () => {
  for (const p of ['package-lock.json', 'yarn.lock', 'pnpm-lock.yaml',
    'Cargo.lock', 'poetry.lock', 'go.sum', 'composer.lock',
    'sub/dir/package-lock.json']) {
    assert.strictEqual(M.classifyFilePriority(p), 'low', p);
  }
});

test('classify: generated artifacts are low priority', () => {
  assert.strictEqual(M.classifyFilePriority('app.min.js'), 'low');
  assert.strictEqual(M.classifyFilePriority('dist/bundle.js'), 'low');
  assert.strictEqual(M.classifyFilePriority('dist/nested/x.css'), 'low');
});

test('classify: source files are normal priority', () => {
  assert.strictEqual(M.classifyFilePriority('src/index.js'), 'normal');
  assert.strictEqual(M.classifyFilePriority('.github/scripts/diff-anchor-filter.js'), 'normal');
  assert.strictEqual(M.classifyFilePriority('lib/foo.ts'), 'normal');
});

test('classify: explicit linguist-generated set marks file low', () => {
  const gen = new Set(['vendor/big.js']);
  assert.strictEqual(M.classifyFilePriority('vendor/big.js', gen), 'low');
  assert.strictEqual(M.classifyFilePriority('vendor/other.js', gen), 'normal');
});

// ---- selectFilesWithinBudget ----

test('select: under budget keeps everything incl. low-priority', () => {
  const files = [
    { path: 'src/a.js', tokens: 100 },
    { path: 'README.md', tokens: 50 },
  ];
  const { included, excluded } = M.selectFilesWithinBudget(files, { maxTotalInput: 1000 });
  assert.strictEqual(included.length, 2);
  assert.strictEqual(excluded.length, 0);
});

test('select: over budget drops low-priority first, logs excluded', () => {
  const files = [
    { path: 'src/a.js', tokens: 600 },
    { path: 'docs/big.md', tokens: 600 },
  ];
  const { included, excluded } = M.selectFilesWithinBudget(files, { maxTotalInput: 1000 });
  assert.deepStrictEqual(included.map((f) => f.path), ['src/a.js']);
  assert.deepStrictEqual(excluded.map((f) => f.path), ['docs/big.md']);
});

test('select: never drops normal-priority files even if still over budget', () => {
  const files = [
    { path: 'src/a.js', tokens: 800 },
    { path: 'src/b.js', tokens: 800 },
  ];
  const { included, excluded } = M.selectFilesWithinBudget(files, { maxTotalInput: 1000 });
  assert.strictEqual(included.length, 2);
  assert.strictEqual(excluded.length, 0);
});

test('select: PR of only low-priority files still classifies (all dropped if over)', () => {
  const files = [
    { path: 'docs/a.md', tokens: 700 },
    { path: 'docs/b.md', tokens: 700 },
  ];
  const { included, excluded } = M.selectFilesWithinBudget(files, { maxTotalInput: 1000 });
  // dropping low until under budget: drop one (700 left <= 1000) → keep one
  assert.strictEqual(included.length + excluded.length, 2);
  assert.ok(excluded.length >= 1, 'at least one low file dropped when over budget');
});

// ---- groupIntoChunks ----

test('chunk: under threshold yields a single chunk (no chunking regression)', () => {
  const files = [
    { path: 'a.js', tokens: 100 },
    { path: 'b.js', tokens: 100 },
  ];
  const chunks = M.groupIntoChunks(files, { maxChunkTokens: 80000 });
  assert.strictEqual(chunks.length, 1);
  assert.strictEqual(chunks[0].tokens, 200);
  assert.strictEqual(chunks[0].truncated, false);
});

test('chunk: greedy splits when adding would exceed threshold', () => {
  const files = [
    { path: 'a.js', tokens: 60 },
    { path: 'b.js', tokens: 60 },
    { path: 'c.js', tokens: 30 },
  ];
  const chunks = M.groupIntoChunks(files, { maxChunkTokens: 100 });
  assert.strictEqual(chunks.length, 2);
  assert.deepStrictEqual(chunks[0].files.map((f) => f.path), ['a.js']);
  assert.deepStrictEqual(chunks[1].files.map((f) => f.path), ['b.js', 'c.js']);
  for (const c of chunks) assert.ok(c.tokens <= 100, 'each chunk under threshold');
});

test('chunk: single file over threshold gets own chunk, truncated to maxSingleFileContent', () => {
  const files = [{ path: 'huge.js', tokens: 200000 }];
  const chunks = M.groupIntoChunks(files, {
    maxChunkTokens: 80000, maxSingleFileContent: 30000,
  });
  assert.strictEqual(chunks.length, 1);
  assert.strictEqual(chunks[0].truncated, true);
  assert.strictEqual(chunks[0].files[0].truncated, true);
  assert.strictEqual(chunks[0].tokens, 30000);
});

test('chunk: oversize file flushes the in-progress chunk first', () => {
  const files = [
    { path: 'a.js', tokens: 100 },
    { path: 'huge.js', tokens: 200000 },
    { path: 'b.js', tokens: 100 },
  ];
  const chunks = M.groupIntoChunks(files, {
    maxChunkTokens: 80000, maxSingleFileContent: 30000,
  });
  assert.strictEqual(chunks.length, 3);
  assert.deepStrictEqual(chunks[0].files.map((f) => f.path), ['a.js']);
  assert.strictEqual(chunks[1].truncated, true);
  assert.deepStrictEqual(chunks[2].files.map((f) => f.path), ['b.js']);
});

// ---- fingerprint (byte-identical with the workflow inline impl) ----

test('normalizeTitle matches the workflow normalization', () => {
  // Replicates the exact inline algorithm currently in both workflows.
  const ref = (s) => String(s == null ? '' : s)
    .normalize('NFKC').toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  for (const s of ['Hello,  World!!', '  Tabs\tand   spaces ', 'Ａｐｐｌｅ', null, '한글 제목 (테스트)']) {
    assert.strictEqual(M.normalizeTitle(s), ref(s), JSON.stringify(s));
  }
});

test('computeFingerprint matches the workflow fingerprint byte-for-byte', () => {
  const ref = (f) => crypto.createHash('sha256')
    .update([f.file || '', f.review_perspective || '',
      String(f.title == null ? '' : f.title).normalize('NFKC').toLowerCase()
        .replace(/[^\p{L}\p{N}]+/gu, ' ').trim()].join(' '))
    .digest('hex').slice(0, 16);
  const f = { file: 'src/x.js', review_perspective: 'security', title: 'SQL Injection!' };
  assert.strictEqual(M.computeFingerprint(f), ref(f));
  assert.strictEqual(M.computeFingerprint(f).length, 16);
});

// ---- mergeFindings ----

test('merge: dedups across chunks by fingerprint, first occurrence wins', () => {
  const a = { file: 'src/x.js', review_perspective: 'sec', title: 'Bug A', body: 'first' };
  const aDup = { file: 'src/x.js', review_perspective: 'sec', title: 'bug   a', body: 'second' };
  const b = { file: 'src/y.js', review_perspective: 'perf', title: 'Bug B' };
  const merged = M.mergeFindings([[a, b], [aDup]]);
  assert.strictEqual(merged.length, 2, 'A and B only; aDup is the same fingerprint as A');
  assert.strictEqual(merged[0].body, 'first', 'first occurrence kept');
});

test('merge: empty chunks yield empty merged findings', () => {
  assert.deepStrictEqual(M.mergeFindings([[], []]), []);
  assert.deepStrictEqual(M.mergeFindings([]), []);
});

// ---- decideReviewEvent ----

test('decide: APPROVE only when all approve, no findings, may_approve, no truncation', () => {
  assert.strictEqual(M.decideReviewEvent({
    chunkVerdicts: ['approve', 'approve'], mergedFindingsCount: 0,
    mayApprove: true, anyTruncated: false,
  }), 'APPROVE');
});

// #451: 모델이 0 findings 에서도 comment verdict 를 반환하는 비일관성 흡수 — comment 도 APPROVE.
test('decide: APPROVE when a chunk verdict is comment but no findings (#451)', () => {
  assert.strictEqual(M.decideReviewEvent({
    chunkVerdicts: ['approve', 'comment'], mergedFindingsCount: 0,
    mayApprove: true, anyTruncated: false,
  }), 'APPROVE');
});

test('decide: COMMENT when a chunk verdict is request_changes/needs_context (불완전·차단)', () => {
  assert.strictEqual(M.decideReviewEvent({
    chunkVerdicts: ['approve', 'request_changes'], mergedFindingsCount: 0,
    mayApprove: true, anyTruncated: false,
  }), 'COMMENT');
  assert.strictEqual(M.decideReviewEvent({
    chunkVerdicts: ['comment', 'needs_context'], mergedFindingsCount: 0,
    mayApprove: true, anyTruncated: false,
  }), 'COMMENT');
});

test('decide: COMMENT when merged findings remain', () => {
  assert.strictEqual(M.decideReviewEvent({
    chunkVerdicts: ['approve'], mergedFindingsCount: 1,
    mayApprove: true, anyTruncated: false,
  }), 'COMMENT');
});

test('decide: COMMENT when may_approve false', () => {
  assert.strictEqual(M.decideReviewEvent({
    chunkVerdicts: ['approve'], mergedFindingsCount: 0,
    mayApprove: false, anyTruncated: false,
  }), 'COMMENT');
});

test('decide: COMMENT when any chunk was truncated', () => {
  assert.strictEqual(M.decideReviewEvent({
    chunkVerdicts: ['approve'], mergedFindingsCount: 0,
    mayApprove: true, anyTruncated: true,
  }), 'COMMENT');
});

test('decide: COMMENT when there are no chunks at all', () => {
  assert.strictEqual(M.decideReviewEvent({
    chunkVerdicts: [], mergedFindingsCount: 0,
    mayApprove: true, anyTruncated: false,
  }), 'COMMENT');
});

// ---- needsChunking ----

test('needsChunking: true only above the chunk threshold', () => {
  assert.strictEqual(M.needsChunking(80001, { maxDiffBeforeChunking: 80000 }), true);
  assert.strictEqual(M.needsChunking(80000, { maxDiffBeforeChunking: 80000 }), false);
  assert.strictEqual(M.needsChunking(1, { maxDiffBeforeChunking: 80000 }), false);
});

// ---- splitUnifiedDiffByFile ----

const SAMPLE_DIFF = [
  'diff --git a/src/a.js b/src/a.js',
  'index 111..222 100644',
  '--- a/src/a.js',
  '+++ b/src/a.js',
  '@@ -1,2 +1,3 @@',
  ' ctx',
  '+added line',
  ' ctx2',
  'diff --git a/docs/readme.md b/docs/readme.md',
  'index 333..444 100644',
  '--- a/docs/readme.md',
  '+++ b/docs/readme.md',
  '@@ -1 +1 @@',
  '-old',
  '+new',
].join('\n');

test('split: separates a unified diff into per-file segments with paths', () => {
  const segs = M.splitUnifiedDiffByFile(SAMPLE_DIFF);
  assert.strictEqual(segs.length, 2);
  assert.deepStrictEqual(segs.map((s) => s.path), ['src/a.js', 'docs/readme.md']);
  // each segment starts at its own `diff --git` header and is self-contained
  assert.ok(segs[0].segment.startsWith('diff --git a/src/a.js'));
  assert.ok(segs[0].segment.includes('+added line'));
  assert.ok(!segs[0].segment.includes('docs/readme.md'), 'segment 0 does not bleed into file 2');
  assert.ok(segs[1].segment.startsWith('diff --git a/docs/readme.md'));
});

test('split: reports estimated tokens per segment (chars/4)', () => {
  const segs = M.splitUnifiedDiffByFile(SAMPLE_DIFF);
  for (const s of segs) {
    assert.strictEqual(s.tokens, M.estimateTokens(s.segment));
    assert.ok(s.tokens > 0);
  }
});

test('split: derives path of a deleted file from the --- a/ header', () => {
  const del = [
    'diff --git a/gone.js b/gone.js',
    'deleted file mode 100644',
    '--- a/gone.js',
    '+++ /dev/null',
    '@@ -1 +0,0 @@',
    '-x',
  ].join('\n');
  const segs = M.splitUnifiedDiffByFile(del);
  assert.strictEqual(segs.length, 1);
  assert.strictEqual(segs[0].path, 'gone.js');
});

test('split: empty / whitespace diff yields no segments', () => {
  assert.deepStrictEqual(M.splitUnifiedDiffByFile(''), []);
  assert.deepStrictEqual(M.splitUnifiedDiffByFile(null), []);
  assert.deepStrictEqual(M.splitUnifiedDiffByFile('no headers here\njust text'), []);
});

test('split → chunk: segments feed straight into the budget/chunk pipeline', () => {
  const segs = M.splitUnifiedDiffByFile(SAMPLE_DIFF);
  const { included } = M.selectFilesWithinBudget(segs, { maxTotalInput: 1000000 });
  const chunks = M.groupIntoChunks(included, { maxChunkTokens: 1000000 });
  assert.strictEqual(chunks.length, 1, 'small diff stays a single chunk (no regression)');
  assert.deepStrictEqual(chunks[0].files.map((f) => f.path), ['src/a.js', 'docs/readme.md']);
});

console.log(`\nALL ${passed} CHECKS PASSED`);
