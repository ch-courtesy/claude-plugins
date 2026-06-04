'use strict';

// Shared token-budget chunking module for the codex / claude PR review
// workflows (Phase 4: Token Optimized Review).
//
// When a PR diff is large enough that feeding it to the review model in one
// shot would exceed the input budget, the review must instead split the
// changed files into token-bounded chunks, review each chunk independently,
// and merge the per-chunk findings into a single review submission. Files with
// little review value (docs, lockfiles, generated artifacts) are dropped first
// when the total estimated input would exceed the overall budget.
//
// This is the SINGLE shared definition of that logic: both workflows `require`
// it from their github-script inline steps (same pattern as
// diff-anchor-filter.js) so their behaviour stays symmetric — no inline copy
// of the chunking / classification / merge logic exists in either workflow.
//
// CommonJS, pure functions, no I/O or network: everything operates on the diff
// text and finding objects the workflow already has in hand. The only host API
// used is node's crypto for the finding fingerprint, which is intentionally
// byte-identical with the inline fingerprint the workflows already compute.

const crypto = require('crypto');

// SPEC 권장 기본값(상수). 토큰 추정은 chars/4 휴리스틱(셸/Actions 런타임에
// 토크나이저가 없음). 이 값들은 권장 기본값으로, 호출부가 opts 로 덮어쓸 수 있다.
const LIMITS = Object.freeze({
  maxTotalInput: 250000,            // 총 입력 예산(이 위에서 저우선 파일 강등)
  maxDiffBeforeChunking: 80000,     // 이 위에서 청크링 발동(청크당 임계)
  maxSingleFileContent: 30000,      // 단독 임계 초과 파일 truncate 한도
  maxRelatedFilesPerChangedFile: 5, // needs_context follow-up 요청 파일 상한
  maxUnchangedContextExpansionDepth: 2,
  maxOutputTokens: 16000,
});

// 추정 입력 토큰 = 문자수 / 4 (올림). 토크나이저 부재 휴리스틱.
function estimateTokens(text) {
  if (typeof text !== 'string' || text.length === 0) return 0;
  return Math.ceil(text.length / 4);
}

// 저우선 파일 분류. 'low' | 'normal'.
//  - 문서 전용: *.md, docs/** (디렉터리 어디에 있든)
//  - lockfile 전용: 알려진 lockfile 파일명
//  - 생성물 전용: *.min.js, dist/**, 그리고 호출부가 .gitattributes 의
//    linguist-generated 로 식별해 넘긴 generatedPaths 집합
function classifyFilePriority(filePath, generatedPaths) {
  const p = String(filePath || '');
  if (generatedPaths && typeof generatedPaths.has === 'function'
      && generatedPaths.has(p)) {
    return 'low';
  }
  const base = p.split('/').pop();

  // 문서 전용
  if (/\.md$/i.test(p)) return 'low';
  if (p === 'docs' || p.startsWith('docs/')) return 'low';

  // lockfile 전용
  const LOCKFILES = new Set([
    'package-lock.json', 'npm-shrinkwrap.json', 'yarn.lock', 'pnpm-lock.yaml',
    'Cargo.lock', 'poetry.lock', 'Pipfile.lock', 'go.sum', 'composer.lock',
    'Gemfile.lock',
  ]);
  if (LOCKFILES.has(base)) return 'low';

  // 생성물 전용
  if (/\.min\.(js|css)$/i.test(p)) return 'low';
  if (p === 'dist' || p.startsWith('dist/')) return 'low';

  return 'normal';
}

// 총 추정 입력이 예산을 넘으면 저우선(low) 파일을 입력 순서대로(저우선만)
// 예산 이하가 될 때까지 제외한다. normal 파일은 절대 제외하지 않는다
// (그 크기는 청크링이 처리). 예산 이하인 동안에는 저우선도 포함한다.
// files: [{ path, tokens, priority? }]. 반환: { included, excluded }.
function selectFilesWithinBudget(files, opts) {
  const list = Array.isArray(files) ? files : [];
  const maxTotalInput = (opts && opts.maxTotalInput) || LIMITS.maxTotalInput;
  const generatedPaths = opts && opts.generatedPaths;

  const withPriority = list.map((f) => ({
    ...f,
    priority: f.priority || classifyFilePriority(f.path, generatedPaths),
  }));

  let total = withPriority.reduce((s, f) => s + (f.tokens || 0), 0);
  if (total <= maxTotalInput) {
    return { included: withPriority, excluded: [] };
  }

  // 예산 초과 → 저우선 파일을 (입력 순서대로) 하나씩 떨어뜨린다.
  const included = withPriority.slice();
  const excluded = [];
  for (let i = 0; i < included.length && total > maxTotalInput; ) {
    if (included[i].priority === 'low') {
      total -= included[i].tokens || 0;
      excluded.push(included[i]);
      included.splice(i, 1);
    } else {
      i += 1;
    }
  }
  return { included, excluded };
}

// 변경 파일을 추정 토큰 기준 greedy 묶기로 청크화. 각 청크의 합산 토큰이
// maxChunkTokens 이하가 되도록 입력 순서대로 채운다. 단일 파일이 단독으로
// maxChunkTokens 를 넘으면 자체 청크에 두되 maxSingleFileContent 한도로
// truncate 하고 truncated 플래그를 세운다.
// files: [{ path, tokens }]. 반환: [{ files:[{path,tokens,truncated}], tokens, truncated }].
function groupIntoChunks(files, opts) {
  const list = Array.isArray(files) ? files : [];
  const maxChunkTokens = (opts && opts.maxChunkTokens) || LIMITS.maxDiffBeforeChunking;
  const maxSingleFileContent = (opts && opts.maxSingleFileContent) || LIMITS.maxSingleFileContent;

  const chunks = [];
  let current = { files: [], tokens: 0, truncated: false };
  const flush = () => {
    if (current.files.length > 0) chunks.push(current);
    current = { files: [], tokens: 0, truncated: false };
  };

  for (const f of list) {
    const tokens = f.tokens || 0;
    if (tokens > maxChunkTokens) {
      // 진행 중 청크를 먼저 닫고, 초과 파일을 단독 청크로(truncate).
      flush();
      const capped = Math.min(tokens, maxSingleFileContent);
      chunks.push({
        files: [{ ...f, tokens: capped, truncated: true }],
        tokens: capped,
        truncated: true,
      });
      continue;
    }
    if (current.files.length > 0 && current.tokens + tokens > maxChunkTokens) {
      flush();
    }
    current.files.push({ ...f, truncated: false });
    current.tokens += tokens;
  }
  flush();
  return chunks;
}

// 결정적 finding fingerprint 정규화 — 두 워크플로의 인라인 구현과
// byte-identical 해야 한다(정의 표류 방지). file·review_perspective·정규화
// 제목만으로 산출하며 line/start_line 은 의도적으로 제외한다.
function normalizeTitle(s) {
  return String(s == null ? '' : s)
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}

function computeFingerprint(f) {
  return crypto
    .createHash('sha256')
    .update([f.file || '', f.review_perspective || '', normalizeTitle(f.title)].join(' '))
    .digest('hex')
    .slice(0, 16);
}

// 청크별로 흩어진 findings 를 fingerprint 기준으로 중복 제거·병합한다.
// 첫 등장이 우선(나중 청크의 동일 fingerprint 는 버린다). 입력은 청크별
// findings 배열들의 배열. keyFn 으로 fingerprint 함수를 주입할 수 있다.
function mergeFindings(findingsArrays, keyFn) {
  const key = keyFn || computeFingerprint;
  const seen = new Set();
  const merged = [];
  for (const arr of findingsArrays || []) {
    for (const f of arr || []) {
      const fp = key(f);
      if (seen.has(fp)) continue;
      seen.add(fp);
      merged.push(f);
    }
  }
  return merged;
}

// 통합(unified) diff 텍스트를 파일 단위 세그먼트로 분할한다. 각 세그먼트는
// 한 파일의 `diff --git ...` 헤더부터 다음 파일 헤더 직전까지를 그대로 보존하며
// (모델에 그대로 다시 먹일 수 있도록), 파일 경로와 추정 토큰을 함께 돌려준다.
// 경로는 `+++ b/<path>` 우선, 없으면(삭제 파일) `--- a/<path>`, 그것도 없으면
// `diff --git a/<path> b/<path>` 헤더에서 도출한다. diff 가 비면 빈 배열.
// 반환: [{ path, segment, tokens }] (입력 파일 순서 보존).
function splitUnifiedDiffByFile(diffText) {
  const text = typeof diffText === 'string' ? diffText : '';
  if (text.length === 0) return [];
  const lines = text.split('\n');
  const segments = [];
  let cur = null;
  const pushCur = () => {
    if (!cur) return;
    const segment = cur.lines.join('\n');
    segments.push({ path: cur.path, segment, tokens: estimateTokens(segment) });
  };
  const pathFromGitHeader = (line) => {
    // diff --git a/<p> b/<p>
    const m = line.match(/^diff --git a\/(.+?) b\/(.+)$/);
    return m ? m[2] : '';
  };
  for (const line of lines) {
    if (line.startsWith('diff --git ')) {
      pushCur();
      cur = { path: pathFromGitHeader(line), lines: [line] };
      continue;
    }
    if (!cur) continue; // preamble before first file header — ignore
    cur.lines.push(line);
    if (line.startsWith('+++ ')) {
      const m = line.match(/^\+\+\+ b\/(.*)$/);
      if (m && m[1] && m[1] !== '/dev/null') cur.path = m[1];
    } else if (line.startsWith('--- ') && !cur.path) {
      const m = line.match(/^--- a\/(.*)$/);
      if (m && m[1] && m[1] !== '/dev/null') cur.path = m[1];
    }
  }
  pushCur();
  return segments;
}

// 청크 임계 초과 여부. estimatedDiffTokens 가 maxDiffBeforeChunking 를
// 초과할 때만 청크링을 발동(이하면 기존 단일 패스 유지 — 회귀 없음).
function needsChunking(estimatedDiffTokens, opts) {
  const threshold = (opts && opts.maxDiffBeforeChunking) || LIMITS.maxDiffBeforeChunking;
  return (estimatedDiffTokens || 0) > threshold;
}

// 리뷰 이벤트 결정(전 청크 합산): 모든 청크 verdict 가 approve 이고, 병합된
// findings 가 비어 있고, may_approve=true 이며, 어떤 청크도 truncate 되지
// 않았고, 청크가 하나 이상일 때만 APPROVE. 그 외 COMMENT.
function decideReviewEvent({ chunkVerdicts, mergedFindingsCount, mayApprove, anyTruncated }) {
  const verdicts = Array.isArray(chunkVerdicts) ? chunkVerdicts : [];
  if (verdicts.length === 0) return 'COMMENT';
  const allApprove = verdicts.every((v) => v === 'approve');
  if (allApprove && mergedFindingsCount === 0 && !!mayApprove && !anyTruncated) {
    return 'APPROVE';
  }
  return 'COMMENT';
}

module.exports = {
  LIMITS,
  estimateTokens,
  classifyFilePriority,
  selectFilesWithinBudget,
  groupIntoChunks,
  normalizeTitle,
  computeFingerprint,
  mergeFindings,
  splitUnifiedDiffByFile,
  needsChunking,
  decideReviewEvent,
};
