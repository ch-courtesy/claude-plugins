# 문서 템플릿

세션 산출물은 `.forum/<session-id>.md` **단일 파일 1개**이며 아래 템플릿의 섹션 구조를 유지한다.

## 단일 세션 파일 템플릿

```markdown
# Forum Session: <session-id>

## 상태
- session-id:
- state:
- updated-at:
- frame-approved-at:
- validation-approved-at:
- agent-calls-used:
- research-calls-used:
- completed-sections:
- next-action:
- inconsistencies:

## 브리프

## 연구 컨텍스트

## 로스터

## 아이디어 풀

## 군집

## 숏리스트

## 검증 계획

## 실험

## 최종 보고
```

각 섹션의 내용은 SKILL.md 시작 워크플로의 해당 단계가 정의한다.

## 아이디어 풀 항목

```markdown
### IDEA-001
- idea-id: IDEA-001
- parent-id: none
- strategy: Brainwriting | SCAMPER
- lens:
- cluster-ids:
- idea:
- expected-value:
- novelty:
- assumptions:
- duplicate-of:
- status: raw | transformed | clustered | shortlisted | parked | eliminated
- park-recondition:
- elimination-reason:
- core-fact:
- independent-sources:
```

원본 아이디어를 보존하고 삭제하지 않는다. 변환은 새 항목으로 추가하며 `parent-id`로 부모를 추적한다. `parked`는 범위 밖 보존 상태로 관찰 가능한 재검토 조건(park-recondition)을 필수로 남기고, `eliminated`는 근거 있는 탈락(elimination-reason 필수)으로 재논의하지 않는다. 둘 다 삭제가 아니다.

`core-fact`는 이 아이디어를 뒷받침하는 핵심 사실 문장이다. `independent-sources`는 그 사실을 뒷받침하는 독립인 출처 수(정수)를 기록한다. 두 필드는 정량 측정 하니스가 파싱하는 구조화 마커이므로 kebab-case `key: value` 형식을 지킨다. 마커 값에는 주석·부연을 붙이지 않는다(순수 값만 — 예: `independent-sources: 2`). 출처 성격·독립성 의문 같은 부연은 연구 컨텍스트의 서술(주의사항)에 적는다. 값이 오염되면 하니스가 fail-loud로 실패한다.

## 숏리스트 후보 항목

```markdown
### Candidate C-01
- source-idea-ids:
- value-proposition:
- requester-value-fit:
- differentiation:
- learning-value:
- key-risks:
- evidence-level:
- dissent:
- validation-priority:
```

## 검증 계획 실험 항목

```markdown
### Experiment E-01
- candidate-id:
- assumption:
- approved-type: research | agent-critique | document | mockup | prototype
- method:
- success-signal:
- stop-condition:
- estimated-cost:
- approval-status: proposed | approved | rejected
```

승인 전에는 계획만 작성한다. 실험 산출물(문서·목업·프로토타입 스케치)은 `## 실험` 섹션 안에 기록한다.

## 실험 결과 항목

관찰과 해석을 분리해 실험 ID, 승인 범위, 수행 내용, 산출물 위치(텍스트로 담을 수 없는 산출물이 있으면 `.forum/` 아래 경로), 관찰, 반증, 한계, 후보에 미치는 영향을 `## 실험` 섹션에 기록한다. 실패와 불확실성도 그대로 보존한다.
