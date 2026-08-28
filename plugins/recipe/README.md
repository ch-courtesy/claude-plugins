# recipe

에이전트 협업 도구 모음. ① 판단 전담 Advisor가 Worker(호출 세션)를 감독하는 위임·검증 워크플로, ② 외부 에이전트 CLI를 한 번 실행하는 벤더 중립 raw 래퍼, ③ codex-review CI의 `CODEX_AUTH_JSON` 시크릿을 격리 재시드하는 운영 스킬.

## 스킬

| 스킬 | 역할 |
|---|---|
| `advisor` | 판단 전담 Advisor 서브에이전트 감독 아래 구현하는 역할 역전 워크플로 (브리프·검증·커밋 승인) |
| `oneshot` | 외부 에이전트 CLI(claude·codex·agy) 1회 실행 raw 래퍼 — 벤더 관례 흡수, 격리·커밋·반복·판정은 호출자 몫 |
| `codex-auth-reseed` | codex-review CI가 인증 오류로 깨질 때 `CODEX_AUTH_JSON` 시크릿을 격리 `CODEX_HOME`에서 재시드 |

## 벤더 중립 규약

SKILL.md 본문은 특정 런타임 도구명을 쓰지 않으며(`allowed-tools` frontmatter만 Claude 전용 — 타 런타임은 무시), 실행 지시는 "구조화된 사용자 질문 기능", "서브에이전트 기능" 같은 중립 문구를 쓴다.
