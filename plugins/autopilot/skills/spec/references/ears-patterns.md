# EARS 패턴 가이드

EARS = Easy Approach to Requirements Syntax. 5개 패턴으로 모호성 없는 수용 기준을 작성.

## 5개 패턴

### 1. Ubiquitous (무조건)
형식: `The system shall <응답>`

용례: 시스템의 *기본 행동*. 트리거나 조건 없이 항상 성립.

예시:
- The system shall log all authentication attempts.
- The system shall expire idle sessions after 30 minutes.

### 2. Event-driven (이벤트 기반)
형식: `When <트리거>, the system shall <응답>`

용례: 외부 입력·내부 이벤트로 촉발되는 행동.

예시:
- When a user submits an empty password, the system shall reject the request with a 400 status.
- When the refresh token expires, the system shall invalidate the session.

### 3. State-driven (상태 기반)
형식: `While <상태>, the system shall <지속 응답>`

용례: 시스템이 특정 상태일 때만 *지속적으로* 성립.

예시:
- While the database is in read-only mode, the system shall reject all write operations with 503.
- While a user is impersonated, the system shall include "X-Impersonated-By" in every response.

### 4. Optional (조건부 기능)
형식: `Where <조건>, the system shall <응답>`

용례: 특정 환경·feature flag·구성에서만 활성.

예시:
- Where the audit-log feature flag is enabled, the system shall record every state mutation.
- Where MFA is configured, the system shall require a second factor on login.

### 5. Unwanted behavior (불가용·오류)
형식: `If <불가용/오류>, then the system shall <복구·거부>`

용례: 실패·예외 상황의 명시적 처리.

예시:
- If the database connection fails, then the system shall return 503 with a retry-after header.
- If a webhook delivery fails three times, then the system shall mark the subscription as inactive.

## 자유 텍스트 → EARS 변환 가이드

자체 검토 단계에서 자유 텍스트가 발견되면 다음 휴리스틱으로 변환 시도:

| 자유 텍스트 시그널 | 추천 패턴 |
|---|---|
| "사용자가 X 하면 Y" | Event-driven (When) |
| "X 동안에는 Y" | State-driven (While) |
| "X 환경에서만 Y" | Optional (Where) |
| "X 실패 시 Y", "X 안 되면 Y" | Unwanted (If/then) |
| 위 어디에도 안 맞음 | Ubiquitous (그대로 "shall") |

변환 후 사용자에게 `AskUserQuestion`으로 적용 여부 확인. 거절 시 `[NEEDS CLARIFICATION: EARS 패턴으로 재작성 필요 — 원문: "<원문>"]` 마커 박음.

## Independent-Test 규칙

각 EARS 기준은 verify 명령 안에서 *어떤 형태로든 fail 가능*해야 합니다. 그렇지 않다면 검증되지 않는 기준이며 무의미.

자체 검토 시 각 기준에 대해:
- "이 기준이 위반되면 verify 명령이 0이 아닌 exit를 낼 수 있는가?"
- "어떤 테스트를 작성하면 이 기준의 위반을 잡을 수 있는가?" (loop이 결정할 일이지만, *원리적으로 가능한가*만 확인)

불가능한 기준은 `[NEEDS CLARIFICATION: 검증 가능한 형태로 재작성 — 어떤 fail 시나리오?]` 마커.
