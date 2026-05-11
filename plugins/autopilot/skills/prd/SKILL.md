---
name: prd
description: "autopilot:dispatch 입력으로 받는 PRD(Product Requirements Document)를 대화형 9-step으로 작성. 한 질문씩 명확화·섹션별 승인·자유 산문 PRD·[NEEDS CLARIFICATION] 마커로 dispatch가 도중 질문 없이 분해 가능한 자기완결적 PRD를 만듭니다. 호출 'Skill(skill=\"prd\", args=\"<milestone-id>\")' 또는 '<milestone-id> --resume' 또는 '<milestone-id> --import <path>'."
---

# prd

`autopilot:dispatch` 스킬이 입력으로 받는 `milestones/<m>/prd/PRD.md`를 대화형으로 생성. dispatch가 도중 질문 없이 child SPEC들로 분해할 수 있는 자기완결적 PRD가 목표.

본 스킬은 `spec` 스킬의 mirror다 — 단일 task용 SPEC.md 대신 multi-task 분해를 위한 PRD.md를 작성한다.

## 호출 방법

- 새 PRD 작성: `Skill(skill: "prd", args: "<milestone-id>")`
- 외부 PRD 임포트: `Skill(skill: "prd", args: "<milestone-id> --import <path>")`
- 마커 해결 모드: `Skill(skill: "prd", args: "<milestone-id> --resume")`

또는 사용자가 자연어로 의도 전달 시 모델이 자동 호출.

## 출력 경로

- PRD 본문: `milestones/<milestone-id>/prd/PRD.md`
- 디렉토리 생성: `mkdir -p milestones/<milestone-id>/prd/`

`milestones/<milestone-id>/dispatch/`는 dispatch 스킬이 처음 진입 시 만든다. prd는 `prd/`만 책임.

## 9단계 워크플로

호출 시 다음 9단계를 TodoWrite로 등록·실행. 각 단계는 사용자 결정·승인을 `AskUserQuestion`으로 받습니다.

### 1. 사전 검사

- milestone-id 형식 검증 (loop.sh의 `validate_task_id`와 동일 규칙): 비어 있거나, `..` 포함, `.` 단독 컴포넌트, `__` 포함, 공백 포함 시 abort. milestone-id는 단일 컴포넌트(예: `auth-overhaul`)를 권장하지만 슬래시도 허용.
- `regular`는 ad-hoc 단일 task의 catch-all로 예약 — `prd regular` 호출 거부.
- **일반 모드**: `milestones/<milestone-id>/prd/PRD.md` 존재 시 abort + `AskUserQuestion`으로 3옵션 (다른 milestone-id / `--resume` / 백업 후 새로)
- **--resume 모드**: `milestones/<milestone-id>/prd/PRD.md` 부재 시 abort. 잔존 `[NEEDS CLARIFICATION` 마커 0개 시 "해결할 마커 없음" 안내 후 종료
- **--import 모드**: 외부 PRD 파일 경로 검증 후 `milestones/<milestone-id>/prd/PRD.md`로 복사

### 2. 컨텍스트 탐색

다음 명령으로 프로젝트 컨텍스트 자동 수집 (사용자에게 요약만):
```
git log --oneline -5
ls -A          # 최상위 트리만 (재귀 없음)
cat CLAUDE.md  # 있으면
ls rules/      # 있으면
ls milestones/ # 기존 milestones (참고)
```

목적: 테스트 컨벤션·CLAUDE.md 룰·디렉터리 구조·이전 milestones 파악.

`--resume` / `--import` 모드: 자체 검토에 필요한 최소 정보만 수집.

### 3. 명확화 라운드

한 번에 한 질문 (`AskUserQuestion`, 가능하면 멀티초이스). 수집할 정보:
- 핵심 문제: 이 milestone이 해결하는 사용자/시스템 문제는?
- 비전·목표: 완료 시 어떤 상태가 되는가?
- 성공 기준: 어떻게 "이 milestone 완료"를 판정하는가?
- 범위: 포함 영역과 비-목표(out of scope)
- 제약: 환경·도구·호환성·시간 등
- 위험: 이미 알려진 dead-end·금지 영역

`--resume` 모드: 마커가 박힌 섹션 관련 질문만.
`--import` 모드: 이 단계 생략 (기존 PRD 본문 그대로 사용).

### 4. 접근법 비교 (조건부)

명확화에서 PRD가 비-자명한 설계 결정을 포함한다고 판단되면 2-3 접근법 + 트레이드오프 + 추천 제시. 자명하면 생략.

판단 기준 (하나라도 해당):
- 사용자가 "어떻게 할까?" 묻거나 모호한 요구를 표현
- 분해 방향(영역별·계층별·기능별)에 명확한 선택이 필요
- 외부 의존성·라이브러리 선택이 PRD 결과에 큰 영향

### 5. 섹션별 PRD 제시·승인

다음 순서로 한 섹션씩 사용자에게 제시 → `AskUserQuestion`으로 "이 섹션 OK?" 확인:
1. 제목
2. 문제 (이 milestone이 해결하는 것)
3. 목표·비전 (완료 시 모습)
4. 성공 기준 (자유 산문, EARS 강제 아님 — dispatch가 분해 후 child SPEC에서 EARS로 정밀화)
5. 범위 (포함·비-목표)
6. 제약 (있을 때만)
7. 위험 (있을 때만)
8. 분해 힌트 (선택) — dispatch가 자동 분해하지만 사용자가 명시적 단위 후보를 제공할 수 있음

승인 안 받은 섹션은 다시 제시·수정. 한 번에 통째로 보여주지 않음.

`--resume` 모드: 마커가 박힌 섹션만.
`--import` 모드: 이 단계 생략.

### 6. PRD.md 작성

`references/prd-template.md` 읽어 placeholder 치환:
- `{{prd_title}}` → 단계 5에서 합의된 제목
- `{{milestone}}` → milestone-id
- `{{problem}}` → 섹션 2 합의 내용
- `{{goals}}` → 섹션 3 합의 내용
- `{{success_criteria}}` → 섹션 4 합의 내용
- `{{scope_in}}` / `{{scope_out}}` → 섹션 5
- `{{constraints}}` / `{{risks}}` → 섹션 6/7. 빈 값이면 빈 줄 한 줄로 치환 (헤더는 남김)
- `{{decomposition_hints}}` → 섹션 8 (선택, 빈 값 허용)

미해결 항목은 `[NEEDS CLARIFICATION: <구체 질문>]` 마커로 박은 채 작성.

`mkdir -p milestones/<milestone-id>/prd/` 후 PRD.md 기록.

`--import` 모드: step 1에서 복사된 본문을 그대로 사용 (placeholder 치환 없음).

### 7. 자체 검토

`references/self-review.md` 5항목 체크 (placeholder · 모순 · 범위(decomposable) · 모호성 · 마커 잔존). 발견 시 인라인 수정 또는 `[NEEDS CLARIFICATION: <구체 질문>]` 마커만 — 사용자 Q&A 없음(단계 9에서 일괄 해결). 재루프 없음. 수정·마커 후 PRD.md 재기록.

`--import` 모드: 본 단계가 임포트 흐름의 시작점 — 외부 PRD에 부족한 부분을 자동 마커.

### 8. 사용자 최종 검토

PRD.md 경로·요약 안내 + `AskUserQuestion`으로 검토 결과 수집:
- 승인: 단계 9로 진행
- 변경: 어느 섹션을 변경할지 묻고 단계 5/6 재진입

### 9. 다음 단계 안내

PRD 본문에 남은 `[NEEDS CLARIFICATION` 마커 검사:
- **마커 0개**: dispatch로 진행 — *"PRD 완성: milestones/<milestone-id>/prd/PRD.md\n다음 단계: Skill(skill: \"dispatch\", args: \"<milestone-id>\")"*
- **마커 1개 이상**: 정상 종료 차단 — *"PRD에 미해결 [NEEDS CLARIFICATION] 마커 N개 잔존. 해결: Skill(skill: \"prd\", args: \"<milestone-id> --resume\")"*

## --resume 모드 요약

위 9단계 중:
- 1: 마커 0개 시 즉시 종료
- 2: 최소 정보만
- 3: 마커 위치 기준 질문 좁힘
- 4: 조건부 (마커가 설계 결정에 박힌 경우)
- 5: 마커 박힌 섹션만
- 나머지 동일

## --import 모드 요약

위 9단계 중:
- 1: 외부 파일 검증 + 복사
- 2: 최소 정보만
- 3, 4, 5: 생략 (사용자 대화 없음)
- 6: 복사된 본문 사용
- 7: 시작점 — 부족 부분 자동 마커
- 8, 9: 동일 (마커 잔존 시 --resume 안내)

## 모듈 구성 (references/)

| 파일 | 역할 |
|---|---|
| `prd-template.md` | PRD.md placeholder 템플릿 (자유 산문 가이드 주석 포함) |
| `self-review.md` | 자체 검토 5항목 체크리스트 (PRD 전용: placeholder·모순·범위(decomposable)·모호성·마커) |

## 규칙

- 본 스킬은 target 프로젝트의 `milestones/<milestone-id>/prd/PRD.md`만 작성한다. `milestones/<milestone-id>/dispatch/`나 다른 파일 생성·수정 안 함.
- 모든 결정·선택·확인은 `AskUserQuestion`으로. 자유 텍스트 끝에 질문 종결구 다는 방식 금지 (CLAUDE.md 규칙).
- 한 주제씩 (한 `AskUserQuestion` 호출에 관련 소문항 최대 4개 허용).
- `[NEEDS CLARIFICATION` 마커는 `dispatch start`에서 차단됨. 사용자에게 명시적으로 마커가 박혔음을 알리고 `--resume`으로 해결하도록 안내.
- `regular` milestone-id 거부 — 그 이름은 ad-hoc 단일 task catch-all로 예약.
