#!/usr/bin/env python3
"""치환: 템플릿 frontmatter 제거 + {{field}} 치환 + 미응답 보존 + bullet_list 렌더.

SKILL.md '생성 절차' 5단계의 결정적 치환을 고정한다. 에이전트의 즉흥 정규식
치환을 제거해 미응답 보존·bullet 렌더 규칙을 단일 출처로 유지한다.

사용법:
    python3 render_rule.py <template_path>   # answers JSON 은 stdin

answers(JSON 객체) — 키는 입력 name:
  - 문자열 값(비어 있지 않음)  -> {{name}} 을 그 값으로 치환.
  - 빈 문자열 / 키 부재         -> {{name}} 을 그대로 보존(미응답).
  - 리스트 값                   -> bullet_list 로 렌더:
        비어 있지 않으면 각 항목을 '- `<item>`' 로,
        빈 리스트면 '(워치 대상 없음 — 검토 필요)' 로 치환.

출력(stdout): frontmatter 를 제거하고 치환을 적용한 본문.
"""
import json
import re
import sys

EMPTY_LIST_SENTINEL = "(워치 대상 없음 — 검토 필요)"
PLACEHOLDER_RE = re.compile(r"\{\{([^}]+)\}\}")


def strip_frontmatter(text):
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "\n".join(lines[i + 1:])
    return text


def _render_value(value):
    """치환할 문자열을 반환. 보존해야 하면 None 을 반환."""
    if isinstance(value, list):
        if not value:
            return EMPTY_LIST_SENTINEL
        return "\n".join("- `{}`".format(item) for item in value)
    if isinstance(value, str):
        return value if value != "" else None
    if value is None:
        return None
    return str(value)


def render(template_text, answers):
    body = strip_frontmatter(template_text)

    def repl(match):
        name = match.group(1).strip()
        if name not in answers:
            return match.group(0)
        rendered = _render_value(answers[name])
        return match.group(0) if rendered is None else rendered

    return PLACEHOLDER_RE.sub(repl, body)


def main(argv):
    if len(argv) != 1:
        sys.stderr.write("usage: render_rule.py <template_path>  (answers JSON via stdin)\n")
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
