#!/usr/bin/env bash
# test-task-body-template.sh — 작성자 공용(feature·fix) 본문 템플릿 단일 출처 검증.
#   frontmatter-first 스펙 구조, title H1·depends_on 부재, 진단 섹션(fix 전용) 위치,
#   ears-patterns 공용 참조를 검증한다(#471 feature/fix 개별 테스트 통합).
set -uo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
REF="$REPO_ROOT/plugins/autopilot/lib/references"
TPL="$REF/task-body-template.md"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }

[[ -f "$TPL" ]] || { echo "FAIL  공용 task-body-template.md 부재"; exit 1; }

# 펜스(```markdown … ```) 안 스켈레톤만 추출
skel="$(awk '/^```/{f=!f;next} f' "$TPL")"

# frontmatter-first: 스켈레톤 첫 비어있지 않은 줄이 ---
first="$(printf '%s\n' "$skel" | sed '/^$/d' | head -1)"
[[ "$first" == "---" ]] && ok "스켈레톤 frontmatter-first(--- 시작)" || bad "frontmatter-first (got '$first')"

# scope frontmatter 필드
grep -q '^scope:' <<<"$skel"   && ok "scope: 존재" || bad "scope: 존재"
grep -q 'include:' <<<"$skel"  && ok "scope.include 존재" || bad "scope.include 존재"
grep -q 'rules/\*\*' <<<"$skel" && ok "exclude rules/** 존재" || bad "exclude rules/** 존재"

# 스펙 동등 섹션 (진단 = fix 전용 형판 포함)
for s in '## 무엇을 만들 것인가' '## 목적' '## 진단' '## 완료 조건' '## 범위' '## 검증'; do
  grep -qF "$s" <<<"$skel" && ok "섹션 $s" || bad "섹션 $s"
done

# 진단 하위 항목 유지 (fix 전용)
for s in '### 증상' '### 재현 맥락' '### 근본 원인 가설'; do
  grep -qF "$s" <<<"$skel" && ok "진단 $s" || bad "진단 $s"
done

# 진단은 목적 다음, 완료 조건 앞
ln_p="$(grep -nF '## 목적' <<<"$skel" | head -1 | cut -d: -f1)"
ln_d="$(grep -nF '## 진단' <<<"$skel" | head -1 | cut -d: -f1)"
ln_a="$(grep -nF '## 완료 조건' <<<"$skel" | head -1 | cut -d: -f1)"
[[ -n "$ln_p" && -n "$ln_d" && -n "$ln_a" && "$ln_p" -lt "$ln_d" && "$ln_d" -lt "$ln_a" ]] \
  && ok "진단 위치(목적<진단<완료 조건)" || bad "진단 위치 (목적=$ln_p 진단=$ln_d 완료=$ln_a)"

# 진단 섹션이 fix 전용임을 형판이 명시(feature 본문엔 없음)
grep -q 'fix 전용' "$TPL" && ok "진단 fix 전용 표기" || bad "진단 fix 전용 표기"

# title H1·depends_on 금지(스켈레톤 안)
grep -q 'depends_on' <<<"$skel" && bad "depends_on 미포함" || ok "depends_on 미포함"
# 스켈레톤에 markdown H1 제목 줄(^# …) 없음 — 단, YAML 주석 '# ears_language' 는 예외
h1="$(grep -E '^# ' <<<"$skel" | grep -v 'ears_language' || true)"
[[ -z "$h1" ]] && ok "title H1 미포함" || bad "title H1 미포함 (got '$h1')"

# EARS 공용 단일 출처 참조(spec 스킬 참조 아님)
grep -q 'ears-patterns.md' "$TPL" && ok "ears-patterns 참조" || bad "ears-patterns 참조"
[[ -f "$REF/ears-patterns.md" ]] && ok "공용 ears-patterns.md 존재" || bad "공용 ears-patterns.md 존재"
grep -q 'skills/spec' "$REF/ears-patterns.md" && bad "spec 스킬 미참조" || ok "spec 스킬 미참조"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
