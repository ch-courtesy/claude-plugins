# Brainstorm Session: 20260801-onboarding-dropout-b3

## 상태
- session-id: 20260801-onboarding-dropout-b3
- state: validation_approval
- updated-at: 2026-08-01
- frame-approved-at: 2026-08-01 (측정 모드: 픽스처 브리프로 사전 승인 간주, AskUserQuestion 미사용)
- validation-approved-at: (none — 검증 계획은 작성·제시되었으나 승인은 아직 기록되지 않음. 측정 모드 지시 "validation_approval 상태에서 종료"를 문자 그대로 적용해, 이 상태의 정의(계획 재제시 및 승인/수정 대기)를 유지함. 아래 "검증 계획" 섹션 서두에 이 해석을 명시함)
- agent-calls-used: 0 (서브에이전트 호출 불가 환경 — 아이디어 생성자 6개 렌즈를 세션 책임자 컨텍스트 안에서 순차 수행으로 대체. 아래 "로스터" 섹션에 명시)
- research-calls-used: 3 (WebSearch 3회, 최소 중앙 리서치 단계에서만 사용)
- completed-sections: 브리프, 연구 컨텍스트, 로스터, 아이디어 풀, 군집, 숏리스트, 검증 계획
- next-action: 의뢰자에게 검증 계획(Experiment E-01~E-05)을 제시하고 승인 또는 수정을 요청한다. 승인 시 `validating` 상태로 전환해 승인된 실험(연구·에이전트 비판·문서에 한함)만 수행한다.
- inconsistencies:
  - (1) NGT 수렴은 원래 "생성자 또는 별도 평가자의 독립 평가"를 요구하나, 이번 측정 세션은 서브에이전트 호출이 불가해 세션 책임자 단일 평가로 대체했다. 다중 독립 평가가 아님을 숏리스트 섹션 서두에 명시함.
  - (2) 측정 모드 지시문은 "프레이밍 인터뷰·프레임 승인·검증 계획 승인"을 픽스처로 사전 승인된 것으로 간주하라고 하면서도 동시에 "검증 계획 작성까지 수행하고 실험은 실행하지 않는다(validation_approval 상태에서 종료)"라고 명시한다. 두 지시가 문면상 긴장 관계에 있어, frame-status는 approved로 처리해 발산 단계까지 진행하되, 검증 계획 승인은 SKILL.md의 validation_approval 상태 정의(계획을 "다시 제시하고 승인 또는 수정만 요청") 그대로 유지하여 validation-approved-at을 비워두었다. 이 판단 자체를 불일치로 기록해 재개 시 재검토할 수 있게 한다.

## 브리프

- session-id: 20260801-onboarding-dropout-b3
- requester: 픽스처 브리프 제공자(개별 이름 미기재, B2B SaaS 제품팀 대리로 간주)
- problem-or-opportunity: 신규 사용자 온보딩 완료율이 업계 평균 대비 낮고(34% vs 업계 평균 52%), 최초 로그인 후 7일 이내 이탈이 58%에 달하는 상황을 개선할 기회.
- target: 중소기업(SMB) IT 담당자 — 비개발자 다수.
- requester-value: 온보딩 완료율 상승과 초기(7일 이내) 이탈 감소. 특히 이탈이 집중되는 3단계(데이터 연동 설정, 28% 이탈)의 개선을 통한 전체 퍼널 개선.
- how-might-we: "비개발자가 다수인 SMB IT 담당자가 3단계 데이터 연동 설정에서 이탈하지 않고 온보딩을 완료하도록 어떻게 도울 수 있을까?" (특정 해결책을 미리 고정하지 않음)
- scope: 온보딩 경험(이메일 시퀀스 7단계, 인앱 툴팁 3개, 3단계 데이터 연동 흐름)에 대한 아이디어 발굴과 검증 계획 작성까지. 실제 실험 실행은 이번 측정 세션 범위 밖.
- out-of-scope: 코드 구현, 실제 사용자 대상 실험 배포, 조직 구조·영업 계약·가격 정책 변경, React+Node 이외 스택 도입.
- constraints:
  - 개발 예산 3인월 이하
  - 출시 일정 6주 이내
  - 기술 스택 React+Node.js 변경 불가
  - 고객 세그먼트: 중소기업 IT 담당자, 비개발자 다수
- existing-attempts: 현재 온보딩은 이메일 시퀀스 7단계 + 인앱 툴팁 3개로 구성되어 있으며 운영 중. 효과는 제한적(완료율 34%, 3단계 이탈 28%, 7일 이내 이탈 58%). 이메일 시퀀스가 사용자의 실제 진행 상태를 인지해 분기하는지(상태 인지형인지 고정 드립인지)는 브리프에 명시되지 않음 — 미확인.
- assumptions:
  - (가정 A) 3단계 이탈의 주된 원인은 기술적 복잡성이다 — 브리프에 원인 분석은 없고 이탈률 수치만 제공됨. 미검증.
  - (가정 B) 온보딩은 현재 1→7 순차 구조로, 앞 단계를 완료해야 다음 단계로 진행 가능하다 — "3단계"라는 표현에서 유추. 미확인.
  - (가정 C) 이메일 시퀀스와 인앱 툴팁은 서로 독립적으로 동작하며 사용자의 실제 진행 상태와 항상 동기화되어 있지는 않을 수 있다 — 미확인.
- success-signals: 온보딩 완료율 상승(34%→업계 평균 이상), 3단계 이탈률 하락(28%→), 최초 로그인 후 7일 이내 이탈률 하락(58%→).
- evaluation-criteria (의뢰자 가치 기반, 가중치 상대순):
  1. step3-dropoff-reduction-potential — 28% 이탈의 실제 원인을 겨냥하는 정도 (최우선)
  2. feasibility-within-constraints — 3인월/6주/스택 유지 제약 안에서 실행 가능한 정도 (필수 게이트, 미충족 시 숏리스트 제외 사유)
  3. non-developer-usability-fit — 비개발자 다수 세그먼트에 대한 적합성
  4. differentiation-vs-root-cause — 증상 완화가 아니라 근본 원인에 닿는 정도
  5. risk-and-reversibility — 실패 시 되돌리기 쉬운 정도
  - trade-off 명시: 4번(차별성·근본 원인 지향)과 2번(제약 내 실행 가능성)이 충돌할 수 있다. 이번 세션은 의뢰자가 제시한 하드 제약(3인월/6주/스택 고정)을 우선 게이트로 삼고, 그 안에서 차별성과 근본 원인 적합성을 비교한다.
- frame-status: approved

## 연구 컨텍스트

측정 모드 제약: 이번 세션은 WebSearch만 사용했고(WebFetch로 원문을 직접 열어 확인하지 않음), 각 통계치는 검색 엔진이 여러 링크를 종합해 생성한 요약에서 가져왔다. 특정 숫자가 정확히 어느 링크에서 나왔는지 1:1로 재확인하지 못한 경우가 많아, 개별 통계는 보수적으로 `unconfirmed`(단일/미확인 출처)로 분류했다. `independent-sources`는 검색 결과 목록에서 서로 다른 두 개 이상의 도메인이 같은 수치·범위를 각각 보도한 것으로 판단될 때만 2로 표시했다.

### RF-00
- topic: 요청자 제공 배경 수치(외부 미확인)
- content: 온보딩 완료율 34%(업계 평균 52%로 요청자 제시), 최초 로그인 후 7일 이내 이탈 58%, 3단계 데이터 연동 설정에서 28% 이탈.
- type: assumption (요청자가 제시한 배경 수치이며, 이번 세션이 독립적으로 검증하지 않음)
- source: 사용자 제공 픽스처 브리프
- confirmed-date: 2026-08-01
- independent-sources: 0 (외부 검증 안 함)

### RF-01
- topic: B2B SaaS 온보딩 완료율 업계 벤치마크
- content: 일반적인 B2B SaaS 온보딩 완료율은 40~60% 범위이며 60% 이상이 양호, 80% 이상이 우수로 평가됨. Userpilot의 2025년 62개 B2B SaaS 벤치마크 기준 평균 사용자 활성화율은 37.5%. 신규 가입 첫 세션의 이탈률은 일반적으로 30~50% 범위.
- type: fact (검색 결과에 명시적 수치로 등장, 다만 원문 직접 확인은 안 함)
- source: [B2B SaaS Funnel Conversion Benchmarks](https://userpilot.com/blog/b2b-saas-funnel-conversion-benchmarks/), [Benchmarking Your Onboarding: Industry Standards for 2026](https://www.adoptkit.com/posts/onboarding-benchmarks-industry-standards-2026)
- confirmed-date: 2026-08-01
- independent-sources: 2 (서로 다른 두 도메인이 유사 범위를 각각 보도)
- 참고: 요청자가 제시한 "업계 평균 52%"는 이 40~60% 범위 안에 들어 정성적으로 상충하지 않는다.

### RF-02
- topic: 데이터/기술 연동 단계가 온보딩 이탈의 대표적 병목
- content: 기술적 연동(트래킹 스니펫/SDK 설치 등)을 온보딩 중 요구하는 제품에서, 한 SaaS 팀 사례로 연동 설정 단계에서 사용자의 35%가 이탈한 것으로 언급됨. 연동은 가치 체감 이전에 요구되는 선행 조건이라 이탈 위험이 크다는 해석이 함께 제시됨.
- type: unconfirmed (구체 출처 1건, 사례성 수치이며 산업 전반 대표값인지 불명확)
- source: [12 User Onboarding Tools for SaaS](https://www.appcues.com/blog/user-onboarding-tools) 계열 검색 요약(정확한 원 출처 미특정)
- confirmed-date: 2026-08-01
- independent-sources: 1
- 참고: 요청자 제시 28%(RF-00)와 정성적으로 같은 방향(연동 단계가 병목)이지만 수치가 다르며, 이 세션은 두 수치를 상충 정보로 보존한다(하나를 임의 채택하지 않음).

### RF-03
- topic: 마일스톤 기반 온보딩과 7일차 이탈
- content: 마일스톤 기반 온보딩 구조가 Day 7 이탈을 28% 감소시켰다는 결과가 보고됨. 온보딩 완료 사용자는 미완료 사용자 대비 30일 이탈률이 약 2배 낮음.
- type: unconfirmed (단일 출처)
- source: [The Science of SaaS Onboarding](https://www.saasfactor.co/blogs/the-science-of-saas-onboarding-a-comprehensive-framework-for-reducing-friction-improving-activation-and-preventing-churn)
- confirmed-date: 2026-08-01
- independent-sources: 1

### RF-04
- topic: 전략적 휴먼 지원과 활성화율
- content: 온보딩 중 전략적 휴먼 지원을 제공받은 사용자는 활성화율이 40% 높고 90일 리텐션이 50% 더 좋다는 결과가 보고됨.
- type: unconfirmed (단일 출처)
- source: [SaaS User Activation: Proven Onboarding Strategies](https://www.saasfactor.co/blogs/saas-user-activation-proven-onboarding-strategies-to-increase-retention-and-mrr)
- confirmed-date: 2026-08-01
- independent-sources: 1

### RF-05
- topic: 시간-가치(Time-to-Value)와 행동 기반(실시간 신호) 온보딩
- content: 최초 가치 체감(아하 모먼트)까지 5분 이내인 경우 30일 리텐션이 15분 이상 소요 대비 40% 높음. 행동 기반 온보딩(주저·비활동·반복 실패 등 실시간 신호에 반응)이 고정 스케줄 방식보다 우수하다는 방향성이 제시됨. 20단계를 초과하는 흐름은 완료율을 30~50% 떨어뜨림.
- type: unconfirmed (단일 출처, 여러 수치가 한 기사에 묶여 보도됨)
- source: [SaaS Onboarding Flow: 10 Best Practices That Reduce Churn](https://designrevision.com/blog/saas-onboarding-best-practices)
- confirmed-date: 2026-08-01
- independent-sources: 1

## 로스터

서브에이전트 호출이 불가한 측정 세션이므로, 아래 6개 렌즈를 세션 책임자가 자신의 컨텍스트 안에서 **순차적으로** 수행했다. 각 렌즈는 role-prompts.md의 공통 생성자 brief 형식(역할/프레임/보호할 가치/관련 정보/전제/과업/금지/출력)을 따르되, 뒤 렌즈를 작성할 때 앞 렌즈의 산출물을 참조하지 않고 독립적으로 발산했다(진짜 독립 서브에이전트가 아니므로 완전한 인지적 격리는 보장할 수 없다는 한계를 명시함).

| 렌즈 | 초점 | 보호할 가치 |
|---|---|---|
| 사용자·고객 탐색자 | 비개발자 IT 담당자의 미충족 욕구·불안 | 기술 지식이 없어도 가치를 체감할 권리 |
| 도메인 유추자 | 기기 설정, 게임 튜토리얼, 여행 체크인 등 타 도메인의 작동 원리 | 표면적 카피가 아닌 구조적 유추 |
| 제약 전환자 | 3인월/6주/스택 고정을 설계 재료로 전환 | 제약을 무시하지 않고 오히려 활용 |
| 시스템 사고자 | 이메일·툴팁·CS·영업 등 행위자 간 피드백 루프 | 단일 화면 최적화에 매몰되지 않기 |
| 급진적 탐색자 | "온보딩 중 연동이 필수"라는 가정 자체를 뒤집기 | 충격만을 위한 아이디어 배제 |
| 실용적 조합자 | 기존 이메일·툴팁 컴포넌트 재사용, 단계적 접근 | 이미 있는 자산을 우선 활용 |

## 아이디어 풀

Brainwriting 6개 렌즈에서 각 3개씩 총 18개(IDEA-001~018) 발산 후, 주제가 기존 제품 개선형이므로(strategy-protocols.md 규칙에 따라 다양성 정체 여부와 무관하게) SCAMPER를 적용해 7개(IDEA-019~025)를 변환 생성했다. 총 25개.

### IDEA-001
- idea-id: IDEA-001
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: A
- idea: 3단계에서 실제 연동을 요구하기 전에, 샘플/데모 데이터로 채워진 "샌드박스 모드"를 먼저 보여줘 비개발자 IT 담당자가 실제 연동 없이도 제품 가치를 먼저 체감하게 한다.
- expected-value: 3단계 진입 시점의 기술적 위협감을 낮추고, 가치를 먼저 보여줌으로써 연동을 "선택"으로 재구성.
- novelty: medium (분석 도구 업계의 데모 환경 패턴과 유사 — RF-02 인접 사례)
- assumptions: 사용자가 실제 데이터 없는 데모를 가치 있다고 느낀다 / 데모 이후 실제 연동 전환율이 낮아지지 않는다.
- duplicate-of: none
- status: parked
- park-recondition: C-03(비순차 체크리스트) 검증에서 "이탈이 막힘 후 미복귀 패턴"이라는 결과가 나오지 않고, 오히려 "연동 자체에 대한 심리적 장벽"이 확인되면 재검토.
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-002
- idea-id: IDEA-002
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: B
- idea: "데이터를 연결하세요"라는 범용 안내 대신, 자주 쓰는 SMB 도구(예: 구글 워크스페이스, 회계 SW, 범용 CSV)를 자동 감지해 도구별 맞춤 가이드나 원클릭 흐름을 제공하는 역할 인지형 마법사.
- expected-value: "API 키", "웹훅" 같은 개발자 용어를 몰라도 되게 하여 비개발자의 인지 부담을 낮춤.
- novelty: medium
- assumptions: SMB 고객의 도구 사용이 소수의 흔한 도구에 집중되어 사전 매핑이 가능하다.
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-003
- idea-id: IDEA-003
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: C
- idea: 3단계에서 일정 시간 이상 멈춘 사용자에게 15분 내외의 예약형 라이브/비동기 화면공유 지원("컨시어지")을 제안해 함께 연동을 완료한다.
- expected-value: 현재는 이메일+툴팁뿐인데, 휴먼 지원 채널을 스톨 감지 시에만 트리거해 비개발자의 불안을 직접 해소.
- novelty: low-medium (CS 패턴 자체는 흔하지만 현재 온보딩에는 없음)
- assumptions: 스톨 감지 트리거 구현이 가능하고, 지원 인력 여력이 있다(운영 비용은 개발 예산과 별개).
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 전략적 휴먼 지원이 활성화율을 높인다는 외부 연구 존재(RF-04, 단일 출처, 미확인)
- independent-sources: 1

### IDEA-004
- idea-id: IDEA-004
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: B
- idea: 가정용 라우터·스마트홈 기기 설정 앱의 "단일 화면, 큰 버튼, 실시간 연결 상태(확인 중...연결됨!)" 패턴을 3단계 UI에 적용.
- expected-value: 비개발자에게 익숙한 정신 모델을 제공해 단계형 이탈을 줄임.
- novelty: medium
- assumptions: 연동 단계를 개별 검증 가능한 체크포인트로 쪼갤 수 있다.
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-005
- idea-id: IDEA-005
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: (미배정)
- idea: 게임 튜토리얼처럼, 가짜/샌드박스 자격증명으로 3단계 UI 조작을 먼저 "연습"하게 한 뒤 실제 자격증명으로 넘어가게 한다.
- expected-value: 실제 비즈니스 데이터로 "잘못할까 봐"의 불안을 낮춤.
- novelty: medium-high (IDEA-001과 유사하지만 "연습" 프레이밍이 다름)
- assumptions: 별도의 가짜 자격증명 처리 로직이 안전하게 구현 가능하다.
- duplicate-of: none
- status: eliminated
- park-recondition:
- elimination-reason: 가짜 자격증명 기반 연습 모드를 안전하게 구현하려면 인증/자격증명 처리 로직을 사실상 이중으로 구축해야 해 3인월/6주 제약을 구조적으로 초과할 가능성이 높고, 동일 가치(사전 체감)를 IDEA-001(읽기 전용 데모, 별도 자격증명 로직 불필요)이 더 낮은 비용으로 제공한다.
- core-fact: n/a
- independent-sources: 0

### IDEA-006
- idea-id: IDEA-006
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: A
- idea: 항공권/호텔 체크인의 "준비되면 이메일로 알려드릴게요" 패턴처럼, 3단계를 지금 완료하지 않고 다른 온보딩 단계로 넘어갔다가 나중에 다시 안내받을 수 있게 한다.
- expected-value: 3단계 정체가 온보딩 전체를 막지 않게 하여 7일 이내 이탈(58%)에도 영향.
- novelty: medium
- assumptions: 연동이 완료되지 않아도 다른 단계가 유의미한 가치를 준다.
- duplicate-of: none
- status: parked
- park-recondition: C-03(비순차 체크리스트) 검증이 승인되어 실제 실행 단계로 넘어갈 경우, 이메일 기반 비동기 리마인드 강화안으로 통합 검토.
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-007
- idea-id: IDEA-007
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: E
- idea: 새 모달/마법사 컴포넌트를 새로 만드는 대신 기존 툴팁 컴포넌트를 재사용해 "체크리스트 레일"(항상 보이는 사이드바 진행 목록)을 만든다.
- expected-value: 빌드 비용이 낮아 예산 제약에 맞고, 마일스톤 기반 온보딩 패턴을 저비용으로 적용.
- novelty: low (well-established 패턴)이지만 제약 적합도 높음
- assumptions: 체크리스트만으로도(흐름 전체 재설계 없이) 완료율·리텐션에 의미 있는 영향을 준다.
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 마일스톤 기반 온보딩이 Day 7 이탈을 28% 감소시켰다는 외부 연구 존재(RF-03, 단일 출처, 미확인)
- independent-sources: 1

### IDEA-008
- idea-id: IDEA-008
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: F
- idea: 새 백엔드 로직 없이, 3단계를 "노코드 데이터 연결 — 엔지니어가 아니라 IT 담당자를 위해 만들었습니다" 같은 카피/마이크로카피로 재프레이밍한다.
- expected-value: 근접 제로 비용으로 심리적/프레이밍 장벽을 낮춤.
- novelty: low (기술적으로) — 저비용 개입으로서의 위치가 특징
- assumptions: 현재 이탈의 일부가 순수 프레이밍/자신감 문제이지 능력 문제가 아니다.
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-009
- idea-id: IDEA-009
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: E
- idea: 전체 재설계 대신, 3단계 중간에 나간 사용자가 처음부터 다시 시작하지 않도록 "진행 상태 저장 + 재개" 기능만 최소로 구현한다.
- expected-value: "멈추고 돌아오지 않는" 실패 경로를 저비용으로 직접 겨냥.
- novelty: low
- assumptions: 이탈자 다수가 돌아올 의도는 있으나 재개 수단/리마인드 부재로 돌아오지 않는다(연동 자체를 거부하는 것이 아니다).
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-010
- idea-id: IDEA-010
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: D
- idea: 현재의 고정된 7단계 이메일 시퀀스 대신, 3단계 이탈이라는 실제 이벤트에 반응하는 분기형 시퀀스(1일차 "연동 도움이 필요하신가요?", 3일차 컨시어지 제안, 6일차 단순화된 대안 제시)로 교체.
- expected-value: 현재 시퀀스는 사용자가 실제로 어디서 멈췄는지와 무관하게 동일 메시지를 보냄 — 실제 병목(28% 이탈)을 겨냥한 메시지로 전환.
- novelty: medium (실시간 신호 기반 온보딩 — RF-05 방향성과 일치)
- assumptions: 현재 이메일/마케팅 인프라가 이벤트 기반 분기를 지원할 수 있다(브리프에 미확인).
- duplicate-of: none
- status: parked
- park-recondition: C-01 또는 C-03 실험이 승인되어 실제 구현으로 이어질 경우, 정적 이메일 시퀀스를 이벤트 기반 분기로 교체하는 후속 과제로 재검토.
- elimination-reason:
- core-fact: 실시간 행동 신호 기반 온보딩이 고정 스케줄 방식보다 우수하다는 방향성 언급(RF-05, 단일 출처, 미확인)
- independent-sources: 1

### IDEA-011
- idea-id: IDEA-011
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: C
- idea: SMB의 IT 담당자가 유일한 이해관계자가 아닐 수 있다는 점에 착안해, 3단계 연동 작업만 범위를 한정한 임시·만료형 초대 링크로 동료/외주 담당자에게 위임할 수 있게 한다.
- expected-value: 병목이 "비개발자가 개발자용 작업을 마주함"이라는 역할 불일치 문제라면, 작업을 UI로 쉽게 만드는 대신 수행 주체 자체를 바꿔 해결.
- novelty: medium-high
- assumptions: SMB IT 담당자에게 위임할 기술 인력(외주/벤더/동료)이 존재하거나 접근 가능하다 / 범위 한정 초대 메커니즘이 예산 내 구현 가능하다.
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-012
- idea-id: IDEA-012
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: F
- idea: 진행률 게이지를 작은 실질적 보상(연장된 체험판, 잠긴 리포트 해제 등)과 연결해 3단계를 통과할 인센티브를 시스템 차원에서 추가.
- expected-value: 저비용으로 빌드 가능한 인센티브형 넛지.
- novelty: low-medium
- assumptions: 외재적 보상이 이 B2B 페르소나(IT 담당자)의 행동을 의미 있게 바꾼다(소비자 게이미피케이션에서 차용한 가정, 미검증).
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-013
- idea-id: IDEA-013
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: A
- idea: 3단계 화면에 "지금은 건너뛰고 제한된 데모 모드로 보기" 버튼을 명시적으로 추가해(IDEA-001의 데모 개념과 UI 탈출구를 결합), 막힌 사용자가 완전히 이탈하지 않고 부분 가치라도 얻게 한다.
- expected-value: 3단계의 28% 완전 이탈을 "이탈하지 않는 대안 경로"로 직접 줄임.
- novelty: low (기존/타 아이디어의 조합)
- assumptions: 부분/데모 가치만으로도 완전 이탈보다 사용자를 붙잡을 만큼 매력적이다.
- duplicate-of: none
- status: parked
- park-recondition: C-03(비순차 체크리스트) 검증에서 "진행 허용만으로는 부족하다"는 결과가 나오면, 3단계에 명시적 건너뛰기 버튼을 추가하는 안으로 재검토.
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-014
- idea-id: IDEA-014
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: E
- idea: 기존 인앱 툴팁 3개와 이메일 시퀀스 7단계를 하나의 "진행 상태"로 통합해, 두 채널의 메시지가 사용자의 실제 진행 지점과 항상 일치하도록 한다.
- expected-value: 현재 두 시스템이 서로 다른 상태를 참조해 모순된 안내(이미 끝낸 단계를 다시 안내 등)를 줄 가능성을 제거.
- novelty: low
- assumptions: 툴팁과 이메일 시퀀스가 현재 서로의 상태를 인지하지 못한다(브리프에 미확인, 가정 C 참조).
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-015
- idea-id: IDEA-015
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: B
- idea: 기존 툴팁 컴포넌트를 재사용해 3단계 입력 필드 옆에 실시간 "연결 상태" 인디케이터(녹색/빨강)를 붙여, 전체 제출 후가 아니라 필드 단위로 즉시 피드백을 준다.
- expected-value: 시행착오형 이탈을 줄임 — 이미 연동에 필요한 검증 로직을 재사용.
- novelty: low-medium
- assumptions: 현재 3단계 UI는 필드별이 아니라 제출 시점에만 검증한다(미확인 가정).
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-016
- idea-id: IDEA-016
- parent-id: none
- strategy: Brainwriting
- lens: 급진적 탐색자
- cluster-ids: G (cross-ref A)
- idea: "데이터 연동은 온보딩 중에 끝나야 한다"는 전제를 뒤집어, 연동을 온보딩 완료 조건에서 완전히 제거하고 활성화 이후의 별도 라이프사이클 단계로 재정의한다.
- expected-value: 온보딩 단계의 가장 어려운 단계를 정의에서 제거해 완료율 지표를 직접적으로 개선.
- novelty: high
- assumptions: 실제 데이터 연동 없이도 도달 가능한 진짜 가치 마일스톤이 존재한다 / "완료"를 재정의해도 이탈이 더 늦은(측정 안 되는) 단계로 이동할 뿐이지 않다(핵심 위험 — dissent에서 재논의).
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-017
- idea-id: IDEA-017
- parent-id: none
- strategy: Brainwriting
- lens: 급진적 탐색자
- cluster-ids: (미배정)
- idea: 연동의 주체를 뒤집어, 고객이 직접 데이터를 연결하는 대신 영업/계약 단계에서 사전 협상한 읽기 전용 커넥터를 통해 제품팀(또는 자동화 에이전트)이 고객을 대신해 연결한다.
- expected-value: 비개발자 사용자에게서 기술적 단계를 완전히 제거.
- novelty: high
- assumptions: 영업/계약 단계에서 데이터 접근을 사전 협상하는 것이 조직적으로 가능하다.
- duplicate-of: none
- status: eliminated
- park-recondition:
- elimination-reason: React/Node 스택 유지 여부와 무관하게, 영업·계약 단계에서 커넥터를 사전 협상하는 조직적·법적 변경이 필요해 3인월 개발 예산과 6주 일정으로는 달성 불가능한 범위이며, 이번 세션에 주어진 제약(개발 예산·일정)이 다루는 대상(엔지니어링 산출물)을 벗어나는 조직적 의사결정 사안이다.
- core-fact: n/a
- independent-sources: 0

### IDEA-018
- idea-id: IDEA-018
- parent-id: none
- strategy: Brainwriting
- lens: 급진적 탐색자
- cluster-ids: E
- idea: 1→2→3 순차 구조 자체를 버리고, 데이터 연동을 여러 독립 작업 중 하나로 재구성해 사용자가 순서와 무관하게 쉬운 작업부터 먼저 완료하며 모멘텀을 쌓게 한다.
- expected-value: 3단계에서 멈추면 4~7단계 전체가 막히는 구조적 원인을 직접 해소.
- novelty: medium-high (구조적 전환)
- assumptions: 현재 온보딩이 엄격히 순차/게이트형이다(가정 B 참조) / 비순차 완료도 사용자에게 혼란을 주지 않는다.
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-019
- idea-id: IDEA-019
- parent-id: IDEA-003
- strategy: SCAMPER (Substitute)
- lens: 실용적 조합자(SCAMPER 변환)
- cluster-ids: C
- idea: 예약형 휴먼 컨시어지를 인앱에 내장된 AI 셋업 코파일럿(구조화된 트러블슈팅 스텝을 안내하는 챗 위젯)으로 대체 — 동일한 "함께 해결" 가치를 인력 확장 없이 제공.
- expected-value: 컨시어지 대비 인력 확장 비용 없이 유사 가치를 제공, 3인월 예산에 더 적합.
- novelty: medium
- assumptions: 구조화된 트러블슈팅으로 커버 가능한 문제 범위가 충분히 넓다(엣지 케이스는 여전히 실패할 수 있음).
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-020
- idea-id: IDEA-020
- parent-id: IDEA-007
- strategy: SCAMPER (Combine)
- lens: 제약 전환자 + 시스템 사고자(SCAMPER 결합, cross-ref IDEA-010)
- cluster-ids: D
- idea: IDEA-007의 상시 체크리스트 레일과 IDEA-010의 이벤트 기반 분기 로직을 결합해, 레일의 문구/CTA가 사용자가 멈춘 위치와 시간에 따라 동적으로 바뀌게 한다.
- expected-value: 정적 체크리스트보다 더 적시성 있는 넛지.
- novelty: medium
- assumptions: IDEA-010과 동일 — 이벤트 기반 트리거 인프라 존재 여부 미확인.
- duplicate-of: none
- status: parked
- park-recondition: IDEA-010과 동일 — 이벤트 기반 분기 인프라가 채택되면 체크리스트 레일과 결합한 동적 버전으로 재검토.
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-021
- idea-id: IDEA-021
- parent-id: IDEA-004
- strategy: SCAMPER (Adapt)
- lens: 도메인 유추자(SCAMPER 변환)
- cluster-ids: B
- idea: 기기 설정 마법사의 실시간 상태 패턴을 3단계의 기존 입력 필드에 그대로 이식 — 새 연동 로직 없이 기존 검증 호출을 재사용해 단일 컬럼 마법사로 화면만 재구성.
- expected-value: IDEA-004의 UX 개선을 기존 검증 로직 재사용으로 저비용화.
- novelty: medium
- assumptions: 기존 검증 호출이 필드 단위로 세분화하여 재사용 가능하다.
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-022
- idea-id: IDEA-022
- parent-id: IDEA-018
- strategy: SCAMPER (Modify — 축소)
- lens: 급진적 탐색자(SCAMPER 변환, 범위 축소)
- cluster-ids: E
- idea: 전체 7단계를 비순차 구조로 재설계하는 대신, 3단계 주변에서만 비순차 잠금 해제를 적용 — 3단계 미완료여도 4~7단계는 진행 가능하게 하는 최소 범위 버전.
- expected-value: IDEA-018과 같은 구조적 이점을 더 작은 구현 범위로, 6주 일정에 더 적합하게 확보.
- novelty: medium
- assumptions: 4~7단계가 3단계 완료 없이도 독립적으로 의미 있다.
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-023
- idea-id: IDEA-023
- parent-id: IDEA-015
- strategy: SCAMPER (Put to another use)
- lens: 실용적 조합자(SCAMPER 변환)
- cluster-ids: D
- idea: IDEA-015의 필드별 연결 상태 신호를 사용자에게만 보여주는 대신 내부 CS 대시보드에도 노출해, CS/영업이 3단계에 멈춘 계정을 실시간으로 파악하고 선제적으로 연락하게 한다.
- expected-value: 동일 신호를 재사용해 사용자 대면 UI 밖에서도 개입 지점을 만듦.
- novelty: medium
- assumptions: CS 조직이 이 신호에 기반해 선제 연락할 프로세스/여력이 있다(제품팀 예산과 별개의 조직적 전제).
- duplicate-of: none
- status: parked
- park-recondition: C-01의 필드별 실시간 검증(IDEA-015/021)이 구현되면, 동일 신호를 CS 대시보드로 노출하는 낮은 추가비용의 후속 과제로 재검토.
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-024
- idea-id: IDEA-024
- parent-id: IDEA-016
- strategy: SCAMPER (Eliminate)
- lens: 급진적 탐색자(SCAMPER 변환)
- cluster-ids: C
- idea: IDEA-016을 더 밀어붙여, 셀프서비스 연동 자체를 없애고 모든 신규 고객에게 필수 온보딩 콜을 통해 연동을 완전히 서비스로 위임한다.
- expected-value: 이론상 3단계 이탈을 구조적으로 제거.
- novelty: high
- assumptions: 모든 고객에게 확장 가능한 인력 운영이 가능하다.
- duplicate-of: none
- status: parked
- park-recondition: 리더십이 온보딩을 제품 UX 문제가 아니라 전담 인력을 배정하는 고객 성공 서비스 모델로 전환하기로 결정하면 재검토 — 그 전까지는 3인월 개발 예산이라는 제약의 성격(엔지니어링 범위) 밖.
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

### IDEA-025
- idea-id: IDEA-025
- parent-id: IDEA-008
- strategy: SCAMPER (Reverse)
- lens: 제약 전환자(SCAMPER 변환)
- cluster-ids: F
- idea: "우리에게 접근 권한이 필요합니다"라는 프레이밍을 뒤집어, 기본값은 "아무것도 공유되지 않음"으로 하고 사용자가 필드 단위로 명시적·철회 가능하게 접근을 부여하는 프라이버시 우선 프레이밍으로 전환.
- expected-value: 이탈 원인이 복잡성이 아니라 IT 담당자의 신뢰/보안 우려라면 이를 정면으로 겨냥.
- novelty: high
- assumptions: 28% 이탈이 복잡성이 아니라 신뢰/보안 우려에서 온다는, 브리프에 없는 미확인 전제를 이 아이디어가 도입한다 — 검증 필요.
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: n/a
- independent-sources: 0

## 군집

원본 아이디어는 보존하고, 해결 원리와 만들어내는 가치 기준으로 군집화했다.

### Cluster A — 연동 전에 가치를 먼저 보여주거나 우회
- 포함: IDEA-001, IDEA-006, IDEA-013 (cross-ref IDEA-016)
- 공통 가정: 연동을 완료하지 않아도 사용자가 의미 있는 가치를 체감할 수 있다.
- 차별점: 001은 읽기전용 데모, 006은 다른 단계로 우회 후 리마인드, 013은 명시적 건너뛰기 버튼.
- 미해결 질문: 부분 가치 체감이 실제 연동 완료율까지 끌어올리는지, 아니면 이탈을 뒤로 미루기만 하는지.

### Cluster B — 3단계 자체의 기술적 난이도를 낮추는 UI/UX 재설계
- 포함: IDEA-002, IDEA-004, IDEA-015, IDEA-021
- 공통 가정: 28% 이탈의 주된 원인은 기술적 복잡성이다(가정 A, 미검증).
- 차별점: 002는 도구 자동 감지, 004/021은 실시간 상태 UI, 015는 필드 단위 검증.
- 미해결 질문: 가정 A가 틀렸을 경우(원인이 신뢰/보안이라면, Cluster F 참조) 효과가 제한적일 수 있음.

### Cluster C — 기술 작업을 사람/AI에게 위임
- 포함: IDEA-003, IDEA-011, IDEA-019, IDEA-024
- 공통 가정: 병목은 능력/지식 격차이며, 수행 주체를 바꾸면 해소된다.
- 차별점: 003/019는 지원 채널(휴먼 vs AI), 011은 위임 대상 자체를 바꿈, 024는 서비스 전면 위임(운영 모델 변경, parked).
- 미해결 질문: 휴먼 지원의 운영 비용이 "3인월 개발 예산" 제약의 범위 안인지 밖인지 불명확.

### Cluster D — 정적 드립을 적응형·이벤트 기반 커뮤니케이션으로 전환
- 포함: IDEA-010, IDEA-020, IDEA-023
- 공통 가정: 현재 이메일/툴팁이 사용자의 실제 진행 상태에 반응하지 않는다(가정 C).
- 차별점: 010은 이메일 분기, 020은 UI 레일과 결합, 023은 사용자 대면이 아닌 내부 CS 신호.
- 미해결 질문: 현재 인프라가 이벤트 기반 트리거를 지원하는지 미확인.

### Cluster E — 온보딩 구조 자체의 재설계(순차→비순차, 상태 저장)
- 포함: IDEA-007, IDEA-009, IDEA-014, IDEA-018, IDEA-022
- 공통 가정: 이탈의 상당 부분은 순차 구조상 "한 곳에서 막히면 전체가 막힘"에서 온다(가정 B).
- 차별점: 007/009는 최소 변경(체크리스트 레일, 상태 저장), 014는 채널 간 일관성, 018/022는 구조 전체(018) 대 부분(022) 재설계.
- 미해결 질문: 구조 개선이 "완료를 미루는 것"에 그치고 최종 완료율 자체는 그대로일 위험(Cluster A와 동일한 위험 공유).

### Cluster F — 프레이밍·신뢰 장벽 해소(저비용 개입)
- 포함: IDEA-008, IDEA-012, IDEA-025
- 공통 가정: 이탈의 일부가 기술적 능력이 아니라 프레이밍/신뢰/동기의 문제다 — 브리프에 없는 세션 책임자 가설.
- 차별점: 008은 카피 재프레이밍, 012는 인센티브, 025는 권한 모델 자체를 프라이버시 우선으로 반전.
- 미해결 질문: 이 군집 전체가 딛고 있는 "원인=신뢰/프레이밍" 가설이 맞는지 자체가 미검증 — 다른 군집(B)과 상호 배타적 원인 가설일 수 있음.

### Cluster G — 온보딩 정의·연동 주체 자체를 재구성(급진적)
- 포함: IDEA-016 (cross-ref Cluster A), IDEA-017(eliminated)
- 공통 가정: 문제를 "3단계를 더 쉽게 만들기"가 아니라 "3단계가 온보딩에 있어야 하는가/누가 해야 하는가"로 재정의.
- 차별점: 016은 지표 재정의, 017은 연동 주체를 조직적으로 이전(제약 위반으로 제거됨).
- 미해결 질문: 지표(완료율) 개선과 실질 가치(7일 이탈 58%) 개선이 분리될 위험 — 지표 게이밍 우려.

## 숏리스트

방법론 메모: strategy-protocols.md는 "생성자 또는 별도 평가자가 각 후보를 독립적으로 평가"하도록 요구하나, 이번 측정 세션은 서브에이전트 호출이 불가해 세션 책임자 단일 평가로 대체했다(상태 블록 inconsistencies (1) 참조). 점수 차이·반대 근거는 단순 평균으로 숨기지 않고 dissent 필드에 그대로 남겼다. 서로 다른 가치 제안·위험 프로필을 가진 5개 후보를 선정했으며 단일 승자를 강제하지 않았다.

### Candidate C-01
- source-idea-ids: IDEA-002, IDEA-004, IDEA-015, IDEA-021
- value-proposition: 3단계 자체를 비개발자가 이해 가능한 단일 화면 마법사로 재구성 — 흔한 SMB 툴 자동 감지 + 필드별 실시간 검증으로 기술적 난이도 자체를 낮춘다.
- requester-value-fit: 28% 이탈의 직접 원인이 "복잡성"이라는 가정(A)이 맞다면 적합도 매우 높음.
- differentiation: 대부분 기존 컴포넌트/검증 로직 재사용 — 기술적 새로움은 낮지만 실행 확실성이 높음.
- learning-value: 이탈 원인이 복잡성인지 실험으로 가려낼 수 있음.
- key-risks: 자동 감지가 커버하지 못하는 롱테일 도구 존재 시 효과 제한 / 역할 인지형 마법사 전체 구현 범위가 3인월을 초과할 수 있음(축소 필요 가능).
- evidence-level: 간접(도메인 유추, RF 직접 근거는 약함).
- dissent: 이 후보는 가정 A(원인=복잡성)에 크게 의존한다. 만약 실제 원인이 신뢰/보안(Cluster F 가설)이라면 효과가 제한적일 수 있다는 반대 근거를 병기한다.
- validation-priority: high

### Candidate C-02
- source-idea-ids: IDEA-003, IDEA-011, IDEA-019
- value-proposition: 사용자가 직접 해결하기 어려운 경우, 저비용 AI 코파일럿 또는 스톨 감지 시에만 트리거되는 예약형 휴먼 컨시어지로 3단계를 함께/대신 완료하도록 돕는다.
- requester-value-fit: 비개발자 세그먼트의 핵심 장벽(지식 격차)을 직접 해소 — 적합도 높음.
- differentiation: 현재 이메일+툴팁에는 없는 실시간/양방향 지원 채널 — 차별성 높음.
- learning-value: "도움이 있으면 완료율이 오르는가"를 검증하면 향후 지원 채널 투자 우선순위를 정할 수 있음.
- key-risks: 휴먼 컨시어지의 운영(ops) 인력 비용이 "3인월 개발 예산"의 성격(엔지니어링) 밖일 수 있음(플래그) / AI 코파일럿은 오응답 리스크.
- evidence-level: RF-04(단일 출처, 미확인)만 뒷받침.
- dissent: 휴먼 컨시어지 부분은 6주 일정·개발 예산 프레임과 맞지 않을 수 있다는 반대 의견 — AI 코파일럿(IDEA-019)만 남기는 축소안이 더 현실적이라는 의견을 병기.
- validation-priority: medium (AI 코파일럿 부분 우선)

### Candidate C-03
- source-idea-ids: IDEA-007, IDEA-009, IDEA-014, IDEA-018, IDEA-022
- value-proposition: 3단계를 온보딩의 유일한 관문으로 두지 않고 다른 단계를 먼저/병행 진행할 수 있게 하며, 중단 지점을 저장해 재개 가능하게 한다. 이메일·툴팁의 상태 불일치도 함께 정리.
- requester-value-fit: "막힘 후 이탈"이라는 관찰(28%)을 구조적으로 우회 — 적합도 높음, 특히 7일 이내 58% 이탈에도 기여 가능(다른 단계에서 계속 가치 체감).
- differentiation: 기술적 새로움은 낮지만 기존 컴포넌트 재사용도가 가장 높아 6주/3인월 제약에 가장 잘 맞음.
- learning-value: "이탈이 순차 구조 자체 때문인가"를 검증하는 저비용 실험.
- key-risks: 근본 원인(3단계 자체의 어려움)은 해결하지 못하고 지연시킬 뿐일 수 있다는 반대 근거 — 최종 완료율 개선으로 이어지지 않을 위험.
- evidence-level: RF-03(단일 출처, 미확인)만 뒷받침.
- dissent: C-01(기술 난이도 직접 해소)과 병행하지 않으면 "완료를 미루는 것일 뿐 완료율 자체는 그대로"라는 강한 반대 의견.
- validation-priority: high (가장 저비용·저리스크 — 빠른 실험 우선순위 후보)

### Candidate C-04
- source-idea-ids: IDEA-008, IDEA-012, IDEA-025
- value-proposition: 이탈 원인이 기술적 복잡성이 아니라 데이터 접근권한에 대한 신뢰/보안 우려일 가능성을 정면으로 다뤄, 카피·권한 모델(필드별 선택적 연동)·진행 인센티브로 대응하는 거의 순수 카피/프레이밍 수준의 최저비용 개입.
- requester-value-fit: 가설이 맞다면 파급력 큼(근본 원인 해결), 틀리면 효과 거의 없음 — 조건부 적합.
- differentiation: 브리프에 없는 새로운 원인 가설을 제시 — 차별성 매우 높음.
- learning-value: 매우 높음 — 최저비용으로 "원인이 신뢰인가 복잡성인가"를 가르는 실험이 가능하며, 이는 C-01/C-02/C-03의 우선순위 자체에 영향을 줄 수 있는 정보.
- key-risks: 가설이 틀리면 자원 낭비는 적지만(카피 수준) 시간 낭비 가능 / 필드별 선택적 연동 권한 모델(IDEA-025)은 백엔드 변경이 필요할 수 있어 "카피만"이라는 전제가 깨질 위험.
- evidence-level: 브리프 자체에 이 가설을 뒷받침하거나 반박하는 직접 증거 없음 — 순수 미확인 가설.
- dissent: 이탈 원인 가설 자체가 브리프에 없는 세션 책임자의 추정이라는 점을 명확한 반대 근거로 남긴다 — 검증 없이 채택 금지.
- validation-priority: high (다른 후보들의 우선순위를 좌우할 수 있는 정보이므로 최우선 검증 대상)

### Candidate C-05
- source-idea-ids: IDEA-016
- value-proposition: "온보딩 완료"의 정의 자체를 재설계해 데이터 연동을 완료 조건에서 제거하고, 연동은 활성화 이후 별도 라이프사이클 단계로 이동.
- requester-value-fit: 온보딩 완료율(34%) 지표는 개선되지만, 실제 제품 가치(데이터 연동) 체감은 지연될 뿐 — 지표 개선과 실질 가치 개선이 괴리될 위험이 크다.
- differentiation: 가장 급진적 — 문제 정의 자체를 바꿈.
- learning-value: "완료"의 정의가 무엇이어야 하는가에 대한 의뢰자 판단이 필요 — 통상적 실험보다 의사결정 이슈에 가까움.
- key-risks: 지표 게이밍(metric gaming) 비판 가능 — 완료율은 오르지만 7일 이탈(58%)이나 실제 활성화는 개선되지 않거나 악화될 수 있음.
- evidence-level: 근거 없음 — 순수 구조적 제안.
- dissent: "완료율을 올리는 것"과 "이탈을 줄이는 것"은 다른 목표이며, 이 후보는 전자만 만족시키고 후자는 악화시킬 수도 있다는 강한 우려.
- validation-priority: low (실험보다 의뢰자 의사결정이 선행되어야 함 — 최종 보고에서 별도 플래그)

## 검증 계획

**해석 메모(상태 블록 inconsistencies (2) 참조):** 측정 모드 지시는 프레이밍/프레임 승인과 함께 "검증 계획 승인"도 픽스처로 사전 승인된 것으로 간주하라고 하면서도, 동시에 "실험은 실행하지 않는다(validation_approval 상태에서 종료)"라고 명시한다. 이 세션은 SKILL.md의 `validation_approval` 상태 정의("검증 계획 섹션을 다시 제시하고 승인 또는 수정만 요청")를 그대로 유지해, 아래 실험은 모두 `approval-status: proposed`로 기록하고 `validation-approved-at`은 비워둔다. 즉 계획은 완성해 제시하되, 승인 여부는 의뢰자의 다음 결정으로 남긴다. 모든 승인-유형(approved-type)은 research·agent-critique·document로만 한정했다 — 실제 사용자 대상 배포나 코드 구현은 애초에 제안하지 않는다.

리서치 프로토콜에 따라 "가장 위험하고 결과를 바꿀 가정부터" 순서를 매겼다. C-04(E-01)는 다른 모든 후보의 우선순위 자체를 좌우할 수 있는 정보이므로 최우선으로 배치했다.

### Experiment E-01
- candidate-id: C-04
- assumption: 3단계 28% 이탈의 주요 원인이 기술적 복잡성이 아니라 데이터 접근권한에 대한 신뢰/보안 우려이다.
- approved-type: research
- method: 상세 2차 리서치(B2B SaaS 데이터 연동 시 보안/컴플라이언스 우려 관련 문헌) + 기존 CS 티켓·이탈 사용자 피드백 등 1차 정성 데이터가 있다면 그 검토 계획을 문서화(실제 접근·실행은 별도 조직 승인 필요, 이번 실험은 계획·2차 자료 검토까지).
- success-signal: 신뢰/보안 관련 언급이 이탈 사용자 피드백에서 상당한 비중을 차지한다는 근거가 확인됨.
- stop-condition: 1차 데이터(CS 티켓, 설문) 접근이 불가능하면 외부 2차 자료만으로 결론 내리지 않고 "미확인"으로 보고를 종료한다.
- estimated-cost: 리서치 담당 약 2일.
- approval-status: proposed

### Experiment E-02
- candidate-id: C-03
- assumption: 이탈 사용자 다수가 3단계에서 완전히 포기하는 것이 아니라 "중단 후 미복귀" 패턴이다(진행 저장/재개 기능으로 구제 가능).
- approved-type: research
- method: 기존 제품 애널리틱스(재방문율, 3단계 재시도 여부)를 검토하기 위한 분석 설계 문서화. 실제 로그 접근은 실행 조직의 별도 승인이 필요하므로 이번 실험은 분석 설계·질문 정의까지.
- success-signal: 이탈 사용자 중 일정 비율이 이후 세션에서 재방문했으나 3단계를 재시도하지 않은 패턴이 확인됨.
- stop-condition: 로그 데이터 접근이 불가능하면 가정을 미검증 상태로 유지하고 실험을 보류한다.
- estimated-cost: 분석 설계 약 1~2일.
- approval-status: proposed

### Experiment E-03
- candidate-id: C-01
- assumption: SMB 고객의 데이터 연동 도구 구성이 소수의 일반적 툴로 충분히 커버 가능하다.
- approved-type: research
- method: 외부 2차 자료(SMB 도구 사용 벤치마크) + 내부 고객사 도구 사용 현황 문서 검토 계획(실 접근은 조직 승인 필요).
- success-signal: 상위 N개 도구가 고객 기반의 상당 비율을 커버한다는 근거 확인.
- stop-condition: 도구 파편화가 심해 소수 도구로 커버 불가로 판단되면 마법사 범위를 축소해야 한다는 결론으로 종료한다.
- estimated-cost: 리서치 약 1~2일.
- approval-status: proposed

### Experiment E-04
- candidate-id: C-02
- assumption: AI 코파일럿(구조화된 챗봇형 가이드)이 휴먼 컨시어지 없이도 3단계 완료에 실질적 도움을 줄 수 있다.
- approved-type: agent-critique
- method: 비판자 역할의 별도 에이전트/검토를 통해 이 후보의 실행 가능성과 실패 시나리오(엣지 케이스, 3인월 내 구현 범위 현실성 등)를 공격적으로 검토한다. 아이디어를 임의 삭제하거나 범위 밖 실행을 제안하지 않는다.
- success-signal: 명확한 실패 경로 목록과 각각의 완화책이 도출됨.
- stop-condition: 해당 없음(비판 세션은 항상 완료 가능한 유형).
- estimated-cost: 낮음(비판 세션 1회).
- approval-status: proposed

### Experiment E-05
- candidate-id: C-05
- assumption: "온보딩 완료" 정의에서 데이터 연동을 제외해도 실제 활성화·리텐션 지표(특히 7일 이내 이탈 58%)가 악화되지 않는다.
- approved-type: document
- method: 지표 재정의가 초래할 수 있는 지표 게이밍 리스크와 대안 지표(예: 연동 완료와 무관한 "실질 활성화" 지표 신설)를 정리한 의사결정 메모를 작성한다. 실험이라기보다 의뢰자 의사결정을 위한 브리핑 문서.
- success-signal: 해당 없음 — 의뢰자 판단이 필요한 항목으로 최종 보고에서 별도 플래그.
- stop-condition: 해당 없음.
- estimated-cost: 낮음(문서 작성 약 반나절).
- approval-status: proposed

## 실험

(비어 있음 — `validation_approval` 상태에서 세션을 종료했으며, 검증 계획 승인 전이므로 실험을 실행하지 않았다.)

## 최종 보고

(비어 있음 — 이 세션은 `validation_approval` 상태에서 종료되었다. 최종 보고는 검증 계획 승인 및 `validating` 단계 완료 이후 작성된다.)
