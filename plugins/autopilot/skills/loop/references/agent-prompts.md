# Agent dispatch briefs

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

후속: 통과하면 Self-Review, 실패하면 노트에 기록 후 fix·재검토.

## code-quality-reviewer

용도: spec compliance 이후 품질·구조·절제·테스트 검토. 권장 모델: opus.

Prompt:

```text
시니어 코드 리뷰어로 현재 이터 변경을 검토하라.

## 구현 요약
[무엇을 왜]

## 기준
SPEC와 AGENTS.md·CLAUDE.md Self-Review.

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

후속: 예면 통과, 수정 후 진행이면 Critical/Important fix, 아니오면 노트 의심점.

## persona-adversarial-reviewer (적대 렌즈)

용도: 완료 직전 자체 검토에서 **비자명 변경**(diff 100줄 이상 또는 관여 수용기준 2개 이상)을 세 적대 렌즈로 점검. 렌즈는 **발견만 보고**하고 최종 완료·차단 결정은 내리지 않는다(결정은 메인). 권장 모델: sonnet.

렌즈 정의의 단일 출처는 `plugins/autopilot/references/personas.md`(contrarian·minimalist·constraint-auditor)다. 정의를 복제하지 말고 그 카탈로그를 읽혀 적용한다.

Prompt:

```text
이번 이터 변경을 세 적대 렌즈로 점검하라. 렌즈 정의는 personas.md 카탈로그를 읽고 따른다.

## 렌즈 정의 (단일 출처)
plugins/autopilot/references/personas.md 의 contrarian·minimalist·constraint-auditor 를 읽어 적용하라.

## 변경
[git diff HEAD~1 HEAD 요약 + 의도 + 관여 수용기준]

## 임무
각 렌즈로 변경을 점검하고 렌즈 태그와 함께 발견만 보고한다.

## 금지
최종 완료·차단 결정, 변경 수정, 의심점 기록(이것들은 모두 메인 책임).

## 응답
### [contrarian]
- [위치] <발견> — <이유>
### [minimalist]
- ...
### [constraint-auditor]
- ...
```

후속: 메인이 발견을 검토해 수정·완료·의심점 기록을 결정한다. 미해결 의심은 노트 `## 의심점`에 남긴다.

## lateral-recovery-reframer (측면사고 회복)

용도: 워커-판단 정체로 에스컬레이션하기 직전, 에피소드당 **한 번** 근본 원인 가설을 적대 렌즈로 재구성. **읽기(관찰)를 우선**하고 **발견만 보고**한다 — 최소 변경 재시도와 최종 결정은 메인이 수행한다. 권장 모델: sonnet. 페르소나 카탈로그(`personas.md`)를 재사용한다.

Prompt:

```text
정체 상태의 근본 원인 가설을 적대 렌즈로 재구성하라. read-only 관찰을 우선한다.

## 렌즈 (재사용)
plugins/autopilot/references/personas.md 의 세 렌즈로 현재 가설을 비판·재구성하라.

## 정체 상황
[같은 에러/정체/진동/반복 실패 요약 + 지금까지 시도]

## 임무
- 현재 가설의 약점을 렌즈별로 지적
- 관찰로 검증 가능한 대안 가설(들)과 그 신호 제안
읽기 우선. 필요 시에도 광범위 수정은 하지 않는다.

## 금지
최소 변경 재시도 실행, 광범위 수정, 최종 결정(모두 메인 책임).

## 응답
- 재구성된 가설 후보: ...
- 관찰할 신호 / 최소 검증: ...
```

후속: 메인이 한 차례 최소 변경으로 재시도한다. 진전이면 정상 루프, 무진전이면 표준 차단 에스컬레이션. 시도·판정은 노트에 기록.

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
