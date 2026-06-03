#!/usr/bin/env bash
# autopilot:dispatch 통합 시나리오 — spec-list-driven 재설계 (v0.8+)
#
# SPEC frontmatter 로부터 DAG 를 추론하고, wave 단위로 mock loop 실행기에 위임하며,
# run-id 디렉토리에 상태를 보관하고, list/status/watch/stop/--resume 가 작동하는지 검증.
# 실제 loop.sh 는 호출하지 않는다: LOOP_CMD 환경변수로 mock 셸로 치환.

set -euo pipefail

# 일부 CI/loop 환경이 GIT_AUTHOR_*/GIT_COMMITTER_* 를 빈 문자열로 export 하면
# git config(user.name/email)를 덮어써 git commit 이 "empty ident name" 으로 실패한다.
# 임시 repo 의 로컬 config 가 적용되도록 빈 ident 환경변수를 해제한다.
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL 2>/dev/null || true

REPO_ROOT="$(git rev-parse --show-toplevel)"
DISPATCH_SH="$REPO_ROOT/plugins/autopilot/skills/dispatch/references/dispatch.sh"
[[ -x "$DISPATCH_SH" ]] || { echo "FAIL: dispatch.sh 실행 권한 없음"; exit 1; }

WORK_DIR="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf $WORK_DIR" EXIT

PROJECT="$WORK_DIR/proj"
mkdir -p "$PROJECT"
cd "$PROJECT"
git init -q
git config user.email "test@example.com"
git config user.name "Test"
git commit --allow-empty -m "initial" -q

# ---- mock loop ---------------------------------------------------------------
# 호출자: dispatch.sh 가 'bash $LOOP_CMD <sub> <spec> [...]' 형태로 호출.
# 동작:
#   start <spec>   : <spec>.ctl 에 'terminal|<files>' 기록. files 기본 'DONE',
#                    파일 sidecar '<spec>.outcome' 가 있으면 그 값 사용.
#   status <spec>  : <spec>.ctl 을 읽어 loop.sh status 라인 형식으로 출력.
#                    .ctl 없으면 state=idle, files=-.
#   stop <spec>    : <spec>.stopped 마커 생성, .ctl 정리.
#   list           : 빈 헤더만.
MOCK_LOOP="$WORK_DIR/mock-loop.sh"
cat > "$MOCK_LOOP" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
sub="${1:-}"; shift || true
json=0
if [[ "${1:-}" == "--json" ]]; then json=1; shift; fi
spec="${1:-}"
ctl="${spec}.ctl"
outcome_file="${spec}.outcome"
header_fmt='%-14s %-9s %-20s %-6s %-20s %s\n'
data_fmt='%-14s %-9s %-20s %-6s %-20s %s\n'
# files(콤마 구분) → JSON 배열. "-"·빈 값은 [].
sig_json() {
  local f="$1" out="[" first=1 part
  [[ -z "$f" || "$f" == "-" ]] && { echo "[]"; return; }
  local IFS=','
  for part in $f; do
    [[ -z "$part" || "$part" == "-" ]] && continue
    if (( first == 1 )); then first=0; else out+=","; fi
    out+="\"$part\""
  done
  out+="]"; echo "$out"
}
case "$sub" in
  start)
    [[ -z "$spec" ]] && { echo "mock: start needs spec" >&2; exit 2; }
    files="DONE"
    [[ -f "$outcome_file" ]] && files="$(cat "$outcome_file")"
    printf 'terminal|%s\n' "$files" > "$ctl"
    touch "${spec}.started"
    ;;
  status)
    [[ -z "$spec" ]] && { echo "mock: status needs spec" >&2; exit 2; }
    state="idle"; files="-"
    if [[ -f "$ctl" ]]; then
      IFS='|' read -r state files < "$ctl"
    fi
    if (( json == 1 )); then
      printf '{"key":"mock","state":"%s","signals":%s,"iters":0,"last":"-","spec":"%s"}\n' \
        "$state" "$(sig_json "$files")" "$spec"
    else
      key="mock$(printf '%s' "$spec" | shasum 2>/dev/null | cut -c1-7 || echo "abc1234")"
      # shellcheck disable=SC2059
      printf "$header_fmt" "KEY" "STATE" "FILES" "ITERS" "LAST-UPDATE" "SPEC"
      # shellcheck disable=SC2059
      printf "$data_fmt" "$key" "$state" "$files" "0" "-" "$spec"
    fi
    ;;
  stop)
    [[ -z "$spec" ]] && { echo "mock: stop needs spec" >&2; exit 2; }
    touch "${spec}.stopped"
    rm -f "$ctl"
    ;;
  list)
    printf "$header_fmt" "KEY" "STATE" "FILES" "ITERS" "LAST-UPDATE" "SPEC"
    ;;
  *)
    echo "mock: unknown sub: $sub" >&2; exit 2 ;;
esac
MOCK
chmod +x "$MOCK_LOOP"
export LOOP_CMD="bash $MOCK_LOOP"
# 빠른 폴링·낮은 wave timeout 으로 테스트 즉시 진행.
export DISPATCH_POLL_SECONDS=0
export DISPATCH_WAVE_TIMEOUT_SECONDS=10

dispatch() {
  bash "$DISPATCH_SH" "$@"
}

# 픽스처: SPEC 파일 생성 (frontmatter 만 있으면 OK)
seed_spec() {
  local path="$1"; shift
  local depends="${1:-}"
  mkdir -p "$(dirname "$path")"
  if [[ -n "$depends" ]]; then
    cat > "$path" <<EOF
---
depends_on: $depends
---
# stub
EOF
  else
    cat > "$path" <<EOF
---
---
# stub
EOF
  fi
}

# 결정성 있는 spec slug 디렉토리
SPEC_DIR="$PROJECT/docs/specs"
mkdir -p "$SPEC_DIR"

# ==============================================================================

echo "=== TEST 1: 인자 없으면 usage + non-zero ==="
set +e
out=$(dispatch 2>&1); rc=$?
set -e
[[ $rc -ne 0 ]] || { echo "FAIL: 인자 없을 때 0 exit. got: $out"; exit 1; }
echo "$out" | grep -qiE 'usage|사용' || { echo "FAIL: usage 메시지 없음. got: $out"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 2: start — SPEC 파일 부재 시 거부, run 생성 안 함 ==="
set +e
out=$(dispatch start "$SPEC_DIR/missing.md" 2>&1); rc=$?
set -e
[[ $rc -ne 0 ]] || { echo "FAIL: 없는 SPEC 0 exit. got: $out"; exit 1; }
echo "$out" | grep -qE 'missing\.md|없' || { echo "FAIL: 없는 파일 보고 없음. got: $out"; exit 1; }
[[ ! -d "$PROJECT/.dispatch/runs" ]] || ls "$PROJECT/.dispatch/runs" 2>/dev/null | grep -q . \
  && [[ -d "$PROJECT/.dispatch/runs" ]] && {
    # 디렉토리는 있어도 run 항목은 없어야 함
    [[ -z "$(ls "$PROJECT/.dispatch/runs" 2>/dev/null)" ]] \
      || { echo "FAIL: 부재 입력으로 run 디렉토리 생성됨"; exit 1; }
  }
echo "OK"

echo ""
echo "=== TEST 3: start — depends_on cycle 감지 시 거부 ==="
seed_spec "$SPEC_DIR/2026-05-29-a.md" '["b"]'
seed_spec "$SPEC_DIR/2026-05-29-b.md" '["a"]'
set +e
out=$(dispatch start "$SPEC_DIR/2026-05-29-a.md" "$SPEC_DIR/2026-05-29-b.md" 2>&1); rc=$?
set -e
[[ $rc -ne 0 ]] || { echo "FAIL: cycle 입력 0 exit. got: $out"; exit 1; }
echo "$out" | grep -qiE 'cycle|순환' || { echo "FAIL: cycle 보고 없음. got: $out"; exit 1; }
echo "OK"
rm -f "$SPEC_DIR"/2026-05-29-a.md "$SPEC_DIR"/2026-05-29-b.md

echo ""
echo "=== TEST 4: list — 아직 run 없음 ==="
out=$(dispatch list 2>&1)
echo "$out" | grep -qiE '없|no run|RUN' || { echo "FAIL: list 출력 비정상. got: $out"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 5: start — 2 독립 SPEC, 단일 wave 모두 DONE, run-id 생성·STDOUT ==="
seed_spec "$SPEC_DIR/2026-05-29-foo.md"
seed_spec "$SPEC_DIR/2026-05-29-bar.md"
out=$(dispatch start "$SPEC_DIR/2026-05-29-foo.md" "$SPEC_DIR/2026-05-29-bar.md" 2>&1)
echo "$out" | grep -qE 'run-id[: ]' || { echo "FAIL: run-id 미출력. got: $out"; exit 1; }
run_id=$(echo "$out" | sed -n 's/^run-id:[[:space:]]*//p' | head -1)
[[ -n "$run_id" ]] || { echo "FAIL: run-id 파싱 실패. got: $out"; exit 1; }
[[ -d "$PROJECT/.dispatch/runs/$run_id" ]] \
  || { echo "FAIL: run dir 미생성: $PROJECT/.dispatch/runs/$run_id"; exit 1; }
# 두 mock 모두 start 호출됨
[[ -f "$SPEC_DIR/2026-05-29-foo.md.started" ]] \
  || { echo "FAIL: foo start 미호출"; exit 1; }
[[ -f "$SPEC_DIR/2026-05-29-bar.md.started" ]] \
  || { echo "FAIL: bar start 미호출"; exit 1; }
echo "run-id: $run_id"
echo "OK"

echo ""
echo "=== TEST 6: list — run-id 노출 ==="
out=$(dispatch list 2>&1)
echo "$out" | grep -q "$run_id" \
  || { echo "FAIL: list 에 run-id 없음. got: $out"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 7: status <run-id> — per-spec wave + state ==="
out=$(dispatch status "$run_id" 2>&1)
echo "$out" | grep -q '2026-05-29-foo.md' \
  || { echo "FAIL: status 에 foo spec 없음. got: $out"; exit 1; }
echo "$out" | grep -q '2026-05-29-bar.md' \
  || { echo "FAIL: status 에 bar spec 없음. got: $out"; exit 1; }
# wave 표시 (wave=1 또는 1 또는 W1)
echo "$out" | grep -qE 'wave[[:space:]=]+1|W1|^\s*1\s' \
  || { echo "FAIL: status 에 wave 정보 없음. got: $out"; exit 1; }
# terminal 또는 done 상태
echo "$out" | grep -qE 'terminal|done' \
  || { echo "FAIL: status 에 종료 상태 없음. got: $out"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 8: depends_on 으로 wave 분리 (b depends on a → wave 1=a, wave 2=b) ==="
rm -rf "$PROJECT/.dispatch"
rm -f "$SPEC_DIR"/*.started "$SPEC_DIR"/*.ctl "$SPEC_DIR"/*.outcome 2>/dev/null || true
seed_spec "$SPEC_DIR/2026-05-29-alpha.md"
seed_spec "$SPEC_DIR/2026-05-29-beta.md" '["alpha"]'
out=$(dispatch start "$SPEC_DIR/2026-05-29-alpha.md" "$SPEC_DIR/2026-05-29-beta.md" 2>&1)
run_id=$(echo "$out" | sed -n 's/^run-id:[[:space:]]*//p' | head -1)
[[ -n "$run_id" ]] || { echo "FAIL: run-id 파싱 실패"; exit 1; }
status_out=$(dispatch status "$run_id" 2>&1)
# alpha 는 wave 1, beta 는 wave 2
echo "$status_out" | grep -E '2026-05-29-alpha.md' | grep -qE 'wave[[:space:]=]+1|W1' \
  || { echo "FAIL: alpha 가 wave 1 이 아님. got: $status_out"; exit 1; }
echo "$status_out" | grep -E '2026-05-29-beta.md' | grep -qE 'wave[[:space:]=]+2|W2' \
  || { echo "FAIL: beta 가 wave 2 가 아님. got: $status_out"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 9: 한 wave child 실패 시 다음 wave 진입 차단 ==="
rm -rf "$PROJECT/.dispatch"
rm -f "$SPEC_DIR"/*.started "$SPEC_DIR"/*.ctl "$SPEC_DIR"/*.outcome "$SPEC_DIR"/*.stopped 2>/dev/null || true
seed_spec "$SPEC_DIR/2026-05-29-gate.md"
seed_spec "$SPEC_DIR/2026-05-29-after.md" '["gate"]'
# gate 가 BLOCKED 신호로 종료
echo "BLOCKED" > "$SPEC_DIR/2026-05-29-gate.md.outcome"
set +e
out=$(dispatch start "$SPEC_DIR/2026-05-29-gate.md" "$SPEC_DIR/2026-05-29-after.md" 2>&1)
rc=$?
set -e
[[ $rc -ne 0 ]] || { echo "FAIL: 실패 wave 인데 dispatch start 0 exit. got: $out"; exit 1; }
[[ -f "$SPEC_DIR/2026-05-29-gate.md.started" ]] \
  || { echo "FAIL: gate start 미호출"; exit 1; }
[[ ! -f "$SPEC_DIR/2026-05-29-after.md.started" ]] \
  || { echo "FAIL: 실패 후에도 after wave 진입함"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 10: stop <run-id> — running child 가 있으면 loop stop 위임 ==="
# 새 run, mock 이 'terminal' 로 즉시 끝나는 대신 'running' 으로 유지되도록 ctl 사전 시드.
rm -rf "$PROJECT/.dispatch"
rm -f "$SPEC_DIR"/*.started "$SPEC_DIR"/*.ctl "$SPEC_DIR"/*.outcome "$SPEC_DIR"/*.stopped 2>/dev/null || true
seed_spec "$SPEC_DIR/2026-05-29-longrun.md"
# outcome 을 sentinel 없이 두지만 mock 은 start 시 terminal 로 마킹하므로,
# 여기서는 stop 의 행위만 검증: 시작 후 곧바로 stop 호출.
out=$(dispatch start "$SPEC_DIR/2026-05-29-longrun.md" 2>&1)
run_id=$(echo "$out" | sed -n 's/^run-id:[[:space:]]*//p' | head -1)
# 강제로 running 상태로 가정하기 위해 ctl 덮어쓰기
printf 'running|-\n' > "$SPEC_DIR/2026-05-29-longrun.md.ctl"
dispatch stop "$run_id" >/dev/null 2>&1 || true
[[ -f "$SPEC_DIR/2026-05-29-longrun.md.stopped" ]] \
  || { echo "FAIL: stop 이 mock loop stop 호출 안 함"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 11: watch <run-id> — 모두 종료 시 exit 0 ==="
rm -rf "$PROJECT/.dispatch"
rm -f "$SPEC_DIR"/*.started "$SPEC_DIR"/*.ctl "$SPEC_DIR"/*.outcome "$SPEC_DIR"/*.stopped 2>/dev/null || true
seed_spec "$SPEC_DIR/2026-05-29-wfoo.md"
out=$(dispatch start "$SPEC_DIR/2026-05-29-wfoo.md" 2>&1)
run_id=$(echo "$out" | sed -n 's/^run-id:[[:space:]]*//p' | head -1)
set +e
out=$(dispatch watch "$run_id" 2>&1); rc=$?
set -e
[[ $rc -eq 0 ]] || { echo "FAIL: 모두 DONE 인데 watch exit $rc. got: $out"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 12: watch <run-id> — 실패 있으면 non-zero exit ==="
rm -rf "$PROJECT/.dispatch"
rm -f "$SPEC_DIR"/*.started "$SPEC_DIR"/*.ctl "$SPEC_DIR"/*.outcome "$SPEC_DIR"/*.stopped 2>/dev/null || true
seed_spec "$SPEC_DIR/2026-05-29-wfail.md"
echo "BLOCKED" > "$SPEC_DIR/2026-05-29-wfail.md.outcome"
set +e
out=$(dispatch start "$SPEC_DIR/2026-05-29-wfail.md" 2>&1); rc=$?
set -e
run_id=$(echo "$out" | sed -n 's/^run-id:[[:space:]]*//p' | head -1)
[[ -n "$run_id" ]] || { echo "FAIL: run-id 파싱 실패. got: $out"; exit 1; }
set +e
wout=$(dispatch watch "$run_id" 2>&1); wrc=$?
set -e
[[ $wrc -ne 0 ]] || { echo "FAIL: BLOCKED 인데 watch exit 0. got: $wout"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 13: --resume — 이미 done 인 child 는 재실행 안 함 ==="
rm -rf "$PROJECT/.dispatch"
rm -f "$SPEC_DIR"/*.started "$SPEC_DIR"/*.ctl "$SPEC_DIR"/*.outcome "$SPEC_DIR"/*.stopped 2>/dev/null || true
seed_spec "$SPEC_DIR/2026-05-29-r1.md"
seed_spec "$SPEC_DIR/2026-05-29-r2.md" '["r1"]'
out=$(dispatch start "$SPEC_DIR/2026-05-29-r1.md" "$SPEC_DIR/2026-05-29-r2.md" 2>&1)
run_id=$(echo "$out" | sed -n 's/^run-id:[[:space:]]*//p' | head -1)
# 파일 mtime(초) — GNU(`stat -c %Y`) 우선, 실패 시 BSD/macOS(`stat -f %m`).
# 주의: GNU 에서 `stat -f %m` 는 %m 를 파일명으로 보고 filesystem 모드로 빠져
# 변동하는 free-block 정보를 출력하며 exit 0 이 된다 → BSD-우선 순서면 mtime 이
# 아니라 휘발성 값을 잡아 비교가 비결정적이 된다. 따라서 GNU 를 먼저 시도한다.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
# 모두 done 상태일 것. start 마커 시점 캡처.
r1_started_time=$(mtime "$SPEC_DIR/2026-05-29-r1.md.started")
r2_started_time=$(mtime "$SPEC_DIR/2026-05-29-r2.md.started")
sleep 1
dispatch start --resume "$run_id" >/dev/null 2>&1 || true
r1_new=$(mtime "$SPEC_DIR/2026-05-29-r1.md.started")
r2_new=$(mtime "$SPEC_DIR/2026-05-29-r2.md.started")
[[ "$r1_started_time" == "$r1_new" ]] \
  || { echo "FAIL: --resume 인데 done r1 이 재시작됨"; exit 1; }
[[ "$r2_started_time" == "$r2_new" ]] \
  || { echo "FAIL: --resume 인데 done r2 가 재시작됨"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 14: state 디렉토리 위치 — <project>/.dispatch/runs/<run-id>/ ==="
[[ -d "$PROJECT/.dispatch/runs" ]] \
  || { echo "FAIL: .dispatch/runs/ 디렉토리 없음"; exit 1; }
# 적어도 하나의 run-id 디렉토리
n=$(ls "$PROJECT/.dispatch/runs" 2>/dev/null | wc -l | tr -d ' ')
[[ "$n" -ge 1 ]] || { echo "FAIL: run dir 없음"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 15: cmd_start wave timeout — hung child SIGTERM/KILL + rc=2 ==="
# 별도 mock: start 가 30s sleep 하여 wait 가 실제로 블록.
SLOW_MOCK="$WORK_DIR/slow-mock-loop.sh"
cat > "$SLOW_MOCK" <<'SLOW'
#!/usr/bin/env bash
set -euo pipefail
sub="${1:-}"; shift || true
json=0
if [[ "${1:-}" == "--json" ]]; then json=1; shift; fi
spec="${1:-}"
case "$sub" in
  start)
    [[ -z "$spec" ]] && exit 2
    touch "${spec}.started"
    sleep 30
    ;;
  status)
    [[ -z "$spec" ]] && exit 2
    state="idle"; [[ -f "${spec}.started" ]] && state="running"
    if (( json == 1 )); then
      printf '{"key":"k","state":"%s","signals":[],"iters":0,"last":"-","spec":"%s"}\n' "$state" "$spec"
    else
      printf '%-14s %-9s %-20s %-6s %-20s %s\n' KEY STATE FILES ITERS LAST-UPDATE SPEC
      printf '%-14s %-9s %-20s %-6s %-20s %s\n' k "$state" - 0 - "$spec"
    fi
    ;;
  stop) touch "${spec}.stopped" ;;
  list) printf '%-14s %-9s %-20s %-6s %-20s %s\n' KEY STATE FILES ITERS LAST-UPDATE SPEC ;;
  *) exit 2 ;;
esac
SLOW
chmod +x "$SLOW_MOCK"
rm -rf "$PROJECT/.dispatch"
rm -f "$SPEC_DIR"/*.started "$SPEC_DIR"/*.ctl "$SPEC_DIR"/*.outcome "$SPEC_DIR"/*.stopped 2>/dev/null || true
seed_spec "$SPEC_DIR/2026-05-29-hung.md"

t0=$(date +%s)
set +e
out=$(LOOP_CMD="bash $SLOW_MOCK" DISPATCH_WAVE_TIMEOUT_SECONDS=2 dispatch start "$SPEC_DIR/2026-05-29-hung.md" 2>&1)
rc=$?
set -e
t1=$(date +%s); elapsed=$((t1 - t0))

[[ $rc -eq 2 ]] || { echo "FAIL: timeout rc 기대 2, got $rc. out: $out"; exit 1; }
(( elapsed < 15 )) || { echo "FAIL: timeout 15초 내 종료 기대, ${elapsed}s 경과"; exit 1; }

# 남은 sleep 30 자식 프로세스가 정리되었는지 확인.
# pgrep 무매치 시 rc=1 이라 pipefail 회피.
sleep 1
set +o pipefail
stragglers=$(pgrep -f "sleep 30" 2>/dev/null | wc -l | tr -d ' ')
set -o pipefail
[[ "$stragglers" == "0" ]] || { echo "FAIL: timeout 후 sleep 30 자식 $stragglers 개 잔존"; exit 1; }

run_id=$(echo "$out" | sed -n 's/^run-id:[[:space:]]*//p' | head -1)
[[ -n "$run_id" ]] || { echo "FAIL: run-id 파싱 실패"; exit 1; }
state_files=$(ls "$PROJECT/.dispatch/runs/$run_id"/state.* 2>/dev/null)
[[ -n "$state_files" ]] || { echo "FAIL: state 파일 없음"; exit 1; }
grep -q '^failed$' $state_files || { echo "FAIL: timeout 시 state=failed 기대"; exit 1; }
echo "OK (rc=$rc elapsed=${elapsed}s)"

echo ""
echo "=== TEST 16: 같은 slug 다른 SPEC — state 파일 충돌 없음 ==="
rm -rf "$PROJECT/.dispatch"
rm -f "$SPEC_DIR"/*.started "$SPEC_DIR"/*.ctl "$SPEC_DIR"/*.outcome "$SPEC_DIR"/*.stopped 2>/dev/null || true
# 같은 디렉토리, 다른 날짜, 같은 슬러그 ("collide")
seed_spec "$SPEC_DIR/2026-05-29-collide.md"
seed_spec "$SPEC_DIR/2026-05-28-collide.md"

out=$(dispatch start "$SPEC_DIR/2026-05-29-collide.md" "$SPEC_DIR/2026-05-28-collide.md" 2>&1) || {
  echo "FAIL: dispatch start 실패: $out"; exit 1;
}
run_id=$(echo "$out" | sed -n 's/^run-id:[[:space:]]*//p' | head -1)
[[ -n "$run_id" ]] || { echo "FAIL: run-id 파싱 실패. got: $out"; exit 1; }

# state.collide-<sha7> 가 2 개 별개로 존재해야 한다 (충돌 시 1 개로 합쳐짐).
state_count=$(ls "$PROJECT/.dispatch/runs/$run_id"/state.collide-* 2>/dev/null | wc -l | tr -d ' ')
[[ "$state_count" == "2" ]] || { echo "FAIL: state.collide-* 2 개 기대, $state_count 개. ls: $(ls "$PROJECT/.dispatch/runs/$run_id"/ 2>/dev/null)"; exit 1; }

# 두 파일 모두 done 이어야 한다 (덮어쓰기로 한쪽이 누락되지 않아야).
all_done_lines=$(cat "$PROJECT/.dispatch/runs/$run_id"/state.collide-* 2>/dev/null | grep -c '^done$')
[[ "$all_done_lines" == "2" ]] || { echo "FAIL: 두 state 파일 모두 done 기대 (got $all_done_lines)"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 17: timeout 시 이미 done 인 child 는 done 보존 ==="
# mixed mock: basename 에 hung 포함이면 sleep 30, 아니면 즉시 terminal/DONE.
MIXED_MOCK="$WORK_DIR/mixed-mock-loop.sh"
cat > "$MIXED_MOCK" <<'MIXED'
#!/usr/bin/env bash
set -euo pipefail
sub="${1:-}"; shift || true
json=0
if [[ "${1:-}" == "--json" ]]; then json=1; shift; fi
spec="${1:-}"
case "$sub" in
  start)
    [[ -z "$spec" ]] && exit 2
    touch "${spec}.started"
    base="$(basename "$spec" .md)"
    if [[ "$base" == *hung* ]]; then
      sleep 30
    else
      printf 'terminal|DONE\n' > "${spec}.ctl"
    fi
    ;;
  status)
    [[ -z "$spec" ]] && exit 2
    state="idle"; files="-"
    if [[ -f "${spec}.ctl" ]]; then
      IFS='|' read -r state files < "${spec}.ctl"
    elif [[ -f "${spec}.started" ]]; then
      state="running"
    fi
    if (( json == 1 )); then
      sig="[]"; [[ "$files" != "-" && -n "$files" ]] && sig="[\"$files\"]"
      printf '{"key":"k","state":"%s","signals":%s,"iters":0,"last":"-","spec":"%s"}\n' "$state" "$sig" "$spec"
    else
      printf '%-14s %-9s %-20s %-6s %-20s %s\n' KEY STATE FILES ITERS LAST-UPDATE SPEC
      printf '%-14s %-9s %-20s %-6s %-20s %s\n' k "$state" "$files" 0 - "$spec"
    fi
    ;;
  stop) touch "${spec}.stopped" ;;
  list) printf '%-14s %-9s %-20s %-6s %-20s %s\n' KEY STATE FILES ITERS LAST-UPDATE SPEC ;;
  *) exit 2 ;;
esac
MIXED
chmod +x "$MIXED_MOCK"

rm -rf "$PROJECT/.dispatch"
rm -f "$SPEC_DIR"/*.started "$SPEC_DIR"/*.ctl "$SPEC_DIR"/*.outcome "$SPEC_DIR"/*.stopped 2>/dev/null || true
seed_spec "$SPEC_DIR/2026-05-29-fast.md"
seed_spec "$SPEC_DIR/2026-05-29-hung2.md"

t0=$(date +%s)
set +e
out=$(LOOP_CMD="bash $MIXED_MOCK" DISPATCH_WAVE_TIMEOUT_SECONDS=2 \
  dispatch start "$SPEC_DIR/2026-05-29-fast.md" "$SPEC_DIR/2026-05-29-hung2.md" 2>&1)
rc=$?
set -e
t1=$(date +%s); elapsed=$((t1 - t0))

[[ $rc -eq 2 ]] || { echo "FAIL: rc 2 기대, got $rc. out: $out"; exit 1; }
(( elapsed < 15 )) || { echo "FAIL: 15s 내 종료 기대, ${elapsed}s"; exit 1; }

run_id=$(echo "$out" | sed -n 's/^run-id:[[:space:]]*//p' | head -1)
[[ -n "$run_id" ]] || { echo "FAIL: run-id 파싱 실패. got: $out"; exit 1; }

# fast 의 state 가 done, hung 의 state 가 failed 이어야 한다 (SKILL.md 계약).
fast_state=$(cat "$PROJECT/.dispatch/runs/$run_id"/state.fast-* 2>/dev/null)
hung_state=$(cat "$PROJECT/.dispatch/runs/$run_id"/state.hung2-* 2>/dev/null)
[[ "$fast_state" == "done" ]] \
  || { echo "FAIL: timeout 시 fast 기대 done, got '$fast_state' (계약 위반: 정상 완료 child 를 failed 처리)"; exit 1; }
[[ "$hung_state" == "failed" ]] \
  || { echo "FAIL: hung 기대 failed, got '$hung_state'"; exit 1; }

# sleep 30 자식이 정리되었는지 확인.
sleep 1
set +o pipefail
stragglers=$(pgrep -f "sleep 30" 2>/dev/null | wc -l | tr -d ' ')
set -o pipefail
[[ "$stragglers" == "0" ]] || { echo "FAIL: sleep 30 자식 $stragglers 잔존"; exit 1; }
echo "OK (rc=$rc elapsed=${elapsed}s, fast=done 보존, hung=failed)"

echo ""
echo "=== TEST 18: 종료 상태 판정은 구조화(status --json) 단일 출처 — 텍스트 컬럼 비의존 ==="
# 적대적 mock: 사람용 status 표 컬럼은 의도적으로 틀린 값(STATE=idle, FILES=-)을
# 내고, status --json 만 올바른 종료 상태(terminal/DONE)를 낸다. dispatch 가
# 컬럼이 아니라 구조화 상태로 판정한다면 child 는 done 으로 마킹되어야 한다.
ADV_MOCK="$WORK_DIR/adv-mock-loop.sh"
cat > "$ADV_MOCK" <<'ADV'
#!/usr/bin/env bash
set -euo pipefail
sub="${1:-}"; shift || true
json=0
if [[ "${1:-}" == "--json" ]]; then json=1; shift; fi
spec="${1:-}"
ctl="${spec}.ctl"
case "$sub" in
  start)
    [[ -z "$spec" ]] && exit 2
    touch "${spec}.started"
    printf 'terminal|DONE\n' > "$ctl"
    ;;
  status)
    [[ -z "$spec" ]] && exit 2
    state="idle"; files="-"
    if [[ -f "$ctl" ]]; then IFS='|' read -r state files < "$ctl"; fi
    if (( json == 1 )); then
      # 구조화 상태만 진실을 말한다.
      local_sig="[]"
      if [[ "$files" != "-" && -n "$files" ]]; then local_sig="[\"$files\"]"; fi
      printf '{"key":"k","state":"%s","signals":%s,"iters":0,"last":"-","spec":"%s"}\n' \
        "$state" "$local_sig" "$spec"
    else
      # 사람용 표 — 적대적으로 항상 idle/-(틀린 값)을 낸다.
      printf '%-14s %-9s %-20s %-6s %-20s %s\n' KEY STATE FILES ITERS LAST-UPDATE SPEC
      printf '%-14s %-9s %-20s %-6s %-20s %s\n' k idle - 0 - "$spec"
    fi
    ;;
  stop) touch "${spec}.stopped" ;;
  list) printf '%-14s %-9s %-20s %-6s %-20s %s\n' KEY STATE FILES ITERS LAST-UPDATE SPEC ;;
  *) exit 2 ;;
esac
ADV
chmod +x "$ADV_MOCK"
rm -rf "$PROJECT/.dispatch"
rm -f "$SPEC_DIR"/*.started "$SPEC_DIR"/*.ctl "$SPEC_DIR"/*.outcome "$SPEC_DIR"/*.stopped 2>/dev/null || true
seed_spec "$SPEC_DIR/2026-05-29-adv.md"
set +e
out=$(LOOP_CMD="bash $ADV_MOCK" dispatch start "$SPEC_DIR/2026-05-29-adv.md" 2>&1)
set -e
run_id=$(echo "$out" | sed -n 's/^run-id:[[:space:]]*//p' | head -1)
[[ -n "$run_id" ]] || { echo "FAIL: run-id 파싱 실패. got: $out"; exit 1; }
adv_state=$(cat "$PROJECT/.dispatch/runs/$run_id"/state.adv-* 2>/dev/null)
[[ "$adv_state" == "done" ]] \
  || { echo "FAIL: 구조화 판정 기대 done(컬럼은 idle 적대값), got '$adv_state' — 텍스트 컬럼에 의존 의심"; exit 1; }
echo "OK"

echo ""
echo "=== 모든 dispatch 통합 테스트 통과 ==="
