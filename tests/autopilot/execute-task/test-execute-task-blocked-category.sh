#!/usr/bin/env bash
# test-execute-task-blocked-category.sh — forge 단계 blocked 신호의 category 표면화 회귀 가드 (#600).
#   결함: execute-task 의 forge 단계 blocked 로그(integrate/review/merge 실패)에 `category:` 필드가
#   없어, 자가개선 seam(using-autopilot 카테고리→행동 매핑)이 소비할 정보가 유실된다.
#   기대: forge 단계 blocked append_log 텍스트가 `category:` 값으로 시작한다 — 사유별 기계적 규칙:
#     원격·브랜치·머지 게이트 등 환경 차단(integrate/merge 실패) → environment-gap
#     리뷰 수렴·판정 문제(review 진전 불가/미승인·폴링 상한)     → other
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ET="$HERE/../../../plugins/autopilot/skills/execute-task/references/execute-task.sh"
ADAPTER="$HERE/../../../plugins/autopilot/lib/task-backend/adapter.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q; git config user.email t@t; git config user.name t
bash "$ADAPTER" init --backend filesystem >/dev/null

mkdir -p bin
cat > bin/loop <<'EOF'
#!/usr/bin/env bash
case "$1" in
  status) printf '{"state":"terminal","signals":["DONE"]}\n';;
  *) exit 0;;
esac
EOF
chmod +x bin/loop

# mock forge: FORGE_MODE 로 blocked 지점 선택.
cat > bin/forge <<'EOF'
#!/usr/bin/env bash
case "$1" in
  integrate)
    if [[ "${FORGE_MODE:-}" == "integrate-fail" ]]; then
      echo "integration: push 실패(non-fast-forward)" >&2; exit 4
    fi
    echo "branch: feat/x"
    [[ "${FORGE_MODE:-}" == "direct-unapproved" ]] || echo "pr: 7"   # direct 경로 = PR 없음
    exit 0;;
  review)
    case "${FORGE_MODE:-}" in
      review-stuck)     exit 10;;   # rl_round 계약: 10=에스컬레이션(진전 불가)
      review-wait)      exit 20;;   # 20=대기(비동기 승인 폴링)
      direct-unapproved) exit 1;;   # direct 경로 리뷰 미승인
      merge-fail|*)     exit 30;;   # 30=approve
    esac;;
  merge)
    if [[ "${FORGE_MODE:-}" == "merge-fail" ]]; then
      echo "merge: 승인 차단 — 미해결 리뷰 스레드" >&2; exit 1
    fi
    exit 0;;
  *) exit 0;;
esac
EOF
chmod +x bin/forge

cat > bin/adapter_norenew << EOF
#!/usr/bin/env bash
[[ "\$1" == renew_lease ]] && { echo '{"task_id":"noop"}'; exit 0; }
exec bash "$ADAPTER" "\$@"
EOF
chmod +x bin/adapter_norenew

run() { ADAPTER_CMD="bash $TMP/bin/adapter_norenew" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
        HEARTBEAT_INTERVAL=1 APPROVAL_WAIT_MAX=0 APPROVAL_CHECK_CMD=false BLOCKING_CHECK_CMD=false SLEEP_CMD=: \
        bash "$ET" "$@"; }
task_file(){ printf '%s/.tasks/%s.md' "$TMP" "$1"; }
# blocked 로그 라인이 category 로 시작하는지: `[blocked] category: <값> — ...`
has_cat(){ grep -q "\[blocked\] category: $2" "$(task_file "$1")"; }

# ---- 1: integrate 실패 → category: environment-gap ----
id1="$(bash "$ADAPTER" create_task --title T1 --body '## 목표'$'\n'x | jq -r .task_id)"
FORGE_MODE=integrate-fail run start "$id1" >/dev/null 2>&1 || true
has_cat "$id1" environment-gap && ok "1: integrate 실패 category=environment-gap" \
  || { bad "1: integrate 실패 category=environment-gap"; sed -n '$p' "$(task_file "$id1")"; }

# ---- 2: review 진전 불가(rc=10) → category: other ----
id2="$(bash "$ADAPTER" create_task --title T2 --body '## 목표'$'\n'x | jq -r .task_id)"
FORGE_MODE=review-stuck run start "$id2" >/dev/null 2>&1 || true
has_cat "$id2" other && ok "2: review 진전 불가 category=other" \
  || { bad "2: review 진전 불가 category=other"; sed -n '$p' "$(task_file "$id2")"; }

# ---- 3: review 승인 폴링 상한 초과 → category: other ----
id3="$(bash "$ADAPTER" create_task --title T3 --body '## 목표'$'\n'x | jq -r .task_id)"
FORGE_MODE=review-wait run start "$id3" >/dev/null 2>&1 || true
has_cat "$id3" other && ok "3: 폴링 상한 초과 category=other" \
  || { bad "3: 폴링 상한 초과 category=other"; sed -n '$p' "$(task_file "$id3")"; }

# ---- 4: merge 실패 → category: environment-gap ----
id4="$(bash "$ADAPTER" create_task --title T4 --body '## 목표'$'\n'x | jq -r .task_id)"
FORGE_MODE=merge-fail run start "$id4" >/dev/null 2>&1 || true
has_cat "$id4" environment-gap && ok "4: merge 실패 category=environment-gap" \
  || { bad "4: merge 실패 category=environment-gap"; sed -n '$p' "$(task_file "$id4")"; }

# ---- 5: direct(PR 없음) 경로 review 미승인 → category: other ----
id6="$(bash "$ADAPTER" create_task --title T6 --body '## 목표'$'\n'x | jq -r .task_id)"
FORGE_MODE=direct-unapproved run start "$id6" >/dev/null 2>&1 || true
has_cat "$id6" other && ok "5: direct review 미승인 category=other" \
  || { bad "5: direct review 미승인 category=other"; sed -n '$p' "$(task_file "$id6")"; }

# ---- 6: 성공 경로 회귀 없음(blocked/category 마커 미기록) ----
id5="$(bash "$ADAPTER" create_task --title T5 --body '## 목표'$'\n'x | jq -r .task_id)"
run start "$id5" >/dev/null 2>&1 || true
grep -q '\[blocked\]' "$(task_file "$id5")" \
  && bad "6: 성공 경로에 blocked 마커 없음" || ok "6: 성공 경로에 blocked 마커 없음"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || { echo "FAILURES present"; exit 1; }
