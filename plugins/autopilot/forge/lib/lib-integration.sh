#!/usr/bin/env bash
# lib-integration.sh — forge per-SPEC 통합 상태 헬퍼 (M1)
#
# 책임:
#   - 한 SPEC 의 통합(push→PR)·리뷰·머지 라이프사이클 상태를 호출자(execute-task)의 run
#     디렉토리(<project_root>/.autopilot/runs/<id>/) 하위에 per-SPEC 키로 보관·조회.
#     보관 필드(파일): branch / pr / head / review-round / review-verdict /
#                      review-blocking-hash / int-phase.
#   - 키는 호출자가 계산해 넘긴다(호출자의 spec_slug+hash7 산식과 일치하는
#     `<slug>-<hash7>`). 이 헬퍼는 키를 불투명 문자열로만 다뤄 독립 검증 가능하다.
#
# **하지 않는 일**:
#   - slug/hash 산식 정의(호출자 책임), forge·git·loop 연동, 상태 전이 정책.
#   - run 디렉토리의 다른 상태 파일(state.<key> 등)은 건드리지 않는다 —
#     통합 필드는 별도 네임스페이스(int.<key>.<field>)에 둬 회귀를 막는다.
#
# 이 헬퍼는 sourcing 으로 쓴다. run 디렉토리 밖 경로는 만들지 않는다.
# bash 3.2+ 호환 (associative array 미사용).

# ----- 필드 IO (run_dir + 불투명 key) -----

int_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# int_field_path <run_dir> <key> <field>
int_field_path() {
  echo "$1/int.$2.$3"
}

# int_set <run_dir> <key> <field> <value>
int_set() {
  local rd="$1" key="$2" field="$3" value="$4"
  mkdir -p "$rd"
  printf '%s\n' "$value" > "$(int_field_path "$rd" "$key" "$field")"
}

# int_get <run_dir> <key> <field> [default]
int_get() {
  local rd="$1" key="$2" field="$3" def="${4:-}"
  local f; f="$(int_field_path "$rd" "$key" "$field")"
  if [[ -f "$f" ]]; then cat "$f"; else printf '%s\n' "$def"; fi
}

# ----- 의미 래퍼 -----

int_set_branch()  { int_set "$1" "$2" branch "$3"; }
int_get_branch()  { int_get "$1" "$2" branch ""; }

int_set_pr()      { int_set "$1" "$2" pr "$3"; }
int_get_pr()      { int_get "$1" "$2" pr ""; }

int_set_head()    { int_set "$1" "$2" head "$3"; }
int_get_head()    { int_get "$1" "$2" head ""; }

int_set_verdict() { int_set "$1" "$2" review-verdict "$3"; }
int_get_verdict() { int_get "$1" "$2" review-verdict ""; }

int_set_blocking_hash() { int_set "$1" "$2" review-blocking-hash "$3"; }
int_get_blocking_hash() { int_get "$1" "$2" review-blocking-hash ""; }

# int-phase — per-SPEC 통합 라이프사이클 단계(스케줄러가 읽는 sub-state).
#   loop-done|integrating|review|approved|merging|merged|escalated|blocked
int_set_phase()   { int_set "$1" "$2" int-phase "$3"; }
int_get_phase()   { int_get "$1" "$2" int-phase ""; }

# review-round 카운터.
int_review_round() { int_get "$1" "$2" review-round "0"; }
int_bump_review_round() {
  local rd="$1" key="$2" n
  n=$(( $(int_review_round "$rd" "$key") + 1 ))
  int_set "$rd" "$key" review-round "$n"
  echo "$n"
}

# int_log <run_dir> <key> <message...> — run-dir LOG.md 에 키 prefix 로 append.
int_log() {
  local rd="$1" key="$2"; shift 2
  mkdir -p "$rd"
  printf '[%s] [%s] %s\n' "$(int_now_iso)" "$key" "$*" >> "$rd/LOG.md"
}

# =====================================================================
# selftest — 순수 파일 IO 헬퍼를 독립 검증(runtime artifact 미검사).
# =====================================================================
li_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  local rd="$TMP/.autopilot/runs/run1"
  local k="feat-x-abc1234"
  local fail=0
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }
  chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }

  # 기본값: 미설정 필드는 default 반환.
  chk "기본 branch 빈값"      "$(int_get_branch "$rd" "$k")" ""
  chk "기본 review-round 0"   "$(int_review_round "$rd" "$k")" "0"
  chk "기본 phase 빈값"       "$(int_get_phase "$rd" "$k")" ""
  chk "기본 default 적용"     "$(int_get "$rd" "$k" nope fallback)" "fallback"

  # set/get 왕복.
  int_set_branch "$rd" "$k" "feat/run1-x"
  chk "branch 왕복"           "$(int_get_branch "$rd" "$k")" "feat/run1-x"
  int_set_pr "$rd" "$k" "42"
  chk "pr 왕복"               "$(int_get_pr "$rd" "$k")" "42"
  int_set_head "$rd" "$k" "sha-AAA"
  chk "head 왕복"             "$(int_get_head "$rd" "$k")" "sha-AAA"
  int_set_verdict "$rd" "$k" "approve"
  chk "verdict 왕복"          "$(int_get_verdict "$rd" "$k")" "approve"
  int_set_blocking_hash "$rd" "$k" "deadbeef"
  chk "blocking-hash 왕복"    "$(int_get_blocking_hash "$rd" "$k")" "deadbeef"
  int_set_phase "$rd" "$k" "review"
  chk "phase 왕복"            "$(int_get_phase "$rd" "$k")" "review"

  # round 증가.
  chk "bump→1"                "$(int_bump_review_round "$rd" "$k")" "1"
  chk "bump→2"                "$(int_bump_review_round "$rd" "$k")" "2"
  chk "round 영속=2"          "$(int_review_round "$rd" "$k")" "2"

  # 키 격리: 다른 키는 서로 영향 없음.
  local k2="feat-y-def5678"
  int_set_branch "$rd" "$k2" "feat/run1-y"
  chk "키 격리 k"             "$(int_get_branch "$rd" "$k")" "feat/run1-x"
  chk "키 격리 k2"            "$(int_get_branch "$rd" "$k2")" "feat/run1-y"

  # run 디렉토리의 다른 상태 파일(state.<key>)과 네임스페이스 분리 — int.* 만 만든다.
  [[ -z "$(ls "$rd"/state.* 2>/dev/null)" ]] && ok "state.* 미생성(네임스페이스 분리)" \
    || bad "state.* 미생성(네임스페이스 분리)"

  # 로그 append.
  int_log "$rd" "$k" "hello"
  grep -q 'hello' "$rd/LOG.md" && ok "log append" || bad "log append"

  echo "----"
  [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"
  return $fail
}

# ----- CLI 진입 (sourcing 시 미실행) -----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    selftest) li_selftest ;;
    *) echo "usage: lib-integration.sh selftest  (라이브러리는 sourcing 으로 사용)" >&2; exit 1 ;;
  esac
fi
