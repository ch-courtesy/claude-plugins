#!/usr/bin/env bash
# test-forge-routing.sh — origin url 별 호스트 라우팅 + gitlab 확장점 abort 검증.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="$HERE/../forge.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }

# 라우팅 셀프테스트 위임
if bash "$F" selftest; then ok "forge selftest"; else bad "forge selftest"; fi

# gitlab 구현은 호출 시 비-0 (조용한 실패 금지 — 확장점)
( source "$HERE/../gitlab.sh"; fg_integrate x y z ) >/dev/null 2>&1 && bad "gitlab integrate abort" || ok "gitlab integrate abort(비-0)"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
