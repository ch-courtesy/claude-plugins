# Agent dispatch briefs (optimized)

자율 루프 한 이터 안에서 Agent를 위임할 때 쓰는 brief. 결정·합성은 항상 메인 이터 책임이다.

## spec-compliance-reviewer

용도: 변경이 SPEC 수용 기준과 4-Level Verifier(existence/substantive/wired/runtime)에 맞는지 독립 검증. 권장 모델: sonnet.

Prompt:

```text
현재 이터 변경이 작업 명세에 부합하는지 검증하라.

## 요구사항
[SPEC.md의 작업 정의·수용 기준·범위·verify를 paste. 다시 읽게 하지 말 것]

## 이번 이터 작업
[git diff HEAD~1 HEAD 요약 + 의도]

## 임무
실제 변경 코드를 읽고 다음을 점검:
- Existence: 모든 수용 기준 대응 변경 존재?
- Substantive: stub/mock/TODO/pass/return None/NotImplementedError 아님?
- Wired: 새 코드가 실제 import/use됨?
- Runtime: verify 통과 주장은 직접 실행해 확인.

## 금지
자기 보고만 믿기, verify 미실행 통과 인정, 작은 변경이라며 생략.

## 작업 디렉토리
<worktree path>

## 응답
✅ Spec compliant
또는
❌ Issues found:
- [Existence] ...
- [Substantive] file:line ...
- [Wired] ...
- [Runtime] ...
```

후속: 통과하면 Self-Review, 실패하면 `.loop/memory.md`에 기록 후 fix·재검토.

## code-quality-reviewer

용도: spec compliance 이후 품질·구조·절제·테스트 검토. 권장 모델: opus.

Prompt:

```text
시니어 코드 리뷰어로 현재 이터 변경을 검토하라.

## 구현 요약
[무엇을 왜]

## 기준
SPEC와 CLAUDE.md Self-Review.

## Git 범위
Base: <sha 또는 HEAD~1>
Head: <sha 또는 working tree>

## 점검
- Quality: 이름, 명료성, 파일 크기·복잡도
- Discipline: YAGNI, 기존 패턴, scope 밖 변경 없음
- Testing: 실제 동작 검증, RED 먼저, edge/error
- Architecture: 기존 구조 정합, 단일 책임, 결합도

## 심각도
Critical=버그/보안/데이터 손실/기능 깨짐
Important=architecture/test/error handling 문제
Minor=style/name/polish

## 응답
### 강점
### 발견 사항
#### Critical
#### Important
#### Minor
### 판정
진행 가능한가? 예 | 아니오 | 수정 후 진행
근거: ...
```

후속: 예면 통과, 수정 후 진행이면 Critical/Important fix, 아니오면 `.loop/memory.md` 의심점.

## parallel-hypothesis-tester

용도: 두 개 이상 독립 가설을 병렬 검증. 권장 모델: sonnet. Agent에게 최종 결정을 맡기지 않는다.

Prompt:

```text
가설 <A/B>를 검증하라. read-only 관찰을 우선하고, 필요 시 최소 변경으로만 검증한다.

## 가설
...

## 관찰할 신호
...

## 금지
다른 가설 판단, 광범위 수정, 최종 결정.

## 응답
- 가설: 지지됨 | 반박됨 | 불충분
- 근거: 관찰/명령/파일
- 다음 검증 제안: ...
```
