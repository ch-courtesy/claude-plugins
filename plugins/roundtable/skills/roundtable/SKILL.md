---
name: roundtable
description: "복잡하거나 이해관계가 충돌하는 안건을 구조화해 논의하고 합의서·불합의 보고서를 만들 때 사용. 사용자가 원탁회의, 다중 관점 검토, 숙의, 합의 형성, 의사결정 회의, 회의 재개·상태 확인을 요청할 때 활성화."
allowed-tools:
  - AskUserQuestion
  - Agent
  - Read
  - Write(.roundtable/**)
  - Glob
  - Grep
  - WebSearch
  - WebFetch
  - Bash(ls:*)
  - Bash(find:*)
  - Bash(mkdir -p .roundtable/**)
  - Bash(date:*)
  - Bash(git status:*)
  - Bash(git log:*)
---

# roundtable

메인 세션을 **회의 책임자**로 유지하여 의뢰자 인터뷰, 중앙 리서치, 참여자 구성, 회의 디스패치, 최종 검토를 수행한다. 진행자 서브에이전트는 논의를 지휘·판정하지만 참여자 호출은 메인 세션이 실행한다. 합의 내용을 실제로 실행하는 것은 범위 밖이며 수행하지 않는다.

## 호출

- `roundtable start <회의 설명>`: 새 회의 시작
- `roundtable resume <meeting-id>`: `state.md`의 다음 행동부터 재개
- `roundtable status [meeting-id]`: 상태·산출물·다음 행동 보고

인자가 없으면 `start`로 간주한다. 산출물 루트는 `.roundtable/<meeting-id>/`이며, ID는 로컬 날짜와 안건 slug를 조합한 `YYYYMMDD-<slug>`다. 같은 ID가 있으면 새 suffix를 임의 생성하지 말고 `resume` 또는 다른 제목을 `AskUserQuestion`으로 선택받는다.

## 상태

`interviewing → agenda_approval → researching → research_review → roster_approval → discussing → documenting → completed | no_consensus`

모든 단계 전환 시 `references/document-templates.md`의 `state.md`를 먼저 갱신한다. `resume`은 파일에 기록된 상태와 다음 행동만 신뢰한다. `status`는 파일을 변경하지 않는다.

## resume 라우팅

| 현재 상태 | 재개 행동 |
|---|---|
| `interviewing` | 기존 `agenda.md` 초안을 읽고 아직 비어 있는 충분 조건부터 인터뷰 |
| `agenda_approval` | 아젠다를 다시 제시하고 승인 또는 수정만 요청 |
| `researching` | `research-plan.md`와 기존 증거를 읽고 미완료 조사만 중앙 리서처에게 위임 |
| `research_review` | 증거 팩의 상충·미확인·고위험 항목 검토부터 재개 |
| `roster_approval` | roster와 예산을 다시 제시하고 승인 또는 수정만 요청 |
| `discussing` | `discussion.md`의 마지막 완료 라운드 다음부터 재개하며 초기 입장을 다시 생성하지 않음 |
| `documenting` | 진행자의 최종 판정에 맞는 합의서 또는 불합의 보고서 작성부터 재개 |
| `completed` 또는 `no_consensus` | 읽기 전용 최종 보고만 수행하고 회의를 재실행하지 않음 |

필수 산출물이 없거나 상태와 모순되면 추측해 복구하지 말고 불일치를 보고한다.

## status 보고

`status`는 회의 ID, 현재 상태, 완료된 산출물, 마지막 완료 라운드, 사용한 연구·Agent 호출 수, 남은 정보 공백, 다음 행동을 읽기 전용으로 보고한다. 파일을 생성·수정하거나 Agent를 호출하지 않는다.

## 시작 워크플로

1. **복잡도 게이트.** 단순 사실 조회, 단일 저위험 선택, 관점 충돌이 없는 안건이면 원탁회의 대신 단일 에이전트 자기검토를 권고하고 승인 없이 회의를 시작하지 않는다.
2. **인터뷰.** `references/agenda-template.md`를 읽고 `AskUserQuestion`으로 한 주제씩 목적, 결정 권한, 핵심 질문, 범위, 이해관계자, 제약, 성공 조건을 수집한다.
3. **아젠다 승인.** 아젠다 성격에 맞춰 자문·동의·합의·의결 중 방식을 선택하고 근거를 적는다. `agenda.md`를 보여주고 의뢰자의 명시적 승인 전에는 리서치나 회의를 시작하지 않는다.
4. **중앙 리서치.** `references/research-protocol.md`에 따라 회의 책임자가 `research-plan.md`를 작성하고 중앙 리서처를 한 번 호출해 공통 증거 팩 `evidence-pack.md`를 만든다. 참여자별 중복 리서치를 금지한다.
5. **리서치 검토.** 고위험, 상충 출처, 최신성 의존, 외부 사실 의존이 크면 리서치 검증자를 호출한다. 미확인 정보가 결론을 좌우하면 의뢰자에게 보고하고 강행하지 않는다.
6. **참여자 구성.** `references/participant-personas.md`에서 필요한 관점만 선택·결합한다. 중복 논리를 가진 역할은 제거하고, 예상 참여자 수·라운드·추가 조사 예산을 `roster.md`에 기록한다.
7. **구성 승인.** 의뢰자에게 아젠다, 증거 공백, roster, 합의 기준, 예상 비용을 제시한다. 명시적 승인 전에는 회의를 시작하지 않는다.
8. **회의 실행.** `references/meeting-protocol.md`와 `references/role-prompts.md`를 따른다. 진행자가 라운드를 지휘·판정하고 메인 세션이 참여자를 호출·디스패치한다.
9. **문서화.** 합의 기준 충족 시 기록자가 `agreement.md`, 미충족 시 `no-consensus.md`를 작성한다.
10. **최종 검토.** 회의 책임자는 최종 문서가 아젠다, 증거 팩, 결정 지도, 반대 의견을 정확히 반영하는지 검토한다. 내용을 임의 변경하지 말고 불일치는 기록자에게 수정시킨 뒤 의뢰자에게 보고한다.

## 디스패치 규칙

- 모든 Agent brief는 자기완결적이어야 한다. 서브에이전트는 메인 컨텍스트를 보지 못한다고 가정한다.
- 첫 입장 라운드에서 참여자에게 다른 참여자의 응답을 전달하지 않는다.
- 전체 증거 팩을 모든 참여자 프롬프트에 반복 주입하지 않는다. 공통 핵심 요약, 관련 증거, 상충 정보, 전체 팩 경로만 전달한다.
- 참여자의 추가 조사 요청은 진행자가 통합·중복 제거하고 중앙 리서처에게 한 번 위임한다.
- 진행자는 다음 발언자, 질문, 추가 조사 필요, 합의 판정, 조기 종료를 결정한다. 메인 세션은 해당 지시에 따라 Agent를 호출한다.
- 기록자는 전체 발화를 재작성하지 않고 주장, 근거, 반론, 입장 변화, 결정만 구조화한다.
- 합의 기준을 충족하지 못하면 거짓 합의를 만들지 않는다. `no-consensus.md`는 정상 산출물이다.

## 합의 방식 선택

| 방식 | 선택 조건 | 종료 기준 |
|---|---|---|
| 자문 | 최종 권한자가 의견을 참고해 결정 | 주요 관점·대안·위험이 충분히 정리됨 |
| 동의 | 실행 가능하며 중대한 위해가 없어야 함 | 중대한 반대가 없고 조건이 처리됨 |
| 합의 | 공동 수용과 장기 협력이 중요 | 모든 핵심 관점이 수용 또는 조건부 수용 |
| 의결 | 정해진 권한·정족수에 따른 선택 | 아젠다에 명시한 규칙 충족 |

AI 페르소나는 실제 사람의 동의나 투표권을 대신하지 않는다. 실제 권한자의 승인이 필요하면 최종 문서에 명시한다.

## 참조 파일

| 파일 | 읽는 시점 |
|---|---|
| `references/agenda-template.md` | 인터뷰와 아젠다 작성 |
| `references/research-protocol.md` | 리서치 계획, 증거 팩, 추가 조사 |
| `references/participant-personas.md` | 참여자 선정·구체화 |
| `references/role-prompts.md` | 운영 역할 Agent 호출 |
| `references/meeting-protocol.md` | 회의 라운드 실행·합의 판정 |
| `references/document-templates.md` | 모든 영속 산출물 작성 |

## 안전 경계

- 외부 정보는 출처와 확인일을 기록하고 사실·해석·가정·미확인을 구분한다.
- 민감 정보는 아젠다의 공개 범위 밖 Agent brief에 넣지 않는다.
- 의뢰자 승인 없이 아젠다·결정 권한·합의 방식을 바꾸지 않는다.
- 합의서 작성 이후 실제 코드, 파일, 조직 정책, 외부 상태를 변경하거나 실행하지 않는다.
