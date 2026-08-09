# recipe

에이전트 협업 도구 모음. ① 판단 전담 Advisor가 Worker(호출 세션)를 감독하는 위임·검증 워크플로, ② 입출력 계약이 있는 **typed 스킬**을 노드로 연결해 실행 흐름(파이프라인)을 만들고 독립 실행 가능한 워크플로 스킬로 컴파일하는 도구, ③ 외부 에이전트 CLI(claude·codex·antigravity)를 1회 실행하는 raw 래퍼(`oneshot`), ④ codex-review CI의 `CODEX_AUTH_JSON` 시크릿을 격리 재시드하는 운영 스킬.

**파이프라인 핵심 원칙: 정의 = 소스, 생성된 스킬 = 바이너리.** 정의 YAML을 수정하면 재컴파일한다. 실행은 컴파일된 스킬이 담당한다. 컴파일된 스킬도 typed(`kind: pipeline`)이므로 다른 파이프라인의 노드로 재사용 가능 — 파이프라인 합성.

## 스킬

| 스킬 | 역할 |
|---|---|
| `advisor` | 판단 전담 Advisor 서브에이전트 감독 아래 구현하는 역할 역전 워크플로 (브리프·검증·커밋 승인) |
| `skill` | 단독 호출·노드 편입이 모두 가능한 typed 스킬(입출력 스키마 + 실행법) 생성·단독 테스트·목록 |
| `pipeline` | typed 스킬들을 연결한 그래프 정의 생성, 검증, 자립형 워크플로 스킬 컴파일 |
| `codex-auth-reseed` | codex-review CI가 인증 오류로 깨질 때 `CODEX_AUTH_JSON` 시크릿을 격리 `CODEX_HOME`에서 재시드 |
| `oneshot` | 외부 에이전트 CLI를 **1회** 실행하는 raw 래퍼(`claude -p` 수준) — `vendor`: `claude`·`codex`·`agy`(antigravity). 격리·커밋·반복·판정은 호출자가 정한다 |

## 사용자 프로젝트 레이아웃 (벤더 중립)

```
.agents/skills/<이름>/SKILL.md  # typed 스킬 소스 — 런타임 중립 위치 (커밋 대상)
.agents/skills/<이름>/          # 컴파일된 워크플로 스킬 (kind: pipeline)
.claude/skills/<이름>           # Claude Code 어댑터 — .agents/skills/<이름> 상대 심링크
.pipelines/<이름>.yaml          # 파이프라인 정의 (커밋 대상)
.pipelines/runs/<run-id>/       # 실행 기록 — .gitignore에 추가할 것
```

typed 스킬·컴파일 산출물은 `.agents/skills/`에 한 벌만 두고, 각 런타임은 어댑터(심링크 등)로 연결한다. SKILL.md 본문은 특정 런타임 도구명을 쓰지 않으며(`allowed-tools` frontmatter만 Claude 전용 — 타 런타임은 무시), 실행 지시는 "구조화된 사용자 질문 기능", "서브에이전트 기능" 같은 중립 문구를 쓴다.

## 흐름

1. `skill create` — typed 스킬 정의 (llm / script / http / mcp)
2. `skill test <이름>` — 모의 입력으로 단독 실행, 출력 스키마 검증
3. `pipeline create` — 목표 인터뷰 → 그래프 구성 → validate → compile
4. 생성된 스킬 호출 — `/<이름> [입력]`, 실패 시 `/<이름> resume <run-id>`
5. 필요하면 그 스킬을 다른 파이프라인의 노드로 참조 (`skill: <이름>`)
