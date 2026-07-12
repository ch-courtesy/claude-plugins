#!/usr/bin/env bash
# Static contract for the shared rule-creator dispatcher protocol (#574).
# 완결 절차 서술과 결정적 스크립트는 shared/rule-creator/ 1곳에만 존재하고,
# 각 rule-creator SKILL.md 는 그 단일 출처를 참조 + 자기 고유 사항만 담는다.
set -u

ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
SHARED="$ROOT/plugins/project-init/shared/rule-creator"
SKILLS="$ROOT/plugins/project-init/skills"
ENG="$SKILLS/engineering-rule-creator/SKILL.md"
WSP="$SKILLS/workspace-rule-creator/SKILL.md"

fail=0
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc"; fail=1
  fi
}

# --- 단일 사본: 결정적 스크립트는 shared/rule-creator/ 에 각 1개만 ---
for script in scan_templates.py render_rule.py list_target_dirs.py; do
  check "$script exists in shared/rule-creator" test -f "$SHARED/$script"
  check "$script has exactly one copy under plugins/" bash -c \
    "[ \"\$(find '$ROOT/plugins' -name '$script' | wc -l)\" = 1 ]"
done
check "normalize_path.py stays workspace-local (skill-unique)" \
  test -f "$SKILLS/workspace-rule-creator/references/normalize_path.py"

# --- 공유 프로토콜 문서: 완결 서술 + 스크립트 고정 ---
check "shared protocol doc exists" test -f "$SHARED/protocol.md"
check "protocol pins scan_templates.py" grep -q "scan_templates.py" "$SHARED/protocol.md"
check "protocol pins render_rule.py" grep -q "render_rule.py" "$SHARED/protocol.md"
check "protocol pins list_target_dirs.py for depth1_dirs_filtered (drift fix)" bash -c \
  "grep -q 'depth1_dirs_filtered' '$SHARED/protocol.md' && grep -q 'list_target_dirs.py' '$SHARED/protocol.md'"
check "protocol owns overwrite-approval contract" grep -q "덮어쓴다 (교체)" "$SHARED/protocol.md"

# --- 두 SKILL.md: 단일 출처 참조 + 사본 절차 소멸 ---
for skill in "$ENG" "$WSP"; do
  name="$(basename "$(dirname "$skill")")"
  check "$name references shared protocol" \
    grep -q "shared/rule-creator/protocol.md" "$skill"
  check "$name no longer pins local references/scan_templates.py" bash -c \
    "! grep -q 'references/scan_templates.py' '$skill'"
  check "$name no longer pins local references/render_rule.py" bash -c \
    "! grep -q 'references/render_rule.py' '$skill'"
done
check "engineering keeps its empty-bullet phrase (skill-unique)" \
  grep -q "워치 대상 없음 — 검토 필요" "$ENG"
check "workspace keeps temp_path default .tmp/ (skill-unique)" \
  grep -q "\.tmp/" "$WSP"
check "workspace keeps normalize_path.py pinning (skill-unique)" \
  grep -q "references/normalize_path.py" "$WSP"

# --- 드리프트 가드: 두 SKILL.md 본문 사이 5줄 이상 연속 동일 문단 금지 ---
check "no 5+ consecutive identical body lines between the two SKILL.md" \
  python3 - "$ENG" "$WSP" <<'PY'
import sys

def body(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return [l.strip() for l in lines[i + 1:]]
    return [l.strip() for l in lines]

def grams(lines, n=5):
    out = set()
    for i in range(len(lines) - n + 1):
        window = lines[i:i + n]
        if sum(1 for l in window if l) < 2:  # 공백 위주 구간은 문단이 아님
            continue
        out.add(tuple(window))
    return out

a, b = body(sys.argv[1]), body(sys.argv[2])
common = grams(a) & grams(b)
for g in sorted(common):
    sys.stderr.write("duplicated 5-line block:\n  " + "\n  ".join(g) + "\n")
sys.exit(1 if common else 0)
PY

if [ "$fail" -ne 0 ]; then
  echo "protocol-contract: FAIL"
  exit 1
fi
echo "protocol-contract: PASS"
