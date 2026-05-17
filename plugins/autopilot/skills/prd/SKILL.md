---
name: prd
description: "autopilot:dispatch 입력으로 받는 PRD(Product Requirements Document)를 대화형 9-step으로 작성. 한 질문씩 명확화·섹션별 승인·자유 산문 PRD·[NEEDS CLARIFICATION] 마커로 dispatch가 도중 질문 없이 분해 가능한 자기완결적 PRD를 만듭니다. 탐색 규율(접근법 비교 기본 ON·milestone 단위 적정성 검사·YAGNI 강제 통과·brownfield 동행 개선 질문·visual companion offer)을 흡수해 별도 brainstorming 호출 없이도 milestone 의도를 충분히 추궁합니다. 호출 'Skill(skill=\"prd\", args=\"<milestone-id>\")' 또는 '<milestone-id> --resume' 또는 '<milestone-id> --import <path>'."
---

# prd

`autopilot:dispatch` 스킬이 입력으로 받는 `milestones/<m>/prd/PRD.md`를 대화형으로 생성. dispatch가 도중 질문 없이 child SPEC들로 분해할 수 있는 자기완결적 PRD가 목표.

본 스킬은 `spec` 스킬의 mirror다 — 단일 task용 SPEC.md 대신 multi-task 분해를 위한 PRD.md를 작성한다.

## Anti-Pattern: "이건 너무 단순해서 모든 단계 안 거쳐도 된다"

어떤 milestone도 9단계 **및 서브 게이트(2.5·2.6·3.5)**를 스킵하지 않는다. "이건 작은 milestone이라 step X 생략", "trivial하니 명확화 라운드 압축", "서브 게이트는 원래 9단계 밖이라 옵션" 같은 합리화는 금지다 — "단순"해 보이는 milestone일수록 검증되지 않은 가정이 누적되어 dispatch가 분해 단계에서 헛돈다. 각 단계·게이트의 출력 분량은 milestone 복잡도에 맞게 축약될 수 있지만(자유 산문 한두 문장도 허용), **단계·게이트 자체를 스킵하지 않는다**. step 4(접근법 비교)의 명시 OPT-OUT조차 step을 건너뛰는 게 아니라 "trivial이라 비교 안 함" 한 줄 명문화로 *통과*시키는 것이다. 서브 게이트 2.5·2.6도 동일 — "해당 없음" 한 줄 통과는 허용되나 게이트 자체를 누락하지 않는다.

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

호출 시 다음 9단계(+ 삽입된 2.5·2.6·3.5 서브 게이트)를 TodoWrite로 등록·실행. 각 단계는 사용자 결정·승인을 `AskUserQuestion`으로 받습니다. **어떤 milestone도 9단계를 스킵하지 않는다** — 자세한 anti-pattern 가드는 본 문서 상단 절 참조.

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

### 2.5. Brownfield 동행 개선 질문 (1회, 소프트)

이 milestone이 기존 코드에 손을 댄다고 추정되면 (step 2의 컨텍스트 탐색에서 비어있지 않은 코드베이스가 감지된 경우), `AskUserQuestion`으로 1회 묻는다:

> "이 milestone이 건드릴 영역에서 *동행 개선*(인접한 작은 정리·리네이밍·중복 제거)을 함께 포함할까요? brownfield 코드에선 작업자가 손대는 김에 손볼 가치가 있는 인접 결함이 있곤 합니다 — 단, 명시적으로 PRD 범위에 들어와야 dispatch가 child SPEC로 분해할 수 있습니다."

옵션: (a) 포함 — 범위 섹션에 자동 반영 / (b) 미포함 — 본 milestone은 핵심만 / (c) 모르겠음 — step 3 명확화 라운드에서 다시 점검.

**강제 아님**: 답이 (b)거나 step 2에서 brownfield 신호가 약하면 단순 통과. 단, 본 step을 건너뛰지는 않는다 (anti-pattern guard).

`--resume` 모드: 잔존 마커가 brownfield 영역 관련이 아니면 생략.
`--import` 모드: 생략.

### 2.6. Visual Companion offer 입구

UX·시각 콘텐츠가 무거운 milestone(예: 화면 흐름·다이어그램·레이아웃 비교)을 다룬다고 추정되면, visual companion(브라우저 기반 mockup·비교 이미지 보조)을 1회 offer한다. **이 offer는 단독 메시지여야 한다** — 명확화 질문·요약·다른 콘텐츠와 결합 금지.

offer는 다음 메시지를 단독 텍스트로 먼저 보내고:

> "이 milestone에서 화면·다이어그램·레이아웃 같은 시각 콘텐츠를 다룰 수 있습니다. 원하시면 브라우저 기반 visual companion을 켜서 mockup·비교 이미지를 보여드릴 수 있어요. 토큰 사용량이 늘 수 있고 로컬 URL을 열게 됩니다."

직후 `AskUserQuestion`으로 2선택을 받는다: (a) 켜기 — 이후 시각 콘텐츠는 브라우저 mockup·비교 이미지를 동반 / (b) 텍스트 전용으로 계속. 자유 텍스트 결정 요청 금지 (CLAUDE.md 규칙).

사용자 응답에 따라:
- (a) 켜기 → 이후 명확화·접근법 비교 라운드에서 시각 콘텐츠가 필요한 시점마다 브라우저 mockup·비교 이미지를 생성·표시
- (b) 텍스트 전용 → 모든 후속 단계는 텍스트만

UX·시각 신호가 없으면 본 step은 "해당 없음" 한 줄 통과 — 단계 자체는 건너뛰지 않는다.

`--resume` / `--import` 모드: 생략 (이미 결정 완료).

### 3. 명확화 라운드

한 번에 한 질문 (`AskUserQuestion`, 가능하면 멀티초이스). 수집할 정보:
- 핵심 문제: 이 milestone이 해결하는 사용자/시스템 문제는?
- 비전·목표: 완료 시 어떤 상태가 되는가?
- 성공 기준: 어떻게 "이 milestone 완료"를 판정하는가?
- 범위: 포함 영역과 비-목표(out of scope)
- 제약: 환경·도구·호환성·시간 등
- 위험: 이미 알려진 dead-end·금지 영역

**step 2.5 (c) 재진입 훅**: step 2.5에서 brownfield 동행 개선에 (c) "모르겠음"을 답한 경우, 본 라운드의 *범위* 질문에서 **동행 개선 포함 여부**도 같이 수집한다 — silent drop 금지. 사용자 응답을 (a) 포함 / (b) 미포함 둘 중 하나로 좁혀 step 5 범위 섹션에 반영한다. (c)를 선택하지 않았으면 본 훅은 통과.

`--resume` 모드: 마커가 박힌 섹션 관련 질문만.
`--import` 모드: 이 단계 생략 (기존 PRD 본문 그대로 사용).

### 3.5. Milestone 단위 적정성 검사 (milestone-fit, 1회)

명확화 라운드 직후, 다음 한 질문을 1회 자체 판정한다:

> **이 milestone-id가 단일 PRD로 결착 가능한가, 아니면 더 쪼개야 하는가?**

판단 신호:
- **단일 PRD로 충분**: 명확화 라운드에서 모은 문제·목표·범위가 일관된 한 줄 서사로 묶이고, 분해 시 child SPEC 후보가 1~8개 사이로 예측됨
- **분해 필요**: 명확화 라운드에서 *서로 독립한* 문제 영역 2개 이상이 드러남, 또는 child SPEC 후보가 명백히 8개 초과 (dispatch의 1차 분해 캡)

판정 결과:
- **단일 PRD로 충분** → 통과, step 4로 진행
- **분해 필요** → `AskUserQuestion`으로 사용자에게 판정 근거를 안내하고 3옵션을 받는다 (step 1의 3옵션 패턴과 동일):
  - (a) 분해 후 재시작 — 권고. PRD 작성을 중단하고 "이 milestone을 milestone A·B로 쪼갠 뒤, A부터 `Skill(skill: \"prd\", args: \"<A>\")`를 다시 호출하세요" 안내 후 종료
  - (b) 그래도 단일 PRD로 계속 — 사용자가 판정을 override. "분해 필요로 판정됐으나 사용자 결정으로 단일 PRD 진행" 한 줄을 자체 기록으로 남기고 step 4로 진행
  - (c) 범위 줄여 다시 판정 — step 3 명확화 라운드의 범위 항목으로 되돌아가 축소 합의 후 본 step을 재실행

**dispatch 분해와의 책임 분리** (사용자 인터랙션 중복 회피):
- 본 step의 milestone-fit은 *PRD 자체의 결착 가능성*만 본다 — "이 milestone-id가 단일 PRD 한 장으로 끝낼 수 있는가"
- dispatch의 분해는 *합의된 PRD를 child SPEC 단위로 쪼개기*만 본다 — "PRD 안에서 어떤 단위로 작업을 나눌까"
- 두 책임이 겹치지 않도록, PRD의 milestone-fit이 "통과"라면 dispatch는 PRD 분해를 그대로 진행한다 (재질문 없음)

`--resume` 모드: 잔존 마커가 milestone-fit과 무관하면 생략.
`--import` 모드: 생략 (기존 PRD가 이미 결착 가정).

### 4. 접근법 비교 (기본 ON, mandatory)

접근법 비교는 **기본 활성화**(mandatory)다. 모든 milestone에 대해 2-3 접근법 + 트레이드오프 + 추천을 1회 제시한다. 이전 버전의 "조건부 OPT-IN"은 폐기됨 — 거의 모든 PRD가 설계 결정을 내포하며, "자명"하다는 판단 자체가 자주 틀린다.

표준 흐름:
1. 명확화 라운드에서 도출된 핵심 결정 포인트(분해 방향·기술 선택·범위 경계 등)에 대해 2-3개 접근법 제시
2. 각 접근법의 트레이드오프(복잡도·범위·위험·향후 확장성)를 짧게 비교
3. 모델의 추천 + 근거 한 문단
4. `AskUserQuestion`으로 선택 받기

**OPT-OUT (예외 처리)**: 정말 trivial해서 비교할 접근법이 1개뿐인 경우에 한해 명시적으로 생략 가능. 이때 PRD 작성 흐름에 "접근법 비교: trivial로 생략 (사유: <한 줄>)"을 명문화해 통과시킨다 — 단계 자체를 건너뛰는 것이 아니라 OPT-OUT 사유를 *기록한 채 통과*시키는 것 (anti-pattern guard 준수).

OPT-OUT 허용 신호 (모두 해당해야 함):
- 명확화 라운드 답변이 단일 접근만 자연 유도 (선택의 여지 없음)
- 외부 의존성·라이브러리 선택이 없음
- 분해 방향이 자명 (단일 영역·단일 계층)

이 조건을 모두 충족하지 않으면 비교는 **무조건** 수행한다.

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

**YAGNI 강제 통과 (목표·범위 합의 직후, 1회)**: **섹션 5(범위.포함) 승인 직후 단 1회**, 이미 합의된 섹션 3(목표·비전)과 섹션 5(범위.포함) 항목을 **통합 검토**한다 (섹션 3 승인 시점에는 본 게이트를 발화하지 않는다 — 두 섹션 합산해 한 번만). 검토 형식:

> "[합의 항목 X]를 정말 본 milestone에 포함해야 합니까? 빼도 milestone 정의가 무너지지 않는다면 빼는 게 낫습니다."

각 항목마다 별도의 `AskUserQuestion` 호출로 (a) 유지 / (b) 제거 / (c) 별도 milestone으로 이관 — 3선택을 받는다. 한 항목도 우회되지 않으며, 답변 후 "유지" 항목만 다음 단계로 넘긴다. 이 게이트는 본 step에서 **강제 1회** 실행되며, 사용자의 "다 유지" 일괄 응답도 항목별 명시 확인을 통과한 후에만 인정한다 — 항목 수만큼 질문 호출이 누적되더라도 한 항목 한 결정 원칙을 유지한다 (multi-select 일괄 처리 금지: (c) 이관 선택이 항목별로 의미를 가지므로 항목·결정 1:1 매핑이 필수).

YAGNI 게이트의 출력은 합의된 목표·범위를 *제거된 항목 표시와 함께* PRD 본문에 반영한다 (제거 사유는 본문에 남기지 않고 대화 기록으로 충분).

`--resume` 모드: 마커가 박힌 섹션만. YAGNI 게이트는 마커 해결 후 영향 받은 항목에만 적용.
`--import` 모드: 이 단계 생략 (외부 PRD가 이미 YAGNI 결정 완료 가정).

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

위 9단계(+ 삽입된 2.5·2.6·3.5) 중:
- 1: 마커 0개 시 즉시 종료
- 2: 최소 정보만
- 2.5: 잔존 마커가 brownfield 영역 관련일 때만
- 2.6: 생략 (이미 결정 완료)
- 3: 마커 위치 기준 질문 좁힘
- 3.5: 잔존 마커가 milestone-fit과 무관하면 생략
- 4: 기본 ON 그대로 (마커가 설계 결정에 박힌 경우 비교 재실행)
- 5: 마커 박힌 섹션만 + YAGNI 게이트는 영향 받은 항목에만
- 나머지 동일

## --import 모드 요약

위 9단계(+ 삽입된 2.5·2.6·3.5) 중:
- 1: 외부 파일 검증 + 복사
- 2: 최소 정보만
- 2.5, 2.6, 3, 3.5, 4, 5: 생략 (사용자 대화 없음 — 외부 PRD가 이미 모든 결정 완료 가정)
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
