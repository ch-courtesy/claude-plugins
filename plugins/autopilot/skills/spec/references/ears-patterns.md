# EARS 패턴 가이드

EARS = Easy Approach to Requirements Syntax. 5개 패턴으로 모호성 없는 수용 기준을 작성.

## EARS 작성 언어

EARS 5패턴의 의미·구조(Mavin et al. 표준)는 언어와 무관하게 보존하되, 어휘만 작성 언어에
맞춰 번역한다. **작성 언어 default는 프로젝트 기본 언어**다 — 현 레포의 경우 한국어(`ko`).

SPEC frontmatter `ears_language` 키로 개별 SPEC이 default를 override할 수 있다. 허용 값은
`ko` · `en` · `hybrid` 세 가지이며, 키 미명시 시 디폴트는 `ko`(프로젝트 기본 언어)다.

3모드 정의:
- `ko` — 본문·키워드 모두 한국어. 트리거는 "~할 때 / ~인 동안 / ~인 경우 / ~이면", 응답은
  "시스템은 ~한다" 형태. 예: "사용자가 빈 비밀번호를 제출할 때, 시스템은 400으로 요청을 거부한다."
- `en` — 본문·키워드 모두 영어. 표준 EARS 영어 키워드(`When` · `While` · `Where` · `If` · `shall`).
  예: "When a user submits an empty password, the system shall reject the request with a 400 status."
- `hybrid` — EARS 영어 키워드(`When` · `While` · `Where` · `If` · `shall`)는 그대로 두고 본문만
  한국어로 작성. 형식 정의: `<EARS 영어 키워드> <한국어 본문>, the system shall <한국어 응답>한다.`
  예시 라인: When 사용자가 빈 비밀번호를 제출하면, the system shall 400으로 요청을 거부한다.

자유 텍스트→EARS 변환 시에도 동일 언어 규칙이 적용된다(아래 §변환 가이드).

## 5개 패턴

각 패턴의 의미·구조는 모드 간 동일. 예시는 ko · en · hybrid 3모드를 함께 제시.

### 1. Ubiquitous (무조건)
형식:
- en: `The system shall <응답>`
- ko: `시스템은 <응답>한다`
- hybrid: `The system shall <한국어 응답>한다`

용례: 시스템의 *기본 행동*. 트리거나 조건 없이 항상 성립.

예시:
- (ko) 시스템은 모든 인증 시도를 로그에 기록한다.
- (en) The system shall log all authentication attempts.
- (hybrid) The system shall 모든 인증 시도를 로그에 기록한다.

### 2. Event-driven (이벤트 기반)
형식:
- en: `When <트리거>, the system shall <응답>`
- ko: `<트리거>할 때, 시스템은 <응답>한다`
- hybrid: `When <한국어 트리거>, the system shall <한국어 응답>한다`

용례: 외부 입력·내부 이벤트로 촉발되는 행동.

예시:
- (ko) 사용자가 빈 비밀번호를 제출할 때, 시스템은 400 상태로 요청을 거부한다.
- (en) When a user submits an empty password, the system shall reject the request with a 400 status.
- (hybrid) When 사용자가 빈 비밀번호를 제출하면, the system shall 400 상태로 요청을 거부한다.

### 3. State-driven (상태 기반)
형식:
- en: `While <상태>, the system shall <지속 응답>`
- ko: `<상태>인 동안, 시스템은 <지속 응답>한다`
- hybrid: `While <한국어 상태>인 동안, the system shall <한국어 지속 응답>한다`

용례: 시스템이 특정 상태일 때만 *지속적으로* 성립.

예시:
- (ko) 데이터베이스가 read-only 모드인 동안, 시스템은 모든 쓰기 작업을 503으로 거부한다.
- (en) While the database is in read-only mode, the system shall reject all write operations with 503.
- (hybrid) While 데이터베이스가 read-only 모드인 동안, the system shall 모든 쓰기 작업을 503으로 거부한다.

### 4. Optional (조건부 기능)
형식:
- en: `Where <조건>, the system shall <응답>`
- ko: `<조건>인 경우, 시스템은 <응답>한다`
- hybrid: `Where <한국어 조건>인 경우, the system shall <한국어 응답>한다`

용례: 특정 환경·feature flag·구성에서만 활성.

예시:
- (ko) audit-log feature flag가 활성화된 경우, 시스템은 모든 상태 변경을 기록한다.
- (en) Where the audit-log feature flag is enabled, the system shall record every state mutation.
- (hybrid) Where audit-log feature flag가 활성화된 경우, the system shall 모든 상태 변경을 기록한다.

### 5. Unwanted behavior (불가용·오류)
형식:
- en: `If <불가용/오류>, then the system shall <복구·거부>`
- ko: `<불가용/오류>이면, 시스템은 <복구·거부>한다`
- hybrid: `If <한국어 불가용/오류>이면, then the system shall <한국어 복구·거부>한다`

용례: 실패·예외 상황의 명시적 처리.

예시:
- (ko) 데이터베이스 연결이 실패하면, 시스템은 retry-after 헤더와 함께 503을 반환한다.
- (en) If the database connection fails, then the system shall return 503 with a retry-after header.
- (hybrid) If 데이터베이스 연결이 실패하면, then the system shall retry-after 헤더와 함께 503을 반환한다.

## 자유 텍스트 → EARS 변환 가이드

자체 검토 단계에서 자유 텍스트가 발견되면 다음 휴리스틱으로 변환 시도:

| 자유 텍스트 시그널 | 추천 패턴 |
|---|---|
| "사용자가 X 하면 Y" | Event-driven (When) |
| "X 동안에는 Y" | State-driven (While) |
| "X 환경에서만 Y" | Optional (Where) |
| "X 실패 시 Y", "X 안 되면 Y" | Unwanted (If/then) |
| 위 어디에도 안 맞음 | Ubiquitous (그대로 "shall") |

변환은 spec 스킬이 자체 검토 단계(단계 8)에서 자동으로 시도 — 사용자에게 묻지 않음. 변환 결과의 의미 보존이 모호하거나 자동 변환이 불가능하면 `[NEEDS CLARIFICATION: EARS 변환 — 원문: "<원문>" → 제안: "<변환>"]` 마커. 단계 9 사용자 최종 검토에서 변환 수용·거절 결정.

## Independent-Test 규칙

각 EARS 기준은 verify 명령 안에서 *어떤 형태로든 fail 가능*해야 합니다. 그렇지 않다면 검증되지 않는 기준이며 무의미.

자체 검토 시 각 기준에 대해:
- "이 기준이 위반되면 verify 명령이 0이 아닌 exit를 낼 수 있는가?"
- "어떤 테스트를 작성하면 이 기준의 위반을 잡을 수 있는가?" (loop이 결정할 일이지만, *원리적으로 가능한가*만 확인)

불가능한 기준은 `[NEEDS CLARIFICATION: 검증 가능한 형태로 재작성 — 어떤 fail 시나리오?]` 마커.
