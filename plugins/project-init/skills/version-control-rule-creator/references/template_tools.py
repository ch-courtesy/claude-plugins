#!/usr/bin/env python3
"""version-control-rule-creator의 결정적 보조 도구.

SKILL.md 생성 절차 중 에이전트가 즉흥 재현하면 틀리기 쉬운 결정적 작업만 고정한다.
과설계 금지: 아래 세 가지(파싱·분류·집계) 외의 로직은 두지 않는다.

서브커맨드:
  parse-name <filename>   templates/ 파일명 → "<sub_rule_id>\t<backend>" (변형 없으면 backend 빈칸)
  git-family <backend>    백엔드 식별자가 git 계열이면 exit 0, 아니면 exit 1 (정적 매핑)
  aggregate <v1> <v2> ..  선택된 옵션 값들을 표시 순서로 빈 줄 하나로 이어붙여 출력
"""
import sys

# git 계열 분류의 단일 출처. 매핑에 없는 백엔드의 기본값은 "git 계열 아님".
GIT_FAMILY = {"github", "gitlab"}


def parse_name(filename):
    """파일명에서 .md 제거 후, 점이 있으면 마지막 점 뒤가 backend·앞이 sub-룰 ID.
    점이 없으면 전체가 sub-룰 ID(백엔드 변형 없음). 호스트명 substring 추측을 하지 않는다."""
    base = filename[:-3] if filename.endswith(".md") else filename
    if "." in base:
        sub, backend = base.rsplit(".", 1)
        return sub, backend
    return base, ""


def is_git_family(backend):
    return backend in GIT_FAMILY


def aggregate(values):
    """선택된 옵션 값들을 표시 순서로 빈 줄 하나로 구분해 연결한다. 빈 값은 제외."""
    return "\n\n".join(v for v in values if v.strip())


def main(argv):
    if len(argv) < 2:
        print("usage: template_tools.py {parse-name|git-family|aggregate} ...",
              file=sys.stderr)
        return 2
    cmd = argv[1]
    if cmd == "parse-name":
        if len(argv) < 3:
            print("usage: template_tools.py parse-name <filename>", file=sys.stderr)
            return 2
        sub, backend = parse_name(argv[2])
        print(f"{sub}\t{backend}")
        return 0
    if cmd == "git-family":
        if len(argv) < 3:
            print("usage: template_tools.py git-family <backend>", file=sys.stderr)
            return 2
        return 0 if is_git_family(argv[2]) else 1
    if cmd == "aggregate":
        print(aggregate(argv[2:]))
        return 0
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
