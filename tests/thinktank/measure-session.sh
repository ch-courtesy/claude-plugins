#!/usr/bin/env bash
# measure-session.sh — 측정 세션 산출물 파싱·판정 하니스 (1.2.0)
#
# Usage:
#   bash measure-session.sh --selftest
#   bash measure-session.sh --skill roundtable --record <path>
#   bash measure-session.sh --skill forum  --record <path>
#
# 구조화 마커 (kebab-case key: 라인 확장):
#   roundtable: dissent-forcing-triggered, rebuttal-exchange, core-claim
#   forum:  park-recondition, elimination-reason, parent-id,
#                core-fact, independent-sources
#
# Fail-loud 규정: 필수 마커가 누락되거나 값이 손상(corrupt)된 경우
#   non-zero exit + 명시적 오류 메시지 출력

set -euo pipefail

HARNESS_VERSION="1.2.0"

# ── 전역 헬퍼 ────────────────────────────────────────────────────────────────
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }
info() { echo "INFO: $*"; }

usage() {
  cat >&2 <<'USAGE'
Usage:
  measure-session.sh --selftest
  measure-session.sh --skill (roundtable|forum) --record <path>
  measure-session.sh --skill (roundtable|forum) --record <path> --judge
USAGE
  exit 1
}

# ── 마커 추출 헬퍼 ────────────────────────────────────────────────────────────
# 문서 템플릿의 kebab-case 라인은 "- key: value" (마크다운 목록 항목) 형식.
# 패턴은 선택적 "- " 접두사를 모두 처리한다.

# 첫 번째 매칭 "- key: value" 라인에서 값 추출 (키 없으면 빈 문자열, exit 0)
extract_marker() {
  local key="$1"
  local content="$2"
  printf '%s\n' "$content" \
    | grep -E -m1 "^[[:space:]]*(-[[:space:]]+)?${key}:" \
    | sed -E "s/^[[:space:]]*(-[[:space:]]+)?${key}:[[:space:]]*//" \
    | sed 's/[[:space:]]*$//' \
    || true
}

# 특정 마커 키의 출현 횟수 카운트
count_marker() {
  local key="$1"
  local content="$2"
  printf '%s\n' "$content" | grep -cE "^[[:space:]]*(-[[:space:]]+)?${key}:" || true
}

# 모든 매칭 "- key: value" 라인의 값을 한 줄씩 출력 (세션 집계용 — 라운드·항목별 다중 출현 처리)
extract_marker_all() {
  local key="$1"
  local content="$2"
  printf '%s\n' "$content" \
    | grep -E "^[[:space:]]*(-[[:space:]]+)?${key}:" \
    | sed -E "s/^[[:space:]]*(-[[:space:]]+)?${key}:[[:space:]]*//" \
    | sed 's/[[:space:]]*$//' \
    || true
}

# 아이디어 블록(### 헤딩 단위) 중 status가 <state>인데 비어 있지 않은 <field>가 같은 블록에 없는 블록 수 출력
# — 전역 카운트가 아닌 블록 단위 100% 충족률 검사 (게이트 오판정 방지)
count_blocks_missing_field() {
  local state="$1"
  local field="$2"
  local content="$3"
  printf '%s\n' "$content" | awk -v state="$state" -v field="$field" '
    function check_block() {
      if (block ~ ("(^|\n)[[:space:]]*(-[[:space:]]+)?status:[[:space:]]*" state "[[:space:]]*(\n|$)")) {
        if (block !~ ("(^|\n)[[:space:]]*(-[[:space:]]+)?" field ":[[:space:]]*[^[:space:]]")) missing++
      }
    }
    /^###[[:space:]]/ { check_block(); block = "" }
    { block = block "\n" $0 }
    END { check_block(); print missing + 0 }
  '
}

# ── roundtable 파서 ───────────────────────────────────────────────────────────
# 필수 마커: dissent-forcing-triggered (yes|no), rebuttal-exchange (정수), core-claim (1개+)
# 누락·손상(corrupt) 시 non-zero exit + 명시적 오류
parse_roundtable() {
  local content="$1"
  local errors=0

  info "--- roundtable 파서 실행 ---"

  # 1. dissent-forcing-triggered: 라운드별 다중 출현 — 각 값은 yes|no, 세션 집계는 any-yes
  #    (반대 강제는 발동 조건이 충족된 라운드에만 yes로 기록되므로 첫 값이 아닌 전체를 본다)
  local dissent="" dissent_val dissent_count=0
  while IFS= read -r dissent_val; do
    [[ -z "$dissent_val" ]] && continue
    dissent_count=$((dissent_count + 1))
    if [[ "$dissent_val" != "yes" && "$dissent_val" != "no" ]]; then
      echo "ERROR: 손상된 마커(corrupt value) — dissent-forcing-triggered='${dissent_val}' (허용값: yes|no)" >&2
      errors=$((errors + 1))
    elif [[ "$dissent_val" == "yes" ]]; then
      dissent="yes"
    fi
  done < <(extract_marker_all "dissent-forcing-triggered" "$content")
  if [[ "$dissent_count" -eq 0 ]]; then
    echo "ERROR: 필수 마커 누락 — dissent-forcing-triggered" >&2
    errors=$((errors + 1))
  else
    [[ -z "$dissent" ]] && dissent="no"
    info "dissent-forcing-triggered: ${dissent} (라운드 기록 ${dissent_count}건 any-yes 집계)"
  fi

  # 2. rebuttal-exchange: 라운드별 다중 출현 — 각 값은 정수, 세션 집계는 합계
  local rebuttal_sum=0 rebuttal_val rebuttal_count=0
  while IFS= read -r rebuttal_val; do
    [[ -z "$rebuttal_val" ]] && continue
    rebuttal_count=$((rebuttal_count + 1))
    if ! [[ "$rebuttal_val" =~ ^[0-9]+$ ]]; then
      echo "ERROR: 손상된 마커(corrupt value) — rebuttal-exchange='${rebuttal_val}' (정수 필요)" >&2
      errors=$((errors + 1))
    else
      rebuttal_sum=$((rebuttal_sum + rebuttal_val))
    fi
  done < <(extract_marker_all "rebuttal-exchange" "$content")
  if [[ "$rebuttal_count" -eq 0 ]]; then
    echo "ERROR: 필수 마커 누락 — rebuttal-exchange" >&2
    errors=$((errors + 1))
  else
    info "rebuttal-exchange: 합계 ${rebuttal_sum}왕복 (라운드 기록 ${rebuttal_count}건)"
  fi

  # 3. core-claim: 최소 1개 필요
  local core_claim_count
  core_claim_count="$(count_marker "core-claim" "$content")"
  if [[ "$core_claim_count" -eq 0 ]]; then
    echo "ERROR: 필수 마커 누락 — core-claim (최소 1개 필요)" >&2
    errors=$((errors + 1))
  else
    info "core-claim: ${core_claim_count}개"
  fi

  if [[ "$errors" -gt 0 ]]; then
    fail "roundtable 마커 파싱 실패: ${errors}개 오류"
  fi

  # 파싱 결과 출력 (key=value 형식) — 세션 단위 집계값
  echo "PARSE_DISSENT_TRIGGERED=${dissent}"
  echo "PARSE_REBUTTAL_EXCHANGES=${rebuttal_sum}"
  echo "PARSE_CORE_CLAIM_COUNT=${core_claim_count}"
}

# ── forum 파서 ───────────────────────────────────────────────────────────
# 필수 마커:
#   - park-recondition: status:parked 아이디어 존재 시 필수
#   - elimination-reason: status:eliminated 아이디어 존재 시 필수
#   - core-fact: 최소 1개
#   - independent-sources: 정수
# 정보 마커: parent-id (필수 아님, 계보 추적용)
parse_forum() {
  local content="$1"
  local errors=0

  info "--- forum 파서 실행 ---"

  # 1. park-recondition: status가 parked인 각 아이디어 블록에 비어 있지 않은 값 필수 (블록 단위 100% 검사)
  local parked_count park_missing
  parked_count="$(printf '%s\n' "$content" | grep -cE "^[[:space:]]*(-[[:space:]]+)?status:[[:space:]]*parked" || true)"
  park_missing="$(count_blocks_missing_field "parked" "park-recondition" "$content")"

  if [[ "$park_missing" -gt 0 ]]; then
    echo "ERROR: 필수 마커 누락 — park-recondition 누락 블록 ${park_missing}/${parked_count} (parked 아이디어 전수에 필수)" >&2
    errors=$((errors + 1))
  else
    info "park-recondition: parked ${parked_count}개 블록 전수 충족 (100%)"
  fi

  # 2. elimination-reason: status가 eliminated인 각 아이디어 블록에 비어 있지 않은 값 필수 (블록 단위 100% 검사)
  local eliminated_count elim_missing
  eliminated_count="$(printf '%s\n' "$content" | grep -cE "^[[:space:]]*(-[[:space:]]+)?status:[[:space:]]*eliminated" || true)"
  elim_missing="$(count_blocks_missing_field "eliminated" "elimination-reason" "$content")"

  if [[ "$elim_missing" -gt 0 ]]; then
    echo "ERROR: 필수 마커 누락 — elimination-reason 누락 블록 ${elim_missing}/${eliminated_count} (eliminated 아이디어 전수에 필수)" >&2
    errors=$((errors + 1))
  else
    info "elimination-reason: eliminated ${eliminated_count}개 블록 전수 충족 (100%)"
  fi

  # 3. parent-id: 정보 마커 (필수 아님)
  local parent_id_count
  parent_id_count="$(count_marker "parent-id" "$content")"
  info "parent-id: ${parent_id_count}개 계보 추적"

  # 4. core-fact: 최소 1개 필요
  local core_fact_count
  core_fact_count="$(count_marker "core-fact" "$content")"
  if [[ "$core_fact_count" -eq 0 ]]; then
    echo "ERROR: 필수 마커 누락 — core-fact (최소 1개 필요)" >&2
    errors=$((errors + 1))
  else
    info "core-fact: ${core_fact_count}개"
  fi

  # 5. independent-sources: 연구 항목별 다중 출현 — 각 값은 정수, 세션 집계는 최대값
  #    (핵심 사실 중 가장 잘 검증된 항목의 독립 출처 수를 게이트 대상으로 본다)
  local ind_src_max=0 ind_src_val ind_src_count=0
  while IFS= read -r ind_src_val; do
    [[ -z "$ind_src_val" ]] && continue
    ind_src_count=$((ind_src_count + 1))
    if ! [[ "$ind_src_val" =~ ^[0-9]+$ ]]; then
      echo "ERROR: 손상된 마커(corrupt value) — independent-sources='${ind_src_val}' (정수 필요)" >&2
      errors=$((errors + 1))
    elif [[ "$ind_src_val" -gt "$ind_src_max" ]]; then
      ind_src_max="$ind_src_val"
    fi
  done < <(extract_marker_all "independent-sources" "$content")
  if [[ "$ind_src_count" -eq 0 ]]; then
    echo "ERROR: 필수 마커 누락 — independent-sources (최소 1개 필요)" >&2
    errors=$((errors + 1))
  else
    info "independent-sources: 최대 ${ind_src_max}개 (연구 항목 ${ind_src_count}건)"
  fi

  if [[ "$errors" -gt 0 ]]; then
    fail "forum 마커 파싱 실패: ${errors}개 오류"
  fi

  # 파싱 결과 출력
  echo "PARSE_PARKED_COUNT=${parked_count}"
  echo "PARSE_ELIMINATED_COUNT=${eliminated_count}"
  echo "PARSE_CORE_FACT_COUNT=${core_fact_count}"
  echo "PARSE_INDEPENDENT_SOURCES=${ind_src_max}"
}

# ── 임계치 상수 ───────────────────────────────────────────────────────────────
# 아래 값은 파일럿 실측(표준 시나리오 픽스처로 구동한 실제 스킬 세션) 분산 분석 후
# 구현자 제안 → 사용자 승인(CHANGELOG `- 게이트 승인:` 마커)으로 확정된다.
# decision-mode: '1회 충족' = 단일 측정 세션 통과로 게이트 충족
#               'N회 안정 충족' = N회 연속 측정 통과 필요

# roundtable 절대 임계치 (threshold)
RT_THRESHOLD_DISSENT_FORCED="yes"           # dissent-forcing-triggered 필수값  (decision-mode: 1회 충족)
RT_THRESHOLD_REBUTTAL_MIN=1                 # rebuttal-exchange 최소 왕복 수     (decision-mode: 1회 충족)
RT_THRESHOLD_CORE_CLAIM_MIN=1               # core-claim 최소 개수/세션          (decision-mode: 1회 충족)

# forum 절대 임계치 (threshold)
FORUM_THRESHOLD_CORE_FACT_MIN=1                # core-fact 최소 개수/세션           (decision-mode: 1회 충족)
FORUM_THRESHOLD_INDEPENDENT_SOURCES_MIN=2      # independent-sources 최소 수        (gate-status: shadow — 기록 전용)
# independent-sources는 파일럿 실측 최대값이 1~5로 분산되어 재파일럿 1회 후에도 판정이 갈려
# shadow(기록 전용)로 강등됨 (2026-08-01 게이트 승인). 게이트를 차단하지 않고 GATE_SHADOW로 보고만 한다.
# park-recondition 충족률 100% 및 elimination-reason 충족률 100%는
# parse_forum fail-loud 규정으로 강제 (threshold: 100%, decision-mode: 1회 충족)

# ── roundtable 게이트 판정 ────────────────────────────────────────────────────
# 파싱 결과에 절대 임계치(threshold)를 적용해 gate-status를 결정한다
judge_roundtable() {
  local content="$1"
  local gate_errors=0
  local gates_passed=0

  info "--- roundtable 게이트 판정 (threshold 적용) ---"

  # 파싱 먼저 수행 (fail-loud: 마커 누락·손상 시 즉시 non-zero exit)
  local parse_out
  parse_out="$(parse_roundtable "$content")" || return 1

  # 파싱 결과에서 값 추출
  local dissent rebuttal core_claim_count
  dissent="$(printf '%s\n' "$parse_out"          | grep '^PARSE_DISSENT_TRIGGERED='  | cut -d= -f2)"
  rebuttal="$(printf '%s\n' "$parse_out"         | grep '^PARSE_REBUTTAL_EXCHANGES=' | cut -d= -f2)"
  core_claim_count="$(printf '%s\n' "$parse_out" | grep '^PARSE_CORE_CLAIM_COUNT='   | cut -d= -f2)"

  # Gate 1: dissent-forcing-triggered (threshold: yes, decision-mode: 1회 충족)
  if [[ "$dissent" == "$RT_THRESHOLD_DISSENT_FORCED" ]]; then
    ok "GATE_PASS: dissent-forcing-triggered=${dissent} threshold=${RT_THRESHOLD_DISSENT_FORCED} decision-mode=1회충족"
    gates_passed=$((gates_passed + 1))
  else
    echo "GATE_FAIL: dissent-forcing-triggered=${dissent} threshold=${RT_THRESHOLD_DISSENT_FORCED} decision-mode=1회충족" >&2
    gate_errors=$((gate_errors + 1))
  fi

  # Gate 2: rebuttal-exchange (threshold: ≥RT_THRESHOLD_REBUTTAL_MIN, decision-mode: 1회 충족)
  if [[ -n "$rebuttal" ]] && [[ "$rebuttal" -ge "$RT_THRESHOLD_REBUTTAL_MIN" ]] 2>/dev/null; then
    ok "GATE_PASS: rebuttal-exchange=${rebuttal} threshold>=${RT_THRESHOLD_REBUTTAL_MIN} decision-mode=1회충족"
    gates_passed=$((gates_passed + 1))
  else
    echo "GATE_FAIL: rebuttal-exchange=${rebuttal} threshold>=${RT_THRESHOLD_REBUTTAL_MIN} decision-mode=1회충족" >&2
    gate_errors=$((gate_errors + 1))
  fi

  # Gate 3: core-claim (threshold: ≥RT_THRESHOLD_CORE_CLAIM_MIN, decision-mode: 1회 충족)
  if [[ -n "$core_claim_count" ]] && [[ "$core_claim_count" -ge "$RT_THRESHOLD_CORE_CLAIM_MIN" ]] 2>/dev/null; then
    ok "GATE_PASS: core-claim=${core_claim_count} threshold>=${RT_THRESHOLD_CORE_CLAIM_MIN} decision-mode=1회충족"
    gates_passed=$((gates_passed + 1))
  else
    echo "GATE_FAIL: core-claim=${core_claim_count} threshold>=${RT_THRESHOLD_CORE_CLAIM_MIN} decision-mode=1회충족" >&2
    gate_errors=$((gate_errors + 1))
  fi

  if [[ "$gate_errors" -gt 0 ]]; then
    fail "roundtable 게이트 판정 실패: ${gate_errors}개 지표 threshold 미달"
  fi

  echo "GATE_SKILL=roundtable"
  echo "GATE_STATUS=active"
  echo "GATE_PASS_COUNT=${gates_passed}"
}

# ── forum 게이트 판정 ────────────────────────────────────────────────────
# 파싱 결과에 절대 임계치(threshold)를 적용해 gate-status를 결정한다
judge_forum() {
  local content="$1"
  local gate_errors=0
  local gates_passed=0

  info "--- forum 게이트 판정 (threshold 적용) ---"

  # 파싱 먼저 수행 (fail-loud: 마커 누락·손상 시 즉시 non-zero exit)
  local parse_out
  parse_out="$(parse_forum "$content")" || return 1

  # 파싱 결과에서 값 추출
  local core_fact_count ind_sources
  core_fact_count="$(printf '%s\n' "$parse_out" | grep '^PARSE_CORE_FACT_COUNT='       | cut -d= -f2)"
  ind_sources="$(printf '%s\n' "$parse_out"     | grep '^PARSE_INDEPENDENT_SOURCES='   | cut -d= -f2)"

  # Gate 1: core-fact (threshold: ≥FORUM_THRESHOLD_CORE_FACT_MIN, decision-mode: 1회 충족)
  if [[ -n "$core_fact_count" ]] && [[ "$core_fact_count" -ge "$FORUM_THRESHOLD_CORE_FACT_MIN" ]] 2>/dev/null; then
    ok "GATE_PASS: core-fact=${core_fact_count} threshold>=${FORUM_THRESHOLD_CORE_FACT_MIN} decision-mode=1회충족"
    gates_passed=$((gates_passed + 1))
  else
    echo "GATE_FAIL: core-fact=${core_fact_count} threshold>=${FORUM_THRESHOLD_CORE_FACT_MIN} decision-mode=1회충족" >&2
    gate_errors=$((gate_errors + 1))
  fi

  # Shadow 지표: independent-sources (threshold: ≥FORUM_THRESHOLD_INDEPENDENT_SOURCES_MIN, gate-status: shadow)
  # 실측 분산으로 강등된 기록 전용 지표 — 게이트 판정을 차단하지 않고 관찰값만 보고한다
  if [[ -n "$ind_sources" ]] && [[ "$ind_sources" -ge "$FORUM_THRESHOLD_INDEPENDENT_SOURCES_MIN" ]] 2>/dev/null; then
    info "GATE_SHADOW: independent-sources=${ind_sources} threshold>=${FORUM_THRESHOLD_INDEPENDENT_SOURCES_MIN} (기록 전용 — 관찰: 충족)"
  else
    info "GATE_SHADOW: independent-sources=${ind_sources} threshold>=${FORUM_THRESHOLD_INDEPENDENT_SOURCES_MIN} (기록 전용 — 관찰: 미충족, 게이트 비차단)"
  fi

  # park-recondition 충족률 100% 및 elimination-reason 충족률 100%는
  # parse_forum fail-loud 규정으로 이미 강제됨 (threshold: 100%, decision-mode: 1회 충족)

  if [[ "$gate_errors" -gt 0 ]]; then
    fail "forum 게이트 판정 실패: ${gate_errors}개 지표 threshold 미달"
  fi

  # parse_forum fail-loud가 강제한 park-recondition·elimination-reason 충족률 100% 2건 포함
  gates_passed=$((gates_passed + 2))
  echo "GATE_SKILL=forum"
  echo "GATE_STATUS=active"
  echo "GATE_PASS_COUNT=${gates_passed}"
}

# ── Self-test ─────────────────────────────────────────────────────────────────
run_selftest() {
  local pass=0
  local fail_count=0

  selftest_pass() { echo "  PASS: $1"; pass=$((pass + 1)); }
  selftest_fail() { echo "  FAIL: $1" >&2; fail_count=$((fail_count + 1)); }

  echo "=== measure-session.sh --selftest (harness v${HARNESS_VERSION}) ==="

  # ── roundtable: 정상 케이스 ────────────────────────────────────────────────
  echo ""
  echo "--- [roundtable] 정상 케이스 ---"
  RT_VALID="$(cat <<'FIXTURE'
# Roundtable Meeting: 20240101-test

## 상태
- meeting-id: 20240101-test
- status: completed
- dissent-forcing-triggered: yes
- rebuttal-exchange: 2
- next-action: none

## 논의 기록
### Round 1
- core-claim: 마이크로서비스 전환이 유지보수성을 높인다
FIXTURE
)"

  rt_valid_out="$(parse_roundtable "$RT_VALID" 2>&1)" || true
  if echo "$rt_valid_out" | grep -q "PARSE_DISSENT_TRIGGERED=yes"; then
    selftest_pass "roundtable valid: dissent-forcing-triggered=yes 파싱"
  else
    selftest_fail "roundtable valid: dissent-forcing-triggered 파싱 실패"
  fi
  if echo "$rt_valid_out" | grep -q "PARSE_REBUTTAL_EXCHANGES=2"; then
    selftest_pass "roundtable valid: rebuttal-exchange=2 파싱"
  else
    selftest_fail "roundtable valid: rebuttal-exchange 파싱 실패"
  fi
  if echo "$rt_valid_out" | grep -q "PARSE_CORE_CLAIM_COUNT=1"; then
    selftest_pass "roundtable valid: core-claim=1 파싱"
  else
    selftest_fail "roundtable valid: core-claim count 파싱 실패"
  fi

  # ── roundtable: 다중 라운드 집계 케이스 ───────────────────────────────────
  echo ""
  echo "--- [roundtable] 다중 라운드 집계 케이스 (any-yes·합계) ---"
  RT_MULTI="$(cat <<'FIXTURE'
# Roundtable Meeting: 20240101-multi

## 상태
- meeting-id: 20240101-multi
- status: completed
- next-action: none

## 논의 기록
### Round 1
- core-claim: 첫 라운드 주장
- dissent-forcing-triggered: no
- rebuttal-exchange: 1
### Round 2
- core-claim: 둘째 라운드 주장
- dissent-forcing-triggered: no
- rebuttal-exchange: 0
### Round 3
- dissent-forcing-triggered: yes
- rebuttal-exchange: 1
FIXTURE
)"

  rt_multi_out="$(parse_roundtable "$RT_MULTI" 2>&1)" || true
  if echo "$rt_multi_out" | grep -q "PARSE_DISSENT_TRIGGERED=yes"; then
    selftest_pass "roundtable multi: dissent any-yes 집계 (no,no,yes → yes)"
  else
    selftest_fail "roundtable multi: dissent any-yes 집계 실패"
  fi
  if echo "$rt_multi_out" | grep -q "PARSE_REBUTTAL_EXCHANGES=2"; then
    selftest_pass "roundtable multi: rebuttal 합계 집계 (1+0+1 → 2)"
  else
    selftest_fail "roundtable multi: rebuttal 합계 집계 실패"
  fi

  # ── roundtable: 필수 마커 누락 케이스 ─────────────────────────────────────
  echo ""
  echo "--- [roundtable] 필수 마커 누락 케이스 (fail-loud 검증) ---"
  RT_MISSING="$(cat <<'FIXTURE'
# Roundtable Meeting: 20240101-missing

## 상태
- meeting-id: 20240101-missing
- status: completed
- next-action: none
FIXTURE
)"

  rt_missing_out="$(parse_roundtable "$RT_MISSING" 2>&1)" || true
  if echo "$rt_missing_out" | grep -q "ERROR"; then
    selftest_pass "roundtable missing: ERROR 메시지 포함"
  else
    selftest_fail "roundtable missing: ERROR 메시지 미포함 (fail-loud 위반)"
  fi
  if ! ( parse_roundtable "$RT_MISSING" > /dev/null 2>&1 ); then
    selftest_pass "roundtable missing: non-zero exit 확인"
  else
    selftest_fail "roundtable missing: zero exit (fail-loud 위반)"
  fi

  # ── roundtable: 손상된 마커(corrupt) 케이스 ───────────────────────────────
  echo ""
  echo "--- [roundtable] 손상된 마커(corrupt value) 케이스 ---"
  RT_CORRUPT="$(cat <<'FIXTURE'
# Roundtable Meeting: 20240101-corrupt

## 상태
- meeting-id: 20240101-corrupt
- status: completed
- dissent-forcing-triggered: maybe
- rebuttal-exchange: not-a-number
- next-action: none

## 논의 기록
### Round 1
- core-claim: 테스트 주장
FIXTURE
)"

  rt_corrupt_out="$(parse_roundtable "$RT_CORRUPT" 2>&1)" || true
  if echo "$rt_corrupt_out" | grep -qi "corrupt"; then
    selftest_pass "roundtable corrupt: 'corrupt' 포함 오류 메시지 출력"
  else
    selftest_fail "roundtable corrupt: 'corrupt' 미포함 (fail-loud 위반)"
  fi
  if ! ( parse_roundtable "$RT_CORRUPT" > /dev/null 2>&1 ); then
    selftest_pass "roundtable corrupt: non-zero exit 확인"
  else
    selftest_fail "roundtable corrupt: zero exit (fail-loud 위반)"
  fi

  # ── forum: 정상 케이스 ───────────────────────────────────────────────
  echo ""
  echo "--- [forum] 정상 케이스 ---"
  FORUM_VALID="$(cat <<'FIXTURE'
# Forum Session: 20240101-test

## 상태
- session-id: 20240101-test
- state: completed

## 아이디어 풀

### IDEA-001
- idea-id: IDEA-001
- parent-id: none
- status: parked
- park-recondition: 예산 확보 시 재검토
- core-fact: 클라우드 비용 최적화 효과가 실증됨
- independent-sources: 3

### IDEA-002
- idea-id: IDEA-002
- parent-id: IDEA-001
- status: eliminated
- elimination-reason: 기술 스택 호환 불가
FIXTURE
)"

  forum_valid_out="$(parse_forum "$FORUM_VALID" 2>&1)" || true
  if echo "$forum_valid_out" | grep -q "PARSE_PARKED_COUNT=1"; then
    selftest_pass "forum valid: parked=1 파싱"
  else
    selftest_fail "forum valid: parked 카운트 파싱 실패"
  fi
  if echo "$forum_valid_out" | grep -q "PARSE_ELIMINATED_COUNT=1"; then
    selftest_pass "forum valid: eliminated=1 파싱"
  else
    selftest_fail "forum valid: eliminated 카운트 파싱 실패"
  fi
  if echo "$forum_valid_out" | grep -q "PARSE_CORE_FACT_COUNT=1"; then
    selftest_pass "forum valid: core-fact=1 파싱"
  else
    selftest_fail "forum valid: core-fact 파싱 실패"
  fi
  if echo "$forum_valid_out" | grep -q "PARSE_INDEPENDENT_SOURCES=3"; then
    selftest_pass "forum valid: independent-sources=3 파싱"
  else
    selftest_fail "forum valid: independent-sources 파싱 실패"
  fi

  # ── forum: 다중 항목 집계 케이스 ─────────────────────────────────────
  echo ""
  echo "--- [forum] 다중 항목 집계 케이스 (independent-sources 최대값) ---"
  FORUM_MULTI="$(cat <<'FIXTURE'
# Forum Session: 20240101-multi

## 상태
- session-id: 20240101-multi
- state: completed

## 아이디어 풀

### IDEA-001
- idea-id: IDEA-001
- status: shortlisted
- core-fact: 사실 A
- independent-sources: 1

### IDEA-002
- idea-id: IDEA-002
- status: shortlisted
- core-fact: 사실 B
- independent-sources: 3

### IDEA-003
- idea-id: IDEA-003
- status: shortlisted
- core-fact: 사실 C
- independent-sources: 0
FIXTURE
)"

  forum_multi_out="$(parse_forum "$FORUM_MULTI" 2>&1)" || true
  if echo "$forum_multi_out" | grep -q "PARSE_INDEPENDENT_SOURCES=3"; then
    selftest_pass "forum multi: independent-sources 최대값 집계 (1,3,0 → 3)"
  else
    selftest_fail "forum multi: independent-sources 최대값 집계 실패"
  fi

  # ── forum: 블록 단위 부분 누락 케이스 (100% 충족률 강제) ─────────────
  echo ""
  echo "--- [forum] 블록 단위 부분 누락 케이스 (전역 1건으로 우회 불가) ---"
  FORUM_PARTIAL="$(cat <<'FIXTURE'
# Forum Session: 20240101-partial

## 상태
- session-id: 20240101-partial
- state: completed

## 아이디어 풀

### IDEA-001
- idea-id: IDEA-001
- status: parked
- park-recondition: 예산 확보 시 재검토
- core-fact: 사실 A
- independent-sources: 2

### IDEA-002
- idea-id: IDEA-002
- status: parked
- core-fact: 사실 B
- independent-sources: 2
FIXTURE
)"

  forum_partial_out="$(parse_forum "$FORUM_PARTIAL" 2>&1)" || true
  if echo "$forum_partial_out" | grep -q "누락 블록 1/2"; then
    selftest_pass "forum partial: park-recondition 누락 블록 1/2 검출"
  else
    selftest_fail "forum partial: 블록 단위 누락 미검출 (전역 카운트 우회 — 게이트 오판정)"
  fi
  if ! ( parse_forum "$FORUM_PARTIAL" > /dev/null 2>&1 ); then
    selftest_pass "forum partial: non-zero exit 확인"
  else
    selftest_fail "forum partial: zero exit (fail-loud 위반)"
  fi

  # ── forum: 필수 마커 누락 케이스 ────────────────────────────────────
  echo ""
  echo "--- [forum] 필수 마커 누락 케이스 (fail-loud 검증) ---"
  FORUM_MISSING="$(cat <<'FIXTURE'
# Forum Session: 20240101-missing

## 상태
- session-id: 20240101-missing
- state: completed

## 아이디어 풀

### IDEA-001
- idea-id: IDEA-001
- parent-id: none
- status: parked
FIXTURE
)"
  # parked 존재하나 park-recondition 없음, core-fact 없음, independent-sources 없음

  forum_missing_out="$(parse_forum "$FORUM_MISSING" 2>&1)" || true
  if echo "$forum_missing_out" | grep -q "ERROR"; then
    selftest_pass "forum missing: ERROR 메시지 포함"
  else
    selftest_fail "forum missing: ERROR 메시지 미포함 (fail-loud 위반)"
  fi
  if ! ( parse_forum "$FORUM_MISSING" > /dev/null 2>&1 ); then
    selftest_pass "forum missing: non-zero exit 확인"
  else
    selftest_fail "forum missing: zero exit (fail-loud 위반)"
  fi

  # ── forum: 손상된 마커(corrupt) 케이스 ──────────────────────────────
  echo ""
  echo "--- [forum] 손상된 마커(corrupt value) 케이스 ---"
  FORUM_CORRUPT="$(cat <<'FIXTURE'
# Forum Session: 20240101-corrupt

## 상태
- session-id: 20240101-corrupt
- state: completed

## 아이디어 풀

### IDEA-001
- idea-id: IDEA-001
- parent-id: none
- status: parked
- park-recondition: 예산 확보 시 재검토
- core-fact: 실증된 사실
- independent-sources: not-a-number
FIXTURE
)"

  forum_corrupt_out="$(parse_forum "$FORUM_CORRUPT" 2>&1)" || true
  if echo "$forum_corrupt_out" | grep -qi "corrupt"; then
    selftest_pass "forum corrupt: 'corrupt' 포함 오류 메시지 출력"
  else
    selftest_fail "forum corrupt: 'corrupt' 미포함 (fail-loud 위반)"
  fi
  if ! ( parse_forum "$FORUM_CORRUPT" > /dev/null 2>&1 ); then
    selftest_pass "forum corrupt: non-zero exit 확인"
  else
    selftest_fail "forum corrupt: zero exit (fail-loud 위반)"
  fi

  # ── 결과 집계 ─────────────────────────────────────────────────────────────
  echo ""
  echo "=== selftest 결과: ${pass}개 통과 / $((pass + fail_count))개 전체 ==="
  if [[ "$fail_count" -gt 0 ]]; then
    echo "SELFTEST FAILED: ${fail_count}개 실패" >&2
    exit 1
  fi
  echo "SELFTEST PASSED"
}

# ── 인자 파싱 ─────────────────────────────────────────────────────────────────
SELFTEST=false
JUDGE=false
SKILL=""
RECORD_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --selftest)  SELFTEST=true; shift ;;
    --judge)     JUDGE=true; shift ;;
    --skill)     SKILL="$2"; shift 2 ;;
    --record)    RECORD_PATH="$2"; shift 2 ;;
    *) usage ;;
  esac
done

# ── 메인 디스패치 ─────────────────────────────────────────────────────────────
if $SELFTEST; then
  run_selftest
  exit 0
fi

[[ -n "$SKILL" ]]       || { echo "ERROR: --skill 필요" >&2; usage; }
[[ -n "$RECORD_PATH" ]] || { echo "ERROR: --record 필요" >&2; usage; }
[[ -f "$RECORD_PATH" ]] || fail "레코드 파일 없음: $RECORD_PATH"

CONTENT="$(cat "$RECORD_PATH")"

case "$SKILL" in
  roundtable)
    if $JUDGE; then judge_roundtable "$CONTENT"
    else parse_roundtable "$CONTENT"
    fi
    ;;
  forum)
    if $JUDGE; then judge_forum "$CONTENT"
    else parse_forum "$CONTENT"
    fi
    ;;
  *) fail "알 수 없는 스킬: $SKILL (roundtable|forum 중 선택)" ;;
esac
