#!/usr/bin/env bash
# test-loop-stop-orphan-guard.sh
#
# SPEC: loop stop 워커 트리 완결 종료 + orphan 워커 감지(거짓 "정상 정지" 근절).
#
# 주입 가능 프로세스 인터페이스(proc_alive/proc_term/proc_kill/proc_sleep/proc_children)를
# 모사 프로세스 테이블로 override 해 실제 워커·LLM 없이 결정적으로 검증한다.
#
# 검증 대상 (완료 조건 매핑):
#  C1 stop 이 워커 트리(driver·자식·자손)를 종료하고 전 프로세스 사망 확인 후에만
#     락 해제 + 정상 정지 선언
#  C2 SIGTERM→SIGKILL 에스컬레이션, 생존 잔존 시 락 유지 + 비-0(정상 정지 금지)
#  C3 start/acquire_lock 활성 판정에 worker(orphan 포함) 생존 반영 → 더블 start 거부
#  C4 stale(driver·worker 모두 사망) → 락 정리 후 진행
#  C5 주입 가능 인터페이스 결정적 selftest (본 파일 자체가 증거)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP_SH="$SCRIPT_DIR/../references/loop.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git 미설치"; exit 0; }

# loop.sh source — dispatcher 는 BASH_SOURCE guard 로 비실행.
# shellcheck source=../references/loop.sh
source "$LOOP_SH"
# loop.sh 는 `set -euo pipefail` 을 켜므로, 의도적 비-0 rc 캡처(stop 실패 경로 등)가
# errexit 로 테스트를 중단시키지 않게 errexit 만 해제한다(테스트가 rc 를 직접 검사).
set +e

fail=0
pass() { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; fail=1; }

# ---------------------------------------------------------------------------
# 모사 프로세스 테이블 + 주입 인터페이스 override
#   PALIVE[pid]=1            살아있음
#   PCHILDREN[pid]="c1 c2"   직계 자식
#   POLICY[pid]=term|kill|immortal
#       term     : SIGTERM 에 죽음 (기본)
#       kill     : SIGTERM 무시, SIGKILL 에만 죽음
#       immortal : SIGTERM·SIGKILL 모두 무시 (실패 경로 강제)
# ---------------------------------------------------------------------------
declare -A PALIVE PCHILDREN POLICY

proc_alive()    { [[ "${PALIVE[$1]:-0}" == 1 ]]; }
proc_children() { printf '%s\n' ${PCHILDREN[$1]:-}; }
proc_sleep()    { :; }   # 결정적 — 실제 대기 없음
proc_term()     { local p=$1; [[ "${POLICY[$p]:-term}" == term ]] && PALIVE[$p]=0; return 0; }
proc_kill()     { local p=$1; [[ "${POLICY[$p]:-term}" != immortal ]] && PALIVE[$p]=0; return 0; }

reset_table() { PALIVE=(); PCHILDREN=(); POLICY=(); }

# ---------------------------------------------------------------------------
# A. run_active — 활성 판정 (C3·C4)
# ---------------------------------------------------------------------------
reset_table
PALIVE[100]=1   # driver alive
run_active 100 "" && pass "A1 running(driver alive)=active" || bad "A1 running"

reset_table
PALIVE[200]=0; PALIVE[201]=1   # driver dead, worker alive (orphan)
run_active 200 201 && pass "A2 orphan(worker alive)=active" || bad "A2 orphan"

reset_table
PALIVE[300]=0; PALIVE[301]=0   # both dead (stale)
run_active 300 301 && bad "A3 stale must be inactive" || pass "A3 stale=inactive"

# ---------------------------------------------------------------------------
# B. tree_pids — 트리 스냅샷 (C1)
# ---------------------------------------------------------------------------
reset_table
PALIVE[10]=1; PALIVE[11]=1; PALIVE[12]=1
PCHILDREN[10]="11"; PCHILDREN[11]="12"
snap=$(tree_pids 10 | grep -E '^[0-9]+$' | sort -un | tr '\n' ' ')
[[ "$snap" == "10 11 12 " ]] && pass "B1 tree snapshot incl descendants" || bad "B1 tree snapshot got: $snap"

# ---------------------------------------------------------------------------
# C. terminate_pids — SIGTERM→SIGKILL 에스컬레이션 (C2)
# ---------------------------------------------------------------------------
# C1: 전부 term 정책 → SIGTERM 으로 사망, 생존자 없음
reset_table
PALIVE[20]=1; PALIVE[21]=1; POLICY[20]=term; POLICY[21]=term
surv=$(TERM_WAIT_TRIES=2 KILL_WAIT_TRIES=2 terminate_pids "$(printf '20\n21\n')")
[[ -z "$surv" ]] && pass "C-term all die on SIGTERM" || bad "C-term survivors: $surv"

# C2: kill 정책 → SIGTERM 무시, SIGKILL 에스컬레이션으로 사망
reset_table
PALIVE[30]=1; POLICY[30]=kill
surv=$(TERM_WAIT_TRIES=2 KILL_WAIT_TRIES=2 terminate_pids "30")
[[ -z "$surv" ]] && pass "C-kill escalation kills survivor" || bad "C-kill survivors: $surv"

# C3: immortal → SIGTERM·SIGKILL 모두 무시 → 생존자 보고
reset_table
PALIVE[40]=1; POLICY[40]=immortal
surv=$(TERM_WAIT_TRIES=2 KILL_WAIT_TRIES=2 terminate_pids "40" | tr '\n' ' ')
[[ "$surv" == *40* ]] && pass "C-immortal reported as survivor" || bad "C-immortal expected survivor: $surv"

# ---------------------------------------------------------------------------
# 통합: 임시 git repo + cmd_stop / acquire_lock (C1·C2·C3·C4)
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP"
( cd "$TMP" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
SPEC_DIR_T="$TMP/s"
mkdir -p "$SPEC_DIR_T"
SPEC_T="$SPEC_DIR_T/SPEC.md"
printf -- '---\nscope: {include: ["**"]}\n---\n# t\n' > "$SPEC_T"

# D1: cmd_stop 정상 — driver+worker term 정책 → 트리 사망 → exit 0, 락·워커파일 제거 (C1)
reset_table
PALIVE[500]=1; PALIVE[501]=1; PCHILDREN[500]="501"; POLICY[500]=term; POLICY[501]=term
echo 500 > "$SPEC_DIR_T/.loop-lock"
echo 501 > "$SPEC_DIR_T/.loop-worker"
( TERM_WAIT_TRIES=2 KILL_WAIT_TRIES=2 cmd_stop "$SPEC_T" ) >/dev/null 2>&1
rc=$?
if [[ $rc -eq 0 && ! -f "$SPEC_DIR_T/.loop-lock" && ! -f "$SPEC_DIR_T/.loop-worker" ]]; then
  pass "D1 stop success removes lock+worker after tree death"
else
  bad "D1 stop rc=$rc lock=$([[ -f $SPEC_DIR_T/.loop-lock ]] && echo y || echo n) worker=$([[ -f $SPEC_DIR_T/.loop-worker ]] && echo y || echo n)"
fi

# D2: cmd_stop 생존 — worker immortal → SIGKILL 후에도 생존 → 비-0, 락·워커파일 유지 (C2)
reset_table
PALIVE[600]=1; PALIVE[601]=1; PCHILDREN[600]="601"; POLICY[600]=term; POLICY[601]=immortal
echo 600 > "$SPEC_DIR_T/.loop-lock"
echo 601 > "$SPEC_DIR_T/.loop-worker"
out=$( ( TERM_WAIT_TRIES=2 KILL_WAIT_TRIES=2 cmd_stop "$SPEC_T" ) 2>&1 )
rc=$?
# 성공 선언은 "...전 프로세스 사망 확인" 마커로 식별(실패 메시지의 "정상 정지 선언
# 안 함" 부분 문자열과 구분).
if [[ $rc -ne 0 && -f "$SPEC_DIR_T/.loop-lock" && -f "$SPEC_DIR_T/.loop-worker" ]] \
   && [[ "$out" != *"사망 확인"* ]]; then
  pass "D2 stop with immortal survivor: non-0, lock retained, no success declaration"
else
  bad "D2 stop rc=$rc lock_kept=$([[ -f $SPEC_DIR_T/.loop-lock ]] && echo y || echo n) out=$out"
fi
rm -f "$SPEC_DIR_T/.loop-lock" "$SPEC_DIR_T/.loop-worker"

# D3: cmd_stop stale — driver·worker 모두 사망 → 락 정리 후 exit 0 (C4)
reset_table
PALIVE[700]=0; PALIVE[701]=0
echo 700 > "$SPEC_DIR_T/.loop-lock"
echo 701 > "$SPEC_DIR_T/.loop-worker"
( cmd_stop "$SPEC_T" ) >/dev/null 2>&1
rc=$?
if [[ $rc -eq 0 && ! -f "$SPEC_DIR_T/.loop-lock" ]]; then
  pass "D3 stop stale cleans lock, exit 0"
else
  bad "D3 stop stale rc=$rc lock=$([[ -f $SPEC_DIR_T/.loop-lock ]] && echo y || echo n)"
fi

# E1: acquire_lock orphan — driver dead, worker alive → 거부(비-0), 락 유지 (C3)
reset_table
PALIVE[800]=0; PALIVE[801]=1
echo 800 > "$SPEC_DIR_T/.loop-lock"
echo 801 > "$SPEC_DIR_T/.loop-worker"
( compute_paths "$SPEC_T"; acquire_lock ) >/dev/null 2>&1
rc=$?
if [[ $rc -ne 0 && -f "$SPEC_DIR_T/.loop-lock" ]]; then
  pass "E1 acquire_lock rejects orphan(worker alive)"
else
  bad "E1 acquire_lock orphan rc=$rc lock=$([[ -f $SPEC_DIR_T/.loop-lock ]] && echo y || echo n)"
fi
rm -f "$SPEC_DIR_T/.loop-lock" "$SPEC_DIR_T/.loop-worker"

# E2: acquire_lock stale — 둘 다 사망 → 진행(exit 0)
reset_table
PALIVE[900]=0; PALIVE[901]=0
echo 900 > "$SPEC_DIR_T/.loop-lock"
echo 901 > "$SPEC_DIR_T/.loop-worker"
( compute_paths "$SPEC_T"; acquire_lock ) >/dev/null 2>&1
rc=$?
[[ $rc -eq 0 ]] && pass "E2 acquire_lock proceeds on stale" || bad "E2 acquire_lock stale rc=$rc"

echo
if [[ $fail -eq 0 ]]; then
  echo "ALL CHECKS PASSED"
else
  echo "SOME CHECKS FAILED"; exit 1
fi
