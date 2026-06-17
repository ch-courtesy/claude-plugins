#!/usr/bin/env bash
# test-execute-task-blocking-gate.sh — 승인 게이트 미해결 [blocking] 인라인 가산 차단 검증(#423).
#   통합(폴링 루프, BLOCKING_CHECK_CMD 모킹):
#     (a) APPROVED 라도 head 미해결 [blocking] 있으면 머지 안 함 → 대기 후 상한 미해결 → blocked, merge 미호출
#     (b) 대기 중 [blocking] 가 resolved 되면 승인→머지(done)
#     (c) blocking 없음 + APPROVED → 대기 없이 머지(done)
#     (d) 조회 실패(보수적 차단=대기) → 상한까지 미해결 → blocked, merge 미호출
#   단위(et_blocking_inline_gh, gh 모킹):
#     미해결+head+신뢰봇+[blocking] → 차단(rc1); resolved/old-head/non_blocking → clear(rc0);
#     head 미확정/조회실패 → 보수적 차단(rc1)
#   자동 resolve 금지: 소스에 resolve 뮤테이션 호출 부재
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ET="$HERE/../references/execute-task.sh"
ADAPTER="$HERE/../../../task-backend/adapter.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q; git config user.email t@t; git config user.name t
bash "$ADAPTER" init --backend filesystem >/dev/null

mkdir -p bin
cat > bin/loop <<'EOF'
#!/usr/bin/env bash
case "$1" in
  start|cleanup) exit 0;;
  status) printf '{"state":"terminal","signals":["DONE"]}\n';;
  *) exit 0;;
esac
EOF
chmod +x bin/loop
# mock forge: integrate→branch+pr(7); review→rc20(할 일 없음=깨끗+비동기 승인대기, rl_round #426
#   계약 → 승인 폴링 유지 시나리오에서 미해결 [blocking] 가산 게이트 검증); merge→기록(+rc0)
cat > bin/forge <<'EOF'
#!/usr/bin/env bash
case "$1" in
  integrate) echo "branch: feat/x"; echo "pr: 7"; exit 0;;
  review) exit 20;;
  merge) [[ -n "${MERGE_LOG:-}" ]] && echo merged >> "$MERGE_LOG"; exit 0;;
  *) exit 0;;
esac
EOF
chmod +x bin/forge
# mock approval: 항상 승인(rc0). (blocking 게이트만 분리 검증)
cat > bin/approve <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x bin/approve
# mock blocking gate: 호출 카운트 증가. n>=CLEAR_AFTER 면 clear(rc0), 아니면 blocked(rc1).
#   CLEAR_AFTER 미설정 → 항상 blocked(rc1) = 영구 미해결/조회실패 보수적 차단 시뮬레이션.
cat > bin/block <<'EOF'
#!/usr/bin/env bash
f="${BLOCK_COUNTER:?}"
n=$(( $(cat "$f" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$f"
[[ -n "${CLEAR_AFTER:-}" && "$n" -ge "$CLEAR_AFTER" ]]
EOF
chmod +x bin/block

status_of(){ bash "$ADAPTER" get_task --task-id "$1" | jq -r .status; }
newtask(){ bash "$ADAPTER" create_task --title "$1" --body '## 목표'$'\n'x | jq -r .task_id; }
run() { local id="$1"; shift
  env ADAPTER_CMD="bash $ADAPTER" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
      HEARTBEAT_INTERVAL=1 APPROVAL_CHECK_CMD="bash $TMP/bin/approve" "$@" bash "$ET" start "$id"
}

# (a) APPROVED + 미해결 blocking 영구 → 머지 안 함, 상한까지 대기 후 blocked
id="$(newtask A)"; bc="$TMP/bcA"; : > "$bc"; mlog="$TMP/mlogA"; : > "$mlog"
run "$id" BLOCKING_CHECK_CMD="bash $TMP/bin/block" BLOCK_COUNTER="$bc" \
  APPROVAL_WAIT_MAX=4 APPROVAL_POLL_INTERVAL=2 SLEEP_CMD=: MERGE_LOG="$mlog" >/dev/null 2>&1 || true
chk "(a) APPROVED+blocking → blocked" "$(status_of "$id")" "blocked"
chk "(a) blocking 미해결 시 merge 미호출" "$(wc -l < "$mlog" | tr -d ' ')" "0"
[[ "$(cat "$bc")" -ge 2 ]] && ok "(a) blocking 폴링 대기(2회+)" || bad "(a) blocking 폴링 대기(2회+) got $(cat "$bc")"

# (b) 대기 중 blocking resolved(3회째 clear) → 승인→머지(done)
id="$(newtask B)"; bc="$TMP/bcB"; : > "$bc"; mlog="$TMP/mlogB"; : > "$mlog"
run "$id" BLOCKING_CHECK_CMD="bash $TMP/bin/block" BLOCK_COUNTER="$bc" CLEAR_AFTER=3 \
  APPROVAL_WAIT_MAX=100 APPROVAL_POLL_INTERVAL=10 SLEEP_CMD=: MERGE_LOG="$mlog" >/dev/null 2>&1 || true
chk "(b) blocking resolved → done" "$(status_of "$id")" "done"
chk "(b) resolved 후 merge 호출" "$(grep -c merged "$mlog")" "1"
chk "(b) clear 까지 3회 확인" "$(cat "$bc")" "3"

# (c) blocking 없음(즉시 clear) + APPROVED → 대기 없이 머지(done)
id="$(newtask C)"; bc="$TMP/bcC"; : > "$bc"
run "$id" BLOCKING_CHECK_CMD="bash $TMP/bin/block" BLOCK_COUNTER="$bc" CLEAR_AFTER=1 \
  APPROVAL_WAIT_MAX=100 APPROVAL_POLL_INTERVAL=10 SLEEP_CMD=: >/dev/null 2>&1 || true
chk "(c) blocking 없음 → done" "$(status_of "$id")" "done"
chk "(c) 즉시 clear 시 1회 확인" "$(cat "$bc")" "1"

# (d) 조회 실패(보수적 차단=항상 rc1) → 상한까지 대기 후 blocked, merge 미호출
id="$(newtask D)"; bc="$TMP/bcD"; : > "$bc"; mlog="$TMP/mlogD"; : > "$mlog"
run "$id" BLOCKING_CHECK_CMD="bash $TMP/bin/block" BLOCK_COUNTER="$bc" \
  APPROVAL_WAIT_MAX=6 APPROVAL_POLL_INTERVAL=2 SLEEP_CMD=: MERGE_LOG="$mlog" >/dev/null 2>&1 || true
chk "(d) 조회 실패 보수적 → blocked" "$(status_of "$id")" "blocked"
chk "(d) 조회 실패 시 merge 미호출" "$(wc -l < "$mlog" | tr -d ' ')" "0"

# ===== 단위: et_blocking_inline_gh (gh 모킹) =====
# source 가드로 main 미실행 후 함수 직접 호출. gh 는 PATH mock 으로 치환.
mkdir -p ghbin
cat > ghbin/gh <<'EOF'
#!/usr/bin/env bash
# 인자에 따라 고정 응답(env 는 런타임에 읽음): headRefOid / repo view / graphql
args="$*"
case "$args" in
  *"--json headRefOid"*) printf '%s\n' "${GH_HEAD:-}";;
  *"repo view"*) printf '%s\n' "${GH_REPO:-o n}";;
  *"graphql"*) cat "${GH_GRAPHQL_FILE:?}";;
  *) exit 0;;
esac
EOF
chmod +x ghbin/gh

ubg() { # ubg <head> <repo> <graphql-json-file> → et_blocking_inline_gh 7 의 rc 를 stdout 으로
  local r=0
  env GH_HEAD="$1" GH_REPO="$2" GH_GRAPHQL_FILE="$3" PATH="$TMP/ghbin:$PATH" \
    bash -c 'source "'"$ET"'"; et_blocking_inline_gh 7' || r=$?
  printf '%s' "$r"; }

# 미해결 + head=H1 + 신뢰봇(courtesy-bot) + [blocking] → 차단(rc1)
cat > gq_block.json <<'EOF'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
{"isResolved":false,"comments":{"nodes":[{"author":{"login":"courtesy-bot"},"commit":{"oid":"H1"},"body":"**[blocking/85] foo**"}]}}
]}}}}}
EOF
chk "(u1) 미해결 blocking → 차단(rc1)" "$(ubg H1 "o n" "$TMP/gq_block.json")" "1"

# resolved 스레드는 제외 → clear(rc0)
cat > gq_resolved.json <<'EOF'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
{"isResolved":true,"comments":{"nodes":[{"author":{"login":"courtesy-bot"},"commit":{"oid":"H1"},"body":"**[blocking/85] foo**"}]}}
]}}}}}
EOF
chk "(u2) resolved → clear(rc0)" "$(ubg H1 "o n" "$TMP/gq_resolved.json")" "0"

# old head(commit.oid!=head) → clear(rc0)
chk "(u3) old-head blocking → clear(rc0)" "$(ubg H2 "o n" "$TMP/gq_block.json")" "0"

# non_blocking 태그 → clear(rc0)
cat > gq_nonblock.json <<'EOF'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
{"isResolved":false,"comments":{"nodes":[{"author":{"login":"courtesy-bot"},"commit":{"oid":"H1"},"body":"**[non_blocking/20] nit**"}]}}
]}}}}}
EOF
chk "(u4) non_blocking → clear(rc0)" "$(ubg H1 "o n" "$TMP/gq_nonblock.json")" "0"

# head 미확정(빈값) → 보수적 차단(rc1)
chk "(u5) head 미확정 → 보수적 차단(rc1)" "$(ubg "" "o n" "$TMP/gq_block.json")" "1"

# 비신뢰 작성자 blocking → clear(rc0) (위조 차단 무시)
cat > gq_untrusted.json <<'EOF'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
{"isResolved":false,"comments":{"nodes":[{"author":{"login":"randomuser"},"commit":{"oid":"H1"},"body":"**[blocking/85] foo**"}]}}
]}}}}}
EOF
chk "(u6) 비신뢰 작성자 blocking → clear(rc0)" "$(ubg H1 "o n" "$TMP/gq_untrusted.json")" "0"

# 자동 resolve 금지: 소스에 resolve 뮤테이션 부재
if grep -qE 'resolveReviewThread|unresolveReviewThread' "$ET"; then bad "(z) 자동 resolve 호출 부재"; else ok "(z) 자동 resolve 호출 부재"; fi

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
