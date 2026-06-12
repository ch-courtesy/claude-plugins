#!/usr/bin/env bash
# skill-rubric: rule_checker.py 단위 테스트
# 알려진 good/bad 픽스처로 규칙 검사기의 판정·등급·exit code를 검증한다.
# 의존성: python3, bash. 프레임워크 없음(echo OK/FAIL 패턴).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
CHECKER="$REPO_ROOT/plugins/skill-rubric/skills/rubric/references/rule_checker.py"
REFDIR="$REPO_ROOT/plugins/skill-rubric/skills/rubric/references"
FIXTURES="$REPO_ROOT/tests/skill-rubric/fixtures"
RUBRIC_SKILL="$REPO_ROOT/plugins/skill-rubric/skills/rubric/SKILL.md"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

# 검사기 실행: out.json 저장, exit code를 EC 전역에 기록(set -e 회피).
run() {
  EC=0
  python3 "$CHECKER" "$@" > "$tmp/out.json" 2> "$tmp/err.txt" || EC=$?
}

# 단일 결과(results[0])에 대한 key=value 단언.
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
    elif k.startswith("type:"):
        got = checks[k[5:]]["check_type"]
    else:
        raise SystemExit("unknown assert key: " + k)
    if str(got) != v:
        raise SystemExit(f"  {k}: expected '{v}' got '{got}'")
PY

assert_json() {  # $1=label, 나머지=단언들
  local label="$1"; shift
  python3 "$ASSERT" "$tmp/out.json" "$@" || fail "$label"
}

# TEST 0: 필수 산출물 존재
[ -f "$CHECKER" ] || fail "rule_checker.py 부재"
[ -f "$REFDIR/rubric-definitions.md" ] || fail "rubric-definitions.md 부재"
[ -f "$REFDIR/output-schema.json" ] || fail "output-schema.json 부재"
ok "필수 파일 존재"

# TEST 1: good-fixture → 17항목 전부 통과(S, 0/0/0)
run "$FIXTURES/good-fixture/SKILL.md"
assert_json "good-fixture는 S 0/0/0 이어야 함" grade=S blocker=0 major=0 minor=0
[ "$EC" -eq 0 ] || fail "good-fixture exit code 0 기대(실제 $EC)"
ok "good-fixture: 규칙 17 전부 통과(S)"

# TEST 2: blocker-xml-tag → S-NO-XML BLOCKER → F, exit 1
run "$FIXTURES/blocker-xml-tag/SKILL.md"
assert_json "blocker-xml-tag는 F + S-NO-XML FAIL" grade=F pass:S-NO-XML=false
[ "$EC" -eq 1 ] || fail "blocker-xml-tag exit code 1 기대(실제 $EC)"
ok "blocker-xml-tag: S-NO-XML BLOCKER → F"

# TEST 3: blocker-no-yaml → S-YAML BLOCKER → F
run "$FIXTURES/blocker-no-yaml/SKILL.md"
assert_json "blocker-no-yaml는 F + S-YAML FAIL" grade=F pass:S-YAML=false
ok "blocker-no-yaml: S-YAML BLOCKER → F"

# TEST 4: blocker-secret → SEC-SECRET BLOCKER → F
run "$FIXTURES/blocker-secret/SKILL.md"
assert_json "blocker-secret는 F + SEC-SECRET FAIL" grade=F pass:SEC-SECRET=false
ok "blocker-secret: SEC-SECRET BLOCKER → F"

# TEST 5: major-unknown-key → S-ALLOWED-KEYS MAJOR(블로커 0) → A
run "$FIXTURES/major-unknown-key/SKILL.md"
assert_json "major-unknown-key는 A + S-ALLOWED-KEYS FAIL" \
  grade=A blocker=0 major=1 pass:S-ALLOWED-KEYS=false
ok "major-unknown-key: S-ALLOWED-KEYS MAJOR → A"

# TEST 6: 500줄 초과 본문 → C-LENGTH MINOR(런타임 생성)
mkdir -p "$tmp/long-body"
{
  echo '---'
  echo 'name: long-body'
  echo 'description: "본문이 500줄을 넘어 C-LENGTH MINOR를 유발하는 픽스처 — 길이 검사 확인용으로 사용한다."'
  echo 'allowed-tools:'
  echo '  - Read'
  echo '---'
  echo '# long-body'
  for i in $(seq 1 520); do echo "본문 줄 $i"; done
} > "$tmp/long-body/SKILL.md"
run "$tmp/long-body/SKILL.md"
assert_json "long-body는 C-LENGTH FAIL" pass:C-LENGTH=false
ok "long-body: C-LENGTH MINOR 검출"

# TEST 7: rubric 스킬 자가평가 → 규칙 17 전부 통과(S, 0/0/0)
run "$RUBRIC_SKILL"
assert_json "rubric 스킬은 규칙 17 전부 통과(S 0/0/0)" grade=S blocker=0 major=0 minor=0
ok "rubric 스킬 자가평가: 규칙 17 전부 통과(S)"

# TEST 8: check_type 분류 + JSON 상위 필드
assert_json "S-YAML은 rule 타입" type:S-YAML=rule
python3 - "$tmp/out.json" <<'PY' || fail "JSON 상위 필드 누락"
import json, sys
d = json.load(open(sys.argv[1]))
for key in ("schema_version", "evaluated_at", "results", "summary"):
    assert key in d, key
assert len(d["results"][0]["checks"]) == 17, "규칙 항목은 17개여야 함"
PY
ok "JSON 스키마 상위 필드·규칙 17항목 수 확인"

# TEST 9: all 모드 — 저장소 전체 평가
run all "$REPO_ROOT"
python3 - "$tmp/out.json" <<'PY' || fail "all 모드 결과 이상"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["summary"]["total_skills"] >= 15, d["summary"]["total_skills"]
assert any(r["skill_name"] == "rubric" for r in d["results"]), "rubric 미포함"
PY
ok "all 모드: 저장소 전체 평가($(python3 -c "import json;print(json.load(open('$tmp/out.json'))['summary']['total_skills'])")개 스킬)"

echo "ALL CHECKS PASSED"
