# agent-kit

입출력이 있는 노드를 연결해 실행 흐름(파이프라인)을 만들고, 그 정의를 독립 실행 가능한 워크플로 스킬로 컴파일하는 플러그인.

**핵심 원칙: 정의 = 소스, 생성된 스킬 = 바이너리.** 정의 YAML을 수정하면 재컴파일한다. 실행은 컴파일된 스킬이 담당한다.

## 스킬

| 스킬 | 역할 |
|---|---|
| `node` | 재사용 가능한 노드 타입(입출력 스키마 + 실행법) 생성·단독 테스트·목록 |
| `pipeline` | 노드를 연결한 그래프 정의 생성, 검증, 자립형 워크플로 스킬 컴파일 |

## 사용자 프로젝트 레이아웃

```
.pipelines/<이름>.yaml          # 파이프라인 정의 (커밋 대상)
.pipelines/nodes/<이름>.yaml    # 재사용 노드 타입 라이브러리 (커밋 대상)
.pipelines/runs/<run-id>/       # 실행 기록 — .gitignore에 추가할 것
.claude/skills/<이름>/          # 컴파일된 워크플로 스킬
```

## 흐름

1. `node create` — 노드 타입 정의 (llm / script / http / mcp)
2. `node test <이름>` — 모의 입력으로 단독 실행, 출력 스키마 검증
3. `pipeline create` — 목표 인터뷰 → 그래프 구성 → validate → compile
4. 생성된 스킬 호출 — `/<이름> [입력]`, 실패 시 `/<이름> resume <run-id>`

설계 스펙: `docs/superpowers/specs/2026-08-02-agent-kit-pipeline-node-design.md`
