# 문서 템플릿

세션 산출물은 `.brainstorm/<session-id>.md` **단일 파일 1개**다. 파일은 아래 템플릿의 섹션 구조를 유지하며, 세션 시작 시 전체 뼈대를 한 번 만든 뒤에는 **섹션 단위로만 추가·갱신**하고 다른 섹션은 건드리지 않는다. 전체 파일 재작성을 금지한다. 기존 기록을 덮어써서 계보나 실패 결과를 지우지 않는다.

## 단일 세션 파일 템플릿

상태 블록(`## 상태`)이 항상 파일 최상단 첫 섹션이다. 상태 전환 전에 상태 블록을 먼저 갱신한다.

```markdown
# Brainstorm Session: <session-id>

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

## 섹션별 내용

| 섹션 | 내용 |
|---|---|
| `## 상태` | 현재 상태, 승인 시각, 호출 예산 사용량, 다음 행동, 불일치 |
| `## 브리프` | 승인된 프레임, 의뢰자 가치, 범위, 평가 기준 (`framing-template.md` 규격) |
| `## 연구 컨텍스트` | 발산 전 최소 조사와 shortlist 이후 상세 검증 조사 |
| `## 로스터` | 선택한 3–6명 렌즈, 선택 근거, 예상 호출 예산 |
| `## 아이디어 풀` | 원본과 변환 아이디어 전체, 계보, 중복 표시 |
| `## 군집` | 가치·작동 원리 기반 군집과 미해결 질문 |
| `## 숏리스트` | NGT 평가와 복수 후보군 |
| `## 검증 계획` | 후보별 가정, 승인 요청 실험, 비용, 중단 기준 |
| `## 실험` | 승인된 검증 실험과 관찰 결과 |
| `## 최종 보고` | 후보군, 비교, 불확실성, 검증 결과, 다음 결정 질문 |

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
- status: raw | transformed | clustered | shortlisted | archived
```

원본 아이디어를 보존하고 삭제하지 않는다. 변환은 새 항목으로 추가하며 `parent-id`로 부모를 추적한다. `archived`는 제외 근거를 남기는 상태이지 삭제가 아니다.

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

승인 전에는 계획만 작성한다. 실험 산출물(문서·목업·프로토타입 스케치)은 `## 실험` 섹션 안에 기록한다. 승인 후에도 코드베이스, 조직 정책, 외부 시스템을 변경하지 않는다.

## 실험 결과 항목

관찰과 해석을 분리해 실험 ID, 승인 범위, 수행 내용, 산출물 위치(텍스트로 담을 수 없는 산출물이 있으면 `.brainstorm/` 아래 경로), 관찰, 반증, 한계, 후보에 미치는 영향을 `## 실험` 섹션에 기록한다. 실패와 불확실성도 그대로 보존한다.
