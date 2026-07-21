#!/usr/bin/env bash
# scope-coverage-check.sh — SPEC 본문의 scope.include 소스 경로를 덮는
# 기존 테스트 경로가 scope.include에 함께 있는지 검증한다 (#498).
#
# 소스→테스트 매핑은 컨슈밍 프로젝트가 `.autopilot/scope-coverage-map.json` 으로 공급한다.
# 설정 스키마의 단일 출처: references/scope-coverage-map.md
# 설정이 없으면 검사하지 않고 통과한다. 항상 0 exit — 등록을 막지 않고 누락만 플래그한다.
#
# Usage:
#   bash scope-coverage-check.sh [--body-file <path>]
#   echo "<SPEC 본문>" | bash scope-coverage-check.sh
#
# Output (stdout):
#   누락이 있으면 SCOPE_COVERAGE_WARNING + 누락 경로 목록.
#   없으면 빈 출력.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

# 본문 읽기
body_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --body-file) body_file="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -n "$body_file" ]]; then
  body_path="$body_file"
else
  body_path="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$body_path'" EXIT
  cat > "$body_path"
fi

# Python으로 파싱 + 검증 (stdin = 스크립트, argv = 파일경로)
python3 - "$body_path" "$REPO_ROOT" <<'PYEOF'
import sys, re, os, json, glob

body_path = sys.argv[1]
repo_root = sys.argv[2]

try:
    body = open(body_path).read()
except Exception:
    # 파일 읽기 실패 시 조용히 통과 (등록 차단 방지)
    sys.exit(0)

def parse_includes(body):
    """YAML frontmatter의 scope.include 목록을 반환."""
    m = re.match(r'^---\n(.*?)\n---', body, re.DOTALL)
    if not m:
        return []
    fm = m.group(1)
    includes = []
    in_scope = in_include = False
    for line in fm.split('\n'):
        if re.match(r'^scope\s*:', line):
            in_scope = True
            continue
        if in_scope and re.match(r'\s+include\s*:', line):
            in_include = True
            continue
        if in_include:
            s = line.strip()
            if s.startswith('- '):
                val = s[2:].split('#')[0].strip()
                if val:
                    includes.append(val)
            elif s and not s.startswith('#'):
                in_include = in_scope = False
    return includes

def load_rules(repo_root):
    """프로젝트가 공급한 매핑 규칙 목록. 설정이 없거나 불량이면 빈 목록."""
    cfg = os.path.join(repo_root, '.autopilot', 'scope-coverage-map.json')
    if not os.path.isfile(cfg):
        return []
    try:
        with open(cfg) as f:
            return json.load(f).get('rules', [])
    except Exception:
        return []

def is_covered(test_path, includes):
    """테스트 경로가 includes의 항목 중 하나로 커버되는지 확인.

    매핑 관례(scope-coverage-map.md):
    prefix-포함 또는 정확 일치이면 커버드.
    """
    for inc in includes:
        inc_norm = re.sub(r'\*+$', '', inc)
        if test_path.startswith(inc_norm) or inc == test_path:
            return True
    return False

try:
    includes = parse_includes(body)
    rules = load_rules(repo_root)
    if not includes or not rules:
        sys.exit(0)

    missing = []
    checked = set()

    for rule in rules:
        source = rule.get('source', '')
        tests = rule.get('tests', [])
        if not source or not tests:
            continue

        # source 의 <name> 은 경로 세그먼트 1개를 캡처한다.
        if '<name>' in source:
            pre, post = source.split('<name>', 1)
            pattern = '^' + re.escape(pre) + r'([^/]+)' + re.escape(post)
        else:
            pattern = '^' + re.escape(source)

        for inc in includes:
            m = re.match(pattern, inc)
            if not m:
                continue
            name = m.group(1) if m.groups() else ''
            key = (source, name)
            if key in checked:
                continue
            checked.add(key)

            # 실제로 존재하는 기대 테스트 경로만 수집 (신규 소스 오탐 방지)
            existing = []
            for t in tests:
                expected = t.replace('<name>', name)
                if expected.endswith('/'):
                    if os.path.isdir(os.path.join(repo_root, expected)):
                        existing.append(expected)
                else:
                    for p in sorted(glob.glob(os.path.join(repo_root, expected), recursive=True)):
                        existing.append(os.path.relpath(p, repo_root))

            if not existing:
                continue

            if not any(is_covered(exp, includes) for exp in existing):
                rep = existing[0] + (', ...' if len(existing) > 1 else '')
                missing.append(f'[{name or source}] {rep}')

    if missing:
        print('SCOPE_COVERAGE_WARNING: 아래 소스를 덮는 기존 테스트 경로가 scope.include에 없습니다.')
        print('등록은 계속되지만 loop 실행 중 scope 밖 테스트 편집으로 halt될 수 있습니다:')
        for x in missing:
            print(f'  - {x}')
except Exception:
    # 검증 에러 시 조용히 통과 (등록 차단 방지)
    pass
PYEOF
