#!/usr/bin/env bash
# test-worker-vendor-config.sh — loop 엔진 워커 벤더 해석 회귀 가드 (run 635)
#
# 워커 CLI(claude|codex) 선택이 환경변수 AUTOPILOT_WORKER_VENDOR로만 가능하면
# 무인 경로(cron 드레인, env 미전달)에서 항상 기본값으로 떨어진다. 벤더 중립 설정
# SoT인 .autopilot/task-backend.json의 worker_vendor를 loop 엔진이 읽어야 한다.
#
# 우선순위 계약: env > .autopilot/task-backend.json > 기본값 claude.
# 미지원 값은 지원 벤더 목록을 명시한 오류로 중단(조용한 진행 금지).
#
# loop.sh는 디스패처가 BASH_SOURCE 가드 뒤에 있어 source 시 함수만 노출된다
# (test-loop-sh.sh TEST 11/12 패턴 재사용).
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
LOOP_SH="$REPO_ROOT/plugins/autopilot/skills/loop/references/loop.sh"
[[ -f "$LOOP_SH" ]] || { echo "FAIL: loop.sh 부재: $LOOP_SH"; exit 1; }

WORK_DIR="$(mktemp -d)"
# shellcheck disable=SC2064  # trap-set 시점 값으로 고정 의도
trap "rm -rf $WORK_DIR" EXIT

# 격리된 가짜 프로젝트 (실제 저장소의 .autopilot/ 를 읽지 않게)
PROJECT="$WORK_DIR/project"
mkdir -p "$PROJECT/.autopilot"
cd "$PROJECT"
git init -q
git config user.email "test@example.com"
git config user.name "Test"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

write_config() {  # $1 = worker_vendor 값 ("" 이면 필드 없음)
  if [[ -z "${1:-}" ]]; then
    printf '{\n  "backend": "filesystem"\n}\n' > "$PROJECT/.autopilot/task-backend.json"
  else
    printf '{\n  "backend": "filesystem",\n  "worker_vendor": "%s"\n}\n' "$1" \
      > "$PROJECT/.autopilot/task-backend.json"
  fi
}

# loop.sh 를 source 해 worker_vendor 를 평가한다. env 는 호출자가 지정.
eval_vendor() {  # $1 = AUTOPILOT_WORKER_VENDOR 값("" 이면 미설정)
  (
    cd "$PROJECT"
    if [[ -n "${1:-}" ]]; then export AUTOPILOT_WORKER_VENDOR="$1"; else unset AUTOPILOT_WORKER_VENDOR; fi
    source "$LOOP_SH"
    worker_vendor
  )
}

echo "=== T1: 설정 파일 worker_vendor 채택 (env 없음) ==="
write_config codex
got="$(eval_vendor "")"
[[ "$got" == "codex" ]] || fail "T1: 설정 파일 값 미채택. got='$got' want='codex'"
ok "설정 파일 worker_vendor=codex 채택"

echo "=== T2: env 가 설정 파일보다 우선 ==="
write_config codex
got="$(eval_vendor "claude")"
[[ "$got" == "claude" ]] || fail "T2: env override 실패. got='$got' want='claude'"
ok "env AUTOPILOT_WORKER_VENDOR 우선"

echo "=== T3: 설정 필드·env 모두 없음 → 기본값 claude (후방 호환) ==="
write_config ""
got="$(eval_vendor "")"
[[ "$got" == "claude" ]] || fail "T3: 기본값 회귀. got='$got' want='claude'"
rm -f "$PROJECT/.autopilot/task-backend.json"
got="$(eval_vendor "")"
[[ "$got" == "claude" ]] || fail "T3: config 파일 부재 시 기본값 회귀. got='$got' want='claude'"
ok "기본값 claude 유지"

echo "=== T4: 미지원 벤더 값은 지원 목록 명시 오류로 중단 ==="
write_config bogusvendor
set +e
out=$( { cd "$PROJECT"; unset AUTOPILOT_WORKER_VENDOR; source "$LOOP_SH"; worker_executable; } 2>&1 )
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "T4: 미지원 벤더인데 0 exit (조용한 진행). out='$out'"
echo "$out" | grep -q "bogusvendor" || fail "T4: 오류에 문제 값 미포함. out='$out'"
echo "$out" | grep -q "claude" && echo "$out" | grep -q "codex" \
  || fail "T4: 오류에 지원 벤더 목록(claude, codex) 미포함. out='$out'"
ok "미지원 값 거부 + 지원 목록 명시"

echo "=== T5: 링크드 워크트리 안에서도 메인 워크트리 설정을 읽음 ==="
# 설정은 커밋하지 않는다 — 링크드 워크트리에는 파일이 없어야 메인 루트 확정을 실제로 검증한다.
write_config codex
echo placeholder > "$PROJECT/README.md"
git -C "$PROJECT" add README.md
git -C "$PROJECT" commit -qm init
LINKED="$WORK_DIR/linked"
git -C "$PROJECT" worktree add -q --detach "$LINKED" >/dev/null 2>&1
got="$(
  cd "$LINKED"
  unset AUTOPILOT_WORKER_VENDOR
  source "$LOOP_SH"
  worker_vendor
)"
[[ "$got" == "codex" ]] || fail "T5: 링크드 워크트리에서 메인 설정 미해석. got='$got' want='codex'"
ok "링크드 워크트리에서도 메인 워크트리 설정 해석"

echo "ALL PASS"
