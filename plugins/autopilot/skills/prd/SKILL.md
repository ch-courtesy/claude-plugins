---
name: prd
description: "autopilot:dispatch 입력으로 받는 PRD(Product Requirements Document)를 대화형으로 작성. dispatch가 도중 질문 없이 분해 가능한, milestone 단위 자기완결적 PRD를 만듭니다. 호출 'Skill(skill=\"prd\", args=\"<milestone-id>\")' 또는 '<milestone-id> --resume' 또는 '<milestone-id> --import <path>'."
---

# prd

`autopilot:dispatch` 입력인 `milestones/<m>/prd/PRD.md`를 작성한다. 단일 task용 `spec`의 mirror이며, 목표는 dispatch가 질문 없이 child SPEC으로 분해 가능한 자기완결 PRD다.

## Anti-Pattern: "이건 너무 단순해서 모든 단계 안 거쳐도 된다"

어떤 milestone도 9단계와 서브 게이트(2.5·2.6·3.5)를 스킵하지 않는다. "작으니 step X 생략", "trivial하니 명확화 압축", "서브 게이트는 옵션" 같은 합리화는 금지다. 출력 분량은 줄여도 되지만 단계·게이트 자체는 반드시 실행하거나 "해당 없음"/"trivial로 생략 (사유: ...)"을 기록해 통과시킨다. step 4 OPT-OUT도 단계 생략이 아니라 사유 기록이다.

## 호출

- 새 PRD: `Skill(skill: "prd", args: "<milestone-id>")`
- 마커 해결: `Skill(skill: "prd", args: "<milestone-id> --resume")`
- 외부 PRD 임포트: `Skill(skill: "prd", args: "<milestone-id> --import <path>")`

출력은 `milestones/<milestone-id>/prd/PRD.md`. `dispatch/`는 dispatch 스킬 책임이다.

## 9단계 워크플로

호출 시 9단계와 2.5·2.6·3.5 게이트를 TodoWrite로 등록·실행한다. 어떤 milestone도 9단계를 스킵하지 않는다. 단순하면 한 줄로 통과할 수 있지만 단계 자체는 남긴다.

### 1. 사전 검사

milestone-id는 `validate_task_id` 기본 규칙(빈 값, `..`, `.` 단독 컴포넌트, `__`, 공백 금지)을 따른다. `regular`는 ad-hoc 단일 task catch-all이므로 거부한다. 일반 모드에서 PRD.md가 있으면 다른 milestone-id / `--resume` / 백업 후 새로 중 하나를 묻는다. `--resume`은 PRD 부재 시 abort, 마커 0개면 종료. `--import`는 외부 파일을 검증해 PRD.md로 복사한다.

### 2. 컨텍스트 탐색

`git log --oneline -5`, `ls -A`, 선택적 `cat CLAUDE.md`, `ls rules/`, `ls milestones/`로 구조·룰·선례를 요약한다. `--resume`/`--import`는 자체 검토에 필요한 최소 정보만 수집한다.

### 2.5 Brownfield 동행 개선 질문

기존 코드 변경 신호가 있으면 1회 질문한다: 인접한 작은 정리·리네이밍·중복 제거를 범위에 포함할지. 답은 포함 / 미포함 / 모르겠음. 모르겠음은 step 3 범위 질문에서 다시 결정한다. 해당 없으면 한 줄로 통과한다.

### 2.6 Visual Companion offer

UX·시각 콘텐츠가 무거운 milestone이면 visual companion을 단독 메시지로 offer하고, 이어 `AskUserQuestion`으로 켜기/텍스트 전용을 받는다. 시각 신호가 없으면 "해당 없음"으로 통과한다. `--resume`/`--import`는 생략한다.

### 3. 명확화 라운드

한 번에 한 질문으로 문제, 목표·비전, 성공 기준, 범위, 제약, 위험을 수집한다. step 2.5에서 모르겠음을 택했다면 범위 질문에서 동행 개선 포함 여부를 포함/미포함으로 확정한다. `--resume`은 마커 섹션만, `--import`는 생략.

### 3.5 Milestone-fit

명확화 직후 단일 PRD로 결착 가능한지 1회 판정한다. 단일 서사이고 예상 child SPEC 1-8개면 통과. 독립 문제 영역 2개 이상이거나 8개 초과가 명백하면 사용자에게 근거를 제시하고 `(a) 분해 후 재시작`, `(b) 그래도 단일 PRD`, `(c) 범위 줄여 재판정`을 묻는다. dispatch의 분해 책임과 중복하지 않는다.

### 4. 접근법 비교

기본 ON. 핵심 결정에 대해 2-3 접근법, trade-off, 추천을 제시하고 선택받는다. 정말 trivial하면 "접근법 비교: trivial로 생략 (사유: ...)"을 기록하고 통과한다.

### 5. 섹션별 PRD 승인

제목, 문제, 목표·비전, 성공 기준, 범위, 제약, 위험, 분해 힌트를 한 섹션씩 제시하고 승인받는다. 범위 포함 승인 직후 YAGNI 게이트를 1회 실행해 각 목표·범위 항목마다 유지 / 제거 / 별도 milestone 이관을 묻는다. 제거된 항목은 PRD 본문에 포함하지 않는다.

### 6. PRD.md 작성

`references/prd-template.md` placeholder를 치환한다: `{{prd_title}}`, `{{milestone}}`, `{{problem}}`, `{{goals}}`, `{{success_criteria}}`, `{{scope_in}}`, `{{scope_out}}`, `{{constraints}}`, `{{risks}}`, `{{decomposition_hints}}`. 미해결 항목은 `[NEEDS CLARIFICATION: <구체 질문>]` 마커로 남긴다. `--import`는 복사된 본문을 그대로 사용한다.

### 7. 자체 검토

`references/self-review.md` 5항목(placeholder, 모순, decomposable 범위, 모호성, 마커)을 검사한다. 발견 시 인라인 수정 또는 마커만 남기고 사용자 Q&A는 하지 않는다. `--import`는 여기서 부족 부분을 마커화한다.

### 8. 사용자 최종 검토

PRD.md 경로·요약을 안내하고 승인 또는 변경을 묻는다. 변경은 섹션 선택 후 step 5/6으로 재진입한다.

### 9. 다음 단계 안내

마커 0개면 `PRD 완성: milestones/<milestone-id>/prd/PRD.md`와 `Skill(skill: "dispatch", args: "<milestone-id>")`를 안내한다. 마커가 남으면 정상 종료를 차단하고 `Skill(skill: "prd", args: "<milestone-id> --resume")`를 안내한다.

## 모드 요약

`--resume`: 1에서 마커 0개면 종료, 2는 최소 정보, 2.5·3.5는 관련 마커가 있을 때만, 2.6은 생략, 3·5는 마커 섹션만, 4는 설계 결정 마커가 있으면 재실행, 나머지는 동일.

`--import`: 1에서 복사, 2는 최소 정보, 2.5-5는 생략, 6은 복사 본문 사용, 7부터 자체 검토·최종 확인·다음 단계 안내.

## references

| 파일 | 역할 |
|---|---|
| `prd-template.md` | PRD.md 템플릿 |
| `self-review.md` | PRD 자체 검토 |

## 규칙

- 직접 작성 범위는 `milestones/<milestone-id>/prd/PRD.md`뿐이다.
- 모든 결정·선택·확인은 `AskUserQuestion`.
- 한 주제씩 묻고, 한 호출의 관련 소문항은 최대 4개.
- `[NEEDS CLARIFICATION` 마커가 있으면 dispatch start가 차단된다.
- `regular` milestone-id는 거부한다.
