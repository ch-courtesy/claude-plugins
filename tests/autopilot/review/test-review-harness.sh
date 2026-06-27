#!/usr/bin/env bash
# test-review-harness.sh
#
# autopilot:review 결정적 하니스(review.sh)의 행위 계약 테스트.
# 외부 인터페이스(diff 수집·SPEC 기준·lens 리뷰·스레드 조회)를 모두 주입 가능한
# 명령 변수로 mock 치환하여, 실제 PR·브랜치 아티팩트 없이 mock 만으로 검증한다.
#
# 검증 대상 (수용 기준 매핑):
#  H1  fingerprint: file+perspective+정규화제목 안정, 라인/케이스/공백 무관   (AC5)
#  H2  fingerprint: file 또는 perspective 다르면 값 다름                       (AC5)
#  H3  run: 정확히 하나의 pipeline_verdict(approve|request_changes|unavailable) (AC1)
#  H4  diff 잘림 → unavailable, approve 아님                                    (AC4)
#  H5  lens context_incomplete → unavailable, approve 아님                      (AC4)
#  H6  evidence/신뢰도 게이트: conf<80 또는 증거 누락 finding 출력 제외          (AC3)
#  H7  dedup: 기존 스레드 fingerprint 와 동일 finding 은 skipped_duplicates 로   (AC5)
#  H8  blocking finding → request_changes + rework_brief 3분류 동봉              (AC1/AC6)
#  H9  안전경계(보안 등) blocking 은 adoption=defer 라도 must_adopt 로 고정      (AC6)
#  H10 acceptance_coverage(total/verified/unverified) 출력                       (AC7)
#  H11 미검증 수용기준 잔존 → approve 아님                                       (AC7)
#  H12 전부 통과(검증완료·blocking 없음·컨텍스트 온전) → approve                 (AC1/AC7)
#  H13 selftest 서브커맨드 mock 만으로 0 exit                                    (AC8)
#  H14 list: 빈 상태에서도 0 exit                                               (AC1)
#  H15 status: run 후 마지막 판정 조회                                          (공개표면)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVIEW_SH="$SCRIPT_DIR/../../../plugins/autopilot/skills/review/references/review.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

command -v jq >/dev/null 2>&1 || fail "jq 필요 (테스트 전제)"
[[ -f "$REVIEW_SH" ]] || fail "review.sh 부재: $REVIEW_SH"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export REVIEW_STATE_DIR="$WORK/state"

# ---------------------------------------------------------------------------
# mock 명령 팩토리 — 주입 가능 인터페이스를 셸 스크립트 파일로 만든다.
# ---------------------------------------------------------------------------
mk_ctx() { # $1=truncated $2=context_incomplete -> ctx mock
  local f="$WORK/ctx-$RANDOM.sh"
  cat > "$f" <<EOF
#!/usr/bin/env bash
cat <<'JSON'
{"base_sha":"base000","head_sha":"head111","diff_truncated":$1,"context_incomplete":$2,"files_reviewed":["plugins/x.sh"],"related_files_reviewed":[],"skipped_files":[]}
JSON
EOF
  chmod +x "$f"; echo "$f"
}

mk_spec() { # $1=json array of acceptance ids
  local f="$WORK/spec-$RANDOM.sh"
  cat > "$f" <<EOF
#!/usr/bin/env bash
echo '{"acceptance":$1}'
EOF
  chmod +x "$f"; echo "$f"
}

mk_lens() { # $1=findings json array $2=verified json array $3=context_incomplete
  local f="$WORK/lens-$RANDOM.sh"
  cat > "$f" <<EOF
#!/usr/bin/env bash
echo '{"findings":$1,"verified_criteria":$2,"context_incomplete":$3}'
EOF
  chmod +x "$f"; echo "$f"
}

mk_threads() { # $1=newline fingerprints (literal)
  local f="$WORK/threads-$RANDOM.sh"
  cat > "$f" <<EOF
#!/usr/bin/env bash
printf '%s\n' $1
EOF
  chmod +x "$f"; echo "$f"
}

# 잘 갖춰진 finding (게이트 통과: file/line/body/suggestion + conf>=80)
GOOD_BLOCKING='[{"severity":"blocking","confidence_score":90,"review_perspective":"bug","comment_type":"inline","file":"plugins/x.sh","line":12,"start_line":12,"title":"널 역참조","body":"입력이 비면 NPE 경로","suggestion":"가드 추가","adoption":"must_adopt"}]'
GOOD_NONBLOCK='[{"severity":"non_blocking","confidence_score":85,"review_perspective":"guideline","comment_type":"inline","file":"plugins/x.sh","line":3,"start_line":3,"title":"명명 개선","body":"가독성","suggestion":"이름 변경","adoption":"wont_adopt"}]'

run_review() { # uses env mocks; prints JSON
  bash "$REVIEW_SH" run --task "$1"
}

# === H1: fingerprint 안정성 (라인/케이스/공백 무관) ===
echo "=== H1: fingerprint 안정성 ==="
fp1="$(bash "$REVIEW_SH" fingerprint "a/b.sh" "bug" "Null Deref Found")"
fp2="$(bash "$REVIEW_SH" fingerprint "a/b.sh" "bug" "  null   deref FOUND  ")"
[[ -n "$fp1" ]] || fail "H1: fingerprint 빈 값"
[[ "$fp1" == "$fp2" ]] || fail "H1: 정규화(케이스/공백) 후 동일해야: '$fp1' vs '$fp2'"
ok "H1 fingerprint 정규화 안정 ($fp1)"

# === H2: fingerprint 변별 (file/perspective) ===
echo "=== H2: fingerprint 변별 ==="
fp3="$(bash "$REVIEW_SH" fingerprint "a/c.sh" "bug" "Null Deref Found")"
fp4="$(bash "$REVIEW_SH" fingerprint "a/b.sh" "guideline" "Null Deref Found")"
[[ "$fp1" != "$fp3" ]] || fail "H2: file 다르면 fingerprint 달라야"
[[ "$fp1" != "$fp4" ]] || fail "H2: perspective 다르면 fingerprint 달라야"
ok "H2 fingerprint 변별"

# 공통 mock 환경 export 헬퍼
set_mocks() {
  export REVIEW_DIFF_CMD="$1" REVIEW_SPEC_CMD="$2" REVIEW_LENS_CMD="$3" REVIEW_THREADS_CMD="$4"
}

# === H3: 정확히 하나의 pipeline_verdict ===
echo "=== H3: 단일 pipeline_verdict ==="
set_mocks "$(mk_ctx false false)" "$(mk_spec '["AC1"]')" "$(mk_lens "$GOOD_NONBLOCK" '["AC1"]' false)" "$(mk_threads '')"
out="$(run_review t3)" || fail "H3: run 비정상 종료"
echo "$out" | jq -e . >/dev/null 2>&1 || fail "H3: 유효 JSON 아님"
v="$(echo "$out" | jq -r '.pipeline_verdict')"
case "$v" in approve|request_changes|unavailable) ok "H3 verdict=$v";; *) fail "H3: 잘못된 verdict '$v'";; esac

# === H4: diff 잘림 → unavailable ===
echo "=== H4: diff 잘림 → unavailable ==="
set_mocks "$(mk_ctx true false)" "$(mk_spec '["AC1"]')" "$(mk_lens "$GOOD_NONBLOCK" '["AC1"]' false)" "$(mk_threads '')"
out="$(run_review t4)" || fail "H4: run 비정상 종료"
v="$(echo "$out" | jq -r '.pipeline_verdict')"
[[ "$v" == "unavailable" ]] || fail "H4: diff 잘림인데 verdict=$v (unavailable 기대)"
[[ "$v" != "approve" ]] || fail "H4: approve 금지 위반"
ok "H4 truncated → unavailable"

# === H5: lens context_incomplete → unavailable ===
echo "=== H5: context_incomplete → unavailable ==="
set_mocks "$(mk_ctx false false)" "$(mk_spec '["AC1"]')" "$(mk_lens '[]' '["AC1"]' true)" "$(mk_threads '')"
out="$(run_review t5)" || fail "H5: run 비정상 종료"
v="$(echo "$out" | jq -r '.pipeline_verdict')"
[[ "$v" == "unavailable" ]] || fail "H5: context_incomplete 인데 verdict=$v"
ok "H5 context_incomplete → unavailable"

# === H6: evidence/신뢰도 게이트 ===
echo "=== H6: 게이트 제외 ==="
# 3 finding: (a) 통과, (b) conf<80, (c) suggestion 누락
GATE='[
 {"severity":"non_blocking","confidence_score":88,"review_perspective":"bug","comment_type":"inline","file":"plugins/x.sh","line":5,"start_line":5,"title":"keep me","body":"실패 경로","suggestion":"고쳐라","adoption":"defer"},
 {"severity":"non_blocking","confidence_score":40,"review_perspective":"bug","comment_type":"inline","file":"plugins/x.sh","line":6,"start_line":6,"title":"low conf","body":"b","suggestion":"s","adoption":"defer"},
 {"severity":"non_blocking","confidence_score":95,"review_perspective":"bug","comment_type":"inline","file":"plugins/x.sh","line":7,"start_line":7,"title":"no suggestion","body":"b","suggestion":"","adoption":"defer"}
]'
set_mocks "$(mk_ctx false false)" "$(mk_spec '["AC1"]')" "$(mk_lens "$GATE" '["AC1"]' false)" "$(mk_threads '')"
out="$(run_review t6)" || fail "H6: run 비정상 종료"
n="$(echo "$out" | jq '.findings | length')"
[[ "$n" == "1" ]] || fail "H6: 게이트 후 findings=$n (1 기대)"
title="$(echo "$out" | jq -r '.findings[0].title')"
[[ "$title" == "keep me" ]] || fail "H6: 잘못된 finding 유지 '$title'"
ok "H6 게이트: 1개만 유지"

# === H7: dedup ===
echo "=== H7: dedup ==="
# 동일 finding 의 fingerprint 를 미리 계산해 기존 스레드로 주입
dfp="$(bash "$REVIEW_SH" fingerprint "plugins/x.sh" "bug" "keep me")"
KEEP1='[{"severity":"non_blocking","confidence_score":88,"review_perspective":"bug","comment_type":"inline","file":"plugins/x.sh","line":5,"start_line":5,"title":"keep me","body":"실패","suggestion":"s","adoption":"defer"}]'
set_mocks "$(mk_ctx false false)" "$(mk_spec '["AC1"]')" "$(mk_lens "$KEEP1" '["AC1"]' false)" "$(mk_threads "$dfp")"
out="$(run_review t7)" || fail "H7: run 비정상 종료"
n="$(echo "$out" | jq '.findings | length')"
ndup="$(echo "$out" | jq '.skipped_duplicates | length')"
[[ "$n" == "0" ]] || fail "H7: dedup 안 됨 findings=$n"
[[ "$ndup" == "1" ]] || fail "H7: skipped_duplicates=$ndup (1 기대)"
ok "H7 dedup → skipped_duplicates"

# === H8: blocking → request_changes + rework_brief ===
echo "=== H8: blocking → request_changes + rework_brief ==="
set_mocks "$(mk_ctx false false)" "$(mk_spec '["AC1"]')" "$(mk_lens "$GOOD_BLOCKING" '["AC1"]' false)" "$(mk_threads '')"
out="$(run_review t8)" || fail "H8: run 비정상 종료"
v="$(echo "$out" | jq -r '.pipeline_verdict')"
[[ "$v" == "request_changes" ]] || fail "H8: blocking 인데 verdict=$v"
mustn="$(echo "$out" | jq '.rework_brief.must_adopt | length')"
[[ "$mustn" -ge 1 ]] || fail "H8: rework_brief.must_adopt 비어있음"
ok "H8 blocking → request_changes + rework"

# === H9: 안전경계 must_adopt 고정 ===
echo "=== H9: 안전경계 고정 ==="
SEC='[{"severity":"blocking","confidence_score":92,"review_perspective":"bug","comment_type":"inline","file":"plugins/x.sh","line":9,"start_line":9,"title":"보안 우회 가능","body":"권한 검사 누락으로 보안 경계 붕괴","suggestion":"검사 추가","adoption":"defer"}]'
set_mocks "$(mk_ctx false false)" "$(mk_spec '["AC1"]')" "$(mk_lens "$SEC" '["AC1"]' false)" "$(mk_threads '')"
out="$(run_review t9)" || fail "H9: run 비정상 종료"
inmust="$(echo "$out" | jq -r '.rework_brief.must_adopt[].title' | grep -c '보안 우회 가능')"
indefer="$(echo "$out" | jq -r '.rework_brief.defer[].title' 2>/dev/null | grep -c '보안 우회 가능' || true)"
[[ "$inmust" -ge 1 ]] || fail "H9: 안전경계 finding 이 must_adopt 에 없음(adoption=defer 무시 안 됨)"
[[ "$indefer" == "0" ]] || fail "H9: 안전경계 finding 이 defer 로 강등됨"
ok "H9 안전경계 must_adopt 고정"

# === H10/H11: coverage + 미검증 → approve 아님 ===
echo "=== H10/H11: coverage ==="
set_mocks "$(mk_ctx false false)" "$(mk_spec '["AC1","AC2","AC3"]')" "$(mk_lens '[]' '["AC1","AC2"]' false)" "$(mk_threads '')"
out="$(run_review t10)" || fail "H10: run 비정상 종료"
tot="$(echo "$out" | jq -r '.acceptance_coverage.total')"
ver="$(echo "$out" | jq -r '.acceptance_coverage.verified')"
unv="$(echo "$out" | jq -r '.acceptance_coverage.unverified | length')"
[[ "$tot" == "3" && "$ver" == "2" && "$unv" == "1" ]] || fail "H10: coverage total=$tot ver=$ver unv=$unv (3/2/1 기대)"
v="$(echo "$out" | jq -r '.pipeline_verdict')"
[[ "$v" != "approve" ]] || fail "H11: 미검증 AC 잔존인데 approve"
ok "H10/H11 coverage 3/2/1, 미검증 → approve 아님 (verdict=$v)"

# === H12: 전부 통과 → approve ===
echo "=== H12: approve ==="
set_mocks "$(mk_ctx false false)" "$(mk_spec '["AC1","AC2"]')" "$(mk_lens '[]' '["AC1","AC2"]' false)" "$(mk_threads '')"
out="$(run_review t12)" || fail "H12: run 비정상 종료"
v="$(echo "$out" | jq -r '.pipeline_verdict')"
[[ "$v" == "approve" ]] || fail "H12: 전부 통과인데 verdict=$v (approve 기대)"
ok "H12 approve"

# === H13: selftest 서브커맨드 ===
echo "=== H13: selftest ==="
bash "$REVIEW_SH" selftest >/dev/null 2>&1 || fail "H13: selftest 비정상 종료"
ok "H13 selftest 0 exit"

# === H14: list 빈 상태 0 exit ===
echo "=== H14: list 빈 상태 ==="
export REVIEW_STATE_DIR="$WORK/empty-state"
bash "$REVIEW_SH" list >/dev/null 2>&1 || fail "H14: 빈 list 비정상 종료"
ok "H14 list 빈 상태 0 exit"

# === H15: status 마지막 판정 ===
echo "=== H15: status ==="
export REVIEW_STATE_DIR="$WORK/state2"
set_mocks "$(mk_ctx false false)" "$(mk_spec '["AC1"]')" "$(mk_lens "$GOOD_BLOCKING" '["AC1"]' false)" "$(mk_threads '')"
run_review t15 >/dev/null || fail "H15: run 실패"
st="$(bash "$REVIEW_SH" status --task t15)" || fail "H15: status 실패"
echo "$st" | grep -q "request_changes" || fail "H15: status 에 마지막 판정 없음"
ok "H15 status 마지막 판정 노출"

# === H16: 스레드 라이프사이클 — resolved vs unresolved ===
echo "=== H16: 스레드 라이프사이클 ==="
export REVIEW_STATE_DIR="$WORK/state3"
# 현재 라운드에 제기되는 finding 의 fp (still raised) + 이미 사라진 fp (resolved)
stillfp="$(bash "$REVIEW_SH" fingerprint "plugins/x.sh" "bug" "keep me")"
gonefp="aaaaaaaaaaaa"
STILL='[{"severity":"non_blocking","confidence_score":88,"review_perspective":"bug","comment_type":"inline","file":"plugins/x.sh","line":5,"start_line":5,"title":"keep me","body":"실패","suggestion":"s","adoption":"defer"}]'
set_mocks "$(mk_ctx false false)" "$(mk_spec '["AC1"]')" "$(mk_lens "$STILL" '["AC1"]' false)" "$(mk_threads "$stillfp $gonefp")"
out="$(run_review t16)" || fail "H16: run 비정상 종료"
res="$(echo "$out" | jq -r '.resolved_threads[].fingerprint')"
unres="$(echo "$out" | jq -r '.unresolved_threads[].fingerprint')"
echo "$res"   | grep -q "$gonefp"  || fail "H16: 사라진 스레드가 resolved 에 없음"
echo "$res"   | grep -q "$stillfp" && fail "H16: 유지 스레드가 잘못 resolved 됨" || true
echo "$unres" | grep -q "$stillfp" || fail "H16: 유지 스레드가 unresolved 에 없음"
ok "H16 스레드 라이프사이클: resolved=$gonefp, unresolved=$stillfp"

# === H17: automation_safety.may_approve = (pipeline_verdict==approve) ===
# may_approve 는 verdict 에서 결정적으로 파생된다(review.sh:180). CI claude-review
# 게이트(claude-review.yml)도 동일 규칙(verdict 파생)이어야 하며(#480), 모델 자가판정에
# 의존하지 않는다. 이 불변식이 하니스·CI 양쪽 산출의 단일 출처다.
echo "=== H17: may_approve = (verdict==approve) 파생 불변식 ==="
export REVIEW_STATE_DIR="$WORK/state-h17a"
set_mocks "$(mk_ctx false false)" "$(mk_spec '["AC1","AC2"]')" "$(mk_lens '[]' '["AC1","AC2"]' false)" "$(mk_threads '')"
out="$(run_review t17a)" || fail "H17a: run 비정상 종료"
v="$(echo "$out" | jq -r '.pipeline_verdict')"
ma="$(echo "$out" | jq -r '.automation_safety.may_approve')"
[[ "$v" == "approve" && "$ma" == "true" ]] || fail "H17a: approve 인데 may_approve=$ma (true 기대)"
export REVIEW_STATE_DIR="$WORK/state-h17b"
set_mocks "$(mk_ctx false false)" "$(mk_spec '["AC1"]')" "$(mk_lens "$GOOD_BLOCKING" '["AC1"]' false)" "$(mk_threads '')"
out="$(run_review t17b)" || fail "H17b: run 비정상 종료"
v="$(echo "$out" | jq -r '.pipeline_verdict')"
ma="$(echo "$out" | jq -r '.automation_safety.may_approve')"
[[ "$v" != "approve" && "$ma" == "false" ]] || fail "H17b: non-approve(verdict=$v)인데 may_approve=$ma (false 기대)"
# CI 게이트(claude-review.yml)가 모델 자가판정이 아니라 verdict 파생임을 교차 확인.
# 플러그인 자기완결을 위해 파일이 있을 때만 검사한다(소비 리포 밖 설치 시 graceful skip).
CI_WORKFLOW="${CI_WORKFLOW:-$SCRIPT_DIR/../../../.github/workflows/claude-review.yml}"
if [[ -f "$CI_WORKFLOW" ]]; then
  if grep -qF 'r.automation_safety?.may_approve' "$CI_WORKFLOW"; then
    fail "H17: CI 게이트가 모델 자가판정 automation_safety.may_approve 에 의존 — verdict 파생 불일치 (#480)"
  fi
fi
ok "H17 may_approve 파생 불변식 (하니스·CI 일관)"

echo ""
echo "ALL HARNESS TESTS PASSED"
