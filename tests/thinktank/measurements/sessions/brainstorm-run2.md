# Brainstorm Session: 20260801-onboarding-dropout-b2

## 상태
- session-id: 20260801-onboarding-dropout-b2
- state: validation_approval
- updated-at: 2026-08-01
- frame-approved-at: 2026-08-01 (측정 모드 픽스처 브리프로 사전 승인 — AskUserQuestion 인터뷰 생략)
- validation-approved-at: (미승인 — 검증 계획 승인 대기)
- agent-calls-used: 0 (서브에이전트 호출 불가 환경. 아이디어 생성자 렌즈는 메인 컨텍스트 안에서 순차적으로, 서로의 결과를 참조하지 않는 방식으로 수행함)
- research-calls-used: 4 (WebSearch 4회, 상세는 연구 컨텍스트 섹션)
- completed-sections: 브리프, 연구 컨텍스트, 로스터, 아이디어 풀, 군집, 숏리스트, 검증 계획(제안 단계)
- next-action: 검증 계획 섹션(Experiment E-01~E-05)을 의뢰자에게 다시 제시해 명시적 승인 또는 수정 요청. 승인 전에는 실험을 실행하지 않는다.
- inconsistencies: 이 세션은 측정 하니스용 픽스처 실행으로, 프레이밍 인터뷰·프레임 승인·검증 계획 승인이 실제 AskUserQuestion 없이 사전 브리프로 대체됨. `requester`, `requester-value`, `success-signals` 등 일부 브리프 필드는 명시적 인터뷰 답변이 아니라 픽스처 배경에서 추론한 값이며 브리프의 `assumptions` 필드에 그 사실을 표시함.

## 브리프

- session-id: 20260801-onboarding-dropout-b2
- requester: 미상 — 픽스처 브리프 제공자 (명시적 인터뷰 없음, 이하 필드 중 추론값은 assumptions에 표시)
- problem-or-opportunity: B2B SaaS 제품의 신규 사용자 온보딩 완료율이 34%로 업계 평균(52%로 제시됨) 대비 낮고, 최초 로그인 후 7일 이내 이탈이 58%에 달한다. 특히 온보딩 3단계(데이터 연동 설정)에서 28%가 이탈한다.
- target: 중소기업(SMB) 고객의 IT 담당자. 다수가 비개발자.
- requester-value: 온보딩 완료율과 초기(7일) 리텐션 개선을 통한 활성화 기반 확보로 추정 (assumption — 명시적 확인 없음)
- how-might-we: 비개발자인 중소기업 IT 담당자가 데이터 연동 설정을 포함한 온보딩을 어떻게 하면 더 쉽게 완료하고, 7일 이내에 제품의 핵심 가치를 경험하게 할 수 있을까?
- scope: 신규 가입 후 첫 7일간의 온보딩 경험 전체(이메일 시퀀스 7단계, 인앱 툴팁 3개, 3단계 데이터 연동 설정 포함).
- out-of-scope: 가격·플랜 변경, 영업 프로세스, 90일 이후 장기 리텐션 시책, 온보딩과 무관한 신규 기능 개발, 마케팅 채널 확장.
- constraints: 개발 예산 3인월 이하 / 출시 일정 6주 이내 / React+Node.js 기술 스택 변경 불가 / 대상 고객이 비개발자 다수(IT 담당자이나 개발 지식 낮음).
- existing-attempts: 이메일 시퀀스 7단계 + 인앱 툴팁 3개가 이미 운영 중이나 목표(완료율 개선) 미달성.
- assumptions:
  1. requester-value는 활성화율·초기 리텐션 개선으로 가정함(직접 확인 안 됨).
  2. success-signals는 배경 지표(완료율, 3단계 이탈률, 7일 이탈률)의 개선 방향으로 추정 기재함(픽스처가 명시하지 않음).
  3. "업계 평균 52%"의 1차 출처는 픽스처 제공값이며, 연구 컨텍스트 RF-01에서 방향성만 상호 확인함(정확한 수치 자체는 미검증).
  4. 3단계 이탈(28%)의 원인이 기술적 난이도라는 가설은 세션 내부에서 검증되지 않은 가정이며, 검증 계획(E-01)로 이관함.
  5. "개발 예산 3인월"이 실시간 CS 인력 운영비를 포함하는지 여부는 불명확(검증 계획 E-02로 이관).
- success-signals: 온보딩 완료율 상승, 3단계(데이터 연동) 이탈률 감소, 7일 이내 이탈률 감소 (assumption — 픽스처가 관찰 가능한 신호를 명시하지 않아 배경 지표를 기준으로 추정)
- evaluation-criteria:
  1. (필수, 최우선) 개발 예산 3인월 이하 / 6주 이내 출시 / React+Node.js 스택 내 구현 가능성.
  2. 3단계 데이터 연동 이탈 및 7일 이탈 감소에 대한 기대 효과 크기.
  3. 비개발자인 중소기업 IT 담당자가 실제로 사용 가능한 수준의 사용성.
  4. 학습 가치(핵심 불확실성을 얼마나 값싸게 줄여주는가).
  - trade-off: 임팩트가 커 보여도 제약(1번)을 명백히 초과하는 아이디어는 evidence-level만 기록하고 채택 우선순위는 낮춘다. 제약 충족이 다른 세 기준보다 우선한다.
- frame-status: approved (측정 모드 픽스처로 사전 승인 처리)

## 연구 컨텍스트

측정 모드 지침에 따라 WebSearch 4회로 발산에 필요한 최소 공통 사실·용어·유사 사례만 수집했다. 검색은 모두 2026-08-01에 수행했으며, 대부분의 결과가 1차 리포트를 재인용하는 2차 마케팅/가이드 블로그였다는 점을 그대로 기록한다(과신하지 않도록 유형을 fact/interpretation/assumption/unconfirmed로 구분).

### 용어·현재 상태

- **인앱 툴팁(in-app tooltip)**: 화면 내 특정 UI 요소를 짚어 안내하는 경량 가이드. 현재 3개 운영 중(브리프 제공값, fact — 세션 내부 정보).
- **이메일 시퀀스(email sequence)**: 가입 후 자동 발송되는 이메일 7단계(브리프 제공값, fact — 채널·주기 세부는 미기재라 unconfirmed).
- **iPaaS(Integration Platform as a Service)**: 여러 SaaS 간 데이터 연동을 코드 없이 구성하도록 돕는 중간 플랫폼 계층 (용어 정의, fact).

### 확정 제약·금지선

브리프에 명시된 4개 제약(3인월/6주/React+Node 불변/비개발자 세그먼트) 외에 안전·법적 금지선은 브리프에 명시되지 않음 — 없다고 단정하지 않고 **unconfirmed**로 표시.

### 리서치 발견(RF)

**RF-01**
- 유형: fact (2차 재인용 다수, 완전 독립은 아님)
- 진술: B2B SaaS 온보딩 완료율은 40–60%가 양호한 수준, 60% 이상 우수, 80% 이상 예외적으로 평가됨.
- 출처: [What Is User Onboarding Completion Rate in SaaS?](https://www.alexanderjarvis.com/what-is-user-onboarding-completion-rate-in-saas/) / [Benchmarking Your Onboarding: Industry Standards for 2026](https://www.adoptkit.com/posts/onboarding-benchmarks-industry-standards-2026)
- 확인일: 2026-08-01 (WebSearch)
- independent-sources: 2 (다만 두 출처 모두 Userlist 등 동일 1차 소스를 재인용하는 것으로 보여 완전한 독립으로 보기 어려움 — 주의)
- 비고: 브리프의 "업계 평균 52%"는 이 범위(40–60%) 안에 있어 방향은 상충하지 않지만, 52%라는 특정 수치의 1차 출처는 확인하지 못함(unconfirmed).

**RF-02**
- 유형: unconfirmed (원문 미확보, 2차 인용)
- 진술: Userpilot 2025 SaaS 벤치마크에 따르면 B2B SaaS 62개사 평균 사용자 활성화율은 37.5%.
- 출처: WebSearch 결과 종합, 원문 URL 미확보
- 확인일: 2026-08-01
- independent-sources: 1

**RF-03**
- 유형: unconfirmed (원문 미확보, 2차 인용)
- 진술: Amplitude 2025 Product Benchmark Report(2,600여개사)는 핵심 가치 마일스톤 미도달 신규 사용자의 98% 이상이 2주 내 이탈한다고 보고했다고 함.
- 출처: WebSearch 결과 종합, 원 리포트 URL 미확보
- 확인일: 2026-08-01
- independent-sources: 1 — 인용 정확도 검증 불가

**RF-04**
- 유형: interpretation/unconfirmed (방법론 비공개 마케팅 블로그)
- 진술: 전략적 온보딩 투자가 이탈을 40–60% 감소, LTV를 최대 3배 높인다는 주장이 여러 블로그에서 반복됨.
- 출처: 검색 종합(Medium, Phoenix Strategy Group 등 다수)
- 확인일: 2026-08-01
- independent-sources: 다수지만 방법론 비공개 — 신뢰도 낮음. **아이디어 영감 자료로만 사용, 어떤 idea의 core-fact 근거로도 채택하지 않음.**

**RF-05**
- 유형: fact (다출처, 벤더 이해상충 존재)
- 진술: 데이터 연동/통합 설정은 SaaS 온보딩의 흔한 실패·이탈 지점이며, 이를 해결하기 위한 임베디드 iPaaS·no-code 커넥터·설정 마법사(wizard) 벤더 카테고리가 실재한다.
- 출처: [ConnectorHub](https://connectorhub.ai/blogs/why-saas-companies-moving-away-from-one-off-integrations) / [Skyvia](https://skyvia.com/blog/saas-integration-best-practices/) / [Truto](https://truto.one/blog/dynamic-post-connection-configuration-for-saas-integrations-building-data-driven-setup-flows-without-custom-code/) / [AppSeConnect](https://www.appseconnect.com/best-saas-integration-tools-2025-comparison/) / [Albato](https://albato.com/blog/publications/embedded-saas-integrations-guide)
- 확인일: 2026-08-01
- independent-sources: 5개 이상 서로 다른 벤더/도메인 (모두 자사 제품 판매 목적 — 편향 존재, "no-code 해결 카테고리가 존재한다"는 패턴 자체는 다출처로 확인되나 효과 크기 주장은 별도 검증 필요)

**RF-06**
- 유형: unconfirmed (단일 출처, 구체 수치)
- 진술: 사전 구축 커넥터 기반 임베디드 iPaaS 도입 시 점대점 통합 개발 대비 개발 기간을 최대 80% 절감할 수 있다는 주장.
- 출처: 검색 종합(getknit.dev 관련), 원문 미확보
- 확인일: 2026-08-01
- independent-sources: 1 — 벤더 마케팅 수치로 과장 가능성, **candidate 근거로 과신하지 않음(C-02 참조)**

**RF-07**
- 유형: fact (UX 원칙, 업계 통용, 원 연구 미인용)
- 진술: 점진적 공개(progressive disclosure) — 핵심 기능 먼저, 고급 기능은 이후 — 원칙이 다수 온보딩/UX 가이드에서 공통적으로 제시됨.
- 출처: [Arcade](https://www.arcade.software/post/customer-onboarding-best-practices) / [DesignRevision](https://designrevision.com/blog/saas-onboarding-best-practices) / [Formbricks](https://formbricks.com/blog/user-onboarding-best-practices)
- 확인일: 2026-08-01
- independent-sources: 3 (2차 가이드 성격)

**RF-08**
- 유형: interpretation/unconfirmed (방법론 비공개, 업계 통설)
- 진술: 최초 가치 체감까지 걸리는 시간(time to first value)을 5분 이내로 단축하는 것이 온보딩 이탈 감소의 핵심 권장사항으로 다수 가이드에서 제시됨.
- 출처: WebSearch 결과 종합(온보딩 최적화 가이드 다수), 구체 URL 특정 안 됨
- 확인일: 2026-08-01
- independent-sources: 1(반복 인용되는 업계 통설 수준, 원 데이터 없음)

### 기존 시도·중복 확인

이메일 7단계 + 툴팁 3개가 이미 존재하지만 목표 미달성 — 완전히 새로운 채널보다 기존 자산 위에 추가·재배치하는 방향의 실현 가능성이 상대적으로 높다(제약 3인월/6주 고려). 조직 내부에 다른 유사 시도가 있었는지는 이 세션의 정보만으로 확인 불가(unconfirmed).

### 유사 사례·발산 자산

RF-05·RF-06(no-code 커넥터/설정 마법사), RF-07·RF-08(점진적 공개·time-to-value 단축)이 발산에 유용한 유사 사례로 확인됨.

## 로스터

주제가 (a) UX/여정 문제, (b) 기술 연동 난이도 문제, (c) 자원 제약이 강한 개선형 프로젝트라는 세 층위를 모두 갖고 있어, role-prompts.md의 6개 렌즈 중 서로 다른 관점을 제공하는 5개를 선택했다(급진적 탐색자는 이번 라운드에서 생략 — 개선형 주제 특성상 제약 전환자·실용적 조합자가 더 직접적 가치를 줄 것으로 판단, 필요 시 재개 시점에 추가 가능).

### 사용자·고객 탐색자
- 프레임: how-might-we + scope
- 보호할 가치: 비개발자 IT 담당자의 실제 여정에서의 미충족 욕구·접근성
- 관련 정보: 3단계 이탈 28%, 7일 이탈 58%, 세그먼트(비개발자 다수)
- 전제: 메인 세션 컨텍스트는 보이지 않는다. 이 brief가 전부다. 다른 생성자의 결과를 보지 않고 독립적으로 발산한다.
- 금지: 발산 중 비판·평가·순위·합의, 프레임 밖 실행, 중첩 Agent 호출

### 도메인 유추자
- 프레임: how-might-we + scope
- 보호할 가치: 다른 산업·경험에서 검증된 "비전문가를 위한 복잡한 절차 안내" 원리
- 관련 정보: 3단계가 기술적 설정 단계라는 점
- 전제·금지: 위와 동일

### 제약 전환자
- 프레임: how-might-we + constraints
- 보호할 가치: 3인월/6주/React+Node 불변/비개발자 세그먼트 제약을 무시하지 않고 설계 재료로 삼기
- 관련 정보: constraints 4항목, existing-attempts
- 전제·금지: 위와 동일

### 시스템 사고자
- 프레임: how-might-we + scope
- 보호할 가치: CS·영업·제품 등 여러 행위자 간 피드백 루프와 인센티브
- 관련 정보: 이탈 지점(3단계), 이탈 시점(7일 이내), existing-attempts
- 전제·금지: 위와 동일

### 실용적 조합자
- 프레임: how-might-we + existing-attempts
- 보호할 가치: 새 개발 없이 기존 자산(이메일 7단계, 툴팁 3개)의 재조합으로 낼 수 있는 가치
- 관련 정보: existing-attempts, constraints
- 전제·금지: 위와 동일

## 아이디어 풀

Brainwriting 규칙에 따라 각 렌즈는 다른 렌즈의 결과를 참조하지 않고 독립적으로 발산했다(비판·평가·순위 없음). 이후 이 주제가 기존 프로세스의 **개선형 주제**에 해당하여(strategy-protocols.md 규칙) SCAMPER 변환을 추가 적용했다. 다양성 자체는 20개 원본 아이디어에서 게임화·마켓플레이스·구조 역전 등 다양한 해법 유형이 이미 나타나 뚜렷한 정체 신호는 없었으나, 개선형 주제 기준이 별도로 SCAMPER를 요구하므로 7개 변환을 추가했다.

### IDEA-001
- idea-id: IDEA-001
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: Cluster A
- idea: 가입 직후 짧은 사전 진단 퀴즈로 사용 중인 CRM/ERP 등을 파악해, 3단계 진입 전 맞춤 연동 가이드를 미리 보여준다.
- expected-value: 낯선 화면 앞에서의 막막함 감소, 3단계 진입 전 기대치 형성
- novelty: 중간
- assumptions: 사전 정보 제공만으로 실제 이탈이 줄어든다(미검증)
- duplicate-of: none
- status: parked
- park-recondition: C-01(사전 준비 체크리스트) 검증 후 완료율 개선 여력이 남으면 개인화 강화 단계에서 재검토
- elimination-reason: (해당 없음)
- core-fact: 해당 없음 — 발산 단계 아이디어로 특정 핵심 사실에 근거하지 않음
- independent-sources: 0

### IDEA-002
- idea-id: IDEA-002
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: Cluster B
- idea: 3단계 화면에 "지금 5분 화면공유 도움받기" 버튼을 배치해 예약 없이 바로 상담원과 연결(챗 우선, 필요 시 화면공유).
- expected-value: 막히는 즉시 인적 지원으로 이탈 방지
- novelty: 낮음(일반적 라이브 채팅 패턴)
- assumptions: 실시간 응대 인력이 상시 가용하다
- duplicate-of: none
- status: parked
- park-recondition: C-03(트리거형 라이브 지원) 실험에서 실시간 인력 운영이 실제로 가능하다고 확인되면, 사용자 주도 요청 채널로 추가 검토
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-003
- idea-id: IDEA-003
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: Cluster B
- idea: 담당자가 막히면 그 자리에서 사내 개발자 동료를 초대해 연동 단계만 위임할 수 있는 "부분 위임" 링크 제공.
- expected-value: 조직 내 협업으로 기술 장벽 우회
- novelty: 중간
- assumptions: 고객사 내부에 위임 가능한 동료가 존재한다(세그먼트 특성상 항상 참은 아님)
- duplicate-of: none
- status: parked
- park-recondition: 3단계 이탈 사용자 대상 후속 인터뷰에서 "동료에게 위임하고 싶다"는 니즈가 확인되면 재검토
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-004
- idea-id: IDEA-004
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: Cluster D
- idea: 연동 시도가 실패(에러)할 때마다 에러 메시지를 자동 인식해 관련 FAQ/해결 가이드를 그 자리에서 인라인 노출.
- expected-value: 실패 직후 즉각적 자기 해결 지원
- novelty: 중간
- assumptions: 에러 메시지 패턴이 유한하고 사전 분류 가능하다
- duplicate-of: none
- status: parked
- park-recondition: C-02 배포 후에도 특정 에러 유형이 반복 발생한다는 로그 데이터가 축적되면 재검토
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-005
- idea-id: IDEA-005
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: Cluster C
- idea: 기술 용어(API 키, 웹훅) 대신 "어떤 도구로 고객 정보를 관리하시나요?" 같은 자연어 질문으로 연동 설정을 대화형 인터뷰로 재구성(세무 신고 소프트웨어의 인터뷰 UX 차용).
- expected-value: 기술 용어 노출 최소화로 심리적 장벽 감소
- novelty: 높음
- assumptions: 대화형 응답을 실제 연동 액션(인증, 매핑)으로 자동 변환할 수 있다
- duplicate-of: none
- status: eliminated
- park-recondition: (해당 없음)
- elimination-reason: 대화형 인터뷰로 얻은 답변을 실제 연동 액션(인증·매핑)으로 변환하려면 결국 C-02(IDEA-009/021/024)와 동일한 백엔드 작업이 필요하고, 그 위에 대화형 UI 레이어까지 추가로 구현해야 해 3인월/6주 제약을 C-02보다 명백히 더 초과한다고 판단. 동일 목표를 더 낮은 비용으로 달성하는 대안(C-02)이 이미 존재.
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-006
- idea-id: IDEA-006
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: Cluster D
- idea: 텍스트 지침 대신 단계별 시각 다이어그램(스크린샷+화살표)만으로 구성된 "그림으로 보는 연동 가이드"를 별도 모드로 제공(IKEA식 그림 설명서 차용).
- expected-value: 읽기 부담 감소, 시각적 직관 활용
- novelty: 중간
- assumptions: 시각적 안내가 텍스트보다 비개발자에게 더 효과적이다(RF-07 방향과 일치하나 직접 근거는 아님)
- duplicate-of: none
- status: parked
- park-recondition: C-01/C-02 실험 후에도 사용자가 텍스트 이해에 어려움을 겪는다는 신호가 나오면 재검토
- elimination-reason: (해당 없음)
- core-fact: 점진적 공개·시각 우선 안내가 온보딩 이해도를 높인다는 원칙이 다수 가이드에서 제시됨(RF-07)
- independent-sources: 3

### IDEA-007
- idea-id: IDEA-007
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: Cluster D
- idea: 실제 데이터 연동 전에 가짜(샘플) 데이터로 연동 과정을 미리 연습해보는 "체험판 연동 모드" 제공(비디오게임 튜토리얼 스테이지 차용).
- expected-value: 실패 위험 없는 사전 연습으로 실전 성공률 향상
- novelty: 높음
- assumptions: 격리된 샘플 연동 환경을 별도로 구축할 수 있다
- duplicate-of: none
- status: eliminated
- park-recondition: (해당 없음)
- elimination-reason: 실제 연동과 분리된 샘플 데이터 파이프라인 및 UI 상태 분리를 별도로 구축해야 하며, 이는 3인월/6주 제약을 명백히 초과하는 규모의 작업으로 판단됨(제약 위반이 구체적 근거).
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-008
- idea-id: IDEA-008
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: Cluster A
- idea: 연동 전 필요한 사전 준비물(계정 권한, API 키 발급 여부 등)을 미리 확인하는 "사전 준비 체크리스트"를 3단계 진입 전에 배치(항공 관제 체크리스트 문화 차용).
- expected-value: 진입 후 막히는 상황 자체를 사전에 줄임
- novelty: 낮음-중간
- assumptions: 준비 부족이 이탈의 주요 원인 중 하나다
- duplicate-of: none
- status: shortlisted
- park-recondition: (해당 없음)
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-009
- idea-id: IDEA-009
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: Cluster C
- idea: 새 백엔드 로직 없이 기존 React 컴포넌트 재조합만으로 필드 매핑을 드래그앤드롭 형태로 재배치하는 "코드 0줄 설정" UI.
- expected-value: 신규 인프라 없이 3단계 UX 개선, 3인월 내 구현 가능성 높음
- novelty: 중간
- assumptions: 기존 매핑 로직을 프론트엔드 재구성만으로 개선 가능하다
- duplicate-of: none
- status: shortlisted
- park-recondition: (해당 없음)
- elimination-reason: (해당 없음)
- core-fact: 데이터 연동 설정은 SaaS 온보딩의 흔한 이탈 지점이며 no-code 매핑/마법사 UI가 업계에서 검증된 해법 카테고리로 존재함(RF-05)
- independent-sources: 5

### IDEA-010
- idea-id: IDEA-010
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: Cluster A, Cluster G(교차 참조 — 기존 자산 재배치 성격도 있음)
- idea: 새 기능 개발 없이 기존 7단계 이메일의 발송 순서·타이밍만 재조정, 3단계 데이터 연동 직전에 "5분 완료 가이드" 이메일을 추가 배치.
- expected-value: 개발 리소스 0으로 이탈 지점 사전 보강
- novelty: 낮음
- assumptions: 이메일 발송 시점 재조정이 시스템 상 쉽게 가능하다
- duplicate-of: none
- status: shortlisted
- park-recondition: (해당 없음)
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-011
- idea-id: IDEA-011
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: Cluster F
- idea: 가입 시 "IT 담당자이지만 비개발자"임을 인지하고, 코드/API 언급을 자동 숨기고 "설정 대행 요청" 경로만 노출하는 세그먼트 특화 온보딩 분기.
- expected-value: 세그먼트 특성에 맞춘 부담 감소
- novelty: 중간
- assumptions: 기존 사용자 속성 필드로 비개발자 여부를 분기할 수 있다
- duplicate-of: none
- status: parked
- park-recondition: 대행/위임 경로에 대한 고객 수요가 후속 사용자 인터뷰로 확인되면 재검토
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-012
- idea-id: IDEA-012
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: Cluster E
- idea: 전체 온보딩을 재설계하지 않고 이탈률 28%로 가장 높은 3단계 화면 UX만 좁게 재작업해 6주 내 배포 가능하게 스코프를 의도적으로 제한.
- expected-value: 제약 준수를 보장하는 스코핑 원칙
- novelty: 낮음
- assumptions: 3단계만 개선해도 유의미한 효과가 있다
- duplicate-of: none
- status: eliminated
- park-recondition: (해당 없음)
- elimination-reason: 독립적인 해결책이 아니라 범위 설정 원칙이며, C-01·C-02 후보 설계에 이미 반영되어 있어 별도 후보로 존치할 실체가 없음(구조적 중복).
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-013
- idea-id: IDEA-013
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: Cluster B
- idea: 3단계에서 10분 이상 머무르거나 에러 2회 이상 발생 시 CS팀에 실시간 알림이 가서 능동적으로 접촉하는 피드백 루프.
- expected-value: 이탈 임박 사용자에 대한 선제적 개입
- novelty: 중간
- assumptions: CS팀이 실시간으로 대응할 인력·프로세스를 갖출 수 있다
- duplicate-of: none
- status: shortlisted
- park-recondition: (해당 없음)
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-014
- idea-id: IDEA-014
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: Cluster G
- idea: 복잡한 연동은 사전 인증된 외부 파트너(프리랜서/대행사)에게 유료로 위임할 수 있는 마켓플레이스 링크를 3단계에 노출.
- expected-value: 사내 개발 없이 생태계로 문제 해결 확장
- novelty: 높음
- assumptions: 신뢰할 수 있는 외부 파트너 풀을 확보할 수 있다
- duplicate-of: none
- status: eliminated
- park-recondition: (해당 없음)
- elimination-reason: 외부 파트너 발굴·품질 검증·계약 체결이 필요해 6주 출시 일정 내 실행이 명백히 불가능하고, 파트너 품질에 대한 자사 통제력 부재로 브랜드 리스크가 있음.
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-015
- idea-id: IDEA-015
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: Cluster F
- idea: 온보딩 3단계 완료 시 다음 단계가 잠금 해제되는 게임화된 진행 인센티브와, 완료 시 "온보딩 완료 배지/사내 보고용 요약 리포트" 제공.
- expected-value: 개인 동기(사내 성과 어필)와 제품 목표 연결
- novelty: 중간
- assumptions: 게임화 요소가 B2B 비개발자 담당자에게 실제 동기 요인이다(근거 약함)
- duplicate-of: none
- status: parked
- park-recondition: C-01/C-03 실험 이후에도 완료율이 목표에 못 미치면 동기부여 계층 추가로 검토
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-016
- idea-id: IDEA-016
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: Cluster A
- idea: 영업 단계에서 파악된 고객의 기존 툴 스택 정보를 온보딩 시스템에 자동 전달해, 3단계 진입 시 어떤 연동을 먼저 붙여야 하는지 미리 아는 상태로 시작(부서 간 정보 단절 해소).
- expected-value: 개인화된 3단계 시작점 제공
- novelty: 중간
- assumptions: 영업 CRM과 온보딩 시스템 간 데이터 연동이 이미 존재하거나 저비용으로 구축 가능하다
- duplicate-of: none
- status: parked
- park-recondition: 영업 CRM과 온보딩 시스템 간 데이터 연동이 별도 프로젝트로 승인되면 재검토
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-017
- idea-id: IDEA-017
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: Cluster G
- idea: 기존 인앱 툴팁과 이메일 시퀀스를 분리 운영하지 않고, 3단계에서 이탈(세션 종료)한 사용자에게 1시간 내 발송되는 "이어서 하기" 리마인드 이메일을 신설(기존 두 자산의 이벤트 연동만 추가).
- expected-value: 저비용으로 재유입 기회 확대
- novelty: 낮음
- assumptions: 이메일 시스템이 3단계 이탈 이벤트를 트리거로 받을 수 있다
- duplicate-of: none
- status: shortlisted
- park-recondition: (해당 없음)
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-018
- idea-id: IDEA-018
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: Cluster E
- idea: 3단계 데이터 연동을 온보딩 완료의 필수 관문에서 "나중에 하기"가 가능한 선택 단계로 전환하고, 연동 없이도 체험 가능한 샘플 데이터 기반 임시 대시보드를 우선 제공.
- expected-value: 먼저 가치를 느끼게 한 뒤 연동을 유도(시간-가치 단축, RF-08 방향)
- novelty: 중간
- assumptions: 연동을 미뤄도 장기 리텐션이 유지된다(미검증, C-04 핵심 리스크)
- duplicate-of: none
- status: shortlisted
- park-recondition: (해당 없음)
- elimination-reason: (해당 없음)
- core-fact: 최초 가치 체감까지 걸리는 시간을 단축하는 것이 온보딩 이탈 감소의 핵심 권장사항으로 다수 가이드에서 제시됨(RF-08)
- independent-sources: 1

### IDEA-019
- idea-id: IDEA-019
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: Cluster G
- idea: 기존 지원 문서(도움말 센터)를 3단계 화면에 검색 가능한 사이드 패널로 임베드(신규 콘텐츠 제작 없이 기존 자산 노출 위치만 변경).
- expected-value: 저비용으로 셀프서비스 지원 강화
- novelty: 낮음
- assumptions: 사용 가능한 지원 문서가 이미 존재한다
- duplicate-of: none
- status: parked
- park-recondition: C-02 UI 개편 시 컨텍스트별 도움말 임베드 필요성이 사용자 피드백으로 확인되면 재검토
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-020
- idea-id: IDEA-020
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: Cluster G
- idea: 7단계 이메일 중 반응률 낮은 단계를 축소하고 그 리소스를 3단계 인앱 툴팁을 더 구체적인(에러 예방형) 툴팁으로 강화하는 데 재배분.
- expected-value: 신규 채널 없이 기존 두 자산 간 리소스 재배분으로 효율 개선
- novelty: 낮음
- assumptions: 반응률 낮은 이메일 단계를 데이터로 식별할 수 있다
- duplicate-of: none
- status: parked
- park-recondition: C-01/C-05 실험 결과 이메일 채널 전체 재설계가 필요하다고 판단되면 재검토
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-021
- idea-id: IDEA-021
- parent-id: IDEA-018
- strategy: SCAMPER (Substitute)
- lens: 제약 전환자 관점 확장
- cluster-ids: Cluster C
- idea: "연동 필수→선택" 대신, 3단계를 관리자 승인 없이 백그라운드에서 흔한 CRM 3종에 한해 원클릭 OAuth 연동으로 대체(설정 과정 자체를 인증 클릭 한 번으로 치환).
- expected-value: 지원 대상 고객에게는 연동 자체를 사실상 제거
- novelty: 높음
- assumptions: 상위 3개 커넥터가 고객 기반의 상당 비율을 커버한다(미검증, E-01 핵심 가정)
- duplicate-of: none
- status: shortlisted
- park-recondition: (해당 없음)
- elimination-reason: (해당 없음)
- core-fact: no-code 커넥터/원클릭 인증 방식이 업계에서 검증된 해법 카테고리로 존재함(RF-05). RF-06(개발시간 80% 절감)은 단일 출처 unconfirmed라 근거로 사용하지 않음.
- independent-sources: 5

### IDEA-022
- idea-id: IDEA-022
- parent-id: IDEA-002, IDEA-013
- strategy: SCAMPER (Combine)
- lens: 사용자·고객 탐색자 + 시스템 사고자 결합
- cluster-ids: Cluster B
- idea: 실시간 이탈 신호(IDEA-013)와 라이브 도움 버튼(IDEA-002)을 결합해, 시스템이 이탈 위험을 자동 감지하면 "지금 도와드릴까요?" 버튼을 사용자에게 능동적으로 띄우는 트리거형 라이브 지원.
- expected-value: 사용자 주도 요청과 시스템 감지의 장점을 결합
- novelty: 중간
- assumptions: 실시간 개입 인력 운영이 예산 범위 안에 있다(E-02 핵심 가정)
- duplicate-of: none
- status: shortlisted
- park-recondition: (해당 없음)
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-023
- idea-id: IDEA-023
- parent-id: IDEA-006
- strategy: SCAMPER (Adapt)
- lens: 도메인 유추자 관점 확장
- cluster-ids: Cluster D
- idea: 정적 그림 설명서를 적응시켜, 사용자의 현재 화면 상태를 인식해 다음에 눌러야 할 버튼만 하이라이트하는 "동적 스팟라이트 가이드"로 변형.
- expected-value: 시각적 직관성 + 실시간 상태 인지 결합
- novelty: 중간
- assumptions: 화면 상태를 인식해 하이라이트할 수 있는 수준의 프론트엔드 로직을 3인월 내 구현 가능하다
- duplicate-of: none
- status: parked
- park-recondition: C-02 1차 배포 후에도 사용자가 다음 액션을 못 찾아 헤매는 이탈이 남아있다면 재검토
- elimination-reason: (해당 없음)
- core-fact: 점진적 공개 원칙이 다수 가이드에서 제시됨(RF-07)
- independent-sources: 3

### IDEA-024
- idea-id: IDEA-024
- parent-id: IDEA-009
- strategy: SCAMPER (Modify/확대)
- lens: 제약 전환자 관점 확장
- cluster-ids: Cluster C
- idea: 필드 매핑 드래그앤드롭 UI를 확대하여 입력 필드명 유사도 기반 "자동 필드 매핑 추천" 기능까지 포함하도록 강화.
- expected-value: 수동 매핑 부담을 추가로 경감
- novelty: 중간
- assumptions: 필드명 유사도 매칭만으로 충분히 정확한 추천이 가능하다
- duplicate-of: none
- status: shortlisted
- park-recondition: (해당 없음)
- elimination-reason: (해당 없음)
- core-fact: 데이터 연동 설정은 SaaS 온보딩의 흔한 이탈 지점이며 no-code 매핑/마법사 UI가 업계 표준 해법 카테고리로 존재함(RF-05)
- independent-sources: 5

### IDEA-025
- idea-id: IDEA-025
- parent-id: IDEA-015
- strategy: SCAMPER (Put to another use)
- lens: 시스템 사고자 관점 확장
- cluster-ids: Cluster F
- idea: 온보딩 완료 배지/리포트 자산을 완료하지 못한 사용자에게는 "동종업계 대비 나의 온보딩 진행률" 벤치마크 카드로 재활용해 사회적 비교를 통한 완료 동기 부여.
- expected-value: 동일 자산을 완료/미완료 양쪽에 다른 용도로 활용
- novelty: 높음
- assumptions: 동종업계 비교 데이터를 신뢰성 있게 산출할 수 있다
- duplicate-of: none
- status: parked
- park-recondition: C-05 또는 IDEA-015 게임화 실험에서 동기부여 요소가 유효하다는 신호가 나오면 결합 검토
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-026
- idea-id: IDEA-026
- parent-id: IDEA-020
- strategy: SCAMPER (Eliminate)
- lens: 실용적 조합자 관점 확장
- cluster-ids: Cluster G
- idea: 3단계 도달 전 이메일 4개를 아예 제거하고, 가입 직후 3단계 관련 정보만 담은 단일 환영 이메일로 축소해 정보 과부하를 줄임.
- expected-value: 정보 과부하 감소
- novelty: 중간
- assumptions: 이메일 개수 감소가 정보 과부하로 인한 이탈을 줄인다
- duplicate-of: none
- status: parked
- park-recondition: C-05 도입 후에도 이메일 정보 과부하가 이탈 요인으로 확인되면 재검토
- elimination-reason: (해당 없음)
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-027
- idea-id: IDEA-027
- parent-id: IDEA-018
- strategy: SCAMPER (Reverse)
- lens: 실용적 조합자 관점 확장
- cluster-ids: Cluster E
- idea: 순서를 뒤집어 연동을 3단계가 아닌 마지막(7단계)으로 이동, 1~2단계에서 먼저 저난도 설정(팀원 초대, 알림 설정 등)으로 완료 모멘텀을 만든 뒤 연동을 시도하게 함.
- expected-value: 초반 성공 경험 축적 후 고난도 단계 진입
- novelty: 중간
- assumptions: 순서를 바꿔도 결국 연동 단계의 절대적 난이도는 그대로다(리스크로 남음)
- duplicate-of: none
- status: shortlisted
- park-recondition: (해당 없음)
- elimination-reason: (해당 없음)
- core-fact: 최초 가치 체감까지 걸리는 시간을 단축하는 것이 온보딩 이탈 감소의 핵심 권장사항으로 다수 가이드에서 제시됨(RF-08)
- independent-sources: 1

## 군집

### Cluster A — 사전 대비·마찰 예방
- 포함 idea-id: IDEA-001, IDEA-008, IDEA-010, IDEA-016
- 공통 가정: 사용자가 3단계 도달 전에 필요한 정보/도구를 미리 알면 이탈이 준다.
- 차별점: 퀴즈(능동 응답, 001) vs 체크리스트(정적 안내, 008) vs 발송 타이밍 조정(010) vs 시스템 자동 정보 전달(영업 데이터 재사용, 016).
- 미해결 질문: 사전 준비만으로는 실제 통합의 기술적 마찰(API 키 발급 등) 자체는 줄어들지 않을 수 있다.

### Cluster B — 실시간 인적 지원·능동 개입
- 포함 idea-id: IDEA-002, IDEA-003, IDEA-013, IDEA-022
- 공통 가정: 막히는 순간 사람의 개입이 이탈을 막는 가장 효과적인 방법이다.
- 차별점: 사용자 주도 요청(002) vs 담당자 위임(003) vs 시스템 감지+CS 개입(013) vs 자동 트리거 UI(022, 002+013 결합).
- 미해결 질문: 3인월/6주 제약 내에서 실시간 CS 인력 배치·운영이 가능한지(예산 정의 불명확, E-02로 이관).

### Cluster C — 코드 없는 셀프서비스 연동 단순화
- 포함 idea-id: IDEA-009, IDEA-021, IDEA-024
- 공통 가정: 기술 용어·수동 매핑 자체가 이탈 원인이므로 UI/UX 단순화가 완료율을 높인다.
- 차별점: 시각적 재배치(009) vs 인증 흐름 자체 대체(021, 가장 범위가 큼) vs 지능형 매핑 추천(024).
- 미해결 질문: 021의 원클릭 OAuth는 지원 대상 CRM 3종 한정이라 실제 고객 스택 커버리지가 낮을 위험(E-01 참조).

### Cluster D — 시각적/체험적 학습
- 포함 idea-id: IDEA-004, IDEA-006, IDEA-007, IDEA-023
- 공통 가정: 텍스트보다 시각적/체험적 안내가 비개발자에게 더 효과적이다.
- 차별점: 실패시점 반응형 도움말(004) vs 정적 이미지(006) vs 위험 없는 연습 모드(007) vs 실시간 상태인지형 하이라이트(023).
- 미해결 질문: 샌드박스 모드(007)는 별도 환경 구축이 필요해 예산 초과 위험이 가장 크다는 점이 이미 탈락 근거로 반영됨.

### Cluster E — 온보딩 구조 재설계(순서·필수여부 전환)
- 포함 idea-id: IDEA-012, IDEA-018, IDEA-027
- 공통 가정: 문제는 연동 난이도 자체보다 "언제/얼마나 강제로" 요구하는지의 구조에 있다.
- 차별점: 스코프 좁히기(012, 구조적으로 후보가 아니라 원칙으로 판단해 탈락) vs 선택화+대체가치 제공(018) vs 순서 자체 역전(027).
- 미해결 질문: 연동을 미루면 실제 핵심 가치(데이터 기반 기능) 체감이 늦어져 장기 리텐션에는 오히려 나쁠 수 있다(C-04 핵심 리스크, E-05로 이관).

### Cluster F — 동기부여·게임화·사회적 비교
- 포함 idea-id: IDEA-011, IDEA-015, IDEA-025
- 공통 가정: 완료에 대한 개인적/조직적 동기 부족도 이탈 원인 중 하나다.
- 차별점: 부담 경로 자체 숨김(011) vs 성취 배지(015) vs 사회적 비교 카드(025, 015의 SCAMPER 변형).
- 미해결 질문: 게임화 요소가 B2B 비개발자 IT 담당자에게 실제로 동기 요인인지 근거가 약하다(가정 수준).

### Cluster G — 생태계/기존 자산 재활용
- 포함 idea-id: IDEA-010(교차 참조), IDEA-014, IDEA-017, IDEA-019, IDEA-020, IDEA-026
- 공통 가정: 모든 걸 새로 만들지 않고 기존/외부 자산을 재배치·연결하면 저비용으로 효과를 낼 수 있다.
- 차별점: 외부 유료 파트너(014, 탈락) vs 이탈 트리거 이메일(017) vs 기존 문서 재배치(019) vs 이메일→툴팁 리소스 재배분(020) vs 이메일 정보량 축소(026, 020의 SCAMPER 변형).
- 미해결 질문: 014는 외부 파트너 신뢰성/품질 관리가 회사 통제 밖이라는 점이 탈락 근거로 반영됨.

## 숏리스트

NGT 규칙에 따라 단일 우승자를 강제하지 않고, 서로 다른 가치 제안·위험 프로필을 가진 5개 후보를 선정했다. 평가 기준은 브리프의 evaluation-criteria(제약 충족 최우선, 이탈 감소 기대효과, 사용성, 학습 가치) 순서를 따른다.

### Candidate C-01
- source-idea-ids: IDEA-008, IDEA-010
- value-proposition: 3단계 도달 전 필요한 정보(준비물 체크리스트)와 타이밍 최적화된 안내 이메일로 진입 전 마찰을 예방한다. 신규 백엔드 없이 기존 자산 재배치만으로 구현.
- requester-value-fit: 높음 — 개발 비용 매우 낮음, 완료율 개선에 직접 기여 예상.
- differentiation: 사후 대응이 아닌 예방적 접근.
- learning-value: 중간 — "정보 제공만으로 실제 이탈이 줄어드는가"가 검증되지 않은 핵심 가정.
- key-risks: 3단계 이탈의 진짜 원인이 정보 부족이 아니라 기술적 난이도 자체라면 효과가 제한적일 수 있음.
- evidence-level: 중간(RF-07/RF-08의 사전 안내·시간단축 원칙과 방향은 일치하나 직접 사례는 아님)
- dissent: 제약 전환자 관점 — IDEA-016(영업 데이터 자동 전달)은 시스템 연동이 필요해 3인월 내 완료가 타이트하다는 반대 근거로 candidate 범위에서 제외됨(별도 parked).
- validation-priority: 높음(저비용·빠른 실험 가능)

### Candidate C-02
- source-idea-ids: IDEA-009, IDEA-021, IDEA-024
- value-proposition: 3단계 자체의 기술적 난이도를 직접 낮춘다 — 드래그앤드롭 매핑 UI 개선 + 상위 3개 커넥터 대상 원클릭 인증 + 자동 필드 매핑 추천.
- requester-value-fit: 매우 높음 — 가장 이탈률이 높은 지점(28%)을 정면 공략.
- differentiation: 문제의 근본 원인(연동 복잡도)을 UI 재구성만으로 해결 시도, 기존 React 스택 재사용.
- learning-value: 높음 — 자동 매핑 추천 정확도와 원클릭 인증 커버리지가 핵심 미지수.
- key-risks: IDEA-021(원클릭 OAuth)은 지원 대상 외 커넥터를 쓰는 고객에게는 효과 없음(세그먼트 커버리지 협소 위험). 신규 OAuth 플로우 구현이 3인월 내 타이트할 가능성.
- evidence-level: 중간(RF-05는 다출처로 확인되나, RF-06의 "80% 절감" 수치는 단일 출처 unconfirmed라 근거로 과신하지 않음)
- dissent: 시스템 사고자 관점 — 기술 단순화만으로는 "이해 부족"이 원인인 사용자군에는 효과가 제한적일 수 있다는, Cluster D 원인가설과 상충하는 반대 근거.
- validation-priority: 매우 높음(핵심 이탈 지점을 직접 다루나 구현 비용도 가장 큼)

### Candidate C-03
- source-idea-ids: IDEA-013, IDEA-022
- value-proposition: 3단계에서 일정 시간 이상 머물거나 에러가 반복되면 시스템이 자동으로 감지해 실시간 도움을 능동적으로 제안한다.
- requester-value-fit: 높음 — 7일 이내 이탈(58%) 전반에도 적용 가능한 패턴.
- differentiation: 사전 안내·문서가 아니라 "이탈 직전 실시간 개입"이라는 다른 시점의 해법.
- learning-value: 높음 — CS 인력 실시간 대응 가능 여부(운영 리소스)가 핵심 미검증 가정.
- key-risks: "개발 예산 3인월"이 CS 인력 운영비를 포함하는지 불명확 — 포함된다면 제약 위반 가능성.
- evidence-level: 낮음-중간(RF-05 계열과 간접 관련, 직접 사례 인용 없음)
- dissent: 제약 전환자 관점 — 실시간 인력 배치는 예산 정의에 따라 애초에 범위 밖일 수 있다는 반대 근거(E-02로 확인 필요).
- validation-priority: 중간(비용 불확실성이 커서 범위 확인이 선행되어야 함)

### Candidate C-04
- source-idea-ids: IDEA-018, IDEA-027
- value-proposition: 연동을 필수 관문에서 제거해 샘플 데이터로 먼저 가치를 보여주고, 연동은 순서를 뒤로 미뤄 요구한다.
- requester-value-fit: 중간-높음 — 완료율은 오를 수 있으나 "완료"의 정의가 바뀌는 trade-off 존재.
- differentiation: "더 쉽게 만들기"가 아니라 "구조적으로 미루기" — 다른 후보와 위험 프로필이 다름.
- learning-value: 매우 높음 — "연동을 미뤄도 장기 리텐션이 유지되는가"가 핵심 미해결 질문.
- key-risks: 연동을 뒤로 미루면 결국 연동을 아예 하지 않는 사용자가 늘어 장기 매출/리텐션에 악영향 가능.
- evidence-level: 낮음(RF-08 방향과는 일치하나 "필수 단계 자체를 제거"하는 것은 직접 근거 없음, RF-08 자체도 단일 출처 unconfirmed)
- dissent: 세션 책임자 검토 — 이 후보는 C-02와 상충하는 가설(연동을 늦추는 것이 옳은가 vs 연동 자체를 쉽게 만드는 것이 옳은가)을 대표하므로 단일 승자로 통합하지 않고 별도 후보로 보존.
- validation-priority: 중간(저비용 실험 가능하지만 장기 효과는 6주 내 완전 검증이 어려움)

### Candidate C-05
- source-idea-ids: IDEA-017
- value-proposition: 3단계에서 세션이 끊긴 사용자에게 1시간 내 자동 리마인드 이메일을 발송, 기존 이메일 인프라만 재사용.
- requester-value-fit: 중간 — 근본 난이도 해결은 아니지만 재유입 기회를 늘림.
- differentiation: 가장 저비용·저위험, 다른 후보와 병행 가능한 "안전망" 성격.
- learning-value: 중간 — 트리거 이메일의 재방문 전환율 자체가 검증 대상.
- key-risks: 근본 원인(기술적 난이도)을 해결하지 않으므로 재방문해도 동일 지점에서 다시 이탈할 가능성.
- evidence-level: 낮음-중간(RF-05/RF-07과 간접 관련, 직접 사례는 확보 못함)
- dissent: 실용적 조합자 내부에서도 "이 정도로는 28% 이탈의 근본 원인을 못 건드린다"는 반대 근거 존재 — 그럼에도 비용이 매우 낮아 병행 후보로 보존.
- validation-priority: 높음(가장 빠르게 구현·검증 가능, 다른 후보의 baseline 대조군 역할도 가능)

## 검증 계획

research-protocol.md 2단계 규칙에 따라 후보별 가장 위험하고 결과를 바꾸는 가정부터 조사 대상으로 선정했다. 아래 실험은 모두 **proposed** 상태이며, 의뢰자의 명시적 승인 전에는 실행하지 않는다.

### Experiment E-01
- candidate-id: C-02
- assumption: 지원 대상 상위 3개 커넥터가 SMB IT 담당자 고객 기반의 데이터 연동 니즈 상당 부분(과반)을 커버한다.
- approved-type: research
- method: 최근 6개월 신규 가입 고객이 3단계에서 선택/입력한 연동 대상 시스템 로그 또는 CS 문의 티켓을 정성 분석해 상위 연동 대상 빈도를 집계.
- success-signal: 상위 3개 커넥터가 신규 고객 연동 요청의 50% 이상을 커버한다는 근거 확보.
- stop-condition: 상위 3개 커넥터 커버리지가 30% 미만으로 확인되면 IDEA-021(3종 한정 원클릭)은 C-02 범위에서 제외하고 매핑 UI 개선(IDEA-009, IDEA-024)만 유지.
- estimated-cost: 0.5인주(로그/티켓 분석)
- approval-status: proposed

### Experiment E-02
- candidate-id: C-03
- assumption: "개발 예산 3인월"에는 실시간 CS 대응 인력 운영비가 포함되지 않는다(별도 검토 가능).
- approved-type: research
- method: 세션 문서만으로는 확인 불가한 조직 정책 질문이므로 리서치를 실행하지 않고, 의뢰자에게 직접 확인이 필요한 질문으로 기록만 한다.
- success-signal: 예산 정의에 CS 운영비 포함 여부에 대한 명확한 답변 확보.
- stop-condition: 확인 전까지 C-03 실험(및 관련 실행)은 시작하지 않는다.
- estimated-cost: 0(의뢰자 확인 질문, 외부 조사 아님)
- approval-status: proposed

### Experiment E-03
- candidate-id: C-01
- assumption: 3단계 진입 전 준비 체크리스트+타이밍 조정 이메일을 받은 사용자군은 받지 않은 군보다 3단계 이탈률이 낮다.
- approved-type: document
- method: 체크리스트 콘텐츠 초안 + 이메일 재배치안을 문서로 설계하고, 배포 후 측정할 지표(3단계 진입률, 3단계 완료율)를 사전 정의한다.
- success-signal: 설계 문서가 실제 A/B 테스트로 실행 가능한 수준의 구체성(카피, 발송 시점, 측정 지표)을 갖춤.
- stop-condition: 설계 과정에서 기존 이메일 시스템이 이벤트 기반(3단계 도달) 트리거를 지원하지 않는다는 기술적 제약이 발견되면 즉시 "발송 시점 고정형"으로 범위를 축소해 재설계.
- estimated-cost: 0.3인주(문서 설계)
- approval-status: proposed

### Experiment E-04
- candidate-id: C-05
- assumption: 3단계 이탈 후 1시간 내 리마인드 이메일을 받은 사용자는 받지 않은 사용자보다 재방문·재시도율이 높다.
- approved-type: research
- method: 유사 SaaS 기업의 "이탈 후 리마인드 이메일" 재참여율 관련 외부 사례·벤치마크를 추가 조사(현재 중앙 리서치 RF-01~08에서는 다루지 않음).
- success-signal: 유사 트리거 이메일의 재참여율이 유의미한 수준이라는 근거를 최소 1개 이상 확보.
- stop-condition: 관련 벤치마크를 전혀 찾지 못하면 evidence-level을 "낮음"으로 유지한 채 C-05는 저비용 후보로 보존하되 validation-priority를 낮춘다.
- estimated-cost: 0.1인주(리서치)
- approval-status: proposed

### Experiment E-05
- candidate-id: C-04
- assumption: 샘플 데이터로 먼저 가치를 체감한 사용자는 연동을 필수로 요구받은 사용자와 동등하거나 더 나은 7일/30일 리텐션을 보인다.
- approved-type: agent-critique
- method: 서브에이전트 호출이 불가한 환경이라 세션 책임자가 직접 에이전트 비판 역할을 겸해, "샘플 데이터 체감이 '가짜 가치'로 인식되어 오히려 진짜 연동을 미루는 학습된 회피가 생길 수 있다"는 반증 가설을 정리한다.
- success-signal: 반대 근거를 포함한 비판 메모가 후보의 key-risks/dissent에 명시적으로 반영됨(숏리스트 C-04에 이미 반영 완료).
- stop-condition: 6주 내에는 30일 리텐션 데이터를 확보할 수 없으므로, 이 실험은 리서치/비판까지만 수행하고 실제 코호트 검증은 이번 세션 범위 밖으로 명시, 향후 별도 실험으로 이관.
- estimated-cost: 0.2인주(비판 메모 작성)
- approval-status: proposed

## 실험

(state가 validation_approval이며 검증 계획이 아직 승인되지 않아 실험은 실행하지 않았다. 승인 후 이 섹션에 실험 결과를 기록한다.)

## 최종 보고

(state가 validation_approval이며 검증 완료 전 단계이므로 최종 보고는 아직 작성하지 않는다. SKILL.md 시작 워크플로 9~10단계(검증 → 보고)는 검증 계획 승인 이후에 진행한다.)
