# agent-kit

입출력 계약이 있는 **typed 스킬**을 노드로 연결해 실행 흐름(파이프라인)을 만들고, 그 정의를 독립 실행 가능한 워크플로 스킬로 컴파일하는 플러그인.

**핵심 원칙: 정의 = 소스, 생성된 스킬 = 바이너리.** 정의 YAML을 수정하면 재컴파일한다. 실행은 컴파일된 스킬이 담당한다. 컴파일된 스킬도 typed(`kind: pipeline`)이므로 다른 파이프라인의 노드로 재사용 가능 — 파이프라인 합성.

## 스킬

| 스킬 | 역할 |
|---|---|
| `skill` | 단독 호출·노드 편입이 모두 가능한 typed 스킬(입출력 스키마 + 실행법) 생성·단독 테스트·목록 |
| `pipeline` | typed 스킬들을 연결한 그래프 정의 생성, 검증, 자립형 워크플로 스킬 컴파일 |

## 사용자 프로젝트 레이아웃

```
.claude/skills/<이름>/SKILL.md  # typed 스킬 (노드이자 스킬, 커밋 대상)
.pipelines/<이름>.yaml          # 파이프라인 정의 (커밋 대상)
.pipelines/runs/<run-id>/       # 실행 기록 — .gitignore에 추가할 것
.claude/skills/<이름>/          # 컴파일된 워크플로 스킬 (kind: pipeline)
```

## 흐름

1. `skill create` — typed 스킬 정의 (llm / script / http / mcp)
2. `skill test <이름>` — 모의 입력으로 단독 실행, 출력 스키마 검증
3. `pipeline create` — 목표 인터뷰 → 그래프 구성 → validate → compile
4. 생성된 스킬 호출 — `/<이름> [입력]`, 실패 시 `/<이름> resume <run-id>`
5. 필요하면 그 스킬을 다른 파이프라인의 노드로 참조 (`skill: <이름>`)

설계 스펙: `docs/superpowers/specs/2026-08-02-agent-kit-pipeline-node-design.md`
