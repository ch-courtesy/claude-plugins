#!/usr/bin/env bash
# test-forge-routing.sh — origin url 별 호스트 라우팅 + gitlab 확장점 abort 검증.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="$HERE/../../plugins/autopilot/lib/forge/forge.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }

# 라우팅 셀프테스트 위임
if bash "$F" selftest; then ok "forge selftest"; else bad "forge selftest"; fi

# review-loop 셀프테스트 위임 — 판정 분기·세 가드·#549 재매핑 대기·#571 같은 head 재평가 회귀 가드.
RL_OUT="$(bash "$HERE/../../plugins/autopilot/lib/forge/lib/review-loop.sh" selftest 2>&1)" \
  && [[ "$RL_OUT" == *"ALL PASS"* ]] && ok "review-loop selftest" \
  || { bad "review-loop selftest"; echo "$RL_OUT"; }

# gitlab 구현은 호출 시 비-0 (조용한 실패 금지 — 확장점)
( source "$HERE/../../plugins/autopilot/lib/forge/gitlab.sh"; fg_integrate x y z ) >/dev/null 2>&1 && bad "gitlab integrate abort" || ok "gitlab integrate abort(비-0)"

# fg_review 위임 검증(#426): github 은 review-loop.sh `round`(rl_round 코드 0/10/20/30 표면화),
#   direct 는 `run-direct`(기존 동기 리뷰, collapse). 스텁 review-loop.sh 로 서브커맨드 캡처.
TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/ref"
cat > "$TMPD/ref/review-loop.sh" <<'EOF'
#!/usr/bin/env bash
echo "$1" > "$RL_SUB"
EOF
( source "$HERE/../../plugins/autopilot/lib/forge/github.sh"; FG_REF="$TMPD/ref" RL_SUB="$TMPD/sub.gh" fg_review rd key spec 7 br )
[[ "$(cat "$TMPD/sub.gh")" == "round" ]] && ok "github fg_review → review-loop.sh round" || bad "github fg_review → round (got '$(cat "$TMPD/sub.gh")')"
( source "$HERE/../../plugins/autopilot/lib/forge/direct.sh"; FG_REF="$TMPD/ref" RL_SUB="$TMPD/sub.dir" fg_review rd key spec "" br )
[[ "$(cat "$TMPD/sub.dir")" == "run-direct" ]] && ok "direct fg_review → review-loop.sh run-direct(불변)" || bad "direct fg_review → run-direct (got '$(cat "$TMPD/sub.dir")')"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
