#!/usr/bin/env bash
# test-loop-base-ref.sh
#
# resolve_base_ref() 회귀 가드 (#488) — 워크트리 base 를 로컬 체크아웃 HEAD 가
# 아닌 origin/<default-branch> 기준으로 잡는지 검증.
#   C1 stale 로컬 HEAD (기본 모드)        → base 가 origin tip
#   C2 caller 가 base ref 주입            → 그 ref 사용 (origin 무시)
#   C3 origin 부재로 fetch 실패           → 로컬 HEAD fallback + 경고 로그

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP_SH="$SCRIPT_DIR/../../../plugins/autopilot/skills/loop/references/loop.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git 미설치"; exit 0; }

# loop.sh source — dispatcher 는 BASH_SOURCE guard 로 비실행, 함수만 노출.
# shellcheck source=../../../plugins/autopilot/skills/loop/references/loop.sh
source "$LOOP_SH"
set +e   # loop.sh 의 errexit 해제 — 함수 반환·fallback 캡처 위해 필수

fail=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- fixture: bare 원격 + seed + stale 로컬 클론 + origin 전진 ----
REMOTE="$TMP/remote.git"
git init -q --bare -b main "$REMOTE"
SEED="$TMP/seed"
git init -q -b main "$SEED"
git -C "$SEED" config user.email t@t; git -C "$SEED" config user.name t
echo a > "$SEED/f"; git -C "$SEED" add .; git -C "$SEED" commit -qm c1
git -C "$SEED" remote add origin "$REMOTE"; git -C "$SEED" push -q origin main

LOCAL="$TMP/local"
git clone -q "$REMOTE" "$LOCAL"
git -C "$LOCAL" config user.email t@t; git -C "$LOCAL" config user.name t
LOCAL_HEAD="$(git -C "$LOCAL" rev-parse HEAD)"

# origin 전진 — 로컬이 뒤처진 stale 상태 재현.
echo b > "$SEED/f2"; git -C "$SEED" add .; git -C "$SEED" commit -qm c2
git -C "$SEED" push -q origin main
ORIGIN_TIP="$(git -C "$SEED" rev-parse HEAD)"

[[ "$LOCAL_HEAD" != "$ORIGIN_TIP" ]] \
  || { echo "FAIL: fixture — 로컬이 origin 과 동일(stale 아님)"; exit 1; }

# C1 stale 로컬 HEAD, 기본 모드 → origin tip
BASE_REF=""
got="$(resolve_base_ref "$LOCAL" 2>/dev/null)"
if [[ "$got" == "$ORIGIN_TIP" ]]; then
  echo "PASS  C1 stale 로컬 → origin tip"
else
  echo "FAIL  C1 got=$got expected=$ORIGIN_TIP"; fail=1
fi

# C2 caller 주입 base ref → 그 ref 사용(여기선 로컬 옛 HEAD)
BASE_REF="$LOCAL_HEAD"
got="$(resolve_base_ref "$LOCAL" 2>/dev/null)"
if [[ "$got" == "$LOCAL_HEAD" ]]; then
  echo "PASS  C2 주입 ref 사용"
else
  echo "FAIL  C2 got=$got expected=$LOCAL_HEAD"; fail=1
fi
BASE_REF=""

# C3 origin 부재(fetch 실패) → 로컬 HEAD fallback + 경고
NOORIG="$TMP/noorigin"
git init -q -b main "$NOORIG"
git -C "$NOORIG" config user.email t@t; git -C "$NOORIG" config user.name t
echo x > "$NOORIG/f"; git -C "$NOORIG" add .; git -C "$NOORIG" commit -qm c1
NO_HEAD="$(git -C "$NOORIG" rev-parse HEAD)"
err="$TMP/c3.err"
got="$(resolve_base_ref "$NOORIG" 2>"$err")"
if [[ "$got" == "$NO_HEAD" ]] && grep -qi '경고' "$err"; then
  echo "PASS  C3 fetch 실패 → 로컬 HEAD fallback + 경고"
else
  echo "FAIL  C3 got=$got expected=$NO_HEAD err=$(cat "$err")"; fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "FAIL: resolve_base_ref 일부 case 실패"
  exit 1
fi
echo "PASS: resolve_base_ref 모든 case (3건)"
