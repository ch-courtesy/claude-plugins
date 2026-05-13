---
id: 04-real-loop
role: spec-compliance-reviewer
description: 실 운영 task — milestones/regular/loops/69 (완료된 루프) 의 실제 SPEC + 최종 commit을 입력으로 사용. 합성 task 3종의 대표성을 보강.
source: milestones/regular/loops/69/SPEC.md (tracked) + origin/autonomous-loop/regular/69 branch commit log
prerequisites:
  - "git: tracked file `milestones/regular/loops/69/SPEC.md` 존재 (모든 clone에 포함)"
  - "git: `origin/autonomous-loop/regular/69` branch fetch 완료 (없으면 `git fetch origin autonomous-loop/regular/69`)"
expected_signal:
  - applies_actual_4_level_verifier_to_real_change
  - finds_or_confirms_no_issues_in_actual_diff
quality_rubric:
  - "[1] SPEC AC를 코드 변경과 1:1 매핑: pass | partial | fail"
  - "[2] 실제 git diff를 읽고 평가 (보고만 보지 않음): pass | partial | fail"
  - "[3] 4-Level 4 단계 모두 명시 점검: pass | partial | fail"
  - "[4] verify 명령 실행 (또는 실행 의지 표명): pass | partial | fail"
  - "[5] 응답 양식 준수: pass | partial | fail"
---

당신은 자율 루프의 현재 이터레이션에서 만든 변경이 작업 명세에 부합하는지 검증합니다.

## 요구사항

`milestones/regular/loops/69/SPEC.md` (git tracked, 모든 clone에 포함) 의 작업 정의·수용 기준·검증 명령을 읽고 적용한다.

## 이번 이터가 한 작업 (자기 보고)

`git log --oneline origin/main..origin/autonomous-loop/regular/69` 의 #69 commit들을 검토. 브랜치가 fetch 안 돼 있으면 `git fetch origin autonomous-loop/regular/69` 후 재시도.

## 임무

이번 이터에서 실제로 변경된 코드를 읽고 헌법 §3.4의 4-Level Verifier에 대해 검증한다:

**Existence**: 수용 기준의 모든 항목에 대응하는 코드 변경이 있는가?
**Substantive**: stub·placeholder가 아닌가?
**Wired**: 새 함수·모듈이 호출처에 사용되는가?
**Runtime**: verify 명령이 통과하는가? (직접 실행)

## 작업 디렉토리

본 워크트리. 모든 도구 호출은 이 디렉토리 기준.

## 응답 양식

✅ Spec compliant — 4 단계 모두 통과
❌ Issues found:
- [Existence] 누락 항목 X (수용 기준 N번)
- [Substantive] stub at file:line
- [Wired] 사용 안 되는 새 함수 X
- [Runtime] verify 실패 (이유)

## 비고

본 task는 합성 1·2번이 가진 단순화 가정(linear 함수·작은 diff)을 깨고, 실 운영 워크트리의 multi-file diff·CI 명령·tooling 의존을 다룰 수 있는지 측정한다.
