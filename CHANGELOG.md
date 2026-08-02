# Changelog

이 저장소가 **현재 배포하는 플러그인**의 사용자 가시(behavior-changing) 변경을 기록합니다. 버전의 단일 출처(SoT)는 각 플러그인의 `plugin.json`입니다. 배포에서 제거된 플러그인(autopilot·project-init·skill-rubric 등)의 엔트리는 본 파일에서 정리하며, 그 과거 기록은 git 이력에 보존됩니다. 분류: 새 기능 / 변경(호환) / 변경(깨짐) / 버그 수정 / 보안.

## agent-kit 0.2.0

### 새 기능
- **skill 스킬(typed 스킬)** — 단독 호출과 파이프라인 노드 편입이 모두 가능한 typed 스킬을 만들고 검증한다. typed 스킬은 frontmatter에 기계 가독 계약(JSON Schema식 inputs/outputs + kind별 실행법 — `llm`(서브에이전트) / `script`(셸) / `http`(curl) / `mcp`(도구 호출))을 선언한 `.claude/skills/<이름>/SKILL.md`다. 확장 필드는 harness가 무시하고 pipeline validate·compile이 읽으며, 본문은 계약의 실행 지시(frontmatter가 정본). `create`(대화형 정의) / `test <이름>`(모의 입력 단독 실행 후 출력 스키마 대조 — script·http는 실행 전 명령 전문 확인) / `list`(kind 있는 typed 스킬만).
- **pipeline 스킬(워크플로 컴파일러)** — typed 스킬들을 노드로 연결한 그래프를 `.pipelines/<이름>.yaml`로 정의하고 자립 실행형 워크플로 스킬(`.claude/skills/<이름>/` — SKILL.md + graph.yaml 스냅샷)로 컴파일한다. 원칙: 정의 = 소스, 생성된 스킬 = 바이너리(`compiled-from` 해시로 드리프트 감지, `list`가 재컴파일 필요를 표시). edge 선언 없이 `$노드id.출력` 참조로 의존성 자동 도출, 의존 없는 노드는 자동 병렬. 유틸 노드 5종(if/switch·foreach·merge·transform(jq)·human-gate) + 공통 속성 retry/timeout/on_error. compile은 validate(참조 무결성·필수 입력·타입 일치·순환) 통과 시에만 산출한다. 컴파일된 스킬 자체도 typed(`kind: pipeline`, inputs/outputs)라 다른 파이프라인이 `skill:`로 노드처럼 참조 가능 — 파이프라인 합성. 생성된 스킬은 실행마다 `.pipelines/runs/<run-id>/`에 노드별 출력과 state.json을 남기고 `resume <run-id>`로 실패·중단 지점부터 재개한다. 설계 스펙: `docs/superpowers/specs/2026-08-02-agent-kit-pipeline-node-design.md`.

## agent-kit 0.1.0

### 새 기능
- **advisor 스킬** — 호출 세션(Worker)이 판단 전담 Advisor 서브에이전트를 생성해 감독 아래 구현하는 역할 역전 워크플로. Advisor는 요구사항 분석·작업 브리프 작성·결과 검증(diff·테스트 직접 실행)·커밋 승인을 소유하고, 구현 노동은 Worker가 수행한다. 상태 태그 6종(BRIEF/QUESTION/SKIP/APPROVED/REVISE/ESCALATE) 프로토콜, REVISE 3라운드 초과 시 사용자 에스컬레이션, 커밋은 사용자가 요청한 세션에서만 실행.

## explain-diff 0.1.0

### 새 기능
- **explain 스킬(설명서)** — 방금 바뀐 코드(작업 트리 diff·커밋·브랜치·PR)를 코드베이스가 처음인 독자에게 설명한다. 주변 코드를 넓게 탐색한 뒤 배경 → 직관(장난감 데이터 예시) → 코드 워크스루 순서를 강제하고, 코드는 맨 마지막에만 보여준다.
- **quiz 스킬(퀴즈)** — 직전 설명 내용으로 중간 난이도 4지선다 5문항을 출제·채점한다. 전부 맞히기 전에는 정답·해설을 공개하지 않고, 틀린 문항이 드러내는 오해 지점만 짚어 재시도를 유도한다(명시적 포기 시에만 공개).
- **playground 스킬(놀이터)** — 방금 개발한 코드를 자체 완결 단일 HTML 파일(목차·배경·직관·코드 워크스루, 상호작용 데모·HTML 다이어그램)로 시각화한다. 서비스 코드는 수정하지 않으며 산출물은 버전 관리 밖에 날짜 접두사 파일명으로 저장한다. geoffreylitt의 explain-diff-html 프롬프트(gist)를 기반으로 했다.

## thinktank 2.0.0

### 변경(깨짐)
- **brainstorm 스킬 → forum 이름 변경** — 타 마켓플레이스·사용자 레벨 스킬과의 `brainstorm` 이름 충돌을 피하기 위해 스킬 이름을 `forum`으로 바꿨다. 호출은 `Skill(skill="thinktank:forum", ...)` / `forum start|resume|status`. 세션 디렉토리도 `.brainstorm/` → `.forum/`으로 바뀌며, 기존 `.brainstorm/` 세션 파일의 자동 이관은 없다(재개하려면 `.forum/`으로 수동 이동). 활성화 트리거(브레인스토밍, 아이디어 발산 등)와 매니페스트 키워드(`brainstorming`·`ideation`)는 그대로 유지되어 기존 자연어 요청으로는 동일하게 발동한다. 테스트·픽스처·runbook의 스킬명 참조를 함께 갱신했다(`tests/thinktank/test-forum-skill.sh`, `fixtures/forum/`). 과거 측정 기록(`measurements/`)은 이력 보존을 위해 이름을 유지한다.

## thinktank 1.2.0

### 새 기능
- **roundtable 반대 강제(거짓 합의 방지)** — 합의 후보 검증에서 모든 핵심 참여자의 평가가 수용·조건부 수용뿐이면(중대한 반대·판단 불가 0건), 진행자가 종료 판정 전 참여자 1명(로스터에 반대 관점 대변인이 있으면 그 역할)에게 가장 강한 반대 논거 1건을 증거 ID와 함께 요구한다. 논거가 중대한 반대 요건을 충족하면 정상 숙의로 처리하고, 반박되면 반박 근거를 결정 지도에 기록 후 종료 판정으로 진행한다(`meeting-protocol.md`).
- **roundtable 상호 반박 왕복** — 핵심 이견 쟁점은 진행자가 대립 입장의 참여자를 지정해 반박 → 재반박 1왕복을 교환하게 하고, 이때만 해당 쟁점의 상대 주장 전문과 근거 ID를 그대로 전달한다. 미해소 쟁점은 결정 지도에 기록하고 같은 쟁점의 추가 왕복은 새 증거·논거가 있을 때만 허용한다(`meeting-protocol.md`).
- **핵심 주장 증거 임계치** — roundtable: 합의문·결정사항이 직접 의존하는 핵심 주장은 서로 독립인 출처 2개 이상이어야 `확인`으로 표시하고, 단일 출처면 `추정` + 주의사항 기록, 반증 시도 결과를 함께 기록한다(`research-protocol.md`). brainstorm: 후보 채택·탈락을 좌우하는 핵심 사실에 같은 독립 출처 2개·추정 표시·반증 기록 규칙을 적용한다(`research-protocol.md` 2단계).
- **정량 검증 인프라 — 구조화 마커·측정 하니스·표준 시나리오 픽스처·runbook** — 세션 파일 템플릿에 하니스 파싱용 kebab-case 구조화 마커를 추가했다(roundtable 라운드 항목: `core-claim`·`dissent-forcing-triggered`·`rebuttal-exchange` / brainstorm: `core-fact`·`independent-sources` 신규 + 기존 `park-recondition`·`elimination-reason`·`parent-id` 재사용). 측정 하니스 `tests/thinktank/measure-session.sh`(마커 파싱·절대 임계치 판정·fail-loud — 필수 마커 누락·손상 시 non-zero exit, selftest 15케이스), 스킬별 표준 시나리오 픽스처(`tests/thinktank/fixtures/`), 측정 절차·모델 교체 재검증 runbook(`tests/thinktank/measurement-runbook.md`)을 추가했다. 임계치·판정 방식은 아래 "정량 게이트 임계치 확정" 항목으로 발효됐다.

### 정량 게이트 임계치 확정 (파일럿 실측 기반)

- **측정 방법** — 커밋된 표준 시나리오 픽스처로 스킬 계약을 실제 수행하는 세션을 구동해(세션에 측정 목표 비공개, 원본 산출물 `tests/thinktank/measurements/sessions/` 보존) 하니스로 판정했다. 측정 모델: claude-fable-5. 세션 집계 의미론: dissent any-yes / rebuttal 라운드 합계 / independent-sources 항목 최대값.
- **roundtable 게이트 지표** (gate-status: active, decision-mode: 1회 충족) — `dissent-forcing-triggered`=yes (실측 3/3 발동), `rebuttal-exchange` ≥1왕복 (실측 합계 1/2/2), `core-claim` ≥1개 (실측 3/6/4).
- **brainstorm 게이트 지표** — `core-fact` ≥1개/세션 (active, 실측 25~27), `park-recondition`·`elimination-reason` 충족률 100% (active, fail-loud 강제, 전 실행 100%). `independent-sources` ≥2는 **shadow(기록 전용) 강등** — 실측 최대값 1~5 분산으로 템플릿 규약 조정·재파일럿 1회 상한 후에도 판정이 갈림(스킬별 안정 지표 ≥1 요건은 active 3개로 충족).
- 초기 파일럿 중 3회는 마커 값 산문 주석(형식 위반)으로 판정 제외 — 문서 템플릿에 "마커 값은 순수 값만" 규칙을 추가하고 정책상 재파일럿 1회로 대체했다. 상세: `tests/thinktank/measurements/*-pilot-20260801.md`, `tests/thinktank/measurement-runbook.md`.
- 게이트 승인: 2026-08-01, 사용자 승인 — roundtable active 3지표·brainstorm active 3지표 + shadow 1지표(independent-sources)로 1.2.0 정량 게이트 발효.

### 버그 수정
- **디스패치 규범이 brief 템플릿에 미구현 (정합성 결함)** — 두 SKILL.md는 "서브에이전트 brief에 메인 컨텍스트 비가시성과 중첩 Agent 호출 금지를 명시한다"고 규정했지만 실제 brief 템플릿에는 해당 문구가 없었다(`participant-personas.md`의 중첩 Agent 금지 1건 제외). brainstorm·roundtable `role-prompts.md`와 `participant-personas.md`에 명시 문구를 반영했다. 회귀 가드: 두 테스트 스크립트에 명시 문구 grep 가드 추가.

### 변경(호환)
- **roundtable 상태 블록 필드 kebab-case 통일** — `meeting_id`·`current_round`·`max_rounds`·`research_calls_used`·`agent_calls_used`·`next_action`·`last_updated`를 brainstorm과 동일한 kebab-case(`meeting-id` 등)로 통일했다(`document-templates.md`). 호환 분류 근거: 이 필드명은 새 회의 파일 작성 시에만 적용되는 문서 템플릿 계약이고, 상태 머신 enum 값(`agenda_approval` 등)은 변경하지 않았다. `resume`는 회의 파일에 기록된 상태 블록을 산문으로 읽으므로 구 회의 파일의 snake_case 필드도 해석에 영향이 없고, 불일치는 기존 "resume 불일치 보고" 규율이 처리한다 — 마이그레이션 불필요. 회귀 가드: roundtable 테스트에 snake_case 잔존 부정 가드 추가.

## thinktank 1.1.0

### 변경(호환)
- **brainstorm 아이디어 상태 `archived` → `parked`·`eliminated` 분리 (성숙도 재분석 권고 2건 적용)** — `archived` 단일 상태를 `parked`(관찰 가능한 재검토 조건 `park-recondition` 필수)와 `eliminated`(근거 있는 탈락 사유 `elimination-reason` 필수)로 분리했다. 최종 enum: `raw | transformed | clustered | shortlisted | parked | eliminated`. NGT 수렴 절에 성숙도 미사용 규칙(구체화 부족을 후보 탈락 근거로 쓰지 않는다)과 상태 전환 규칙(수렴 완료 시 세션 책임자가 미선택 아이디어를 관찰 가능한 재검토 조건 유무에 따라 parked 또는 eliminated로 판별 표시)을 추가했다. 호환 분류 근거: 이 enum은 새 세션 파일 작성 시에만 적용되는 문서 템플릿 계약이며, 릴리스 시점 검증에서 `archived`를 참조하는 외부 소비자·코드·테스트·기존 `.brainstorm/` 세션 파일이 없음을 확인했다(참조는 `document-templates.md` 자신 2곳뿐). `resume` 라우팅은 세션 상태 블록 기준이라 아이디어 status 값에 의존하지 않으며, 구 세션 파일의 `archived` 잔존은 기존 "resume 불일치 보고" 규율이 처리한다 — 마이그레이션 불필요.

## marketplace 0.4.0

### 새 기능
- **agent-kit 0.1.0 등록** — 에이전트 협업 플러그인(`plugins/agent-kit/`)을 마켓플레이스에 추가하고 버전을 `0.3.0 → 0.4.0`으로 올렸다.

## marketplace 0.2.0

### 변경(깨짐)
- **배포 범위를 `thinktank` 하나로 축소 — `autopilot`·`project-init`·`superpowers` 제거 (run 650)** — 서로 무관한 네 플러그인을 한 저장소가 안고 있어 늘어나던 유지 비용과 상호 참조를 끊고 저장소 책임을 단일화한다. 세 플러그인의 본체 디렉터리(`plugins/autopilot/`·`plugins/project-init/`·`plugins/superpowers/`), Claude 마켓플레이스 등록(`.claude-plugin/marketplace.json`), Codex 마켓플레이스 매니페스트(`.agents/plugins/marketplace.json` — `project-init`이 유일한 Codex 플러그인이었고 `thinktank`에는 Codex 매니페스트가 없어 Codex 지원 자체를 제거), 저장소 로컬 활성화 설정(`.claude/settings.json`의 `enabledPlugins`를 비움), 해당 플러그인 전용 테스트(`tests/autopilot/`·`tests/forge/`), 고아가 된 테스트-소스 커버리지 매핑 규칙(`.autopilot/scope-coverage-map.json`)을 함께 제거했다. README를 Claude 전용 구성으로 갱신하고 마켓플레이스 버전을 `0.1.0 → 0.2.0`으로 올렸다(0.x 구간이므로 호환성 깨짐을 MINOR로 표현). `thinktank` 본체·테스트·버전 값과 PR 리뷰 CI 자동화(저장소 공통 자산)는 변경하지 않았다. **영향** — 이 저장소 마켓플레이스를 구독하던 환경에서 제거된 세 플러그인의 설치·업데이트가 끊긴다.

## thinktank 1.0.2

### 변경(호환)
- **공유 session-conventions 해체 — 규범을 각 SKILL.md에 용어 특화 인라인 (run 604)** — `skills/shared/session-conventions.md`를 제거하고 규범 5영역(호출 규약·세션 파일 규율·디스패치 공통 규범·중앙 리서치 공통 규범·공통 안전 경계)을 brainstorm(세션 파일, `.brainstorm/<session-id>.md`)·roundtable(회의 파일, `.roundtable/<meeting-id>.md`) 각 SKILL.md 본문에 각 스킬 용어로 자체 정의. `../shared/` 참조·위임 문구 제거(스킬 자기완결). 규범 의미·강도 불변.

## thinktank 1.0.1

### 변경(호환)
- **brainstorm·roundtable 스킬 문서 단일 출처화·간소화 (#592)** — 두 스킬이 사본으로 갖던 공유 규범(호출 규약·세션 파일 규율·디스패치·중앙 리서치·공통 안전 경계)을 `skills/shared/session-conventions.md` 단일 출처로 모으고, 각 SKILL.md·references의 중복 문장을 제거해 스킬 문서군 총 줄 수를 줄였다. 런타임 계약(frontmatter 키·allowed-tools 스코프·상태 머신·산출물 단일 파일 구조·호출 시그니처)과 description 트리거 계약은 변경 없음. 테스트는 이동한 규범의 단언 위치를 shared로 재지정하고, 버전 검사를 고정값(1.0.0) 대신 plugin.json↔marketplace 동등성 검사로 재작성했다.

## thinktank 1.0.0

### 변경(깨짐)
- **brainstorm·roundtable 세션 산출물을 세션당 단일 파일로 취합 (#581)** — 산출물 계약을 "세션당 디렉터리 + 다중 파일"에서 단일 파일 1개로 교체했다. brainstorm은 `.brainstorm/<session-id>/` 아래 10개 파일(state·brief·research-context·roster·idea-pool·clusters·shortlist·validation-plan·experiments·report) 대신 `.brainstorm/<session-id>.md` 하나에, roundtable은 `.roundtable/<meeting-id>/` 아래 다수 파일 대신 `.roundtable/<meeting-id>.md` 하나에 상태 블록(최상단, 현재 상태·다음 행동)과 기존 산출물별 대응 섹션을 둔다. 상태 전환은 상태 블록 먼저 갱신, 갱신은 섹션 단위만(전체 파일 재작성 금지·다른 섹션 비접촉), resume/status는 단일 세션 파일 하나만 읽는다. roundtable 최종 문서 섹션은 진행자 판정에 따라 합의·실행서 또는 불합의 보고서 중 하나로 기록한다(불합의는 정상 산출물). 워크플로 상태 머신·승인 게이트·안전 경계·산출물 루트·allowed-tools 스코프는 변경 없음. 구 형식(디렉터리) 세션·회의는 자동 마이그레이션하지 않으며 resume 시 불일치로 보고된다.
