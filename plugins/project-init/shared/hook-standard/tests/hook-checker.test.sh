#!/usr/bin/env bash
# shared/hook-standard: hook_checker.py 단위 테스트.
# 소비 프로젝트 .claude/hooks/ 구조 표준의 결정적 검사기 판정·등급·exit code를 검증한다.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$DIR/hook_checker.py"
FIXTURES="$DIR/tests/fixtures"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

run() {
  EC=0
  python3 "$CHECKER" "$@" > "$tmp/out.json" 2> "$tmp/err.txt" || EC=$?
}

ASSERT="$tmp/assert.py"
cat > "$ASSERT" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
checks = {c["id"]: c for c in r["checks"]}
for a in sys.argv[2:]:
    k, v = a.split("=", 1)
    if k == "grade":
        got = r["grade"]
    elif k in ("blocker", "major", "minor"):
        got = str(r[k + "_count"])
    elif k.startswith("pass:"):
        got = str(checks[k[5:]]["passed"]).lower()
    elif k.startswith("evidence:"):
        cid = k[len("evidence:"):]
        got = "nonempty" if checks[cid]["evidence"].strip() else "empty"
    else:
        raise SystemExit("unknown assert key: " + k)
    if str(got) != v:
        raise SystemExit(f"  {k}: expected '{v}' got '{got}'")
PY

assert_json() {
  local label="$1"; shift
  python3 "$ASSERT" "$tmp/out.json" "$@" || fail "$label"
}

[ -f "$CHECKER" ] || fail "hook_checker.py 부재"
[ -f "$DIR/standard.md" ] || fail "standard.md 부재"
[ -f "$DIR/checker-invocation.md" ] || fail "checker-invocation.md 부재"
ok "필수 산출물 존재"

# 표준 문서가 검사기 항목과 모델 판정 항목을 분리된 절로 정의한다
grep -q '^## .*모델 판정' "$DIR/standard.md" || fail "standard.md 모델 판정 절 부재"
grep -q '^## .*검사기' "$DIR/standard.md" || fail "standard.md 검사기 항목 절 부재"
ok "standard.md: 검사기 항목·모델 판정 항목 분리 절"

# 픽스처의 실행권한은 git mode 로 보존되지만, 체크아웃 환경 차이를 배제하기 위해 명시 부여.
chmod +x "$FIXTURES"/good/hooks/*.sh "$FIXTURES"/good/hooks/lib/*/*.sh
chmod +x "$FIXTURES"/violation-bad-name/hooks/*.sh
chmod +x "$FIXTURES"/violation-settings-mismatch/hooks/*.sh
chmod +x "$FIXTURES"/violation-wrong-event/hooks/*.sh
chmod +x "$FIXTURES"/violation-stray-script/hooks/*.sh "$FIXTURES"/violation-stray-script/hooks/helpers/*.sh
chmod +x "$FIXTURES"/violation-shebang/hooks/*.sh
chmod -x "$FIXTURES"/violation-no-exec/hooks/pre-tool-use.sh

run "$FIXTURES/good/hooks"
[ "$EC" -eq 0 ] || fail "good exit code 0 기대(실제 $EC): $(cat "$tmp/err.txt")"
assert_json "good 픽스처는 BLOCKER·MAJOR 0" grade=S blocker=0 major=0
ok "good: 표준 준수 → BLOCKER·MAJOR 0"

run "$FIXTURES/violation-bad-name/hooks"
[ "$EC" -eq 0 ] || fail "결함 존재는 실패가 아님 — exit 0 기대(실제 $EC)"
assert_json "비이벤트명 핸들러는 L-EVENT-NAME FAIL" grade=F pass:L-EVENT-NAME=false evidence:L-EVENT-NAME=nonempty
ok "violation-bad-name: L-EVENT-NAME BLOCKER → F"

run "$FIXTURES/violation-no-exec/hooks"
[ "$EC" -eq 0 ] || fail "violation-no-exec exit 0 기대(실제 $EC)"
assert_json "실행권한 없음은 S-EXEC-HANDLER FAIL" grade=F pass:S-EXEC-HANDLER=false evidence:S-EXEC-HANDLER=nonempty
ok "violation-no-exec: S-EXEC-HANDLER BLOCKER → F"

run "$FIXTURES/violation-settings-mismatch/hooks"
[ "$EC" -eq 0 ] || fail "violation-settings-mismatch exit 0 기대(실제 $EC)"
assert_json "등록↔파일 불일치는 양방향 FAIL" grade=F pass:G-REGISTERED=false pass:G-FILE-EXISTS=false \
  evidence:G-REGISTERED=nonempty evidence:G-FILE-EXISTS=nonempty
ok "violation-settings-mismatch: G-REGISTERED·G-FILE-EXISTS BLOCKER → F"

# 같은 파일명이라도 다른 이벤트에 등록되면 정합이 아니다 — (이벤트, 파일명) 쌍 비교.
run "$FIXTURES/violation-wrong-event/hooks"
[ "$EC" -eq 0 ] || fail "violation-wrong-event exit 0 기대(실제 $EC)"
assert_json "다른 이벤트 등록은 G-REGISTERED FAIL" grade=F pass:G-REGISTERED=false \
  pass:G-FILE-EXISTS=true evidence:G-REGISTERED=nonempty
ok "violation-wrong-event: 이벤트↔핸들러 불일치 G-REGISTERED BLOCKER → F"

run "$FIXTURES/violation-stray-script/hooks"
[ "$EC" -eq 0 ] || fail "violation-stray-script exit 0 기대(실제 $EC)"
assert_json "lib 밖 기능 스크립트는 L-NO-STRAY-SCRIPT FAIL" blocker=0 pass:L-NO-STRAY-SCRIPT=false \
  evidence:L-NO-STRAY-SCRIPT=nonempty
ok "violation-stray-script: L-NO-STRAY-SCRIPT MAJOR"

run "$FIXTURES/violation-shebang/hooks"
[ "$EC" -eq 0 ] || fail "violation-shebang exit 0 기대(실제 $EC)"
assert_json "셔뱅 불일치는 S-SHEBANG FAIL" blocker=0 pass:S-SHEBANG=false evidence:S-SHEBANG=nonempty
ok "violation-shebang: S-SHEBANG MAJOR"

# settings.local.json 에만 등록돼도 위반이 아니다(과판정 회피).
cp -r "$FIXTURES/good" "$tmp/local-only"
mv "$tmp/local-only/settings.json" "$tmp/local-only/settings.local.json"
run "$tmp/local-only/hooks"
assert_json "settings.local.json 등록도 인정" pass:G-REGISTERED=true
ok "settings.local.json 단독 등록: 과판정 없음"

# 인용부호·인터프리터 접두 명령도 핸들러 참조로 인식한다(과판정 회피).
cp -r "$FIXTURES/good" "$tmp/quoted-cmd"
cat > "$tmp/quoted-cmd/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "hooks": [ { "type": "command", "command": "\"${CLAUDE_PROJECT_DIR}/.claude/hooks/pre-tool-use.sh\"" } ] }
    ],
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "sh \"${CLAUDE_PROJECT_DIR}/.claude/hooks/session-start.sh\"" } ] }
    ]
  }
}
JSON
run "$tmp/quoted-cmd/hooks"
assert_json "인용·인터프리터 접두 등록도 정합" grade=S blocker=0 major=0
ok "인용부호·인터프리터 접두 명령: 과판정 없음"

# 훅 디렉터리 직속의 비스크립트 파일(README 등)은 핸들러 판정 대상이 아니다.
cp -r "$FIXTURES/good" "$tmp/with-readme"
echo '# hooks' > "$tmp/with-readme/hooks/README.md"
run "$tmp/with-readme/hooks"
assert_json "직속 README.md 는 핸들러 위반이 아님" grade=S blocker=0 major=0 \
  pass:L-EVENT-NAME=true pass:S-EXEC-HANDLER=true pass:G-REGISTERED=true
ok "직속 비스크립트 파일: 과판정 없음"

run "$FIXTURES/__does-not-exist__/hooks"
[ "$EC" -eq 4 ] || fail "존재하지 않는 경로는 exit 4 기대(실제 $EC)"
ok "존재하지 않는 경로: 입력 오류 exit 4"

echo "ALL CHECKS PASSED"
