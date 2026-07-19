---
name: brainstorm
description: "새로운 아이디어, 대안, 기회 영역을 폭넓게 탐색하고 후보군과 검증 계획을 만들 때 사용. 사용자가 브레인스토밍, 아이디어 발산, 콘셉트 탐색, 대안 생성, 아이디어 검증, 세션 재개·상태 확인을 요청할 때 활성화."
allowed-tools:
  - AskUserQuestion
  - Agent
  - Read
  - Write(.brainstorm/**)
  - Glob
  - Grep
  - WebSearch
  - WebFetch
  - Bash(ls:*)
  - Bash(find:*)
  - Bash(mkdir -p .brainstorm/**)
  - Bash(date:*)
  - Bash(git status:*)
  - Bash(git log:*)
---

# brainstorm

메인 세션을 **세션 책임자**로 유지하여 프레이밍 인터뷰, 중앙 리서치, 아이디어 생성자 구성, 전략 전환, 수렴, 검증 승인을 관리한다. 목표는 성급한 단일 결론이 아니라 추적 가능한 **복수 후보군**과 검증 계획을 만드는 것이다.

## 호출

`brainstorm start <주제>` / `brainstorm resume <session-id>` / `brainstorm status [session-id]` — 인자가 없으면 `start`로 간주한다. 세션 ID는 로컬 날짜와 주제 slug를 조합한 `YYYYMMDD-<slug>`다. 같은 ID의 세션이 있으면 임의 suffix를 만들지 말고 `resume` 또는 다른 제목을 선택받는다. 세션 산출물은 `.brainstorm/<session-id>.md` **단일 파일 1개**다.

## 상태

`framing → frame_approval → minimal_research → diverging → transforming → clustering → converging → validation_approval → validating → completed`

세션 파일 템플릿은 `references/document-templates.md`를 따른다.

## 세션 파일 규율

- 상태 블록(`## 상태`)이 항상 세션 파일 최상단 첫 섹션이며, 모든 상태 전환 시 상태 블록을 먼저 갱신한다.
- 세션 시작 시 전체 뼈대를 한 번 만든 뒤에는 **섹션 단위로만 추가·갱신**하고 다른 섹션은 건드리지 않는다. 전체 파일 재작성을 금지한다.
- 기존 기록을 덮어써서 아이디어 계보, 실패한 실험 결과, 반대 근거를 지우거나 성공처럼 재작성하지 않는다.
- `resume`은 단일 세션 파일 하나만 읽고 기록된 상태와 다음 행동만 신뢰한다. 필수 산출물이 없거나 상태와 모순되면 추측해 복구하지 말고 불일치를 보고한다.
- `status`는 단일 세션 파일 하나만 읽어 보고한다. 파일을 생성·수정하거나 Agent를 호출하지 않는다.

## resume 라우팅

| 현재 상태 | 재개 행동 |
|---|---|
| `framing` | 브리프 섹션의 미확정 프레이밍 질문부터 인터뷰 |
| `frame_approval` | 프레임을 다시 제시하고 승인 또는 수정만 요청 |
| `minimal_research` | 연구 컨텍스트 섹션의 미완료 최소 조사만 수행 |
| `diverging` | 완료된 독립 Brainwriting 라운드 다음부터 재개 |
| `transforming` | 다양성 정체 여부에 따라 미완료 SCAMPER 변환만 수행 |
| `clustering` | 원본을 유지하며 미분류 아이디어부터 군집화 |
| `converging` | 의뢰자 가치 기준의 미완료 NGT 평가부터 재개 |
| `validation_approval` | 검증 계획 섹션을 다시 제시하고 승인 또는 수정만 요청 |
| `validating` | 승인된 실험 중 미완료 항목만 수행 |
| `completed` | 읽기 전용 최종 보고만 수행 |

## status 보고

`status`는 세션 ID, 현재 상태, 완료 섹션, 아이디어·군집·후보 수, 사용한 연구·Agent 호출 수, 남은 정보 공백, 승인 대기 항목, 다음 행동을 보고한다.

## 시작 워크플로

1. **적합성 확인.** 이미 정해진 대안을 판정하거나 이해관계 합의가 목표면 `roundtable`을 권고한다. 새로운 가능성 탐색이 목표일 때 진행한다.
2. **프레이밍 인터뷰.** `references/framing-template.md`에 따라 문제, 의뢰자 가치, 대상, 범위, 제약, 기존 시도, 금지 영역, 성공 신호를 한 주제씩 묻고 브리프 섹션을 작성한다.
3. **프레임 승인.** 문제 프레임, 탐색 질문, 가치 기준, 예상 아이디어 생성자 3–6명과 비용을 보여준다. 의뢰자의 **프레임 명시적 승인** 전에는 리서치나 Agent 호출을 시작하지 않는다.
4. **최소 중앙 리서치.** `references/research-protocol.md`에 따라 발산에 필요한 공통 사실·제약·용어만 연구 컨텍스트 섹션에 수집한다.
5. **적응형 구성.** `references/role-prompts.md`에서 서로 다른 탐색 렌즈를 가진 아이디어 생성자 3–6명을 선택해 로스터 섹션에 기록한다.
6. **발산과 변환.** `references/strategy-protocols.md`에 따라 Brainwriting을 항상 수행한다. 다양성이 정체되거나 개선형 주제이면 SCAMPER를 적용한다.
7. **군집과 수렴.** 원본 아이디어를 보존한 채 군집화하고, NGT로 의뢰자 가치 기준에 맞는 후보군을 숏리스트 섹션에 만든다.
8. **검증 계획 승인.** 후보별 핵심 가정, 비용, 중단 기준을 검증 계획 섹션에 작성한다. 의뢰자의 **검증 계획 명시적 승인** 전에는 실험을 실행하지 않는다.
9. **검증.** 승인된 상세 리서치, 에이전트 비판, 단순 문서, 목업, 프로토타입만 `.brainstorm/**` 안에서 수행하고 실험 섹션에 결과를 기록한다.
10. **보고.** 후보군, 계보, 비교, 불확실성, 승인된 검증 결과, 다음 의사결정 질문을 최종 보고 섹션에 정리한다.

## 디스패치 규범

- 모든 Agent brief는 자기완결적이어야 한다. 아이디어 생성자·검증자 서브에이전트는 메인 컨텍스트를 보지 못하며 중첩 Agent 호출을 하지 않는다고 명시한다.
- 전체 자료를 모든 아이디어 생성자에 반복 주입하지 않는다. 각 brief에는 공통 핵심 요약과 해당 역할·과업에 관련된 정보만 전달한다.
- 메인 세션이 Agent 호출과 최종 결정을 소유한다. 서브에이전트에게 세션 운영이나 최종 판단을 위임하지 않는다.

## 중앙 리서치 규범

- 조사는 중앙에서 한 번 수행해 아이디어 생성자별 중복 조사를 방지한다.
- 추가 조사 요청은 통합·중복 제거하고, 기존 증거로 답할 수 있으면 재사용하며, 필요한 질문만 중앙에서 한 번 수행한다.
- 외부 사실은 출처와 확인일을 기록하고 사실·해석·가정·미확인을 구분한다. 출처 없는 주장을 사실로 표시하지 않고, 상충 정보는 하나를 임의 채택하지 말고 함께 보존한다.

## 참조 파일

| 파일 | 읽는 시점 |
|---|---|
| `references/framing-template.md` | 인터뷰와 프레임 승인 |
| `references/research-protocol.md` | 최소 조사와 후보 검증 조사 |
| `references/role-prompts.md` | 아이디어 생성자·검증자 구성과 호출 |
| `references/strategy-protocols.md` | Brainwriting, SCAMPER, 군집화, NGT |
| `references/document-templates.md` | 모든 영속 산출물 작성 |

## 안전 경계

- 승인된 검증 실험은 리서치, 에이전트 비판, 단순 문서, 목업, 프로토타입으로 제한하며 모두 `.brainstorm/**`에 기록한다.
- 코드베이스, 조직 정책, 외부 시스템, 외부 상태를 변경하거나 실제 사용자에게 실험을 배포하지 않는다.
- 민감 정보는 공개 범위 밖 Agent brief에 넣지 않는다.
