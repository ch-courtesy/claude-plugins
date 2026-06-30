#!/usr/bin/env bash
# shared/rubric: rule_checker.py 단위 테스트.
# repair-skill·create-skill이 참조하는 결정적 17항목 검사기의 판정·등급·exit code를 검증한다.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$DIR/rule_checker.py"
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
out = json.load(open(sys.argv[1]))
r = out["results"][0]
checks = {c["id"]: c for c in r["checks"]}
for a in sys.argv[2:]:
    k, v = a.split("=", 1)
    if k == "grade":
        got = r["grade"]
    elif k in ("blocker", "major", "minor"):
        got = str(r[k + "_count"])
    elif k.startswith("pass:"):
        got = str(checks[k[5:]]["passed"]).lower()
    else:
        raise SystemExit("unknown assert key: " + k)
    if str(got) != v:
        raise SystemExit(f"  {k}: expected '{v}' got '{got}'")
PY

assert_json() {
  local label="$1"; shift
  python3 "$ASSERT" "$tmp/out.json" "$@" || fail "$label"
}

[ -f "$CHECKER" ] || fail "rule_checker.py 부재"
[ -f "$DIR/criteria.md" ] || fail "criteria.md 부재"
[ -f "$DIR/output-schema.json" ] || fail "output-schema.json 부재"
ok "필수 산출물 존재"

run "$FIXTURES/good-fixture/SKILL.md"
assert_json "good-fixture는 S, BLOCKER 0, MAJOR 0" grade=S blocker=0 major=0
[ "$EC" -eq 0 ] || fail "good-fixture exit code 0 기대(실제 $EC)"
ok "good-fixture: 규칙 17 전부 통과(S)"

run "$FIXTURES/blocker-xml-tag/SKILL.md"
assert_json "blocker-xml-tag는 F + S-NO-XML FAIL" grade=F pass:S-NO-XML=false
[ "$EC" -eq 0 ] || fail "blocker-xml-tag exit code 0 기대(결함은 JSON에, 실제 $EC)"
ok "blocker-xml-tag: S-NO-XML BLOCKER → F"

run "$FIXTURES/major-unknown-key/SKILL.md"
assert_json "major-unknown-key는 A + S-ALLOWED-KEYS FAIL" grade=A blocker=0 major=1 pass:S-ALLOWED-KEYS=false
ok "major-unknown-key: S-ALLOWED-KEYS MAJOR → A"

run "$FIXTURES/__does-not-exist__/SKILL.md"
[ "$EC" -eq 4 ] || fail "존재하지 않는 경로는 exit 4 기대(실제 $EC)"
ok "존재하지 않는 경로: 입력 오류 exit 4"

run all "$DIR/../../../.."
python3 - "$tmp/out.json" <<'PY' || fail "all 모드 결과 이상"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["summary"]["total_skills"] >= 15, d["summary"]["total_skills"]
assert any(r["skill_name"] == "create-skill" for r in d["results"]), "create-skill 미포함"
PY
ok "all 모드: 저장소 전체 평가"

echo "ALL CHECKS PASSED"
