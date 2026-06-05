#!/usr/bin/env bash
# review.sh — autopilot:review 생산자 스킬의 결정적 하니스 + 서브커맨드 라우터.
#
# 책임 (결정적·테스트 가능):
#   - diff·SPEC 기준·lens 발견·기존 스레드를 주입 가능 명령 변수로 수집.
#   - finding fingerprint(파일+관점+정규화 제목, 라인 무관) 계산.
#   - evidence/신뢰도(>=80) 게이트로 부적격 finding 제외.
#   - 기존 스레드 fingerprint 와 중복 제거(skipped_duplicates).
#   - blocking 발견을 change-adoption 3분류(must_adopt/defer/wont_adopt)로 재작업 브리프 작성,
#     안전경계(보안·데이터 손실·계약·범위·권한) 발견은 must_adopt 로 고정(강등 불가).
#   - SPEC 수용기준 커버리지(total/verified/unverified) 산출.
#   - 단일 머신리더블 판정(pipeline_verdict: approve|request_changes|unavailable) 산출.
#
# **하지 않는 일**:
#   - LLM lens 리뷰 자체 수행(워커가 4 서브에이전트 dispatch 후 병합 결과를 주입).
#   - forge(PR/approve/merge) 호출·게이트 결정(오케스트레이터·머지 규칙 책임).
#   - 자기 상태 디렉토리(REVIEW_STATE_DIR) 밖 경로 생성.
#
# 사용:
#   bash review.sh run --task <task-id>
#   bash review.sh status --task <task-id>
#   bash review.sh list
#   bash review.sh fingerprint <file> <perspective> <title>
#   bash review.sh selftest
#
# 주입 가능 명령 변수 (테스트·오케스트레이터가 mock/실제로 치환):
#   REVIEW_DIFF_CMD <task>     -> ctx JSON {base_sha,head_sha,diff_truncated,context_incomplete,files_reviewed,...}
#   REVIEW_SPEC_CMD <task>     -> {"acceptance":[<id>...]}
#   REVIEW_LENS_CMD <task>     -> {"findings":[...],"verified_criteria":[<id>...],"context_incomplete":<bool>}
#   REVIEW_THREADS_CMD <task>  -> 기존 게시 fingerprint, 한 줄에 하나
#   REVIEW_STATE_DIR           상태 저장 루트 (기본 <git-root>/.review)
#
# bash 3.2 호환 (연관 배열 미사용). jq 의존.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "'jq' 가 필요합니다."

HASH_BIN=""
if command -v sha256sum >/dev/null 2>&1; then HASH_BIN="sha256sum"
elif command -v shasum   >/dev/null 2>&1; then HASH_BIN="shasum -a 256"
else die "sha256sum 또는 shasum 이 필요합니다."; fi

state_root() {
  if [[ -n "${REVIEW_STATE_DIR:-}" ]]; then
    echo "$REVIEW_STATE_DIR"
  else
    local root
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "git 저장소 밖 — REVIEW_STATE_DIR 를 지정하세요."
    echo "$root/.review"
  fi
}

# ---------------------------------------------------------------------------
# fingerprint: 파일 + 관점 + 정규화 제목(소문자·공백 정규화). 라인 무관.
# ---------------------------------------------------------------------------
normalize_title() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

compute_fingerprint() {
  local file="$1" persp="$2" title="$3" norm
  norm="$(normalize_title "$title")"
  printf '%s|%s|%s' "$file" "$persp" "$norm" | $HASH_BIN | awk '{print substr($1,1,12)}'
}

# ---------------------------------------------------------------------------
# 주입 가능 인터페이스 호출 (미설정 시 안전 기본값 — 절대 approve 로 기울지 않음).
# ---------------------------------------------------------------------------
emit_diff() {
  if [[ -n "${REVIEW_DIFF_CMD:-}" ]]; then $REVIEW_DIFF_CMD "$1"
  else echo '{"base_sha":"","head_sha":"","diff_truncated":false,"context_incomplete":true,"files_reviewed":[],"related_files_reviewed":[],"skipped_files":[]}'; fi
}
emit_spec() {
  if [[ -n "${REVIEW_SPEC_CMD:-}" ]]; then $REVIEW_SPEC_CMD "$1"
  else echo '{"acceptance":[]}'; fi
}
emit_lens() {
  if [[ -n "${REVIEW_LENS_CMD:-}" ]]; then $REVIEW_LENS_CMD "$1"
  else
    local f; f="$(state_root)/tasks/$1/lens-findings.json"
    if [[ -f "$f" ]]; then cat "$f"
    else echo '{"findings":[],"verified_criteria":[],"context_incomplete":true}'; fi
  fi
}
emit_threads() {
  if [[ -n "${REVIEW_THREADS_CMD:-}" ]]; then $REVIEW_THREADS_CMD "$1"; else true; fi
}

# ---------------------------------------------------------------------------
# 중재 게이트: 수집된 입력 -> 단일 머신리더블 판정 JSON (stdout).
# ---------------------------------------------------------------------------
mediate() {
  local ctx="$1" spec="$2" lens="$3" existing_raw="$4"

  # 1) finding 별 fingerprint 계산 (해시는 bash, 주입은 jq).
  local n i file persp title fp fps_json="[]"
  n="$(echo "$lens" | jq '.findings | length')"
  for ((i=0; i<n; i++)); do
    file="$(echo "$lens"  | jq -r ".findings[$i].file // \"\"")"
    persp="$(echo "$lens" | jq -r ".findings[$i].review_perspective // \"\"")"
    title="$(echo "$lens" | jq -r ".findings[$i].title // \"\"")"
    fp="$(compute_fingerprint "$file" "$persp" "$title")"
    fps_json="$(echo "$fps_json" | jq --arg fp "$fp" '. + [$fp]')"
  done
  local findings_fp
  findings_fp="$(echo "$lens" | jq --argjson fps "$fps_json" \
    '[.findings | to_entries[] | .value + {fingerprint: $fps[.key], duplicate_of: null}]')"

  # 2) 기존 스레드 fingerprint -> JSON 배열.
  local existing_json
  existing_json="$(printf '%s\n' "$existing_raw" | jq -R . | jq -s 'map(select(length>0))')"

  # 3) jq 중재: 게이트 -> dedup -> rework -> coverage -> verdict -> 출력 조립.
  jq -n \
    --argjson ctx "$ctx" \
    --argjson spec "$spec" \
    --argjson lens "$lens" \
    --argjson F "$findings_fp" \
    --argjson EX "$existing_json" '
    # evidence/신뢰도 게이트: 4증거(file·line·body·suggestion) + conf>=80
    def gated:
      map(select(
        ((.confidence_score // 0) >= 80)
        and ((.file // "") != "")
        and (.line != null) and ((.line | type) == "number") and (.line >= 1)
        and ((.body // "") != "")
        and ((.suggestion // "") != "")
      ));
    # 안전경계 탐지: 보안·데이터 손실·계약·범위·권한 등
    def is_safety:
      (((.title // "") + " " + (.body // ""))
       | test("보안|security|secret|데이터 ?손실|data ?loss|손상|corrupt|계약|contract|범위|scope|권한|permission|injection|인젝션"; "i"));
    # 채택 분류: 안전경계면 must_adopt 고정(adoption 무시), 아니면 adoption 힌트(기본 must_adopt)
    def adopt_class:
      if is_safety then "must_adopt" else (.adoption // "must_adopt") end;

    ($F | gated) as $g
    | ($g | map(.fingerprint)) as $raised
    | ($g | map(select(.fingerprint as $f | ($EX | index($f)) != null))) as $dups
    | ($g | map(select(.fingerprint as $f | ($EX | index($f)) == null))) as $active
    # 스레드 라이프사이클: 기존 스레드 중 이번 라운드에 다시 제기됨=unresolved, 사라짐=resolved
    | ($EX | map(select(. as $f | ($raised | index($f)) == null))) as $resolved_fps
    | ($EX | map(select(. as $f | ($raised | index($f)) != null))) as $unresolved_fps
    | ($active | map(select(.severity == "blocking"))) as $blocking
    | ($spec.acceptance // []) as $all
    | ($lens.verified_criteria // []) as $ver
    | ($all | map(select(. as $a | ($ver | index($a)) != null))) as $verified
    | ($all | map(select(. as $a | ($ver | index($a)) == null))) as $unverified
    | (($ctx.diff_truncated == true)
        or ($ctx.context_incomplete == true)
        or ($lens.context_incomplete == true)) as $unavail
    | (if $unavail then "unavailable"
       elif (($blocking | length) > 0) or (($unverified | length) > 0) then "request_changes"
       else "approve" end) as $verdict
    | {
        eligibility: {
          status: (if $unavail then "unavailable" else "reviewed" end),
          reason: (if $unavail then "diff 잘림 또는 필수 컨텍스트 불완전" else "리뷰 수행됨" end)
        },
        pipeline_verdict: $verdict,
        verdict: (if $verdict == "approve" then "approve"
                  elif $verdict == "unavailable" then "unavailable"
                  else "comment" end),
        confidence: (if $unavail then "low" else "high" end),
        reviewed_context: {
          base_sha: ($ctx.base_sha // ""),
          head_sha: ($ctx.head_sha // ""),
          diff_truncated: ($ctx.diff_truncated // false),
          files_reviewed: ($ctx.files_reviewed // []),
          related_files_reviewed: ($ctx.related_files_reviewed // []),
          skipped_files: ($ctx.skipped_files // [])
        },
        automation_safety: {
          may_approve: ($verdict == "approve"),
          may_request_changes: (($blocking | length) > 0),
          reason: (if $unavail then "안전하게 approve 불가(컨텍스트 불완전)"
                   elif ($verdict == "approve") then "blocking 없음·전 수용기준 검증·컨텍스트 온전"
                   else "blocking 또는 미검증 수용기준 존재" end)
        },
        acceptance_coverage: {
          total: ($all | length),
          verified: ($verified | length),
          unverified: $unverified
        },
        findings: $active,
        rework_brief: {
          must_adopt: ($blocking | map(select(adopt_class == "must_adopt"))),
          defer:      ($blocking | map(select(adopt_class == "defer"))),
          wont_adopt: ($blocking | map(select(adopt_class == "wont_adopt")))
        },
        skipped_duplicates: ($dups | map({fingerprint: .fingerprint, duplicate_of: .fingerprint, reason: "이전 리뷰에 이미 게시됨"})),
        resolved_threads: ($resolved_fps | map({fingerprint: ., reason: "현재 변경에서 더 이상 제기되지 않음"})),
        unresolved_threads: ($unresolved_fps | map({fingerprint: ., reason: "동일 지적 유지"})),
        context_requests: []
      }
  '
}

# ---------------------------------------------------------------------------
# 상태 저장 (자기 상태 디렉토리 내부에만).
# ---------------------------------------------------------------------------
persist_state() {
  local task="$1" output="$2" verdict="$3"
  local dir; dir="$(state_root)/tasks/$task"
  mkdir -p "$dir"
  local round=0
  [[ -f "$dir/review-round" ]] && round="$(cat "$dir/review-round")"
  round=$((round + 1))
  echo "$round" > "$dir/review-round"
  echo "$verdict" > "$dir/verdict"
  echo "$output" > "$dir/last-output.json"
  echo "$output" | jq -r '.findings[].fingerprint' > "$dir/fingerprints"
}

# ----- subcommand: run -----
cmd_run() {
  local task=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task) task="${2:-}"; shift 2 ;;
      *) die "알 수 없는 인자: $1 (사용: run --task <id>)" ;;
    esac
  done
  [[ -n "$task" ]] || die "사용: run --task <task-id>"

  local ctx spec lens existing output verdict
  ctx="$(emit_diff "$task")"
  spec="$(emit_spec "$task")"
  lens="$(emit_lens "$task")"
  existing="$(emit_threads "$task" || true)"

  output="$(mediate "$ctx" "$spec" "$lens" "$existing")"
  verdict="$(echo "$output" | jq -r '.pipeline_verdict')"
  persist_state "$task" "$output" "$verdict"
  echo "$output"
}

# ----- subcommand: status -----
cmd_status() {
  local task=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task) task="${2:-}"; shift 2 ;;
      *) die "사용: status --task <id>" ;;
    esac
  done
  [[ -n "$task" ]] || die "사용: status --task <task-id>"
  local dir; dir="$(state_root)/tasks/$task"
  [[ -d "$dir" ]] || die "리뷰 상태 없음: $task"
  local verdict round
  verdict="$(cat "$dir/verdict" 2>/dev/null || echo unknown)"
  round="$(cat "$dir/review-round" 2>/dev/null || echo 0)"
  echo "task: $task"
  echo "pipeline_verdict: $verdict"
  echo "review-round: $round"
  echo "fingerprints:"
  if [[ -s "$dir/fingerprints" ]]; then sed 's/^/  - /' "$dir/fingerprints"; else echo "  (없음)"; fi
}

# ----- subcommand: list -----
cmd_list() {
  local base; base="$(state_root)/tasks"
  if [[ ! -d "$base" ]]; then
    echo "리뷰 상태가 있는 작업 없음."
    return 0
  fi
  local found=0 d task verdict round
  for d in "$base"/*/; do
    [[ -d "$d" ]] || continue
    found=1
    task="$(basename "$d")"
    verdict="$(cat "$d/verdict" 2>/dev/null || echo unknown)"
    round="$(cat "$d/review-round" 2>/dev/null || echo 0)"
    printf '%-30s verdict=%-16s round=%s\n' "$task" "$verdict" "$round"
  done
  [[ "$found" == "1" ]] || echo "리뷰 상태가 있는 작업 없음."
  return 0
}

# ----- subcommand: fingerprint -----
cmd_fingerprint() {
  [[ $# -ge 3 ]] || die "사용: fingerprint <file> <perspective> <title>"
  compute_fingerprint "$1" "$2" "$3"
}

# ----- subcommand: selftest -----
# 결정적 동작을 내장 mock(주입 명령 변수)만으로 검증하고 0 exit. 실제 PR/브랜치 무관.
cmd_selftest() {
  local tmp; tmp="$(mktemp -d)"
  export REVIEW_STATE_DIR="$tmp/state"

  _st_fail() { echo "SELFTEST FAIL: $*" >&2; return 1; }

  mk() { local p="$tmp/$1"; cat > "$p"; chmod +x "$p"; echo "$p"; }

  local ctx_ok spec1 lens_block lens_clean th_empty
  ctx_ok="$(echo '#!/usr/bin/env bash
echo '"'"'{"base_sha":"a","head_sha":"b","diff_truncated":false,"context_incomplete":false,"files_reviewed":["x"],"related_files_reviewed":[],"skipped_files":[]}'"'"'' | mk ctx_ok.sh)"
  local ctx_trunc
  ctx_trunc="$(echo '#!/usr/bin/env bash
echo '"'"'{"base_sha":"a","head_sha":"b","diff_truncated":true,"context_incomplete":false,"files_reviewed":[],"related_files_reviewed":[],"skipped_files":[]}'"'"'' | mk ctx_trunc.sh)"
  spec1="$(echo '#!/usr/bin/env bash
echo '"'"'{"acceptance":["AC1","AC2"]}'"'"'' | mk spec1.sh)"
  lens_block="$(echo '#!/usr/bin/env bash
echo '"'"'{"findings":[{"severity":"blocking","confidence_score":90,"review_perspective":"bug","comment_type":"inline","file":"x","line":1,"start_line":1,"title":"보안 경계 붕괴","body":"권한 누락","suggestion":"가드","adoption":"defer"}],"verified_criteria":["AC1","AC2"],"context_incomplete":false}'"'"'' | mk lens_block.sh)"
  lens_clean="$(echo '#!/usr/bin/env bash
echo '"'"'{"findings":[],"verified_criteria":["AC1","AC2"],"context_incomplete":false}'"'"'' | mk lens_clean.sh)"
  th_empty="$(echo '#!/usr/bin/env bash
true' | mk th_empty.sh)"

  # 시나리오 A: 안전경계 blocking → request_changes + must_adopt 고정
  local out
  out="$(REVIEW_DIFF_CMD="$ctx_ok" REVIEW_SPEC_CMD="$spec1" REVIEW_LENS_CMD="$lens_block" REVIEW_THREADS_CMD="$th_empty" cmd_run --task st_a)"
  [[ "$(echo "$out" | jq -r '.pipeline_verdict')" == "request_changes" ]] || _st_fail "A verdict" || return 1
  [[ "$(echo "$out" | jq -r '.rework_brief.must_adopt | length')" -ge 1 ]] || _st_fail "A must_adopt" || return 1
  [[ "$(echo "$out" | jq -r '.rework_brief.defer | length')" == "0" ]] || _st_fail "A 안전핀 강등" || return 1

  # 시나리오 B: 전부 검증·blocking 없음 → approve
  out="$(REVIEW_DIFF_CMD="$ctx_ok" REVIEW_SPEC_CMD="$spec1" REVIEW_LENS_CMD="$lens_clean" REVIEW_THREADS_CMD="$th_empty" cmd_run --task st_b)"
  [[ "$(echo "$out" | jq -r '.pipeline_verdict')" == "approve" ]] || _st_fail "B verdict" || return 1

  # 시나리오 C: diff 잘림 → unavailable (approve 금지)
  out="$(REVIEW_DIFF_CMD="$ctx_trunc" REVIEW_SPEC_CMD="$spec1" REVIEW_LENS_CMD="$lens_clean" REVIEW_THREADS_CMD="$th_empty" cmd_run --task st_c)"
  [[ "$(echo "$out" | jq -r '.pipeline_verdict')" == "unavailable" ]] || { rm -rf "$tmp"; _st_fail "C verdict"; return 1; }

  rm -rf "$tmp"
  echo "SELFTEST OK"
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    run)         cmd_run "$@" ;;
    status)      cmd_status "$@" ;;
    list)        cmd_list "$@" ;;
    fingerprint) cmd_fingerprint "$@" ;;
    selftest)    cmd_selftest ;;
    ""|-h|--help)
      cat <<'EOF'
review.sh — autopilot:review 결정적 하니스
사용:
  run --task <id>                   리뷰 수행 → 판정 JSON
  status --task <id>                마지막 판정 조회
  list                              리뷰 상태 있는 작업 요약
  fingerprint <file> <persp> <title>  안정 fingerprint 계산
  selftest                          내장 mock 결정적 검증
EOF
      ;;
    *) die "알 수 없는 서브커맨드: $sub" ;;
  esac
}

main "$@"
