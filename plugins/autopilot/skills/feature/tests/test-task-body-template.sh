#!/usr/bin/env bash
# test-task-body-template.sh — feature 본문 템플릿이 frontmatter-first 스펙 구조이고
#   title H1·depends_on 이 없으며 자체 ears-patterns 를 가리키는지 검증(#471).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF="$HERE/../references"
TPL="$REF/task-body-template.md"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }

# 펜스(```markdown … ```) 안 스켈레톤만 추출
skel="$(awk '/^```/{f=!f;next} f' "$TPL")"

# frontmatter-first: 스켈레톤 첫 비어있지 않은 줄이 ---
first="$(printf '%s\n' "$skel" | sed '/^$/d' | head -1)"
[[ "$first" == "---" ]] && ok "스켈레톤 frontmatter-first(--- 시작)" || bad "frontmatter-first (got '$first')"

# scope frontmatter 필드
grep -q '^scope:' <<<"$skel"   && ok "scope: 존재" || bad "scope: 존재"
grep -q 'include:' <<<"$skel"  && ok "scope.include 존재" || bad "scope.include 존재"
grep -q 'rules/\*\*' <<<"$skel" && ok "exclude rules/** 존재" || bad "exclude rules/** 존재"

# 스펙 동등 섹션
for s in '## 무엇을 만들 것인가' '## 목적' '## 완료 조건' '## 범위' '## 검증'; do
  grep -qF "$s" <<<"$skel" && ok "섹션 $s" || bad "섹션 $s"
done

# title H1·depends_on 금지(스켈레톤 안)
grep -q 'depends_on' <<<"$skel" && bad "depends_on 미포함" || ok "depends_on 미포함"
# 스켈레톤에 markdown H1 제목 줄(^# …) 없음 — 단, YAML 주석 '# ears_language' 는 예외
h1="$(grep -E '^# ' <<<"$skel" | grep -v 'ears_language' || true)"
[[ -z "$h1" ]] && ok "title H1 미포함" || bad "title H1 미포함 (got '$h1')"

# EARS 자체 사본 참조(spec 스킬 참조 아님)
grep -q 'references/ears-patterns.md' "$TPL" && ok "ears-patterns 자체참조" || bad "ears-patterns 자체참조"
[[ -f "$REF/ears-patterns.md" ]] && ok "ears-patterns.md 존재" || bad "ears-patterns.md 존재"
grep -q 'skills/spec' "$REF/ears-patterns.md" && bad "spec 스킬 미참조" || ok "spec 스킬 미참조"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
