# Codex Structured PR Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace free-form `codex review` output with structured JSON review output that can drive GitHub review actions and later support other code review platforms.

**Architecture:** Keep the review decision engine platform-neutral through a Korean prompt and JSON schema, then let platform adapters publish comments, resolve threads, and submit approvals. Phase 1 implements the GitHub Actions adapter with schema validation and verdict-based review submission.

**Tech Stack:** GitHub Actions, GitHub CLI, Codex CLI, JSON Schema, `jq`, Bash.

---

### Task 1: Add Review Core Prompt And Schema

**Files:**
- Create: `.github/prompts/codex-pr-review.ko.md`
- Create: `.github/prompts/codex-pr-review.schema.json`

- [x] **Step 1: Write Korean prompt**

Create a prompt that covers diff-first review, token budgeting, multi-perspective review, confidence scoring, duplicate handling, approval policy, and JSON-only output.

- [x] **Step 2: Write JSON schema**

Create a strict schema requiring `eligibility`, `verdict`, `reviewed_context`, `automation_safety`, `findings`, thread state arrays, duplicate state, and context requests.

- [x] **Step 3: Validate schema**

Run:

```bash
jq empty .github/prompts/codex-pr-review.schema.json
```

Expected: exit 0.

### Task 2: Document Workflow And Cross-Platform Boundary

**Files:**
- Create: `docs/codex/pr-review-workflow.md`
- Create: `docs/superpowers/plans/2026-05-20-codex-structured-pr-review.md`

- [x] **Step 1: Document current MVP**

Describe `codex exec --output-schema`, schema validation, managed comment, and verdict-based GitHub review submission.

- [x] **Step 2: Document phased roadmap**

Capture phases for inline comments, thread lifecycle, token optimized chunking, and multi-perspective parallel review.

- [x] **Step 3: Separate review core from platform adapters**

Document which parts can be reused for GitLab and which must remain platform-specific.

### Task 3: Update GitHub Workflow

**Files:**
- Modify: `.github/workflows/codex-review.yml`
- Modify: `tests/codex/test-codex-review-workflow.sh`

- [x] **Step 1: Replace `codex review` with `codex exec`**

Use stdin to avoid shell argument limits and `--output-schema` to force structured output.

- [x] **Step 2: Collect trusted review context**

Collect base/head SHAs, PR metadata, changed files, existing comments, existing review comments, and the diff. Treat PR user text as untrusted context.

- [x] **Step 3: Publish verdict**

Use `gh pr review --approve`, `--request-changes`, or `--comment` based on validated JSON and automation safety.

- [x] **Step 4: Preserve managed issue comment**

Update the marker-based issue comment so humans can see the structured result even when a review event was submitted.

- [x] **Step 5: Add static tests**

Check that the workflow uses the prompt file, schema file, `codex exec`, stdin, `jq`, `gh pr review`, and keeps trusted `@codex` trigger guards.

### Task 4: Verification

**Files:**
- Test: `tests/codex/test-codex-review-workflow.sh`
- Test: `.github/workflows/codex-review.yml`
- Test: `.github/prompts/codex-pr-review.schema.json`

- [x] **Step 1: Run workflow contract tests**

```bash
bash tests/codex/test-codex-review-workflow.sh
```

Expected: all checks pass.

- [x] **Step 2: Parse workflow YAML**

```bash
yq e '.' .github/workflows/codex-review.yml >/dev/null
```

Expected: exit 0.

- [x] **Step 3: Parse JSON schema**

```bash
jq empty .github/prompts/codex-pr-review.schema.json
```

Expected: exit 0.
