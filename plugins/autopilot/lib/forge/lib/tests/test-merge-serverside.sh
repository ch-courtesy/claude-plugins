#!/usr/bin/env bash
# test-merge-serverside.sh — mg_merge_pr_serverside 의 "발행 ≠ 완료" 계약 검증.
#   - 머지 발행 성공 + PR state==MERGED 폴링 확인 → 0(완료).
#   - 머지 발행 성공이나 상한까지 PR 미머지(--auto 예약만, OPEN 지속) → 1(차단; 조용한 완료 금지).
#   - 머지 발행 실패 → 1.
# FORGE_CMD(gh)·MG_SLEEP_CMD 를 스텁으로 치환해 결정적으로 검증한다.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MERGE="$HERE/../merge.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

# merge.sh 를 source (하단 BASH_SOURCE 가드로 main 미실행)
# shellcheck disable=SC1090
MG_SLEEP_CMD=true source "$MERGE"

mkstub() {  # <path> <merge_issue_rc> <state_script>
  cat > "$1" <<EOF
#!/usr/bin/env bash
# gh 스텁: 'pr merge' 발행 / 'pr view --json state --jq .state' 상태 조회
args="\$*"
case "\$1 \$2" in
  "pr merge") exit $2 ;;
  "pr view")
    # 호출 횟수 카운트 파일로 상태 진행 시뮬레이션
    n=\$(cat "$1.calls" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$1.calls"
    $3
    ;;
esac
exit 0
EOF
  chmod +x "$1"; : > "$1.calls"
}

# --- 1: 발행 성공 + 3번째 조회에서 MERGED → 0(완료) ---
T1="$(mktemp -d)"; mkstub "$T1/gh" 0 'if [ "$n" -ge 3 ]; then echo MERGED; else echo OPEN; fi'
rc1=0; ( FORGE_CMD="$T1/gh" MG_SLEEP_CMD=true MERGE_CONFIRM_WAIT_MAX=100 MERGE_CONFIRM_POLL_INTERVAL=1 \
        mg_merge_pr_serverside "$T1" 99 feat/x ) >/dev/null 2>&1 || rc1=$?
chk "1: 발행+MERGED 확인 → rc 0" "$rc1" "0"

# --- 2: 발행 성공이나 OPEN 지속(예약만) → 상한 후 1(차단) [버그 수정 핵심] ---
T2="$(mktemp -d)"; mkstub "$T2/gh" 0 'echo OPEN'
rc2=0; ( FORGE_CMD="$T2/gh" MG_SLEEP_CMD=true MERGE_CONFIRM_WAIT_MAX=5 MERGE_CONFIRM_POLL_INTERVAL=1 \
        mg_merge_pr_serverside "$T2" 99 feat/x ) >/dev/null 2>&1 || rc2=$?
chk "2: 발행됐으나 미머지(예약만) → rc 1(차단)" "$rc2" "1"

# --- 3: 머지 발행 자체 실패 → 1 ---
T3="$(mktemp -d)"; mkstub "$T3/gh" 1 'echo OPEN'
rc3=0; ( FORGE_CMD="$T3/gh" MG_SLEEP_CMD=true MERGE_CONFIRM_WAIT_MAX=5 MERGE_CONFIRM_POLL_INTERVAL=1 \
        mg_merge_pr_serverside "$T3" 99 feat/x ) >/dev/null 2>&1 || rc3=$?
chk "3: 머지 발행 실패 → rc 1" "$rc3" "1"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || { echo "FAILURES present"; exit 1; }
