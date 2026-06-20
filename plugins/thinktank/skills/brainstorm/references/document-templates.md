# 문서 템플릿

모든 파일은 `.brainstorm/<session-id>/` 아래에 둔다. 상태 전환 전에 `state.md`를 먼저 갱신하며, 기존 기록을 덮어써서 계보나 실패 결과를 지우지 않는다.

## `state.md`

```markdown
# Session State
- session-id:
- state:
- updated-at:
- frame-approved-at:
- validation-approved-at:
- agent-calls-used:
- research-calls-used:
- completed-artifacts:
- next-action:
- inconsistencies:
```

## 필수 산출물

| 파일 | 내용 |
|---|---|
| `brief.md` | 승인된 프레임, 의뢰자 가치, 범위, 평가 기준 |
| `research-context.md` | 발산 전 최소 조사와 shortlist 이후 상세 검증 조사 |
| `roster.md` | 선택한 3–6명 렌즈, 선택 근거, 예상 호출 예산 |
| `idea-pool.md` | 원본과 변환 아이디어 전체, 계보, 중복 표시 |
| `clusters.md` | 가치·작동 원리 기반 군집과 미해결 질문 |
| `shortlist.md` | NGT 평가와 복수 후보군 |
| `validation-plan.md` | 후보별 가정, 승인 요청 실험, 비용, 중단 기준 |
| `experiments.md` | 승인된 검증 실험과 관찰 결과 |
| `report.md` | 후보군, 비교, 불확실성, 검증 결과, 다음 결정 질문 |

## `idea-pool.md` 항목

```markdown
## IDEA-001
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

## `shortlist.md` 후보 항목

```markdown
## Candidate C-01
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

## `validation-plan.md` 실험 항목

```markdown
## Experiment E-01
- candidate-id:
- assumption:
- approved-type: research | agent-critique | document | mockup | prototype
- method:
- output-path: .brainstorm/<session-id>/...
- success-signal:
- stop-condition:
- estimated-cost:
- approval-status: proposed | approved | rejected
```

승인 전에는 계획만 작성한다. 승인 후에도 `.brainstorm/**` 밖 파일, 코드베이스, 조직 정책, 외부 시스템을 변경하지 않는다.

## `experiments.md` 결과 항목

관찰과 해석을 분리해 실험 ID, 승인 범위, 수행 내용, 산출물 경로, 관찰, 반증, 한계, 후보에 미치는 영향을 기록한다. 실패와 불확실성도 그대로 보존한다.
