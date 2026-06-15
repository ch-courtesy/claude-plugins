#!/usr/bin/env python3
"""경로 정규화: temp_path 입력값에 후행 '/' 를 보장한다.

SKILL.md '생성 절차' 4단계의 경로 정규화를 고정한다. 에이전트가 즉흥으로
후행 슬래시를 붙이는 대신 이 스크립트를 호출해 단일 출처로 정규화한다.

사용법:
    python3 normalize_path.py <path>

출력(stdout): 후행 '/' 가 보장된 경로 문자열.

예:
    ".scratch"   -> ".scratch/"
    ".tmp/"      -> ".tmp/"
    "temp"       -> "temp/"
    ""           -> ".tmp/"  (빈 값은 기본값 .tmp/ 로 대체)
"""
import sys


DEFAULT_TEMP_PATH = ".tmp/"


def normalize(path: str) -> str:
    """후행 '/' 를 보장. 빈 문자열이면 기본값 .tmp/ 를 반환."""
    p = path.strip()
    if not p:
        return DEFAULT_TEMP_PATH
    return p if p.endswith("/") else p + "/"


def main(argv):
    if len(argv) != 1:
        sys.stderr.write("usage: normalize_path.py <path>\n")
        return 2
    print(normalize(argv[0]), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
