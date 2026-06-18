#!/usr/bin/env bash
# test-execute-task-approval-marker.sh — et_approval_gh 경로 b(강등 승인 마커) 봇 로그인 매칭(#432).
#   결함: REVIEW_BOT_LOGINS_RE(앵커 포함)을 login\tbody 결합 라인에 grep → \[bot\]$·^github-actions$
#   앵커가 영영 매치 안 됨. 정규식을 login 필드 단독에 적용해야 [bot]/github-actions 계열 신뢰봇의
#   COMMENT형 verdict=approve 마커가 감지된다.
#   단위(et_approval_gh, gh 모킹): 봇 로그인 매치(통과)/비신뢰·위조·head불일치(거부)/경로 a(APPROVED) 불변.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ET="$HERE/../references/execute-task.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/ghbin"
# mock gh: reviewDecision / headRefOid / reviews(login\tbody) 를 env 시나리오 변수로 구동.
#   reviews jq 는 무시하고 GH_REVIEWS(login\tbody 줄들)를 그대로 반환 — login\tbody 결합 라인을
#   재현해 정규식이 login 필드에만 적용되는지 결정적으로 검증.
cat > "$TMP/ghbin/gh" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"--json reviewDecision"*) printf '%s\n' "${GH_DECISION:-}";;
  *"--json headRefOid"*)     printf '%s\n' "${GH_HEAD:-}";;
  *"--json reviews"*)        printf '%b' "${GH_REVIEWS:-}";;
  *) exit 0;;
esac
EOF
chmod +x "$TMP/ghbin/gh"

# uag <decision> <head> <reviews> → et_approval_gh 7 의 rc 를 stdout 으로.
uag() {
  local r=0
  env GH_DECISION="$1" GH_HEAD="$2" GH_REVIEWS="$3" PATH="$TMP/ghbin:$PATH" \
    bash -c 'source "'"$ET"'"; et_approval_gh 7' >/dev/null 2>&1 || r=$?
  printf '%s' "$r"; }

H="headSHA1"
mk(){ printf '%s\t<!-- %s head_sha=%s verdict=approve -->\n' "$1" "${3:-x-formal-review}" "${2:-$H}"; }

# 경로 b: [bot]/github-actions 계열 봇 마커 → 승인(rc0).
chk "(a1) github-actions[bot] 마커 → 승인(rc0)" "$(uag "" "$H" "$(mk 'github-actions[bot]')")" "0"
chk "(a2) codex[bot] 마커 → 승인(rc0)"          "$(uag "" "$H" "$(mk 'codex[bot]')")" "0"
chk "(a3) github-actions 마커 → 승인(rc0)"       "$(uag "" "$H" "$(mk 'github-actions')")" "0"
chk "(a4) courtesy-bot 마커 → 승인(rc0)"         "$(uag "" "$H" "$(mk 'courtesy-bot')")" "0"

# 거부: 비신뢰 로그인 / head 불일치 → 미승인(rc1).
chk "(b1) 비신뢰(evil-user) 마커 → 미승인(rc1)" "$(uag "" "$H" "$(mk 'evil-user')")" "1"
chk "(b2) head 불일치 마커 → 미승인(rc1)"        "$(uag "" "$H" "$(mk 'github-actions[bot]' 'oldSHA')")" "1"
chk "(b3) 마커 없음 → 미승인(rc1)"               "$(uag "" "$H" "github-actions[bot]\t단순 코멘트\n")" "1"

# 경로 a: reviewDecision==APPROVED → 마커 무관 즉시 승인(rc0, 불변).
chk "(c1) APPROVED → 승인(rc0)" "$(uag "APPROVED" "$H" "")" "0"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
