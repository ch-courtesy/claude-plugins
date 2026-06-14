#!/usr/bin/env python3
"""치환: 템플릿 frontmatter 제거 + placeholder 치환 + 미응답 보존 + temp_path 기본값 적용.

SKILL.md '생성 절차' 5단계의 결정적 치환을 고정한다. 에이전트의 즉흥 정규식
치환을 제거해 미응답 보존·temp_path 기본값·경로 정규화 규칙을 단일 출처로 유지한다.

사용법:
    python3 render_rule.py <template_path>   # answers JSON 은 stdin

answers(JSON 객체) — 키는 입력 name:
  - 문자열 값(비어 있지 않음)  -> 해당 placeholder 를 그 값으로 치환.
    temp_path 값은 normalize_path.py 와 동일 규칙(후행 '/')으로 정규화 후 치환.
  - 빈 문자열 / 키 부재(일반 입력)  -> placeholder 를 그대로 보존(미응답).
  - 빈 문자열 / 키 부재(temp_path)  -> placeholder 를 기본값 '.tmp/' 로 치환.

출력(stdout): frontmatter 를 제거하고 치환을 적용한 본문.
"""
import json
import re
import sys

DEFAULT_TEMP_PATH = ".tmp/"
PLACEHOLDER_RE = re.compile(r"\{\{([^}]+)\}\}")


def strip_frontmatter(text):
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "\n".join(lines[i + 1:])
    return text


def _normalize_path(p):
    """후행 '/' 보장. 빈 문자열이면 기본값."""
    p = p.strip()
    if not p:
        return DEFAULT_TEMP_PATH
    return p if p.endswith("/") else p + "/"


def render(template_text, answers):
    body = strip_frontmatter(template_text)

    def repl(match):
        name = match.group(1).strip()
        value = answers.get(name, "")
        if name == "temp_path":
            # 빈 값이면 기본값 .tmp/, 그 외엔 후행 / 정규화
            return _normalize_path(value) if not value else _normalize_path(value)
        # 일반 입력: 빈 값이면 placeholder 보존
        if not value:
            return match.group(0)
        return value

    return PLACEHOLDER_RE.sub(repl, body)


def main(argv):
    if len(argv) != 1:
        sys.stderr.write(
            "usage: render_rule.py <template_path>  (answers JSON via stdin)\n"
        )
        return 2
    with open(argv[0], encoding="utf-8") as f:
        template_text = f.read()
    raw = sys.stdin.read().strip()
    answers = json.loads(raw) if raw else {}
    if not isinstance(answers, dict):
        sys.stderr.write("error: answers 는 JSON 객체여야 합니다\n")
        return 2
    sys.stdout.write(render(template_text, answers))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
