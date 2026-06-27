#!/usr/bin/env bash
# test-loop-read-scope-yaml.sh
#
# read_scope_yaml 회귀 가드: 첫 줄이 `---` 인 일반 frontmatter에서 scope.include·
# test_paths 를 정확히 추출하고, 닫는 `---` 이후 본문은 새어 들어오지 않아야 한다.
# (sed `1,/^---$/` 는 addr2 정규식을 2번째 줄부터 매칭하므로 첫 줄에서 종료되지 않는다.)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP_SH="$SCRIPT_DIR/../../../plugins/autopilot/skills/loop/references/loop.sh"

command -v yq  >/dev/null 2>&1 || { echo "SKIP: yq 미설치"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git 미설치"; exit 0; }

# loop.sh 를 source 해 함수만 사용 (dispatcher 는 BASH_SOURCE guard 로 비실행).
# shellcheck source=../../../plugins/autopilot/skills/loop/references/loop.sh
source "$LOOP_SH"
set +e   # loop.sh 가 켠 errexit 해제 — 테스트는 조건 분기를 직접 제어

fail() { echo "FAIL: $1"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
SPEC_PATH="$tmp/spec.md"
cat > "$SPEC_PATH" <<'SPEC'
---
scope:
  include:
    - src/alpha/**
    - lib/beta.py
  exclude:
    - dist/**
test_paths:
  - tests/**
---
# 제목
본문 — 닫는 --- 이후라 frontmatter 가 아니다.
scope:
  include:
    - SHOULD_NOT_APPEAR
SPEC

inc="$(read_scope_yaml | yq '.scope.include[]' 2>/dev/null)"
[[ -n "$inc" ]] || fail "scope.include 가 비어 있음 — frontmatter 추출 실패"
grep -Fqx 'src/alpha/**' <<<"$inc" || fail "src/alpha/** 누락: [$inc]"
grep -Fqx 'lib/beta.py'  <<<"$inc" || fail "lib/beta.py 누락: [$inc]"
grep -Fq 'SHOULD_NOT_APPEAR' <<<"$inc" && fail "닫는 --- 이후 본문 라인이 frontmatter 로 새어 들어옴"

tp="$(read_scope_yaml | yq '.test_paths[]' 2>/dev/null)"
grep -Fqx 'tests/**' <<<"$tp" || fail "test_paths 추출 실패: [$tp]"

echo "PASS: read_scope_yaml frontmatter 추출 정상 (scope.include·test_paths, 본문 누수 없음)"
