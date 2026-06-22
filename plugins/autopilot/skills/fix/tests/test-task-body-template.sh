#!/usr/bin/env bash
# test-task-body-template.sh — fix 본문 템플릿이 frontmatter-first 스펙 구조 + 진단 섹션이고
#   title H1·depends_on 이 없으며 자체 ears-patterns 를 가리키는지 검증(#471).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF="$HERE/../references"
TPL="$REF/task-body-template.md"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }

skel="$(awk '/^```/{f=!f;next} f' "$TPL")"

first="$(printf '%s\n' "$skel" | sed '/^$/d' | head -1)"
[[ "$first" == "---" ]] && ok "스켈레톤 frontmatter-first(--- 시작)" || bad "frontmatter-first (got '$first')"

grep -q '^scope:' <<<"$skel"   && ok "scope: 존재" || bad "scope: 존재"
grep -q 'include:' <<<"$skel"  && ok "scope.include 존재" || bad "scope.include 존재"
grep -q 'rules/\*\*' <<<"$skel" && ok "exclude rules/** 존재" || bad "exclude rules/** 존재"

for s in '## 무엇을 만들 것인가' '## 목적' '## 진단' '## 완료 조건' '## 범위' '## 검증'; do
  grep -qF "$s" <<<"$skel" && ok "섹션 $s" || bad "섹션 $s"
done

# 진단 하위 항목 유지
for s in '### 증상' '### 재현 맥락' '### 근본 원인 가설'; do
  grep -qF "$s" <<<"$skel" && ok "진단 $s" || bad "진단 $s"
done

# 진단은 목적 다음, 완료 조건 앞
ln_p="$(grep -nF '## 목적' <<<"$skel" | head -1 | cut -d: -f1)"
ln_d="$(grep -nF '## 진단' <<<"$skel" | head -1 | cut -d: -f1)"
ln_a="$(grep -nF '## 완료 조건' <<<"$skel" | head -1 | cut -d: -f1)"
[[ -n "$ln_p" && -n "$ln_d" && -n "$ln_a" && "$ln_p" -lt "$ln_d" && "$ln_d" -lt "$ln_a" ]] \
  && ok "진단 위치(목적<진단<완료 조건)" || bad "진단 위치 (목적=$ln_p 진단=$ln_d 완료=$ln_a)"

grep -q 'depends_on' <<<"$skel" && bad "depends_on 미포함" || ok "depends_on 미포함"
h1="$(grep -E '^# ' <<<"$skel" | grep -v 'ears_language' || true)"
[[ -z "$h1" ]] && ok "title H1 미포함" || bad "title H1 미포함 (got '$h1')"

grep -q 'references/ears-patterns.md' "$TPL" && ok "ears-patterns 자체참조" || bad "ears-patterns 자체참조"
[[ -f "$REF/ears-patterns.md" ]] && ok "ears-patterns.md 존재" || bad "ears-patterns.md 존재"
grep -q 'skills/spec' "$REF/ears-patterns.md" && bad "spec 스킬 미참조" || ok "spec 스킬 미참조"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
