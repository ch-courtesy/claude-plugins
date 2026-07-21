#!/usr/bin/env bash
# test-github-status-fail.sh — set_status 라벨 설정 실패 시 원본 stderr 가 진단에 보존되는지 검증(github).
# 회귀 가드: 권한 거부 등 실제 원인이 "라벨 존재 필요" 고정 문구로 오귀속되지 않아야 한다.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
A="$HERE/../adapter.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q; git config user.email t@t; git config user.name t
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }

# gh 스텁: --add-label 편집만 권한 거부로 실패, 나머지는 성공(무출력).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
GH_FAIL_MODE="${GH_FAIL_MODE:-perm}"
for a in "$@"; do
  if [[ "$a" == "--add-label" && "$GH_FAIL_MODE" == "perm" ]]; then
    echo "GraphQL: someuser does not have the correct permissions to execute AddLabelsToLabelable (addLabelsToLabelable)" >&2
    exit 1
  fi
done
exit 0
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

bash "$A" init --backend github-project --github-owner o --github-repo r >/dev/null

# 실패 경로: 권한 거부 → 원본 메시지 보존, "라벨 존재 필요" 단정 없음, 비0 exit
set +e
err="$(bash "$A" set_status --task-id 42 --status in_progress 2>&1 >/dev/null)"
rc=$?
set -e
[[ $rc -ne 0 ]] && ok "실패 시 비0 exit" || bad "실패 시 비0 exit (rc=$rc)"
[[ "$err" == *"does not have the correct permissions"* ]] \
  && ok "원본 stderr 보존" || bad "원본 stderr 보존 (got '$err')"
[[ "$err" != *"라벨 존재 필요"* ]] \
  && ok "라벨 부재 오귀속 없음" || bad "라벨 부재 오귀속 없음 (got '$err')"

# 성공 경로: 진단 무출력
set +e
err2="$(GH_FAIL_MODE=none bash "$A" set_status --task-id 42 --status backlog 2>&1 >/dev/null)"
rc2=$?
set -e
[[ $rc2 -eq 0 && -z "$err2" ]] && ok "성공 시 무진단" || bad "성공 시 무진단 (rc=$rc2, got '$err2')"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
