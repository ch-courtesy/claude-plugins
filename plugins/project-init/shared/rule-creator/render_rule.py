#!/usr/bin/env python3
"""치환: 템플릿 frontmatter 제거 + placeholder 치환 + 미응답 보존
+ bullet_list 렌더 + temp_path 기본값·경로 정규화.

rule-creator 공유 프로토콜(protocol.md) 5단계의 결정적 치환을 고정한다.
에이전트의 즉흥 정규식 치환을 제거해 치환 규칙을 단일 출처로 유지한다.

사용법:
    python3 render_rule.py <template_path> [empty_list_sentinel]
    # answers JSON 은 stdin

answers(JSON 객체) — 키는 입력 name:
  - 문자열 값(비어 있지 않음)  -> 해당 placeholder 를 그 값으로 치환.
  - 빈 문자열 / 키 부재(일반 입력)  -> placeholder 를 그대로 보존(미응답).
  - 리스트 값                   -> bullet_list 로 렌더:
        비어 있지 않으면 각 항목을 '- `<item>`' 로,
        빈 리스트면 empty_list_sentinel(스킬 고유 문구, 미지정 시
        '(대상 없음 — 검토 필요)') 로 치환.
  - temp_path 특례              -> normalize_path.py 와 동일 규칙(후행 '/')으로
        정규화 후 치환. 빈 문자열/키 부재면 기본값 '.tmp/' 로 치환.

출력(stdout): frontmatter 를 제거하고 치환을 적용한 본문.
"""
import json
import re
import sys

DEFAULT_EMPTY_LIST_SENTINEL = "(대상 없음 — 검토 필요)"
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


def _render_value(value, empty_list_sentinel):
    """치환할 문자열을 반환. 보존해야 하면 None 을 반환."""
    if isinstance(value, list):
        if not value:
            return empty_list_sentinel
        return "\n".join("- `{}`".format(item) for item in value)
    if isinstance(value, str):
        return value if value != "" else None
    if value is None:
        return None
    return str(value)


def render(template_text, answers, empty_list_sentinel=DEFAULT_EMPTY_LIST_SENTINEL):
    body = strip_frontmatter(template_text)

    def repl(match):
        name = match.group(1).strip()
        if name == "temp_path":
            value = answers.get(name, "")
            return _normalize_path(value if isinstance(value, str) else str(value))
        if name not in answers:
            return match.group(0)
        rendered = _render_value(answers[name], empty_list_sentinel)
        return match.group(0) if rendered is None else rendered

    return PLACEHOLDER_RE.sub(repl, body)


def main(argv):
    if len(argv) not in (1, 2):
        sys.stderr.write(
            "usage: render_rule.py <template_path> [empty_list_sentinel]"
            "  (answers JSON via stdin)\n"
        )
        return 2
    with open(argv[0], encoding="utf-8") as f:
        template_text = f.read()
    sentinel = argv[1] if len(argv) == 2 else DEFAULT_EMPTY_LIST_SENTINEL
    raw = sys.stdin.read().strip()
    answers = json.loads(raw) if raw else {}
    if not isinstance(answers, dict):
        sys.stderr.write("error: answers 는 JSON 객체여야 합니다\n")
        return 2
    sys.stdout.write(render(template_text, answers, sentinel))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
