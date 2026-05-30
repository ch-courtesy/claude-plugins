#!/usr/bin/env bash
# autopilot:dispatch — per-spec directory layout 행위 검증.
#
# SPEC: spec/loop/dispatch per-spec directory layout 전환.
#   AC5 — 신 형식(<date>-<slug>/SPEC.md) 에서 slug·상태 식별자·depends_on 의존성을
#         구 형식과 동일한 의미로 해석.
#   AC4 — 구·신 형식 경로를 모두 정상 해석.
#
# 실제 loop.sh 는 호출하지 않는다: LOOP_CMD 환경변수로 mock 셸 치환.
# test-dispatch-integration.sh 와 동일한 mock 계약(start→<spec>.ctl terminal|DONE).

set -euo pipefail

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

MOCK_LOOP="$WORK_DIR/mock-loop.sh"
cat > "$MOCK_LOOP" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
sub="${1:-}"; shift || true
spec="${1:-}"
ctl="${spec}.ctl"
outcome_file="${spec}.outcome"
fmt='%-14s %-9s %-20s %-6s %-20s %s\n'
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
    [[ -f "$ctl" ]] && IFS='|' read -r state files < "$ctl"
    # shellcheck disable=SC2059
    printf "$fmt" "KEY" "STATE" "FILES" "ITERS" "LAST-UPDATE" "SPEC"
    # shellcheck disable=SC2059
    printf "$fmt" "k" "$state" "$files" "0" "-" "$spec"
    ;;
  stop) touch "${spec}.stopped"; rm -f "$ctl" ;;
  list) printf "$fmt" "KEY" "STATE" "FILES" "ITERS" "LAST-UPDATE" "SPEC" ;;
  *) echo "mock: unknown sub: $sub" >&2; exit 2 ;;
esac
MOCK
chmod +x "$MOCK_LOOP"
export LOOP_CMD="bash $MOCK_LOOP"
export DISPATCH_POLL_SECONDS=0
export DISPATCH_WAVE_TIMEOUT_SECONDS=10

dispatch() { bash "$DISPATCH_SH" "$@"; }

# seed_new <date> <slug> [depends] — 신 형식 <date>-<slug>/SPEC.md 생성. 경로 출력.
seed_new() {
  local date="$1" slug="$2" depends="${3:-}"
  local dir="$PROJECT/docs/specs/${date}-${slug}"
  mkdir -p "$dir"
  if [[ -n "$depends" ]]; then
    printf -- '---\ndepends_on: %s\n---\n# %s\n' "$depends" "$slug" > "$dir/SPEC.md"
  else
    printf -- '---\n---\n# %s\n' "$slug" > "$dir/SPEC.md"
  fi
  echo "$dir/SPEC.md"
}
# seed_old <date> <slug> [depends] — 구 형식 <date>-<slug>.md. 경로 출력.
seed_old() {
  local date="$1" slug="$2" depends="${3:-}"
  mkdir -p "$PROJECT/docs/specs"
  local p="$PROJECT/docs/specs/${date}-${slug}.md"
  if [[ -n "$depends" ]]; then
    printf -- '---\ndepends_on: %s\n---\n# %s\n' "$depends" "$slug" > "$p"
  else
    printf -- '---\n---\n# %s\n' "$slug" > "$p"
  fi
  echo "$p"
}

runid_of() { sed -n 's/^run-id:[[:space:]]*//p' <<< "$1" | head -1; }

# ==============================================================================

echo "=== TEST 1: 신 형식 slug — state 파일이 state.<slug>-* (state.SPEC-* 아님) ==="
a="$(seed_new 2026-05-30 newfmt)"
out=$(dispatch start "$a" 2>&1) || { echo "FAIL: start 실패: $out"; exit 1; }
rid="$(runid_of "$out")"
[[ -n "$rid" ]] || { echo "FAIL: run-id 파싱 실패. got: $out"; exit 1; }
RD="$PROJECT/.dispatch/runs/$rid"
ls "$RD"/state.newfmt-* >/dev/null 2>&1 \
  || { echo "FAIL: state.newfmt-* 부재 (slug 도출 오류). ls: $(ls "$RD")"; exit 1; }
ls "$RD"/state.SPEC-* >/dev/null 2>&1 \
  && { echo "FAIL: state.SPEC-* 존재 — 신 형식 slug 가 'SPEC' 로 잘못 도출됨"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 2: 신 형식 depends_on — 형제 디렉토리 slug 해석 + wave 분리 ==="
rm -rf "$PROJECT/.dispatch"
al="$(seed_new 2026-05-30 alpha2)"
be="$(seed_new 2026-05-30 beta2 '["alpha2"]')"
out=$(dispatch start "$al" "$be" 2>&1) || { echo "FAIL: start 실패: $out"; exit 1; }
rid="$(runid_of "$out")"
status_out=$(dispatch status "$rid" 2>&1)
echo "$status_out" | grep -E 'alpha2' | grep -qE 'wave[[:space:]=]+1|W1' \
  || { echo "FAIL: alpha2 wave1 아님. got: $status_out"; exit 1; }
echo "$status_out" | grep -E 'beta2' | grep -qE 'wave[[:space:]=]+2|W2' \
  || { echo "FAIL: beta2 wave2 아님 (depends_on 신 형식 해석 실패). got: $status_out"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 3: 혼합 형식 — 신 형식이 구 형식 형제 slug 의존 해석 ==="
rm -rf "$PROJECT/.dispatch"
oldbase="$(seed_old 2026-05-30 oldbase)"
newdep="$(seed_new 2026-05-30 newdep '["oldbase"]')"
out=$(dispatch start "$oldbase" "$newdep" 2>&1) || { echo "FAIL: start 실패: $out"; exit 1; }
rid="$(runid_of "$out")"
status_out=$(dispatch status "$rid" 2>&1)
echo "$status_out" | grep -E 'oldbase' | grep -qE 'wave[[:space:]=]+1|W1' \
  || { echo "FAIL: oldbase wave1 아님. got: $status_out"; exit 1; }
echo "$status_out" | grep -E 'newdep' | grep -qE 'wave[[:space:]=]+2|W2' \
  || { echo "FAIL: newdep wave2 아님 (혼합 형식 의존 해석 실패). got: $status_out"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 4: 다른 날짜 같은 slug 신 형식 — state 충돌 없음 (2 개 별개) ==="
rm -rf "$PROJECT/.dispatch"
c1="$(seed_new 2026-05-30 collidenew)"
c2="$(seed_new 2026-05-29 collidenew)"
out=$(dispatch start "$c1" "$c2" 2>&1) || { echo "FAIL: start 실패: $out"; exit 1; }
rid="$(runid_of "$out")"
RD="$PROJECT/.dispatch/runs/$rid"
n=$(ls "$RD"/state.collidenew-* 2>/dev/null | wc -l | tr -d ' ')
[[ "$n" == "2" ]] || { echo "FAIL: state.collidenew-* 2 개 기대, $n. ls: $(ls "$RD")"; exit 1; }
echo "OK"

echo ""
echo "=== 모든 dispatch new-layout 테스트 통과 ==="
