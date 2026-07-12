#!/usr/bin/env python3
"""파싱: templates/*.md frontmatter -> 정규화된 후보 JSON.

rule-creator 공유 프로토콜(protocol.md) 2~3단계의 결정적 파싱을 고정한다. frontmatter YAML 은
프로젝트 표준 파서인 yq(mikefarah)로 읽는다(rule_checker 와 동일, 새 의존성 아님).

사용법:
    python3 scan_templates.py <skill_dir>

출력(stdout, JSON):
    {"candidates": [{"id","label","description","recommended",
                     "inputs","dynamic_inputs","on_create"} ...],
     "skipped":    [{"id","reason"} ...]}

규칙:
  - id = 템플릿 파일명에서 .md 를 뺀 값.
  - label 필수. 없으면 skipped(후보 제외).
  - recommended: true 인 항목을 맨 앞으로(여럿이면 파일명순), 나머지는 파일명순.
  - inputs/dynamic_inputs 누락 시 빈 리스트, description/on_create 누락 시 null.
"""
import glob
import json
import os
import subprocess
import sys


def _parse_frontmatter(text):
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return None
    block = "\n".join(lines[1:end])
    proc = subprocess.run(
        ["yq", "eval", "-o=json", "-"],
        input=block, capture_output=True, text=True,
    )
    if proc.returncode != 0:
        return None
    out = proc.stdout.strip()
    if not out or out == "null":
        return {}
    try:
        fm = json.loads(out)
    except json.JSONDecodeError:
        return None
    return fm if isinstance(fm, dict) else None


def scan(skill_dir):
    candidates = []
    skipped = []
    paths = sorted(glob.glob(os.path.join(skill_dir, "templates", "*.md")))
    for path in paths:
        sub_id = os.path.basename(path)[:-3]
        with open(path, encoding="utf-8") as f:
            fm = _parse_frontmatter(f.read())
        if fm is None:
            skipped.append({"id": sub_id, "reason": "frontmatter 파싱 실패"})
            continue
        if not fm.get("label"):
            skipped.append({"id": sub_id, "reason": "label 필수 필드 누락"})
            continue
        candidates.append({
            "id": sub_id,
            "label": fm["label"],
            "description": fm.get("description"),
            "recommended": bool(fm.get("recommended", False)),
            "inputs": fm.get("inputs") or [],
            "dynamic_inputs": fm.get("dynamic_inputs") or [],
            "on_create": fm.get("on_create"),
        })
    candidates.sort(key=lambda c: (not c["recommended"], c["id"]))
    return {"candidates": candidates, "skipped": skipped}


def main(argv):
    if len(argv) != 1:
        sys.stderr.write("usage: scan_templates.py <skill_dir>\n")
        return 2
    print(json.dumps(scan(argv[0]), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
