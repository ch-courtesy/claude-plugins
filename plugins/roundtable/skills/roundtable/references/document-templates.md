# 영속 문서 템플릿

모든 문서는 `.roundtable/<meeting-id>/` 아래에 저장한다. 전체 발화가 아니라 근거와 결정 변화를 구조화해 기록한다.
전체 발화 기록은 감사 요구가 명시되고 의뢰자가 추가 토큰 예산을 승인한 경우에만 별도 부록으로 저장한다.

## `state.md`

```markdown
# Roundtable State
- meeting_id:
- status: interviewing | agenda_approval | researching | research_review | roster_approval | discussing | documenting | completed | no_consensus
- current_round:
- max_rounds:
- research_calls_used:
- agent_calls_used:
- next_action:
- last_updated:
```

## `research-plan.md`

`research-protocol.md`의 리서치 질문, 범위, 최신성, 예산, 중단 조건을 기록한다.

## `evidence-pack.md`

`research-protocol.md`의 공통 증거 팩 형식을 사용한다.

## `roster.md`

```markdown
# 참여자 구성
| 역할 ID | 페르소나 | 대표 관점 | 선정 근거 | 관련 증거 ID |
|---|---|---|---|---|

## 운영 역할
- 회의 책임자:
- 진행자:
- 기록자:
- 중앙 리서처:
- 리서치 검증자 필요 여부:

## 예산
- 예상 참여자 호출:
- 최대 라운드:
- 추가 조사 한도:
```

## `initial-positions.md`

각 역할의 독립 초기 입장을 역할 ID별로 기록한다. 다른 참여자 의견을 본 뒤 작성된 내용과 섞지 않는다.

## `decision-map.md`

```markdown
# 결정 지도
## 합의된 내용
## 핵심 이견과 가치 충돌
## 공통 지지
## 정보 공백과 가정
## 비가역적 결정
## 실패 조건
## 집중 논의할 질문
```

## `discussion.md`

```markdown
# 구조화 논의 기록
## Round <N>
- 질문:
- 참여 역할:
- 주요 주장과 증거 ID:
- 반론과 해소 조건:
- 입장 변화와 이유:
- 추가 조사:
- 진행자 판정:
```

## `agreement.md`

```markdown
# <안건명> 원탁회의 합의·실행서
## 합의 상태와 적용 범위
## 최종 합의문
## 결정사항과 근거
## 조건·예외·중단 조건
## 실행 과제와 실제 책임자 승인 필요사항
## 성공 기준과 재검토일
## 반대·소수 의견
## 증거 추적표
## 확인
```

실행 과제는 문서화만 한다. roundtable 스킬은 합의 내용을 실제 실행하지 않는다.

## `no-consensus.md`

```markdown
# <안건명> 원탁회의 불합의 보고서
## 합의된 부분
## 해결되지 않은 핵심 이견
## 각 입장과 근거
## 정보 공백
## 검토한 대안
## 의뢰자·실제 결정권자가 결정할 사항
## 재논의 조건
## 증거 추적표
```

불합의는 실패한 문서가 아니라 거짓 합의를 방지하는 정상 종료 산출물이다.
