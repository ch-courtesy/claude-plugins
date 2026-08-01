# Brainstorm Session: 20260801-onboarding-dropout-b4

## 상태
- session-id: 20260801-onboarding-dropout-b4
- state: validation_approval
- updated-at: 2026-08-01
- frame-approved-at: 2026-08-01 (픽스처 브리프 사전 승인 — 측정 세션, AskUserQuestion 미사용)
- validation-approved-at: 2026-08-01 (픽스처 브리프 사전 승인 — 측정 세션, AskUserQuestion 미사용)
- agent-calls-used: 0 (측정 모드: 서브에이전트 호출 불가 환경. Agent 대신 세션 책임자가 5개 아이디어 생성자 렌즈를 컨텍스트 내에서 순차·독립 수행)
- research-calls-used: 8 (WebSearch 8회 — 최소 중앙 리서치 단계)
- completed-sections: 브리프, 연구 컨텍스트, 로스터, 아이디어 풀, 군집, 숏리스트, 검증 계획
- next-action: 승인된 실험 E-01~E-04 실행(다음 세션에서 수행 — 이번 측정 세션은 검증 계획 작성까지만 수행하고 실험은 실행하지 않음)
- inconsistencies: 없음. (측정 모드 조정 사항: 프레이밍 인터뷰·프레임 승인·검증 계획 승인은 픽스처 브리프로 사전 승인 처리, AskUserQuestion 미사용. 아이디어 생성자는 Agent 서브에이전트 대신 세션 책임자가 순차 수행하되 각 렌즈의 발산은 다른 렌즈 결과를 참조하지 않고 독립적으로 작성함.)

## 브리프

- session-id: 20260801-onboarding-dropout-b4
- requester: 픽스처 브리프 제공자 (측정 세션)
- problem-or-opportunity: B2B SaaS 신규 사용자 온보딩 완료율이 34%로 업계 평균 52% 대비 낮고, 최초 로그인 후 7일 이내 58%가 이탈한다. 3단계 데이터 연동 설정에서 28%가 이탈해 단일 최대 병목으로 나타난다.
- target: 중소기업(SMB) IT 담당자 — 다수가 비개발자로 API 키·연동 설정 등 기술 개념에 익숙하지 않음
- requester-value: 온보딩 완료율과 7일 잔존율을 높여 초기 이탈 감소·유료 전환 기반 확대
- how-might-we: 비개발자인 SMB IT 담당자가 데이터 연동 설정을 포함한 온보딩을, 6주·3인월 제약 안에서 어떻게 이탈 없이 완료하고 초기 가치를 경험하게 할 수 있을까?
- scope: 가입 완료~온보딩 7단계 전체 및 최초 7일 리텐션에 영향을 주는 제품 내 UX, 이메일/인앱 커뮤니케이션, 프로세스 변경. 기존 React+Node.js 스택 내에서 구현 가능한 범위.
- out-of-scope: 백엔드 아키텍처 재설계, 신규 언어/프레임워크 도입, 가격·영업 정책 변경, 3단계 이후 심화 기능 온보딩, 온보딩 이탈 데이터의 온보딩 프로젝트 외 활용(예: 향후 제품 로드맵 의사결정)
- constraints: 개발 예산 3인월 이하 / 6주 이내 출시 / React+Node.js 스택 변경 불가 / 대상 사용자 다수가 비개발자
- existing-attempts: 이메일 시퀀스 7단계 + 인앱 툴팁 3개 — 현재 운영 중이나 완료율 34%로 업계 평균 미달, 3단계 데이터 연동에서 28% 집중 이탈 지속
- assumptions: (1) 3단계 데이터 연동 설정의 기술적 복잡성이 이탈의 핵심 원인이라는 가정 — 미확인. 연동 자체의 난이도인지, 자격 증명 오류 등 실패인지, 단순 동기 부족인지 구분되지 않음. (2) 이메일 시퀀스·툴팁의 낮은 참여도가 아니라 연동 단계 자체의 난이도가 문제라는 가정 — 미확인.
- success-signals: 온보딩 완료율 34% → 업계 평균 52% 근접 이상 / 최초 로그인 후 7일 이내 이탈률 58% 감소 / 3단계 이탈률 28%의 유의미한 감소
- evaluation-criteria: 1순위 이탈률·완료율 개선 기여도(의뢰자 핵심 가치) / 2순위 3인월·6주 제약 내 구현 가능성 / 3순위 비개발자 사용성 적합도 / 4순위 기존 React+Node 스택 호환성. 임팩트가 크지만 예산·일정을 초과하는 아이디어는 탈락시키지 않고 단계적 구현 옵션 또는 parked로 표시해 trade-off를 보존한다.
- frame-status: approved

## 연구 컨텍스트

**용어·현재 상태**
- [사실] B2B SaaS 온보딩 완료율 업계 벤치마크는 출처마다 40–60%(평균) / 60–70%(양호) / 70–80%+(상위권)로 표기되며 서로 다른 임계값을 병기함 — 상충 정보를 하나로 임의 확정하지 않고 병기. 출처: dock.us "Customer Onboarding Metrics", productgrowth.in "SaaS Onboarding Benchmarks 2026". 확인일: 2026-08-01.
- [해석] 위와 별개로 "활성화율(activation rate)"은 완료율과 다른 지표로, B2B SaaS 평균 37.5%/중앙값 37% 수준으로 보고됨(Userpilot 2024 리포트, 62개 B2B SaaS 대상). 브리프의 "완료율 34%"가 이 활성화율 정의와 동일한지는 미확인 — 지표 정의 불일치 가능성을 열어둠. 출처: getmonetizely.com, dock.us. 확인일: 2026-08-01.
- [미확인] 3단계 데이터 연동 이탈의 근본 원인(연동 개념 이해 부족 vs 자격 증명/기술 오류 vs 동기 부족)은 외부 자료로 확인 불가 — 세션 내 가정으로만 존재.

**제약·안전/법적 금지선**
- [사실] 제약(3인월/6주/React+Node.js 유지/비개발자 세그먼트)은 브리프에서 직접 확정됨. 추가 안전·법적 금지선은 브리프에 명시되지 않음.

**기존 시도 관련 최소 배경 및 유사 사례**
- [사실/해석 혼재, 미확인 다수] 수동 입력 필드 1개당 온보딩 완료율이 5–7% 감소한다는 주장 — 출처 1개(truto.one)만 확인, 1차 연구 인용 없음 → 미확인으로 취급, 단일 출처. 확인일: 2026-08-01.
- [해석] 3단계 온보딩 투어는 72% 완료, 7단계 투어는 16%로 급락한다는 통계 — 출처 1개(digitalapplied.com)만 확인, 1차 연구 인용 없음 → 미확인, 현재 온보딩의 "이메일 7단계" 구조와 관련될 수 있음. 확인일: 2026-08-01.
- [해석] 진행률 바·체크리스트가 완료율을 최대 40%까지, 게이미피케이션 요소가 최대 50% 더 높은 완료율을 낸다는 주장 — 서로 다른 도메인 3곳(userpilot.com, strivecloud.io, uxcam.com)에서 유사 수치가 반복되나, "Stanford Persuasive Technology Lab" 언급이 1차 출처 링크 없이 재인용되어 동일 원출처를 재인용했을 가능성을 배제할 수 없음 — 독립성에 주의. 확인일: 2026-08-01.
- [사실] 사전 구축 커넥터는 커스텀 API 개발 대비 연동 소요 시간을 80–90% 단축한다는 주장 — 서로 다른 도메인 2곳(softsuave.com, saber.app)에서 확인. 확인일: 2026-08-01.
- [해석] 라이브챗·인앱 proactive 메시지가 온보딩 정체 시점 이탈 감소에 활용된다는 주장 — 도메인 2곳(chameleon.io, gleap.io)에서 확인되나 두 출처 모두 라이브챗/온보딩 툴 벤더로 이해상충 가능성이 있음 — 효과 크기가 과장되었을 수 있음에 주의. 확인일: 2026-08-01.
- [해석] 기술적 전제조건이 있는 온보딩에서는 그 전제조건 이전에 가치를 먼저 경험시키는 방식(Stripe의 샌드박스 테스트 결제 예시)이 채택된다 — 출처 1개(navattic.com)의 단일 사례, 정량 효과 크기 미확인. 확인일: 2026-08-01.
- [해석] 화이트글러브/콜 기반 온보딩은 통상 연 계약 규모(ACV) 약 1.5만 달러 이상 세그먼트에서 비용이 정당화되고, 그 미만은 셀프서브·자동화가 지배적이라는 관찰 — 본 세션의 SMB 세그먼트가 이 임계선 아래에 있을 가능성이 있어, 화상콜 기반 아이디어(사람 개입)에 대한 잠재적 반증으로 취급. 출처: digitalapplied.com. 확인일: 2026-08-01.
- [사실] 개인화된 온보딩이 일반형 대비 잔존율을 40% 높인다는 주장 — 출처 1개(designrevision.com)만 확인, 미확인으로 취급. 확인일: 2026-08-01.

**리서치 컨텍스트 총평(주의사항)**
검색된 출처 다수가 1차 연구·데이터를 직접 인용하지 않는 마케팅/제품 블로그이며, 동일 통계가 여러 블로그에 재인용되는 경우가 많아 "서로 다른 도메인"이더라도 진짜 독립 출처인지 확신할 수 없다. 이 불확실성은 각 독립 출처 수 판단에 보수적으로 반영했다(동일 1차 연구 재인용 의심 시 낮게 카운트). 반증 증거는 화이트글러브 임계선 관찰(SMB 세그먼트에 사람 개입 모델이 맞지 않을 수 있음) 외에는 적극적으로 발견되지 않았다 — 추가 반증 탐색은 후속 상세 검증(2단계) 대상이다.

## 로스터

측정 모드 조정: Agent 서브에이전트 호출이 불가능한 환경이므로, 아래 5개 아이디어 생성자 렌즈를 세션 책임자가 컨텍스트 내에서 **순차적으로, 각 렌즈가 다른 렌즈의 산출물을 참조하지 않고 독립적으로** 수행했다(Brainwriting의 독립 발산 원칙 준수).

- 사용자·고객 탐색자 — 비개발자 IT 담당자의 미충족 욕구·접근성 관점
- 도메인 유추자 — 의료 접수, 제조/조립, 항공 셀프체크인, 오픈소스 설치 경험에서 원리 차용
- 제약 전환자 — 3인월/6주/스택 고정/비개발자 세그먼트라는 제약 자체를 설계 재료로 전환
- 시스템 사고자 — 이메일·인앱·CS·제품팀 간 피드백 루프와 인센티브 구조
- 실용적 조합자 — 기존 이메일 7단계·툴팁 3개 자산의 재조합과 단계적 접근

**선택 근거**: 주제가 급진적 신사업 발굴이 아니라 기존 온보딩 퍼널의 명확한 병목(3단계, 28% 이탈)을 다루는 개선형 문제이므로, 6번째 렌즈인 급진적 탐색자(가정 뒤집기, 비연속 대안)는 별도 생성자로 두지 않고 대신 전략 프로토콜에 따라 **SCAMPER의 Reverse/Eliminate**로 급진성을 보완했다(아래 전략과 변환 참고). 개선형 주제라는 조건 자체가 SCAMPER 적용 사유이므로, 다양성 정체 여부와 무관하게 발산 후 SCAMPER를 수행했다.

## 아이디어 풀

### IDEA-001
- idea-id: IDEA-001
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: CL-A
- idea: 비개발자 친화 "연동 마법사" — 자연어/드롭다운 기반 단계별 연동 설정, API 키·토큰 등 기술 용어를 담당자 눈높이 언어로 치환하고 단계별 진행 상황을 표시한다.
- expected-value: 3단계 이탈(28%)을 직접 겨냥한 완료율 개선
- novelty: 낮음(업계 관행형이나 현재 미적용)
- assumptions: 기술 용어 자체가 이탈 유발 요인이라는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 수동 입력 필드 1개당 온보딩 완료율이 5~7% 감소한다는 관찰이 있다
- independent-sources: 1

### IDEA-002
- idea-id: IDEA-002
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: CL-B
- idea: "연동 없이도 먼저 가치 보기" — 샘플/데모 데이터로 3단계 이전에 핵심 가치(리포트, 대시보드 등)를 미리 체험시키고, 실제 데이터 연동은 이후 단계로 재배치한다.
- expected-value: 초기 동기 부여로 7일 이내 이탈(58%) 완화
- novelty: 중간
- assumptions: 가치를 먼저 보여주면 이후 연동을 완료할 동기가 높아진다는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 기술적 전제조건이 있는 온보딩에서는 그 전제조건 이전에 가치를 먼저 경험시키는 방식(예: Stripe 샌드박스 결제)이 실무에서 채택된다
- independent-sources: 1

### IDEA-003
- idea-id: IDEA-003
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: CL-C
- idea: 3단계에서 일정 시간 정체가 감지되면 인앱 실시간 채팅/콜백 요청 버튼을 proactive하게 노출한다.
- expected-value: 자동화로 못 줄이는 이탈을 사람 개입으로 구제
- novelty: 낮음
- assumptions: 정체 시점에 도움을 요청할 의향이 있다는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 인앱 라이브챗과 정체 시점 proactive 메시지가 온보딩 이탈 감소에 활용된다
- independent-sources: 2

### IDEA-004
- idea-id: IDEA-004
- parent-id: none
- strategy: Brainwriting
- lens: 사용자·고객 탐색자
- cluster-ids: CL-D
- idea: 비개발자를 위한 짧은 스크린캐스트 가이드 영상을 3단계 화면 옆에 임베드한다.
- expected-value: 낮은 구현 비용으로 이해도 보완
- novelty: 낮음
- assumptions: 영상이 텍스트 툴팁보다 이해도를 높인다는 가정
- duplicate-of: none
- status: parked
- park-recondition: C-04(콘텐츠 재배치) 실행 후 3단계 이탈률 개선이 목표치에 미달하면 영상 가이드 추가를 재검토한다
- elimination-reason:
- core-fact: 없음(직접 근거 미발견, 관찰 기반 추론)
- independent-sources: 0

### IDEA-005
- idea-id: IDEA-005
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: CL-G
- idea: 병원 "사전 문진표" 유추 — 연동에 필요한 계정 정보·자격 증명을 온보딩 세션 이전에 이메일로 미리 수집해 3단계 체류 시간을 단축한다.
- expected-value: 3단계 실시간 체류 시간·마찰 감소
- novelty: 중간
- assumptions: 사용자가 사전 이메일 요청에 응답해 정보를 미리 준비할 것이라는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 없음(직접 근거 미발견, 유추 기반)
- independent-sources: 0

### IDEA-006
- idea-id: IDEA-006
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: CL-D, CL-A(교차 참조)
- idea: 이케아 조립 설명서 유추 — 연동 단계를 텍스트 최소화, 그림/아이콘 중심의 순차적 "조립식" 체크리스트로 재설계한다.
- expected-value: 비개발자의 시각적 이해도 향상
- novelty: 중간
- assumptions: 시각적 단계 표현이 텍스트 설명보다 이해하기 쉽다는 가정
- duplicate-of: none
- status: transformed
- park-recondition:
- elimination-reason:
- core-fact: 없음(직접 근거 미발견, 유추 기반) — IDEA-025로 결합·변환되어 C-01에 편입, 원본은 단독 채택하지 않음
- independent-sources: 0

### IDEA-007
- idea-id: IDEA-007
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: CL-C
- idea: 항공사 셀프 체크인 카운터 옆 "도움 데스크" 유추 — 셀프서비스 연동 실패 시 즉시 사람에게 넘기는 에스컬레이션 경로(콜백 예약)를 둔다.
- expected-value: 셀프서브 실패의 구제 경로 확보
- novelty: 낮음
- assumptions: 실패 시점에 즉시 에스컬레이션 경로가 노출되면 이탈 대신 전환된다는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 없음(직접 근거 미발견, 유추 기반)
- independent-sources: 0

### IDEA-008
- idea-id: IDEA-008
- parent-id: none
- strategy: Brainwriting
- lens: 도메인 유추자
- cluster-ids: CL-A
- idea: 오픈소스 프로젝트 "quick start vs advanced install" 유추 — 온보딩을 표준 경로(사전 구성 템플릿 연동)와 커스텀 경로로 분기해 비개발자는 표준 경로로 유도한다.
- expected-value: 다수(비개발자)를 위한 저마찰 표준 경로 제공
- novelty: 중간
- assumptions: 대부분의 SMB 고객이 표준 연동 대상 시스템을 사용한다는 가정
- duplicate-of: none
- status: parked
- park-recondition: C-01(연동 마법사) 실행 후 단일 간소화 경로만으로 이탈률 개선이 부족하면 표준/커스텀 경로 분기를 재검토한다
- elimination-reason:
- core-fact: 없음(직접 근거 미발견, 유추 기반)
- independent-sources: 0

### IDEA-009
- idea-id: IDEA-009
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: CL-A
- idea: React+Node 변경 불가 제약을 자산으로 삼아, 기존 프론트엔드에 단계별 진행 상태 저장(자동 재개) 기능만 추가해 이탈 후 재방문 시 처음부터 다시 시작하지 않도록 한다.
- expected-value: 재방문 이탈 감소, 적은 개발 공수
- novelty: 낮음
- assumptions: 반복 이탈의 상당 부분이 "처음부터 다시 시작해야 하는 부담" 때문이라는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 없음(직접 근거 미발견, 논리적 추론)
- independent-sources: 0

### IDEA-010
- idea-id: IDEA-010
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: CL-D
- idea: "3인월 이하" 제약을 활용해 신규 개발 대신 기존 인앱 툴팁 3개를 3단계 직전·도중에 재배치하고 문구만 재작성하는 저비용 카피 개선을 한다.
- expected-value: 매우 낮은 비용으로 빠른 개선
- novelty: 낮음
- assumptions: 현재 툴팁 위치·문구가 이탈에 기여한다는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 없음(직접 근거 미발견)
- independent-sources: 0

### IDEA-011
- idea-id: IDEA-011
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: CL-C
- idea: "6주 이내" 제약을 활용해 정식 기능 개발 대신, 3단계 도달 고객에게 자동 이메일 + 캘린더 링크로 15분 화상 셋업 콜을 제안한다(신규 코드 거의 없음).
- expected-value: 코드 개발 없이 빠르게 실행 가능한 구제책
- novelty: 낮음
- assumptions: SMB 비개발자 고객이 화상 콜 제안에 응할 것이라는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 화이트글러브/콜 기반 온보딩은 통상 연 계약 규모 약 1.5만 달러 이상에서 비용이 정당화되고 그 미만은 셀프서브가 지배적이라는 관찰이 있어, SMB 세그먼트에는 반증적일 수 있다
- independent-sources: 1

### IDEA-012
- idea-id: IDEA-012
- parent-id: none
- strategy: Brainwriting
- lens: 제약 전환자
- cluster-ids: CL-A
- idea: "비개발자 다수" 제약을 역으로 활용해, API 키를 요구하지 않는 대체 연동 경로(CSV 업로드/수동 데이터 입력)를 3단계에 병렬 제공하고 정식 연동은 이후로 유도한다.
- expected-value: 즉시 우회 가능한 저마찰 경로 확보
- novelty: 중간
- assumptions: CSV 업로드가 API 연동보다 비개발자에게 쉽다는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 없음(직접 근거 미발견, 논리적 추론)
- independent-sources: 0

### IDEA-013
- idea-id: IDEA-013
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: CL-E
- idea: 이메일 7단계와 인앱 툴팁 3개가 서로 다른 채널에서 비동기·중복으로 작동해 사용자가 어느 채널을 봐야 할지 혼란을 겪는다는 가설 하에, 두 채널을 하나의 상태 기반 진행 시스템으로 통합한다.
- expected-value: 채널 간 혼란 제거로 전체 완료율 개선
- novelty: 중간
- assumptions: 두 채널의 비동기성 자체가 혼란·이탈 요인이라는 가정(미검증)
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 없음(직접 근거 미발견, 내부 관찰 기반 가설)
- independent-sources: 0

### IDEA-014
- idea-id: IDEA-014
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: CL-E, CL-C(교차 참조)
- idea: 영업/CS 팀 인센티브를 재정렬해 "3단계 통과율"을 온보딩 콜의 핵심 KPI로 부여하고, 3단계 도달 고객을 CS 대시보드에 실시간 노출해 능동 개입을 유도한다(프로세스 변화, 개발 비용 거의 0).
- expected-value: 개발 없이 조직 프로세스만으로 개입 가능
- novelty: 중간
- assumptions: CS 인력이 추가 개입 여력을 가진다는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 없음(외부 출처 해당 없음, 조직 프로세스 설계)
- independent-sources: 0

### IDEA-015
- idea-id: IDEA-015
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: CL-E
- idea: 3단계에서 이탈한 사용자를 위한 별도의 자동화된 "재시도" 이메일 시퀀스를 기존 7단계와 분리해 설계한다(현재는 이탈 후 후속 조치가 없다는 가정). 재시도 시 이전 입력값은 유지한다.
- expected-value: 현재 비어 있는 이탈 후 재유입 루프 신설
- novelty: 중간
- assumptions: 현재 이탈 후 전용 후속 조치가 없다는 가정(미검증)
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 없음(직접 근거 미발견)
- independent-sources: 0

### IDEA-016
- idea-id: IDEA-016
- parent-id: none
- strategy: Brainwriting
- lens: 시스템 사고자
- cluster-ids: CL-A
- idea: 자주 연동되는 대상 시스템(회계·CRM 등) 공급사와 제휴해 "원클릭 인증"형 사전 구축 커넥터를 상위 3~5개 시스템에 한정해 제공한다.
- expected-value: 커버되는 고객 비중에서 연동 마찰 대폭 감소
- novelty: 중간
- assumptions: 상위 3~5개 시스템이 이탈 고객 상당 비중을 커버한다는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 사전 구축 커넥터는 커스텀 API 개발 대비 연동 소요 시간을 80~90% 단축한다
- independent-sources: 2

### IDEA-017
- idea-id: IDEA-017
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: CL-D
- idea: 기존 인앱 툴팁 3개를 삭제하지 않고 상단에 전체 온보딩 진행률 바(체크리스트)를 추가해 결합한다.
- expected-value: 저비용으로 동기 부여 강화
- novelty: 낮음
- assumptions: 진행률 가시화가 완료 동기를 높인다는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 진행률 표시·체크리스트는 온보딩 완료율을 최대 40%까지, 게이미피케이션 요소는 최대 50% 더 높은 완료율을 낸다는 관찰이 있다(원출처 독립성 불확실 — 연구 컨텍스트 참고)
- independent-sources: 3

### IDEA-018
- idea-id: IDEA-018
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: CL-G, CL-D(교차 참조)
- idea: 이메일 시퀀스 7단계 중 1개를 3단계 데이터 연동 전용 "준비 이메일"(연동에 필요한 정보·권한을 미리 안내)로 재배치한다. 나머지 이메일 순서는 유지한다.
- expected-value: 저비용 콘텐츠 개선으로 3단계 사전 준비 유도
- novelty: 낮음
- assumptions: 사전 안내가 실제 준비 행동으로 이어진다는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 없음(직접 근거 미발견)
- independent-sources: 0

### IDEA-019
- idea-id: IDEA-019
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: CL-A
- idea: 드롭다운 기반 연동 폼(필드 개수 최소화)과 기존 자격 증명 자동완성(브라우저/세션 정보 활용)을 결합한다.
- expected-value: 입력 오류·수동 타이핑 감소
- novelty: 낮음
- assumptions: 필드 수를 줄이면 완료율이 높아진다는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 수동 입력 필드 1개당 온보딩 완료율이 5~7% 감소한다는 관찰이 있다(IDEA-001과 동일 근거 재사용)
- independent-sources: 1

### IDEA-020
- idea-id: IDEA-020
- parent-id: none
- strategy: Brainwriting
- lens: 실용적 조합자
- cluster-ids: CL-F
- idea: 6주 내 1차로 3단계 UI 문구·필드 개선(저비용)만 먼저 출시하고, 2차로 진행률 저장·재개 기능을 후속 스프린트로 배치하는 단계적 출시 로드맵을 짠다.
- expected-value: 리스크 분산, 빠른 초기 개선 확인
- novelty: 낮음
- assumptions: 1차 저비용 개선만으로도 측정 가능한 개선 신호를 얻을 수 있다는 가정
- duplicate-of: none
- status: parked
- park-recondition: 숏리스트 후보(C-01~C-04) 확정 후 실제 실행 계획 수립 단계에서 스프린트 분할 방식으로 재검토한다
- elimination-reason:
- core-fact: 없음(전달 전략, 외부 출처 해당 없음)
- independent-sources: 0

### IDEA-021
- idea-id: IDEA-021
- parent-id: IDEA-009
- strategy: SCAMPER
- lens: SCAMPER-Eliminate
- cluster-ids: CL-B
- idea: 3단계를 온보딩 순서에서 완전히 제거하고 온보딩 "완료"의 정의 자체를 재정의한다. 연동 없이도 핵심 기능(리포트 템플릿 체험 등)을 쓸 수 있으면 "활성화"로 간주하고, 연동은 별도의 "성장" 트랙으로 분리한다.
- expected-value: 완료율 지표 자체를 달성 가능한 형태로 재설계
- novelty: 높음
- assumptions: 연동 없는 활성화가 의뢰자 가치(성공 신호)로 인정될 수 있다는 가정 — 성공 신호 정의와 충돌 가능성 있음
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 없음(IDEA-002의 원리를 극단화한 파생 아이디어, 독립 근거 미확보)
- independent-sources: 0

### IDEA-022
- idea-id: IDEA-022
- parent-id: IDEA-002
- strategy: SCAMPER
- lens: SCAMPER-Reverse
- cluster-ids: CL-B
- idea: 순서를 반전해 데이터 연동을 온보딩 마지막에 배치하고, 초반에 빠른 승리(quick win)를 먼저 경험시켜 3단계에 도달하기 전에 이미 가치를 느낀 상태로 만든다.
- expected-value: 동기가 형성된 상태에서 연동 단계 진입
- novelty: 높음
- assumptions: 순서 반전이 연동 자체의 난이도를 낮추지는 못하지만 완주 동기를 높인다는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 짧은 단계 수 온보딩 투어(3단계)가 긴 단계 수(7단계) 대비 완료율이 크게 높다는 관찰이 있어, 구조·순서 변경이 완료율에 영향을 줄 수 있음을 시사한다
- independent-sources: 1

### IDEA-023
- idea-id: IDEA-023
- parent-id: IDEA-011
- strategy: SCAMPER
- lens: SCAMPER-Substitute
- cluster-ids: CL-C
- idea: 화상 콜 대신 비동기 스크린 레코딩 요청 방식으로 대체한다. 사용자가 화면 녹화로 문제를 보내면 CS가 비동기로 원격 설정을 대신 처리한다(시간대 문제·비개발자의 화상통화 부담 완화).
- expected-value: 화상콜 부담 없이 사람 개입 경로 확보
- novelty: 중간
- assumptions: 사용자가 화면 녹화를 남기는 것을 화상 콜보다 덜 부담스러워한다는 가정
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 없음(직접 근거 미발견, IDEA-011의 반증 관찰에 대응해 설계된 대안)
- independent-sources: 0

### IDEA-024
- idea-id: IDEA-024
- parent-id: IDEA-014
- strategy: SCAMPER
- lens: SCAMPER-Put to another use
- cluster-ids: CL-E
- idea: 3단계 이탈 데이터를 온보딩 개선 외에 제품 설계팀의 "연동 난이도 지표"로 전용해, 향후 신규 연동 대상 시스템 선정 시 난이도를 사전 심사하는 기준으로 재사용한다.
- expected-value: 장기적 제품 의사결정 품질 향상(온보딩 이탈 지표와는 별개 가치)
- novelty: 중간
- assumptions: 온보딩 이탈 데이터가 제품 로드맵 의사결정에 전용 가능한 형태라는 가정
- duplicate-of: none
- status: eliminated
- park-recondition:
- elimination-reason: 온보딩 이탈률 개선이라는 의뢰자 핵심 가치(evaluation-criteria 1순위)에 직접 기여하지 않고 별도 제품 로드맵 프로세스에 속함 — 브리프의 out-of-scope("온보딩 이탈 데이터의 온보딩 프로젝트 외 활용")에 명시적으로 해당해 범위 밖으로 판단. 구체화 부족이 아닌 범위 불일치가 탈락 근거임.
- core-fact: 해당 없음
- independent-sources: 0

### IDEA-025
- idea-id: IDEA-025
- parent-id: IDEA-006
- strategy: SCAMPER
- lens: SCAMPER-Combine
- cluster-ids: CL-A
- idea: 이케아식 시각적 단계 체크리스트(IDEA-006)와 진행 상태 저장(IDEA-009)을 결합해 "시각적 단계 표시 + 자동 재개"가 함께 동작하는 통합 위젯을 만든다.
- expected-value: 이해도와 재방문 지속성을 동시에 개선
- novelty: 중간
- assumptions: 두 요소의 결합 효과가 개별 효과의 단순 합보다 작지 않다는 가정(미검증)
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 없음(IDEA-017의 체크리스트 근거와 원리적으로 연결되나 이 조합 자체는 독립적으로 검증되지 않음)
- independent-sources: 0

### IDEA-026
- idea-id: IDEA-026
- parent-id: IDEA-012
- strategy: SCAMPER
- lens: SCAMPER-Modify
- cluster-ids: CL-A
- idea: CSV 업로드 대체 경로(IDEA-012)를 수정해, 업로드된 CSV를 기반으로 시스템이 정식 API 연동 매핑을 자동 추천하여 임시 우회가 아니라 정식 연동으로 자연스럽게 이어지게 한다.
- expected-value: 우회 경로가 회피가 아닌 정식 연동으로의 다리 역할을 함
- novelty: 중간
- assumptions: CSV 구조로부터 정식 API 매핑을 자동 추천하는 로직이 3인월 내 구현 가능하다는 가정(리스크 요소)
- duplicate-of: none
- status: shortlisted
- park-recondition:
- elimination-reason:
- core-fact: 없음(직접 근거 미발견, 논리적 추론)
- independent-sources: 0

## 군집

### CL-A: 연동 자체의 기술적 마찰 감소
- 설명: 3단계 데이터 연동 화면·입력 방식 자체를 비개발자 친화적으로 단순화해 마찰을 직접 제거하는 원리
- 포함 idea-id: IDEA-001, IDEA-008, IDEA-009, IDEA-012, IDEA-016, IDEA-019, IDEA-025, IDEA-026
- 공통 가정: 연동 이탈의 상당 부분이 기술적 입력 마찰(필드 수, 용어, 재시작 부담)에서 온다
- 차별점: 폼 단순화(001/019) vs 경로 분기(008) vs 우회 경로(012/026) vs 파트너 사전 커넥터(016) vs 진행 저장(009) vs 시각+재개 결합(025)
- 미해결 질문: 근본 이탈 원인이 실제로 기술적 마찰인지(브리프 assumption 1이 미확인 상태)

### CL-B: 연동 전 가치 선체험으로 순서 재구성
- 설명: 기술적 연동을 뒤로 미루고 먼저 제품 가치를 체험시켜 완주 동기를 만드는 원리
- 포함 idea-id: IDEA-002, IDEA-021, IDEA-022
- 공통 가정: 가치 선체험이 이후 연동 단계를 완료할 동기를 높인다
- 차별점: 병행 제공(002) vs 완료 정의 자체 재정의(021, 더 급진적) vs 순서 반전(022)
- 미해결 질문: 순서를 늦춰도 결국 연동 단계에서 다시 이탈하지 않는지(문제를 뒤로 미루는 것일 위험)

### CL-C: 정체 시점 인간 개입
- 설명: 자동화로 해결되지 않는 이탈을 사람(채팅/콜/CS)이 개입해 구제하는 원리
- 포함 idea-id: IDEA-003, IDEA-007, IDEA-011, IDEA-023
- 공통 가정: 정체 시점에 적절한 사람 개입이 제공되면 이탈 대신 전환된다
- 차별점: 실시간 채팅(003) vs 콜백 예약(007/011, 동기 방식) vs 비동기 스크린 레코딩(023)
- 미해결 질문: SMB 세그먼트에서 사람 개입 모델의 비용 대비 효과가 화이트글러브 임계선(연구 컨텍스트) 관찰과 상충하지 않는지

### CL-D: 동기부여·콘텐츠 재배치(저비용)
- 설명: 신규 기능 개발 없이 기존 콘텐츠(툴팁·이메일·진행 표시)를 재배치·보강해 동기를 높이는 원리
- 포함 idea-id: IDEA-004, IDEA-006(교차), IDEA-010, IDEA-017, IDEA-018(교차)
- 공통 가정: 콘텐츠·동기 개선만으로도 측정 가능한 완료율 개선이 가능하다
- 차별점: 영상(004) vs 시각적 체크리스트(006) vs 카피 재배치(010) vs 진행률 바(017) vs 준비 이메일(018)
- 미해결 질문: 근본적 연동 난이도를 건드리지 않고도 목표(34%→52%) 격차를 얼마나 메울 수 있는지

### CL-E: 시스템·조직 프로세스 재설계
- 설명: 채널 간 피드백 루프, 조직 인센티브, 재유입 루프 등 시스템 수준의 구조를 바꾸는 원리
- 포함 idea-id: IDEA-013, IDEA-014, IDEA-015, IDEA-024
- 공통 가정: 개별 화면보다 채널·조직 간 상호작용 구조가 이탈에 영향을 준다
- 차별점: 채널 통합(013) vs CS 인센티브·개입(014) vs 재시도 루프(015) vs 데이터 전용(024, 범위 밖으로 탈락)
- 미해결 질문: 채널 비동기성이 실제 혼란·이탈 요인인지(013)는 미검증

### CL-F: 단계적 출시 로드맵(메타 전략)
- 설명: 특정 해결 원리가 아니라 여러 후보를 어떤 순서로 출시할지에 대한 전달 전략
- 포함 idea-id: IDEA-020
- 공통 가정: 저비용 개선을 먼저 출시해 빠르게 신호를 확인하는 것이 유리하다
- 차별점: 고유 아이디어로, 다른 군집과 강제로 합치지 않음
- 미해결 질문: 어떤 후보를 1차/2차로 배치할지는 숏리스트 확정 후 결정 필요

### CL-G: 사전 정보·기대치 설정
- 설명: 온보딩 세션(3단계) 진입 전에 정보·기대치를 미리 준비시켜 실시간 마찰을 줄이는 원리
- 포함 idea-id: IDEA-005, IDEA-018(교차)
- 공통 가정: 사전 커뮤니케이션이 실제 준비 행동으로 이어진다
- 차별점: 전용 사전 수집 이메일(005) vs 기존 시퀀스 내 재배치(018)
- 미해결 질문: 사전 이메일에 대한 응답률·행동 전환율은 미확인

## 숏리스트

### Candidate C-01
- source-idea-ids: IDEA-001, IDEA-009, IDEA-012, IDEA-016, IDEA-019, IDEA-025, IDEA-026
- value-proposition: 3단계 데이터 연동 화면 자체의 기술적 마찰(필드 수, 용어, 재시작 부담)을 직접 낮춰 최대 이탈 지점(28%)을 정면으로 타격한다.
- requester-value-fit: 매우 높음 — 평가 기준 1순위(이탈률·완료율 기여)에 직접 부합
- differentiation: 기존 툴팁·이메일과 달리 3단계 폼 구조 자체를 바꾸는 유일한 후보군
- learning-value: 중간 — 필드 감소 효과에 대한 외부 유추적 근거는 있으나(단일 출처, 미확인) 자사 제품 데이터로 별도 검증 필요
- key-risks: React+Node 내 드롭다운·자동완성·CSV 자동 매핑(IDEA-026) 구현 범위가 3인월을 초과할 수 있음 / CSV 우회 경로(IDEA-012)가 오히려 정식 연동을 지연시켜 장기 활성화를 낮출 위험
- evidence-level: 낮음~중간 (핵심 근거가 단일 미확인 출처, 파트너 커넥터 근거만 독립 출처 2개)
- dissent: 필드 단순화가 정말 효과적인지, 혹은 애초에 연동 자체가 개념적으로 어려운 것인지 불확실 — 브리프 assumption(1)이 미확인 상태라는 반대 근거가 있음
- validation-priority: 최우선

### Candidate C-02
- source-idea-ids: IDEA-002, IDEA-021, IDEA-022
- value-proposition: 연동 이전에 제품 핵심 가치를 먼저 경험시켜 동기를 만든 뒤 연동을 진행하도록 온보딩 구조를 재배치한다.
- requester-value-fit: 높음 — 완료율뿐 아니라 7일 이내 이탈(58%)에도 기여 가능
- differentiation: 온보딩 "완료"의 정의·순서 자체를 재구성하는 구조적 변화(경쟁사 유사 사례 존재)
- learning-value: 높음 — "진짜 이탈 원인이 연동 난이도가 아니라 가치 인식 부족인지"를 시험할 수 있음
- key-risks: 샘플 데이터 체험 후 실제 연동으로 전환하는 시점에 이탈이 재발할 수 있어 문제를 뒤로 미루는 것에 그칠 위험 / 순서 재배치의 React+Node 구현 공수가 불확실
- evidence-level: 낮음 (단일 사례, 출처 1개)
- dissent: "가치를 먼저 보여줘도 결국 3단계를 통과해야 하므로 이탈 시점만 늦춘다"는 반대 의견이 유효함
- validation-priority: 상

### Candidate C-03
- source-idea-ids: IDEA-003, IDEA-007, IDEA-011, IDEA-014, IDEA-023
- value-proposition: 자동화만으로 해결되지 않는 이탈을 CS·사람 개입으로 구제하며, 제품 개발보다 프로세스 변화 중심이라 6주 내 실현이 용이하다.
- requester-value-fit: 중간~높음
- differentiation: 코드 변경을 최소화하면서도 3단계 이탈에 개입할 수 있는 유일한 후보군
- learning-value: 중간
- key-risks: CS 인력 확장이 필요하면 "개발 예산 3인월" 제약 산정에 잡히지 않는 숨은 비용일 위험 / 스케일 시 CS 응답 병목 / 화이트글러브 임계선 관찰(SMB는 통상 셀프서브 지배)과 상충 가능
- evidence-level: 낮음 (라이브챗 벤더 블로그 중심, 이해상충 가능성 있음)
- dissent: 근거 출처들이 라이브챗 툴 벤더라 효과 크기가 과장되었을 수 있다는 우려가 있음
- validation-priority: 중

### Candidate C-04
- source-idea-ids: IDEA-005, IDEA-010, IDEA-013, IDEA-015, IDEA-017, IDEA-018
- value-proposition: 기존 자산(이메일 7단계 + 툴팁 3개)의 저비용 재배치·보강(진행률 바, 준비 이메일, 채널 통합, 재시도 루프)만으로 신규 기능 개발 없이 빠르게 개선한다.
- requester-value-fit: 중간 — 3단계 근본 기술 난이도는 건드리지 않고 동기·정보 격차만 완화
- differentiation: 4개 후보 중 구현 리스크가 가장 낮고 6주·3인월 제약을 가장 안전하게 충족
- learning-value: 중간
- key-risks: 근본 원인(연동 난이도)을 해결하지 않아 목표(34%→52%)에 못 미칠 위험이 큼
- evidence-level: 중간 (진행률 바 근거는 3개 도메인이나 원출처 독립성 불확실)
- dissent: "안전하지만 임팩트가 부족해 목표 미달 가능"이라는 반대 근거가 강하게 존재함
- validation-priority: 중 (우선 빠르게 실행해 baseline 개선을 확인한 뒤 C-01/C-02와 병행하는 방안을 권고)

## 검증 계획

### Experiment E-01
- candidate-id: C-01
- assumption: 폼 필드 축소·비개발자 친화 문구·자동완성이 3단계 데이터 연동 이탈을 유의미하게 낮춘다
- approved-type: mockup
- method: 3단계 연동 화면의 저충실도 목업(현행안 vs 개선안)을 제작하고, 에이전트 비판자 역할로 비개발자 관점 워크스루를 수행해 혼란 지점·이탈 유발 요소를 식별한다
- success-signal: 개선안 목업에서 기술 용어·수동 입력 관련 혼란 지적이 현행안 대비 감소한다
- stop-condition: 개선안에서도 심각한 신규 혼란 지점이 3개 이상 발견되면 재설계가 필요한 것으로 판정한다
- estimated-cost: 낮음(0.5인주 이내, 개발 착수 전 목업 단계)
- approval-status: approved

### Experiment E-02
- candidate-id: C-02
- assumption: 데이터 연동 전에 샘플/데모 데이터로 핵심 가치를 먼저 보여주면, 순서를 뒤집어도 사용자가 결국 연동을 완료할 동기가 높아진다(연동 회피로 이어지지 않는다)
- approved-type: research
- method: "가치 선체험 후 기술 설정 완료" 패턴을 적용한 유사 SaaS 사례를 Stripe 외에 2건 이상 독립적으로 추가 조사한다
- success-signal: 독립 사례 2건 이상에서 선체험 방식이 연동 완료율 또는 전체 활성화율을 개선했다는 일관된 근거가 확인된다
- stop-condition: 조사 후에도 독립 사례가 1건 이하로 유지되면 근거 부족으로 판정하고 프로토타입 검증으로 전환을 재검토한다
- estimated-cost: 낮음(조사 1~2일)
- approval-status: approved

### Experiment E-03
- candidate-id: C-03
- assumption: 3단계 정체 시점에 실시간 채팅/콜백 제안이 나타나면 비개발자 IT 담당자의 이탈이 감소하며, CS 리소스 확장 없이 3인월·6주 내 실행 가능하다
- approved-type: agent-critique
- method: 에이전트 비판자에게 C-03 설계(정체 감지 로직 + CS 개입 프로세스)를 제시해 실패 경로(예: CS 인력 부족 시 응답 지연으로 인한 역효과)를 공격적으로 검토하도록 요청한다
- success-signal: 비판 결과 3인월·6주 제약 내에서 실행 가능한 최소 버전(예: 정체 감지 시 셀프서브 FAQ를 우선 노출하고 CS 개입은 옵션으로 둠)이 도출된다
- stop-condition: 비판 결과 CS 인력 확장 없이는 실행이 불가능하다는 결론이면 C-03을 비동기 스크린 레코딩(IDEA-023) 중심의 축소 범위로 재정의한다
- estimated-cost: 낮음(0.5일 이내)
- approval-status: approved

### Experiment E-04
- candidate-id: C-04
- assumption: 기존 자산 재배치와 진행률 바 추가만으로 목표 개선폭(34%→52% 근접)의 상당 부분을 달성할 수 있다(근본적 연동 난이도는 그대로 두어도 충분한 임팩트가 있다)
- approved-type: document
- method: C-01/C-02/C-04가 각각 목표 성공 신호(완료율, 7일 이탈률)에 기여할 것으로 예상되는 메커니즘과 한계를 비교하는 내부 비교 문서를 작성한다
- success-signal: 비교 문서에서 C-04 단독 실행 시 목표치 도달 가능성과 남는 격차가 명시적으로 드러난다
- stop-condition: 문서상 C-04만으로는 목표 격차가 크게 남는 것으로 판단되면, 최종 보고의 권고안에 C-01/C-02와의 병행 실행을 명시한다
- estimated-cost: 낮음(0.5일)
- approval-status: approved

## 실험

이번 측정 세션은 검증 계획 작성까지만 수행한다. 위 실험 E-01~E-04는 픽스처 브리프로 사전 승인된 상태(approval-status: approved)이나, **실행하지 않았다.** 세션 상태는 `validation_approval`에서 종료되며, 실험 실행과 관찰 기록은 후속 세션(resume 시 `validating` 라우팅)의 몫이다.

## 최종 보고

**후보군(복수, 단일 승자 강제 없음)**: C-01(연동 마찰 직접 감소), C-02(가치 선체험 순서 재구성), C-03(정체 시점 인간 개입), C-04(저비용 콘텐츠 재배치)는 서로 다른 해결 원리·비용 구조·위험 프로필을 가진다. 특히 C-04는 위험이 가장 낮지만 임팩트도 가장 제한적이고, C-01은 핵심 병목을 직접 겨냥하지만 3인월 초과 위험이 있으며, C-02는 학습 가치가 가장 높지만 증거가 가장 얕고, C-03은 개발 비용은 낮지만 조직 비용(CS 인력)이 예산 산정 밖일 수 있다.

**계보**: 26개 원본/변환 아이디어 중 21개가 4개 후보군에 편입(shortlisted), 1개는 SCAMPER로 변환되어 파생 아이디어에 흡수됨(transformed: IDEA-006 → IDEA-025), 3개는 관찰 가능한 재검토 조건과 함께 보류(parked: IDEA-004, IDEA-008, IDEA-020), 1개는 범위 불일치로 근거를 남기고 탈락(eliminated: IDEA-024).

**비교**: 평가 기준(이탈률 기여 > 제약 내 구현 가능성 > 비개발자 사용성 > 스택 호환성) 기준으로 C-01이 1순위 기여도는 가장 높으나 구현 리스크도 함께 크고, C-04는 구현 리스크가 가장 낮으나 1순위 기여도가 가장 불확실하다. C-02와 C-03은 중간 지점에 있으며 서로 다른 유형의 근거 약점(단일 사례 vs 벤더 이해상충)을 가진다.

**불확실성**: (1) 브리프 단계의 핵심 가정 — "3단계 이탈이 연동 자체의 기술적 난이도 때문"이라는 가정이 세션 전체에서 미확인 상태로 남아 있다. 이는 C-01의 근거이자 동시에 C-01의 최대 반대 근거다. (2) 다수 외부 통계가 1차 연구 인용이 없는 마케팅 블로그에서 나와, "독립 출처 수"가 진짜 독립성을 보장하지 못할 수 있다(연구 컨텍스트 총평 참고). (3) SMB 세그먼트에 대한 화이트글러브(사람 개입) 모델의 경제성은 오히려 반증 관찰과 함께 남겨두었다.

**승인된 검증 결과**: 없음(이번 세션에서 실험 미실행).

**다음 의사결정 질문**:
- E-01~E-04 중 어떤 순서로 실행을 승인할 것인가(권고: E-01·E-04를 우선 병행해 근거를 빠르게 확보한 뒤 E-02·E-03 진행)?
- C-03의 CS 인력 개입 비용을 "개발 예산 3인월" 제약과 별도로 산정할 것인가, 아니면 3인월 제약 안에 포함해 평가할 것인가?
- 브리프 단계의 미확인 핵심 가정(3단계 이탈 원인)을 검증하기 위한 별도의 정성 조사(예: 실제 이탈 고객 인터뷰)를 이번 검증 계획에 추가할 것인가?
