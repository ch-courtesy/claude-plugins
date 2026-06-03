'use strict';

// Shared diff-only anchor filter for the codex / claude PR review workflows.
//
// Both workflows post model findings as inline review comments. GitHub's
// createReview rejects (422 "Path could not be resolved") any inline comment
// anchored to a file/line that is not part of the PR diff's RIGHT side, and
// that rejection takes down the WHOLE review batch — valid findings included.
// This module is the single shared validation unit: it derives the set of
// anchorable RIGHT-side lines (added `+` and context ` ` lines) per file from
// the already-generated unified diff (.review-context/diff.patch) and filters
// findings so only in-diff anchors are submitted. Out-of-diff findings are
// returned separately so the caller can log and drop them.
//
// CommonJS so it can be `require`d from actions/github-script steps. No I/O,
// no network — pure functions over the patch text the workflow already has.

// Parse a unified diff into a map of file path → Set of RIGHT-side (new file)
// line numbers. RIGHT-side lines are added (`+`) and context (` `) lines —
// exactly the lines GitHub will resolve as inline-comment anchors on side RIGHT.
// Removed (`-`) lines do not exist on the RIGHT side and are not counted.
// Deleted files (+++ /dev/null) produce no entry.
function parseDiffRightLines(patch) {
  const map = new Map();
  if (typeof patch !== 'string' || patch.length === 0) return map;

  const lines = patch.split('\n');
  let currentFile = null; // null = no anchorable RIGHT side (e.g. deletion)
  let newLine = 0;
  let inHunk = false;

  const hunkRe = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/;

  for (const line of lines) {
    if (line.startsWith('diff --git ')) {
      currentFile = null;
      inHunk = false;
      continue;
    }
    if (line.startsWith('+++ ')) {
      currentFile = parseNewPath(line.slice(4));
      inHunk = false;
      if (currentFile !== null && !map.has(currentFile)) {
        map.set(currentFile, new Set());
      }
      continue;
    }
    if (line.startsWith('--- ')) {
      // Old-file header — ignored; RIGHT side comes from the +++ line.
      continue;
    }
    const hunk = line.match(hunkRe);
    if (hunk) {
      newLine = Number(hunk[1]);
      inHunk = true;
      continue;
    }
    if (!inHunk || currentFile === null) continue;

    const c = line[0];
    if (c === '+') {
      map.get(currentFile).add(newLine);
      newLine += 1;
    } else if (c === ' ') {
      map.get(currentFile).add(newLine);
      newLine += 1;
    } else if (c === '-') {
      // RIGHT side unaffected — do not advance new-file line counter.
    } else if (c === '\\') {
      // "\ No newline at end of file" — metadata, not a content line.
    } else {
      // Anything else ends the hunk body (blank trailer, next header handled
      // above). Stop counting until the next @@ / +++.
      inHunk = false;
    }
  }

  return map;
}

// Resolve the RIGHT-side file path from a `+++ ` header value (the part after
// "+++ "). Returns null for /dev/null (deleted file). Strips the conventional
// `b/` prefix and unwraps git's C-quoted paths for names with special chars.
function parseNewPath(raw) {
  let p = raw;
  // git may append a trailing tab + timestamp in some diff variants; cut it.
  const tab = p.indexOf('\t');
  if (tab !== -1) p = p.slice(0, tab);
  p = p.trim();
  if (p === '/dev/null') return null;
  if (p.length >= 2 && p.startsWith('"') && p.endsWith('"')) {
    // Minimal C-style unquote for git's quoted paths.
    try { p = JSON.parse(p); } catch { p = p.slice(1, -1); }
  }
  if (p.startsWith('b/')) p = p.slice(2);
  return p;
}

// Compute the anchor line(s) the workflow will submit for a finding, mirroring
// the inline-comment construction in the review workflows:
//   anchor = (line is a positive int) ? line : start_line
//   a multi-line range is emitted only when start_line is a positive int < anchor
// Returns { anchor, ends } where `ends` is the list of line numbers that must
// all resolve on the diff RIGHT side for the comment to be postable.
function findingAnchorEnds(f) {
  const line = (typeof f.line === 'number' && f.line > 0) ? f.line : f.start_line;
  const ends = [];
  if (typeof line === 'number' && line > 0) ends.push(line);
  if (typeof f.start_line === 'number'
      && f.start_line >= 1 && f.start_line < line) {
    ends.push(f.start_line);
  }
  return { anchor: line, ends };
}

// Filter findings against a precomputed RIGHT-side line map.
// Returns { valid, excluded }. A finding is valid only when its file is in the
// diff AND every anchor end (line, and start_line when it forms a range) is in
// that file's RIGHT-side line set. Excluded entries carry { file, line,
// start_line, title, reason } for logging.
function filterFindings(findings, lineMap) {
  const valid = [];
  const excluded = [];
  for (const f of findings || []) {
    const file = f.file;
    const { anchor, ends } = findingAnchorEnds(f);
    let reason = null;

    if (!file || !lineMap.has(file)) {
      reason = 'file not in PR diff';
    } else if (ends.length === 0) {
      reason = 'no positive anchor line';
    } else {
      const set = lineMap.get(file);
      const outside = ends.filter((n) => !set.has(n));
      if (outside.length > 0) {
        reason = `line(s) outside PR diff: ${outside.join(', ')}`;
      }
    }

    if (reason) {
      excluded.push({
        file: file || '(none)',
        line: anchor,
        start_line: f.start_line,
        title: f.title,
        reason,
      });
    } else {
      valid.push(f);
    }
  }
  return { valid, excluded };
}

// Convenience: parse the patch and filter in one call.
function filterFindingsAgainstPatch(findings, patch) {
  return filterFindings(findings, parseDiffRightLines(patch));
}

module.exports = {
  parseDiffRightLines,
  findingAnchorEnds,
  filterFindings,
  filterFindingsAgainstPatch,
};
