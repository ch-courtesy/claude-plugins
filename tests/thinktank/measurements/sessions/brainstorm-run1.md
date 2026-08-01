# Brainstorm Session: 20260801-onboarding-dropout-b1

## 상태
- session-id: 20260801-onboarding-dropout-b1
- state: validation_approval
- updated-at: 2026-08-01
- frame-approved-at: 2026-08-01 (측정 세션 픽스처 브리프로 사전 승인 간주)
- validation-approved-at: (미기입 — 검증 계획은 작성만 완료, 의뢰자 명시적 승인 대기 중이므로 실험 미실행)
- agent-calls-used: 0 (서브에이전트 호출 불가 환경 — 아이디어 생성자 렌즈를 메인 세션 컨텍스트 안에서 순차 수행)
- research-calls-used: 4 (WebSearch 4회: 온보딩 완료율 벤치마크, 데이터 연동 이탈, 화이트글러브 온보딩, 이메일/인앱 효과 비교)
- completed-sections: 브리프, 연구 컨텍스트, 로스터, 아이디어 풀, 군집, 숏리스트, 검증 계획
- next-action: 검증 계획(E-01~E-04)을 의뢰자에게 제시해 명시적 승인을 받는다. 승인 시 `validating` 상태로 전환해 승인된 실험만 수행한다.
- inconsistencies:
  - IDEA-013은 브리프의 out-of-scope("가격/영업 프로세스 변경")와 경계가 겹쳐 eliminated 처리했다. 의뢰자가 영업 프로세스 개입을 실제로 배제할 의도인지는 재확인이 필요할 수 있다.
  - 픽스처가 인용한 "업계 평균 52%"라는 특정 수치와 정확히 일치하는 외부 출처는 찾지 못했다(40~70%대 범위 안에는 든다). 연구 컨텍스트에 미확인으로 기록.
  - IDEA-015(실시간 이탈 대시보드 부재 가정)는 픽스처가 이미 34%/58%/28% 수치를 보유하고 있다는 사실과 부분적으로 상충한다 — "실시간·일 단위 노출"이 없다는 의미로 좁혀 해석했으나 상충 가능성을 그대로 보존한다.

## 브리프

**0. 적합성 확인**: 이미 정해진 대안을 판정하거나 이해관계 합의가 목표가 아니라, 온보딩 이탈 개선을 위한 새로운 가능성을 폭넓게 탐색하는 것이 목표다. `brainstorm` 진행이 적합하며 `roundtable`은 권고하지 않는다.

- session-id: 20260801-onboarding-dropout-b1
- requester: 미지정(측정 세션 픽스처 브리프, 개인 이름 없음)
- problem-or-opportunity: B2B SaaS 제품의 신규 사용자 온보딩 이탈률 개선. 현재 온보딩 완료율 34%(픽스처가 인용한 업계 평균 52% 대비 저조), 최초 로그인 후 7일 이내 이탈 58%, 3단계 데이터 연동 설정 단계에서 28% 이탈(가장 큰 단일 이탈 지점).
- target: 중소기업(SMB) IT 담당자, 비개발자 다수
- requester-value: 온보딩 완료율과 7일 잔존율 상승을 통한 활성화·리텐션 개선. (구체적 목표 수치는 브리프에 미제공 — 브리프 하단 assumptions 참조)
- how-might-we: 중소기업의 비개발자 IT 담당자가, 3단계 데이터 연동 설정을 포함한 온보딩을, 3인월/6주 제약 안에서 어떻게 더 쉽게 완료하도록 도울 수 있을까?
- scope: 기존 스택(React+Node.js) 위에서 가능한 온보딩 경험(이메일 7단계, 인앱 툴팁 3개, 3단계 데이터 연동 설정 플로우) 개선. 3인월/6주 내 구현·검증 가능한 범위.
- out-of-scope: 기술 스택 교체, 가격 정책 변경, 영업(세일즈) 프로세스 변경, 3인월 예산을 초과하는 대규모 재설계, 신규 유료 채널 구축.
- constraints: 개발 예산 3인월 이하 / 출시 일정 6주 이내 / React+Node.js 변경 불가 / 대상 고객 비개발자 다수(기술 문해력 낮음 가정).
- existing-attempts: 이메일 시퀀스 7단계 + 인앱 툴팁 3개(현재 운영 중이나 완료율 34%로 저조 — 효과 불충분).
- assumptions:
  1. 픽스처가 정량 목표 수치를 제공하지 않으므로, "업계 평균 52% 방향으로의 개선"을 잠정 성공 신호로 가정한다.
  2. 3단계 데이터 연동 이탈(28%)이 7일 이내 전체 이탈(58%)의 핵심 병목이라고 가정한다(픽스처가 "주요 이탈 지점"으로 명시했으나 퍼널상 정확한 기여 비율은 미제공).
- success-signals: 온보딩 완료율 상승(34% → 업계 평균 방향), 7일 이내 이탈 감소, 3단계 데이터 연동 이탈(28%) 감소.
- evaluation-criteria:
  1. 3단계 데이터 연동 이탈 감소 기여도 (가중 높음 — 핵심 병목)
  2. 3인월/6주 제약 내 구현 가능성 (가중 높음 — 하드 제약, 게이트)
  3. 비개발자 사용성 적합도 (가중 중)
  4. 7일 잔존 개선 기여도 (가중 중)
  5. React+Node.js 스택 적합성 (게이트 — 위반 시 불가)
  - trade-off 표시: "완료율 상승을 위한 단계 단순화·자유도 축소"와 "데이터 정확성·유연성을 위한 단계 유지"는 서로 충돌할 수 있어 후보별로 이 trade-off 방향을 개별 명시한다.
- frame-status: approved

## 연구 컨텍스트

### 내부 기준 데이터 (픽스처 제공)
- 온보딩 완료율 34%, 업계 평균으로 인용된 52%, 7일 이내 이탈 58%, 3단계 데이터 연동 이탈 28% — 출처: 세션 브리프(픽스처), 확인일: 2026-08-01, independent-sources: 1(내부 단일 출처, 외부 교차 확인 불가).

### 확정 사실 (fact)
1. B2B SaaS 온보딩 완료율 업계 벤치마크는 통상 40~60% 구간이며, 60% 이상을 양호, 80% 이상을 우수로 보는 자료가 있다. — 출처: [What Is User Onboarding Completion Rate in Saas?](https://www.alexanderjarvis.com/what-is-user-onboarding-completion-rate-in-saas/), 확인일 2026-08-01
2. B2B SaaS는 60~70%를 목표로 해야 하며, 40% 미만은 구조적 마찰(systematic friction)의 신호로 본다는 자료가 있다. — 출처: [Understanding Onboarding Completion Rate](https://www.getmonetizely.com/articles/understanding-onboarding-completion-rate-a-critical-metric-for-saas-success), 확인일 2026-08-01
   - 1과 2는 서로 다른 두 출처가 유사한 범위(40~70%대)를 독립적으로 뒷받침 → independent-sources: 2. 단, 픽스처가 인용한 "업계 평균 52%"라는 정확한 수치와 동일한 출처는 찾지 못함 — 범위 안에는 들어가나 수치 자체는 미확인.
3. 데이터 임포트/연동 설정 단계 이탈이 SaaS 온보딩에서 공통 관찰 현상이며, 한 검색 결과 요약은 "약 35%가 연동 설정 단계에서 이탈한다"고 언급한다. — 출처: 검색엔진 요약(appcues.com 등 복수 SaaS 온보딩 도구 가이드류를 종합한 결과, 개별 원문 URL 미확인), 확인일 2026-08-01, independent-sources: 1 — 단일 출처, 반증 자료 미발견, 픽스처의 28%와 정의(퍼널 기준점)가 동일한지는 불확실(미확인).
4. 온보딩 체크리스트 완료율은 평균 19.2%, 중앙값 10.1%(188개 기업 대상)라는 수치가 검색 결과 여러 2차 콘텐츠에 동일 문구로 반복 등장한다. — 출처: getperspective.ai, digitalapplied.com 등 복수 페이지에 동일 문구 인용, 확인일 2026-08-01, independent-sources: 1 — 동일 문구 반복은 원출처가 하나이고 재인용된 것으로 판단되어 독립 확인으로 보지 않음(미확인에 가까움).
5. 온보딩 이메일 시퀀스는 후속 이메일마다 오픈률이 약 3~5%씩 하락하는 경향이 있다. — 출처: [SaaS Onboarding Emails: The Complete Playbook](https://www.sequenzy.com/blog/saas-onboarding-emails-playbook), 확인일 2026-08-01, independent-sources: 1
6. 활성화 단계에서 복잡성(complexity)이 이탈의 가장 큰 동인이라는 주장이 있다. — 출처: [The Science of SaaS Onboarding](https://www.saasfactor.co/blogs/the-science-of-saas-onboarding-a-comprehensive-framework-for-reducing-friction-improving-activation-and-preventing-churn), 확인일 2026-08-01, independent-sources: 1

### 해석 (interpretation)
- 인앱 체크리스트는 세션 간 진행 상태가 유지되고 사용자에게 주도권을 주므로 선형 모달 투어보다 우수하다는 업계 컨센서스에 가까운 해석이 존재한다. — 출처: userpilot.com 외 복수 검색 결과, 확인일 2026-08-01
- "이메일은 활성화(activate)에, 인앱 경험은 리텐션(retain)에 기여한다"는 채널 역할 분담 해석이 존재한다. 단정적 사실이라기보다 실무 통념에 가깝다. — 출처: 검색 결과 요약(원문 개별 미확인), 확인일 2026-08-01

### 가정 (assumption — 이 세션이 명시적으로 채택)
- 픽스처가 목표 수치를 제공하지 않아 "업계 평균 방향 개선"을 성공 신호로 가정한다(브리프 참조).
- 3단계 이탈(28%)이 7일 이탈(58%)의 핵심 병목이라는 인과를 가정한다(정확한 퍼널 기여 비율은 픽스처에 없음).
- 화이트글러브(인적 지원) 관련 ROI 임계치(ACV 약 2.5만불 이상에서 경제성 확보) 자료는 확인일 기준 미래 시점(2027년)을 다루는 추정성 블로그 콘텐츠이며, 이 제품의 실제 ACV 정보가 브리프에 없어 적용 여부는 가정으로만 남긴다. — 출처: [2027 Operator Blueprint](https://pulserevops.com/revenue-architecture/ra0248), 확인일 2026-08-01, 신뢰도 낮음으로 표시(단일 출처·추정성 콘텐츠).

### 미확인 (unconfirmed)
- 이 제품 고유의 3단계 세부 이탈 원인(용어 이해 실패 vs 권한/기술 문제 vs 기타)은 외부 리서치로 확인 불가 — 내부 데이터 필요(검증 계획 E-02로 이관).
- 픽스처의 "업계 평균 52%" 수치의 정확한 원출처는 리서치로 확인하지 못함.
- 이 제품의 이메일-인앱 툴팁 메시지 간 정합성 여부(어긋나 있는지)는 미확인(검증 계획 E-04로 이관).
- 데이터 연동 단계의 35% 이탈(업계 일반)이라는 수치의 측정 정의가 픽스처의 28%(3단계 이탈)와 동일 기준인지 미확인.

## 로스터

- 선정 렌즈(5개, 3–6 범위 준수): 사용자·고객 탐색자, 도메인 유추자, 제약 전환자, 시스템 사고자, 실용적 조합자
- 제외 렌즈: 급진적 탐색자 — 사유: 3인월/6주 하드 제약 하에서는 비연속적 급진 대안의 실행 가능성이 낮다고 판단해 이번 발산 라운드에서는 제외했다. 다만 SCAMPER의 Reverse·Eliminate 변환(IDEA-026, IDEA-027)으로 급진적 관점 일부를 보완했다.
- 디스패치 방식: 측정 세션 환경 제약으로 Agent(서브에이전트) 호출이 불가하여, 메인 세션 컨텍스트 안에서 각 렌즈를 순차적으로 수행했다. 각 렌즈 수행 시 이전 렌즈의 발산 결과를 의도적으로 참조하지 않고 독립적으로 작성해 Brainwriting의 독립성 요건을 근사했다. 이는 진짜로 격리된 서브에이전트 실행과 동등하지 않다는 한계를 그대로 기록한다.
- agent-calls-used: 0

## 아이디어 풀

### IDEA-001
- idea-id: IDEA-001
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: CLUSTER-A
- idea: 3단계 데이터 연동 진입 전, "왜 이 연동이 필요한지" 설명과 함께 실제 연동 없이 체험 가능한 샘플/데모 데이터 모드를 제공해 비개발자가 부담 없이 먼저 제품 가치를 체험하게 한다. 실제 연동은 선택적으로 미룰 수 있게 한다.
- expected-value: 3단계 진입 장벽 감소, 가치 체감 후 연동 동기 부여
- novelty: 중간(업계 유사 패턴 존재, 이 제품엔 미적용)
- assumptions: 샘플 데이터만으로도 핵심 가치 제안을 체감할 수 있다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 데이터 임포트를 선택적으로 미루는 것이 온보딩 이탈 대응 전략으로 업계에서 관찰된다(예: Notion의 "나중에 가져오기" 옵션)
- independent-sources: 1

### IDEA-002
- idea-id: IDEA-002
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: CLUSTER-B
- idea: 온보딩 중 "막힘" 감지 시(예: 3단계에서 90초 이상 정체) 실시간으로 인앱 채팅/스크린샷 첨부 지원 요청 버튼을 노출해 비개발자가 즉시 사람의 도움을 받을 수 있게 한다.
- expected-value: 이탈 직전 개입으로 3단계 이탈률 감소
- novelty: 낮음(라이브 지원 자체는 흔한 패턴이나 이 제품엔 부재)
- assumptions: 실시간 지원 인력/봇 리소스를 3인월 내 마련 가능하다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 약 35%가 연동 설정 단계에서 이탈한다는 업계 관측이 있다
- independent-sources: 1

### IDEA-003
- idea-id: IDEA-003
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: CLUSTER-C
- idea: 데이터 연동 설정 단계의 전문 용어(API 키, OAuth, webhook 등)를 담당자의 익숙한 업무 언어(예: "회계 프로그램과 연결하기")로 전면 재작성한 용어 사전·툴팁 오버레이 제공.
- expected-value: 인지 부담 감소로 3단계 완료율 상승
- novelty: 낮음(카피 개선)이나 즉시 실행 가능
- assumptions: 이탈 원인의 상당 부분이 기술 용어 이해 실패다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 활성화 단계에서 복잡성이 이탈의 가장 큰 동인이라는 주장이 있다
- independent-sources: 1

### IDEA-004
- idea-id: IDEA-004
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: none(미분류 — 어느 군집에도 강제 편입하지 않음)
- idea: 온보딩 여정을 "지금 당장 완료" 강제가 아니라 "체크리스트에 저장하고 나중에 이어서 하기"로 재설계하고, 세션 간 진행 상태를 이메일로 리마인드한다.
- expected-value: 시간 압박으로 인한 즉시 이탈 방지, 세션 간 지속성 확보
- novelty: 낮음~중간
- assumptions: 이탈 사용자 다수가 "지금 이럴 시간이 없어서" 이탈한다
- duplicate-of: none
- status: parked
- park-recondition: 검증 계획 E-02(CS 티켓 정성 분석) 결과 "시간 부족형 이탈"이 유의미한 비중으로 확인되면 재검토한다.
- elimination-reason: n/a
- core-fact: 이메일 시퀀스 후속 발송마다 오픈률이 3~5%씩 하락한다 — 시간 압박형 이탈에 대한 간접 정황
- independent-sources: 1

### IDEA-005
- idea-id: IDEA-005
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: CLUSTER-D
- idea: 항공기 이륙 전 체크리스트(조종사-부조종사 상호 확인) 원리를 차용해, 데이터 연동 단계를 "본인이 직접 입력"과 "동료에게 위임 요청" 두 갈래로 나누고, IT 담당자가 아닌 실제 데이터 소유자(예: 재무팀)에게 특정 하위 단계를 위임할 수 있는 위임 링크를 발급한다.
- expected-value: 담당자 1인이 모든 기술/도메인 지식을 가질 필요 없이 병목 해소
- novelty: 높음(온보딩에 역할 위임 링크 도입)
- assumptions: 조직 내 다른 담당자에게 위임하는 것이 문화적으로 수용 가능하다
- duplicate-of: none
- status: parked
- park-recondition: 대상 고객사 조직 내 데이터 소유자에게 위임이 실제로 가능한 비율을 확인하는 고객 인터뷰(또는 CS 인터뷰) 결과가 확보되면 재검토한다.
- elimination-reason: n/a
- core-fact: 이 제품 고유의 조직 내 위임 가능성에 대한 외부 근거는 확인되지 않았다(미확인)
- independent-sources: 0

### IDEA-006
- idea-id: IDEA-006
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: CLUSTER-C
- idea: 병원 응급실의 트리아지(triage) 원리를 차용해, 온보딩 진입 시 몇 가지 질문(회사 규모, 사용 중인 도구, 기술 역량 자가진단)으로 사용자를 유형별로 분류하고, 유형에 따라 다른 난이도/분량의 온보딩 경로를 자동 배정한다.
- expected-value: 비개발자에게는 더 쉬운 경로, 기술 역량 높은 사용자에게는 빠른 경로 제공해 평균 이탈 감소
- novelty: 중간~높음
- assumptions: 자가진단 응답이 실제 역량과 상관관계가 있다
- duplicate-of: none
- status: transformed
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 활성화 단계에서 복잡성이 이탈의 가장 큰 동인이라는 주장이 있다
- independent-sources: 1

### IDEA-007
- idea-id: IDEA-007
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: CLUSTER-C
- idea: 이케아(IKEA) 가구 조립 설명서 원리를 차용해, 텍스트 설명 대신 순수 시각적 단계별 다이어그램(스크린샷에 번호와 화살표만) 형식으로 데이터 연동 단계를 재구성해 언어·전문성 장벽을 낮춘다.
- expected-value: 인지 부담 감소, 언어 의존도 감소
- novelty: 중간
- assumptions: 시각적 설명이 텍스트 기반 설명보다 비개발자에게 더 잘 통한다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 활성화 단계에서 복잡성이 이탈의 가장 큰 동인이라는 주장이 있다
- independent-sources: 1

### IDEA-008
- idea-id: IDEA-008
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: CLUSTER-B
- idea: 콜센터의 "콜백 예약" 원리를 차용해, 3단계에서 이탈 시도(뒤로가기/닫기)가 감지되면 즉시 이탈시키는 대신 "지금 어려우시면, 담당자와 15분 화면공유 예약"을 원클릭으로 제안한다.
- expected-value: 이탈을 화면공유 전환으로 흡수해 즉시 손실을 방지
- novelty: 낮음~중간
- assumptions: 사용자가 화면공유를 신뢰하고 응한다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 약 35%가 연동 설정 단계에서 이탈한다는 업계 관측이 있다
- independent-sources: 1

### IDEA-009
- idea-id: IDEA-009
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: CLUSTER-C
- idea: "React+Node.js 변경 불가" 제약을 그대로 살려, 새 인프라 없이 기존 스택 위에서 3단계를 "폼 기반 단일 페이지 위저드"로 재구성(신규 백엔드 연동 없이 프런트 UX만 재배치)해 3인월 내 완결 가능한 최소 개편으로 설계한다.
- expected-value: 낮은 개발 비용으로 즉시 체감 가능한 UX 개선
- novelty: 낮음(순수 리팩터링성)이나 제약 적합도 매우 높음
- assumptions: 현재 3단계 이탈의 상당 부분이 백엔드 로직이 아니라 UX 배치 문제다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 활성화 단계에서 복잡성이 이탈의 가장 큰 동인이라는 주장이 있다
- independent-sources: 1

### IDEA-010
- idea-id: IDEA-010
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: CLUSTER-E
- idea: "6주 출시" 제약을 설계 재료로 삼아, 전체 온보딩을 재설계하는 대신 이탈이 집중된 3단계 "직전"과 "직후"에만 좁게 개입하는 최소 개입(minimum viable intervention) 원칙을 채택한다 — 3단계 진입 직전 기대치 설정 화면 1개, 이탈 직후 24시간 내 자동 이메일 1개만 추가.
- expected-value: 최소 범위로 6주 내 검증 가능한 개선
- novelty: 낮음
- assumptions: 좁은 개입만으로도 측정 가능한 이탈률 변화가 난다
- duplicate-of: none
- status: transformed
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 온보딩 체크리스트 완료율 평균 19.2%(188개사) — 저비용 개선의 여지가 크다는 정황
- independent-sources: 1

### IDEA-011
- idea-id: IDEA-011
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: CLUSTER-C
- idea: "비개발자 다수" 제약을 차별화 요소로 전환 — 3단계를 노코드 커넥터 UI(사전 정의된 연동 카드 클릭 방식)로 제한해 자유도를 줄이는 대신 실패 가능성을 낮추고, "개발자 없이 완료 가능"을 제품 차별점으로 삼는다.
- expected-value: 실패 경로 자체를 줄여 이탈 감소, 차별화 포지셔닝
- novelty: 중간
- assumptions: 사전 정의된 커넥터 카드가 대상 고객의 실제 연동 니즈 대부분을 커버한다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 활성화 단계에서 복잡성이 이탈의 가장 큰 동인이라는 주장이 있다
- independent-sources: 1

### IDEA-012
- idea-id: IDEA-012
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: CLUSTER-E
- idea: "3인월 예산" 제약을 이용해 신규 기능 개발 대신 기존 이메일 7단계의 발송 타이밍·문구만 재배치하는 제로 코드 개선(카피라이팅, 발송 간격 조정)을 우선 실행한다.
- expected-value: 개발 리소스 소모 없이 이메일 채널 효과 개선
- novelty: 낮음
- assumptions: 현재 이메일 문구/타이밍이 최적화되지 않았다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 온보딩 이메일 시퀀스는 후속 이메일마다 오픈률이 약 3~5%씩 하락하는 경향이 있다
- independent-sources: 1

### IDEA-013
- idea-id: IDEA-013
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: CLUSTER-F
- idea: 이탈 지점(3단계)만 보지 않고 전체 루프를 본다 — 영업/CS가 계약 체결 시점에 "온보딩 전 데이터 연동 사전 체크리스트"를 미리 전달해, 사용자가 로그인 전에 이미 필요한 권한(API 키, 관리자 계정 등)을 준비하게 하는 온보딩 이전 단계 개입.
- expected-value: 3단계 도달 시점의 준비 부족으로 인한 이탈을 사전에 제거
- novelty: 중간(온보딩 범위를 로그인 이전으로 확장)
- assumptions: 영업 프로세스에 이 체크리스트를 끼워 넣을 수 있다
- duplicate-of: none
- status: eliminated
- park-recondition: n/a
- elimination-reason: 브리프의 out-of-scope에 명시된 "영업 프로세스 변경"과 직접 충돌한다. 온보딩 이전 단계 개입을 구현하려면 영업 프로세스 자체를 수정해야 하며, 이는 승인된 프레임의 범위를 벗어난다(구체화 부족이 아닌 명시적 범위 위반이 탈락 근거).
- core-fact: 이메일은 활성화에, 인앱 경험은 리텐션에 기여한다는 채널 역할 분담 해석이 있다(해석 수준)
- independent-sources: 1

### IDEA-014
- idea-id: IDEA-014
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: none(미분류)
- idea: 인센티브 루프 설계 — IT 담당자가 아닌 조직 내 "실제 데이터를 다루는 실무자"에게도 온보딩 진행 알림이 가도록 시스템을 바꿔, 담당자 1인의 병목이 아니라 조직 차원의 다자 압력(피어 프레셔)으로 완료를 촉진한다.
- expected-value: 단일 담당자 병목 해소, 사회적 압력을 통한 완료 촉진
- novelty: 높음
- assumptions: 조직 내 다른 구성원에게 알림이 가는 것이 부정적으로 받아들여지지 않는다
- duplicate-of: none
- status: parked
- park-recondition: 조직 내 다자 알림이 사용자 불쾌감·프라이버시 우려를 유발하지 않는다는 고객 리서치(설문/인터뷰)가 확보되면 재검토한다.
- elimination-reason: n/a
- core-fact: 이 제품 고유의 조직 내 위임/알림 수용성에 대한 외부 근거는 확인되지 않았다(미확인)
- independent-sources: 0

### IDEA-015
- idea-id: IDEA-015
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: CLUSTER-F
- idea: 피드백 루프 부재가 근본 원인이라고 보고, 온보딩 완료율·이탈 지점 데이터를 실시간으로 CS/PM 대시보드에 노출해 이탈 발생 즉시(주 단위가 아니라 일 단위) 개입할 수 있는 운영 루프를 구축한다(제품 변경이 아니라 운영 체계 변경).
- expected-value: 근본 이탈 원인을 지속적으로 좁혀가는 조직 역량 확보
- novelty: 낮음(관측 가능성 인프라)이나 다른 후보들의 효과를 검증할 기반이 됨
- assumptions: 현재 이탈 데이터가 실시간·일 단위로는 노출되지 않고 있다(픽스처는 34%/58%/28%라는 집계 수치는 이미 보유하고 있어 완전한 부재는 아니라는 점에서 부분 상충 — 상태 블록 inconsistencies에 기록)
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 이메일은 활성화에, 인앱 경험은 리텐션에 기여한다는 채널 역할 분담 해석이 있다(해석 수준)
- independent-sources: 1

### IDEA-016
- idea-id: IDEA-016
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: CLUSTER-A
- idea: 3단계 데이터 연동 성공/실패를 "필수 관문"이 아니라 "제품 가치의 일부"로 재정의해, 연동 없이도 도달 가능한 대체 가치 경로(예: 수동 CSV 업로드로 유사 가치 체감)를 병렬 제공해 단일 관문 의존을 낮춘다.
- expected-value: 단일 접점(연동) 실패가 전체 온보딩 실패로 이어지는 구조를 완화
- novelty: 중간
- assumptions: CSV 업로드 등 대체 경로가 핵심 가치의 상당 부분을 대신할 수 있다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 데이터 임포트를 선택적으로 미루는 것이 온보딩 이탈 대응 전략으로 업계에서 관찰된다(예: Notion의 "나중에 가져오기" 옵션)
- independent-sources: 1

### IDEA-017
- idea-id: IDEA-017
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: CLUSTER-F
- idea: 기존 이메일 7단계 + 인앱 툴팁 3개를 없애지 않고, 3단계 데이터 연동 진입 시점에만 이메일 시퀀스 중 "연동 가이드" 이메일을 인앱 팝업과 동일 콘텐츠로 동기화(현재는 별도 채널로 존재해 메시지가 어긋날 가능성)해 일관된 단일 내러티브로 재결합한다.
- expected-value: 기존 자산 재활용으로 저비용, 메시지 일관성으로 혼란 감소
- novelty: 낮음
- assumptions: 현재 이메일과 인앱 툴팁 메시지가 서로 어긋나 있다(미확인 — 검증 필요)
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 이메일은 활성화에, 인앱 경험은 리텐션에 기여한다는 채널 역할 분담 해석이 있다(해석 수준)
- independent-sources: 1

### IDEA-018
- idea-id: IDEA-018
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: CLUSTER-E
- idea: 단계적 접근 — 6주를 2주씩 3스프린트로 나눠, 1스프린트차 "3단계 이탈 원인 계측 강화"(퍼널 이벤트 세분화), 2스프린트차 "가장 큰 이탈 하위 원인 1개 수정", 3스프린트차 "측정 후 다음 사이클 계획"으로 반복 개선 프로세스 자체를 설계한다.
- expected-value: 3인월 예산 내에서 추측이 아닌 데이터 기반 반복 개선
- novelty: 낮음(프로세스 아이디어)
- assumptions: 현재 3단계 내부의 세부 이탈 원인이 아직 세분화되지 않았다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 온보딩 체크리스트 완료율 평균 19.2%(188개사) — 저비용 개선의 여지가 크다는 정황
- independent-sources: 1

### IDEA-019
- idea-id: IDEA-019
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: CLUSTER-F
- idea: 기존 인앱 툴팁 3개 자산과 이메일 자산을 결합해 "진행률 바 + 다음 이메일 미리보기"를 인앱에 노출하고, 이메일에는 "지금 앱에서 이어하기" 딥링크를 넣어 두 채널을 하나의 진행 상태로 통합한다.
- expected-value: 채널 단절로 인한 재진입 마찰 감소
- novelty: 낮음~중간
- assumptions: 현재 이메일과 인앱 진행 상태가 서로 연동되어 있지 않다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 이메일은 활성화에, 인앱 경험은 리텐션에 기여한다는 채널 역할 분담 해석이 있다(해석 수준)
- independent-sources: 1

### IDEA-020
- idea-id: IDEA-020
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: CLUSTER-B
- idea: 화이트글러브 온보딩(리서치에서 발견한 패턴)을 전체 고객이 아닌 "3단계에서 2회 이상 실패 이력이 있는 사용자"에게만 선별적으로 적용 — 자동화된 셀프서브 온보딩과 소수 대상 수동 지원을 단계적으로 결합해 예산을 소수 고위험군에 집중한다.
- expected-value: 제한된 예산으로 고위험 이탈군만 선별 개입해 ROI 극대화
- novelty: 중간
- assumptions: 2회 이상 실패한 사용자를 식별할 수 있는 계측이 이미 있거나 3인월 내 추가 가능하다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 화이트글러브 온보딩은 통상 ACV 임계치 이상에서 경제성이 맞는다는 주장이 있다(신뢰도 낮음 — 미래 시점 추정 콘텐츠, 이 제품 ACV 정보 없음)
- independent-sources: 1

### IDEA-021
- idea-id: IDEA-021
- parent-id: IDEA-001
- strategy: SCAMPER (Substitute)
- lens: 사용자·고객 탐색자(변환)
- cluster-ids: CLUSTER-A
- idea: "3단계 실제 연동"을 미리 채워진 데모 회사 데이터로 대체(Substitute)해 전체 온보딩을 우선 완주하게 한 뒤, 완주 성취감을 얻은 시점에 "이제 실제 데이터로 전환하기" 버튼 하나로 실제 연동을 뒤로 미룬다.
- expected-value: 온보딩 완료 경험 자체를 먼저 제공해 완료율 지표를 개선하고, 실제 전환은 별도 퍼널로 관리
- novelty: 중간~높음
- assumptions: 데모 완주 후에도 실제 전환 동기가 유지된다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 데이터 임포트를 선택적으로 미루는 것이 온보딩 이탈 대응 전략으로 업계에서 관찰된다(예: Notion의 "나중에 가져오기" 옵션)
- independent-sources: 1

### IDEA-022
- idea-id: IDEA-022
- parent-id: IDEA-008
- strategy: SCAMPER (Combine)
- lens: 도메인 유추자 × 실용적 조합자(변환, IDEA-020과 교차결합)
- cluster-ids: CLUSTER-B
- idea: 이탈 시도 감지(IDEA-008의 실시간 감지) 신호를 즉시 화면공유 제안에만 쓰지 않고, 화이트글러브 선별 기준(IDEA-020)과 결합(Combine)해 "고위험군 자동 태깅" 신호로 활용, 화이트글러브 대상 선정 로직에 자동 반영한다.
- expected-value: 실시간 계측과 선별 개입을 하나의 파이프라인으로 결합해 중복 투자 방지
- novelty: 중간
- assumptions: 이탈 시도 감지 이벤트가 고위험군 판별에 충분한 신호력을 가진다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 약 35%가 연동 설정 단계에서 이탈한다는 업계 관측이 있다
- independent-sources: 1

### IDEA-023
- idea-id: IDEA-023
- parent-id: IDEA-006
- strategy: SCAMPER (Adapt)
- lens: 도메인 유추자(변환)
- cluster-ids: CLUSTER-A, CLUSTER-C(교차 참조)
- idea: 병원 트리아지 원리를 온보딩 "진입 시점"이 아니라 "3단계 진입 직전 시점"에 재적용(Adapt) — 3단계 도달 시 짧은 자가진단(연동하려는 도구가 무엇인지)을 물어, 사전 정의된 노코드 커넥터가 있으면 간소 경로, 없으면 수동 CSV 경로로 즉시 분기한다.
- expected-value: 3단계 내부에서 사용자 상황에 맞는 최소 마찰 경로 제공
- novelty: 중간
- assumptions: 자가진단 한두 문항만으로 적절한 경로 분기가 가능하다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 활성화 단계에서 복잡성이 이탈의 가장 큰 동인이라는 주장이 있다
- independent-sources: 1

### IDEA-024
- idea-id: IDEA-024
- parent-id: IDEA-010
- strategy: SCAMPER (Modify)
- lens: 제약 전환자(변환)
- cluster-ids: CLUSTER-C
- idea: 최소 개입(사전 기대치 설정 화면 1개 + 이탈 후 이메일 1개)의 규모를 확대(Modify)해, 3단계 진입 직전 기대치 화면에 예상 소요 시간과 필요 준비물 체크리스트까지 포함한다.
- expected-value: 사전 기대치 설정을 더 구체화해 진입 전 이탈 가능성을 낮춤
- novelty: 낮음
- assumptions: 소요 시간·준비물 사전 안내가 실제로 완주율에 영향을 준다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 활성화 단계에서 복잡성이 이탈의 가장 큰 동인이라는 주장이 있다
- independent-sources: 1

### IDEA-025
- idea-id: IDEA-025
- parent-id: IDEA-015
- strategy: SCAMPER (Put to another use)
- lens: 시스템 사고자(변환)
- cluster-ids: CLUSTER-F
- idea: CS/PM용으로 설계된 실시간 이탈 대시보드를 최종 사용자(IT 담당자) 본인에게도 노출해 "당신은 3단계에서 동료 사용자 대비 빠르게 진행 중입니다" 같은 사회적 비교 지표로 다른 용도(고객 대상 동기부여)에 전용(Put to another use)한다.
- expected-value: 별도 개발 없이 기존 계측 인프라를 고객 동기부여 용도로 재활용
- novelty: 높음
- assumptions: 사회적 비교 지표 노출이 B2B 비개발자 사용자에게 불쾌감이 아닌 동기부여로 작동한다
- duplicate-of: none
- status: parked
- park-recondition: CLUSTER-F의 계측 인프라(IDEA-015)가 구축된 이후, 최종사용자 대상 사회적 비교 지표 노출의 수용성을 별도 실험(설문 또는 목업 반응 테스트)으로 확인하면 재검토한다.
- elimination-reason: n/a
- core-fact: 이메일은 활성화에, 인앱 경험은 리텐션에 기여한다는 채널 역할 분담 해석이 있다(해석 수준)
- independent-sources: 1

### IDEA-026
- idea-id: IDEA-026
- parent-id: IDEA-012
- strategy: SCAMPER (Eliminate)
- lens: 제약 전환자(변환)
- cluster-ids: CLUSTER-E
- idea: 이메일 7단계 중 3단계 데이터 연동과 무관한 안내성 이메일(예: 커뮤니티 소개, 이벤트 안내 성격의 내용)을 제거(Eliminate)해 사용자의 관심을 연동 완료에 집중시킨다. 정확히 어떤 단계가 무관한지는 이메일 내용 감사가 필요해 검증 계획으로 이관한다.
- expected-value: 시퀀스 단축으로 오픈률 하락 누적 효과 완화, 핵심 메시지 집중도 상승
- novelty: 낮음
- assumptions: 현재 7단계 중 일부가 3단계 연동과 무관한 내용이다(미확인 — 이메일 내용 감사 필요)
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 온보딩 이메일 시퀀스는 후속 이메일마다 오픈률이 약 3~5%씩 하락하는 경향이 있다
- independent-sources: 1

### IDEA-027
- idea-id: IDEA-027
- parent-id: IDEA-009
- strategy: SCAMPER (Reverse)
- lens: 제약 전환자(변환)
- cluster-ids: CLUSTER-C
- idea: 현재 순서(로그인 → 툴팁 → 이메일 안내 → 3단계에서 연동 정보 수집)를 뒤집어(Reverse), 데이터 연동에 필요한 정보 수집(어떤 도구를 쓰는지)을 온보딩의 첫 질문으로 역순 배치해 3단계 도달 전 이미 맞춤 안내가 준비된 상태로 진입하게 한다.
- expected-value: 3단계 도달 시점의 정보 공백 제거, 맞춤화된 안내 사전 준비
- novelty: 중간
- assumptions: 온보딩 초반(가치를 체감하기 전)에 연동 관련 질문을 물어도 이탈이 늘지 않는다
- duplicate-of: none
- status: shortlisted
- park-recondition: n/a
- elimination-reason: n/a
- core-fact: 활성화 단계에서 복잡성이 이탈의 가장 큰 동인이라는 주장이 있다
- independent-sources: 1

## 군집

발산 라운드(IDEA-001~020) 검토 결과: 최근 라운드 대부분이 기존 군집(A~F 성격)에 추가되는 경향이 있었고 렌즈별로 "저비용 UX 단순화"류 해결 원리가 반복되는 경향이 일부 관찰되어 다양성이 완전히 정체되었다고 단정하기는 어려우나, 이 주제는 SKILL.md·strategy-protocols.md 규칙상 **명백한 개선형 주제**이므로(기존 온보딩 방식의 개선) 정체 여부와 무관하게 SCAMPER(IDEA-021~027)를 적용했다.

### CLUSTER-A: 필수 관문 완화 — 연동을 나중으로 미루거나 대체 경로 제공
- 포함 idea-id: IDEA-001, IDEA-016, IDEA-021, IDEA-023(교차 참조)
- 공통 가정: 실제 라이브 연동 없이도 핵심 가치를 체감시킬 수 있다.
- 차별점: 001은 온보딩 전체를 데모로, 016은 부분 대체 경로(CSV), 021은 완주 후 실제 전환 유도, 023은 3단계 진입 시점의 조건 분기.
- 미해결 질문: 데모/대체 경로 사용자가 이후 실제 연동으로 전환하는 비율은 얼마인가?

### CLUSTER-B: 실시간 이탈 감지 및 선별 인적 개입
- 포함 idea-id: IDEA-002, IDEA-008, IDEA-020, IDEA-022
- 공통 가정: 이탈 직전 신호를 계측으로 포착할 수 있다.
- 차별점: 002는 즉시 셀프 지원 버튼, 008은 화면공유 예약, 020/022는 반복 실패 이력 기반 사후 선별 인적 개입.
- 미해결 질문: 실시간 감지에 필요한 계측이 3인월/6주 내 신규 개발 없이 확보 가능한가? 화면공유 등 인적 지원 운영 리소스는 "3인월 개발 예산"에 포함되는가, 별도인가?

### CLUSTER-C: 인지 부담 감소 — 언어·시각·구조 단순화
- 포함 idea-id: IDEA-003, IDEA-006(transformed), IDEA-007, IDEA-009, IDEA-011, IDEA-023(교차 참조), IDEA-024, IDEA-027
- 공통 가정: 이탈의 상당 부분이 UX/언어 이해 실패 또는 구조적 복잡성에서 온다.
- 차별점: 003 카피 재작성, 007 시각화, 009 구조 재배치, 011 자유도 축소형 노코드 카드, 024 기대치 확대, 027 질문 순서 역전.
- 미해결 질문: 이 제품 고유 이탈 사용자 인터뷰/로그로 "이해 실패"가 실제 원인인지 아직 확인되지 않았다(현재 근거는 일반 업계 자료).

### CLUSTER-D: 1인 병목 해소 — 조직 내 위임·분산
- 포함 idea-id: IDEA-005, IDEA-014
- 공통 가정: 조직 내 다른 구성원의 관여가 가능하고 사회적으로 수용된다.
- 차별점: 005는 특정 하위 작업의 명시적 위임, 014는 알림 기반 사회적 압력.
- 미해결 질문: 대상 고객사(중소기업) 조직 구조상 위임 가능한 인원이 실제로 존재하는가? 알림 수신이 반감을 사지 않는가?
- 비고: 두 아이디어 모두 이번 라운드에서는 근거 부족으로 parked, 별도 클러스터로 보존.

### CLUSTER-E: 제약 최적화 — 저비용/저코드 즉시 실행
- 포함 idea-id: IDEA-010(transformed), IDEA-012, IDEA-018, IDEA-024(교차 참조는 CLUSTER-C), IDEA-026
- 공통 가정: 큰 재설계 없이 저비용 개선만으로 유의미한 변화가 가능하다.
- 차별점: 010/024는 최소 개입 원칙, 012/026은 이메일 콘텐츠 조정, 018은 계측 우선 반복 접근.
- 미해결 질문: 저비용 개선만으로 완료율 격차(34% → 업계 평균 방향)를 좁히기에 충분한가, 아니면 구조적 재설계(CLUSTER-A/C)가 필요한가?

### CLUSTER-F: 시스템/채널 정합성 — 접점 간 일관성과 관측 가능성
- 포함 idea-id: IDEA-013(eliminated), IDEA-015, IDEA-017, IDEA-019, IDEA-025
- 공통 가정: 온보딩 실패가 단일 화면이 아니라 여러 접점(영업, 이메일, 인앱, 운영)의 비정합에서 발생한다.
- 차별점: 013은 로그인 이전으로 범위 확장(out-of-scope와 충돌해 eliminated), 015/025는 계측·동기부여 인프라, 017/019는 이메일-인앱 간 일관성.
- 미해결 질문: IDEA-013이 지적한 "온보딩 이전 준비 부족" 문제를, 영업 프로세스를 건드리지 않고 온보딩 내부(예: 첫 이메일에 준비물 안내 강화)만으로 일부 흡수할 수 있는가?

## 숏리스트

### Candidate C-01
- source-idea-ids: IDEA-001, IDEA-016, IDEA-021, IDEA-023
- value-proposition: 실제 라이브 연동 전에 샘플/데모 데이터 또는 CSV 등 대체 경로로 핵심 가치를 먼저 체감시켜 3단계 진입 장벽 자체를 우회하고, 이후 실제 연동 전환을 별도로 유도한다.
- requester-value-fit: 높음 — 3단계 이탈(28%)이라는 핵심 병목에 직접 작용한다.
- differentiation: 이탈을 "막는" 것이 아니라 "미루는" 접근. 업계 사례(Notion류)는 존재하나 이 제품에는 미적용.
- learning-value: 높음 — "데모/대체 경로 이후 실제 전환율"이라는 이전에 없던 지표를 얻게 된다.
- key-risks: 데모 체감 후 실제 전환 없이 이탈이 뒤로 미뤄지기만 할 위험. React+Node 스택에서 데모 모드/CSV 대체 경로 구현 범위가 3인월 내 가능한지 미검증.
- evidence-level: 중간(업계 사례 1건, 독립 출처 부족 — independent-sources 1)
- dissent: 시스템 사고자 렌즈는 "3단계만이 아니라 7일 이내 이탈 전체"를 봐야 한다는 반론을 제기했다. IDEA-016까지 결합하면 범위가 넓어져 3인월을 초과할 우려가 있다는 지적도 있다.
- validation-priority: 최상위

### Candidate C-02
- source-idea-ids: IDEA-003, IDEA-007, IDEA-009, IDEA-011, IDEA-024, IDEA-027
- value-proposition: 3단계 진입 직전 자가진단으로 노코드 커넥터/수동 경로를 분기하고, 용어·시각 단순화 및 질문 순서 재배치로 잔존 단계의 완료율을 높인다.
- requester-value-fit: 높음 — 3단계 이탈에 직접 개입한다.
- differentiation: 여러 저비용 UX 개선의 조합, 새 인프라 불필요, React+Node 스택 그대로 활용.
- learning-value: 중간 — 어떤 하위 개선이 실제 효과가 있는지는 개별 A/B가 필요하다.
- key-risks: 이탈 원인이 "이해 실패"가 아니라 "권한/기술 문제"일 경우 효과가 제한적일 수 있다(미검증 가정).
- evidence-level: 낮음~중간(업계 일반론 위주, 이 제품 고유 데이터 없음 — independent-sources 1 다수)
- dissent: 제약 전환자 렌즈는 이 조합이 "익숙한 UX 개선의 반복"이라 새로움이 낮다고 지적했다.
- validation-priority: 상위

### Candidate C-03
- source-idea-ids: IDEA-002, IDEA-008, IDEA-020, IDEA-022
- value-proposition: 전체 사용자가 아닌 3단계에서 반복 실패한 고위험군만 실시간 감지해 선별적으로 인적 지원(화면공유/채팅)을 제공한다.
- requester-value-fit: 중간~높음 — 이탈 직전 개입이라 효과는 클 수 있으나, 인력 리소스가 3인월 "개발" 예산과는 별도의 운영 비용일 가능성이 있다.
- differentiation: 자동화(셀프서브)와 인적 지원의 하이브리드. 리서치의 화이트글러브 ROI 임계치(ACV 기준) 시사점과는 결이 다르다 — 이 제품의 ACV 정보가 브리프에 없어 경제성 판단이 불가하다(미확인).
- learning-value: 높음 — 실시간 감지 계측 인프라를 구축하는 부수 효과가 있다.
- key-risks: 실시간 감지·화면공유 대응 인력은 브리프가 정의한 "개발 예산 3인월"의 범위인지 불명확 — 운영 리소스 가용성이 불확실(미확인).
- evidence-level: 낮음(화이트글러브 ROI 자료는 있으나 ACV 임계치 정보 없이 이 제품에 그대로 적용할 수 없고, 그 출처(pulserevops.com)도 2027년 시점을 다루는 추정성 블로그로 신뢰도가 낮다).
- dissent: 실용적 조합자 렌즈는 자동화 우선(C-01, C-02)이 예산 효율이 더 높다고 지적했다. 시스템 사고자 렌즈는 고위험군 선별이 근본 원인 해결이 아닌 대증 처방이라고 지적했다.
- validation-priority: 중위

### Candidate C-04
- source-idea-ids: IDEA-012, IDEA-015, IDEA-017, IDEA-018, IDEA-019, IDEA-026
- value-proposition: 새 기능 없이 기존 이메일·인앱 자산을 정합화하고, 3단계 내부 이탈의 세부 원인을 계측으로 먼저 규명한 뒤 다음 스프린트에서 최우선 원인 1개를 수정하는 반복 접근을 취한다.
- requester-value-fit: 중간 — 직접 효과는 다른 후보 대비 간접적이나 실패 위험이 가장 낮고, 다른 후보들의 근거를 보강하는 선행 조건 역할을 한다.
- differentiation: "무엇을 만들지"보다 "무엇이 문제인지 먼저 아는 것"에 투자하는 유일한 후보다.
- learning-value: 최상 — 이후 모든 후보의 가정을 검증할 계측 기반을 제공한다.
- key-risks: 6주 안에 계측만 하고 실제 수정까지 이르지 못할 위험(일정 소진).
- evidence-level: 낮음(이 제품 고유 데이터 없이 일반론 위주) — 다만 이 자체가 이 후보의 존재 이유(계측 공백)다.
- dissent: 속도를 중시하는 관점에서는 "이미 원인(3단계, 28%)이 알려져 있는데 왜 또 계측하냐"는 반론이 있다. 다만 세부 하위 원인(용어/권한/기타)은 실제로 아직 미분류 상태다.
- validation-priority: 최상위(다른 후보들의 선행 조건 성격)

## 검증 계획

의뢰자의 검증 계획 명시적 승인 전에는 아래 실험을 실행하지 않는다. 모든 실험은 `.brainstorm/**` 범위 안의 리서치·문서 작업으로 제한하며 코드베이스·외부 시스템을 변경하지 않는다.

### Experiment E-01
- candidate-id: C-01
- assumption: 샘플/데모 데이터로 핵심 가치를 체감시켜도 사용자가 이후 실제 연동으로 전환한다.
- approved-type: mockup
- method: 클릭 가능한 데모 모드 화면 흐름 목업(3단계를 우회하는 경로 포함)을 제작하고, 대상 페르소나(중소기업 비개발자 IT 담당자)와 유사한 내부/외부 인터뷰 대상자 5명에게 목업을 보여준 뒤 "실제 연동으로 전환하겠는가"에 대한 반응을 수집한다.
- success-signal: 5명 중 60% 이상이 "실제 연동으로 전환하겠다"는 의사를 명확히 표명한다.
- stop-condition: 5명 중 2명 이하만 긍정 반응을 보이면 C-01을 이 형태로는 채택하지 않고 CLUSTER-A 내 다른 조합(IDEA-016 CSV 경로 등)으로 재설계를 검토한다.
- estimated-cost: 약 3일(목업 제작 1.5일 + 인터뷰·정리 1.5일)
- approval-status: proposed

### Experiment E-02
- candidate-id: C-02
- assumption: 이탈의 상당 부분이 전문 용어·UX 복잡성 이해 실패에서 온다.
- approved-type: research
- method: 기존 CS/지원 티켓 로그 중 3단계 데이터 연동 관련 문의를 정성 코딩해 "용어 미이해" / "권한·기술 문제" / "기타" 비중을 분류한다(신규 사용자 대상 실험 배포 없이 기존 내부 기록만 검토).
- success-signal: "용어 미이해"류 문의가 전체 3단계 관련 문의의 40% 이상을 차지한다.
- stop-condition: 관련 티켓 표본이 20건 미만이면 결론을 보류하고 다른 계측 방법(예: 세션 리플레이 검토)을 검증 계획에 추가한다.
- estimated-cost: 약 2일
- approval-status: proposed

### Experiment E-03
- candidate-id: C-03
- assumption: 고위험군(3단계 2회 이상 실패) 선별에 필요한 이벤트 계측이 3인월 내 신규 개발 없이 이미 확보되어 있거나 저비용으로 가능하다.
- approved-type: research
- method: 현재 프런트/백엔드 이벤트 로깅 체계 문서를 검토(코드 수정 없이 열람)하고 필요 계측 항목(3단계 재진입, 실패, 이탈)과의 gap을 분석한다.
- success-signal: 필요 이벤트 3종 중 2종 이상이 이미 로깅되고 있어 신규 계측 부담이 낮다.
- stop-condition: 3종 모두 신규 계측이 필요하다고 확인되면, C-03이 3인월 제약 내 실현 가능한지 재평가가 필요하다고 표시하고 우선순위를 낮춘다.
- estimated-cost: 약 1일
- approval-status: proposed

### Experiment E-04
- candidate-id: C-04
- assumption: 현재 이메일 7단계와 인앱 툴팁 3개의 메시지가 실제로 서로 어긋나 있다(정합성 문제가 존재한다).
- approved-type: document
- method: 이메일 7단계 전문과 인앱 툴팁 3개 문구를 나란히 정리한 대조표를 작성해 상충·중복·누락 지점을 식별한다.
- success-signal: 최소 1건 이상의 명확한 메시지 불일치를 발견한다(불일치가 없다는 결론도 유효한 결과로 기록한다).
- stop-condition: 해당 없음(문서 감사이므로 대조표 완성 시 종료).
- estimated-cost: 약 1일
- approval-status: proposed

## 실험

(비어 있음 — 검증 계획 승인 전이므로 실험 미실행. `validating` 상태 진입 후 승인된 실험만 이 섹션에 기록한다.)

## 최종 보고

(비어 있음 — 세션이 `validation_approval` 상태에서 종료되어 최종 보고는 아직 작성하지 않는다. 검증 계획 승인과 `validating` 단계 완료 후 작성한다.)
