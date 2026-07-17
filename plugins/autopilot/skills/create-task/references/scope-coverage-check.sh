#!/usr/bin/env bash
# scope-coverage-check.sh — SPEC 본문의 scope.include 소스 경로를 덮는
# 기존 테스트 경로가 scope.include에 함께 있는지 검증한다 (#498).
#
# 매핑 관례의 단일 출처: references/scope-coverage-map.md
# 항상 0 exit — 등록을 막지 않고 누락만 플래그한다.
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
import sys, re, os

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
    if not includes:
        sys.exit(0)

    missing = []
    checked = set()

    for inc in includes:
        # 매핑 규칙 1: plugins/autopilot/skills/<S>/...
        m = re.match(r'^plugins/autopilot/skills/([^/]+)/', inc)
        if m:
            skill = m.group(1)
            if skill in checked:
                continue
            checked.add(skill)

            expected = []

            # 1a) tests/autopilot/<S>/ 디렉터리
            dir_test = f'tests/autopilot/{skill}/'
            if os.path.isdir(os.path.join(repo_root, dir_test)):
                expected.append(dir_test)

            # 1b) tests/autopilot/test-<S>*.sh 파일
            test_dir = os.path.join(repo_root, 'tests/autopilot')
            if os.path.isdir(test_dir):
                for f in sorted(os.listdir(test_dir)):
                    if f.startswith(f'test-{skill}') and f.endswith('.sh'):
                        expected.append(f'tests/autopilot/{f}')

            # 기존 테스트 없는 신규 소스 → 오탐 방지, 통과
            if not expected:
                continue

            if not any(is_covered(exp, includes) for exp in expected):
                rep = expected[0] + (', ...' if len(expected) > 1 else '')
                missing.append(f'[{skill}] {rep}')
            continue

        # 매핑 규칙 2: plugins/autopilot/lib/task-backend/...
        if inc.startswith('plugins/autopilot/lib/task-backend/') and 'task-backend' not in checked:
            checked.add('task-backend')
            tb_dir = 'plugins/autopilot/lib/task-backend/tests/'
            if os.path.isdir(os.path.join(repo_root, tb_dir)):
                if not is_covered(tb_dir, includes):
                    missing.append(f'[task-backend] {tb_dir}')

    if missing:
        print('SCOPE_COVERAGE_WARNING: 아래 소스를 덮는 기존 테스트 경로가 scope.include에 없습니다.')
        print('등록은 계속되지만 loop 실행 중 scope 밖 테스트 편집으로 halt될 수 있습니다:')
        for x in missing:
            print(f'  - {x}')
except Exception:
    # 검증 에러 시 조용히 통과 (등록 차단 방지)
    pass
PYEOF
