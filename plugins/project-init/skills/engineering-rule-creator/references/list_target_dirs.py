#!/usr/bin/env python3
"""명령열: target 루트 depth=1 디렉토리 후보 산출(candidate_source: depth1_dirs_filtered).

SKILL.md '생성 절차' 4-bis 의 결정적 명령열을 고정한다.

사용법:
    python3 list_target_dirs.py <target_root>

출력(stdout, JSON): 정렬된 디렉토리 이름 리스트.

규칙:
  - depth=1 디렉토리만. 파일은 제외.
  - 숨김 디렉토리(이름이 '.' 로 시작)와 {node_modules, dist, build, target} 제외.
  - .gitignore 는 무시한다.
"""
import json
import os
import sys

EXCLUDE = {"node_modules", "dist", "build", "target"}


def list_dirs(root):
    out = []
    for name in os.listdir(root):
        if name.startswith("."):
            continue
        if name in EXCLUDE:
            continue
        if os.path.isdir(os.path.join(root, name)):
            out.append(name)
    return sorted(out)


def main(argv):
    if len(argv) != 1:
        sys.stderr.write("usage: list_target_dirs.py <target_root>\n")
        return 2
    print(json.dumps(list_dirs(argv[0]), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
