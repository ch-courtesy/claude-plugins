---
name: pipeline
description: "노드들을 연결한 워크플로 그래프를 정의하고 자립 실행형 워크플로 스킬로 컴파일할 때 사용. 사용자가 파이프라인 생성, 워크플로 자동화 구성, 노드 연결, 파이프라인 컴파일·목록을 요청할 때 활성화."
allowed-tools:
  - AskUserQuestion
  - Read
  - Write(.pipelines/**)
  - Write(.claude/skills/**)
  - Glob
  - Grep
  - Bash(ls:*)
  - Bash(find:*)
  - Bash(mkdir -p .pipelines/**)
  - Bash(mkdir -p .claude/skills/**)
  - Bash(shasum:*)
  - Bash(jq:*)
  - Bash(date:*)
---

# pipeline

입출력이 있는 노드들을 연결해 실행 흐름을 정의하고, 그 정의를 **자립 실행형 워크플로 스킬**로 컴파일한다.

**핵심 원칙: 정의 = 소스, 생성된 스킬 = 바이너리.** 정의는 `.pipelines/<이름>.yaml`, 컴파일 결과는 `.claude/skills/<이름>/`. 정의를 수정하면 재컴파일한다. 실행은 컴파일된 스킬이 담당하며 이 스킬에 run 서브커맨드는 없다.

## 호출

`pipeline create` / `pipeline compile <이름>` / `pipeline list` — 인자가 없으면 `create`로 간주한다. 파이프라인 이름은 kebab-case, 같은 이름 정의가 있으면 덮어쓰지 말고 다른 이름 또는 갱신 여부를 선택받는다.

## 정의 계약

- 파일: `.pipelines/<이름>.yaml` **단일 파일 1개**. 스키마는 `references/pipeline-schema.md`를 따른다.
- 노드 인스턴스는 라이브러리 타입 참조(`type:`), 유틸(`util:`), 일회용 인라인(`inline:`) 셋 중 하나다.
- edge는 따로 선언하지 않는다 — `$노드id.출력` 참조에서 의존성을 자동 도출한다. 의존이 없는 노드끼리는 자동 병렬 대상이다.
- 유틸 노드 5종(if/switch, foreach, merge, transform, human-gate)의 시맨틱은 `references/util-nodes.md`를 따른다.
- 공통 속성: `retry`(기본 0), `timeout`(초), `on_error: fail(기본) | continue`.

## create 워크플로

1. **목표 인터뷰.** 파이프라인의 목적, 트리거 시점의 입력, 최종 산출물을 AskUserQuestion으로 한 주제씩 확정한다.
2. **노드 도출.** 목표를 단계로 분해하고 각 단계를 노드에 대응시킨다. `.pipelines/nodes/`의 기존 타입을 먼저 매칭하고, 없는 노드는 `node` 스킬의 create 워크플로를 이 자리에서 수행해 만든다. 한 번 쓰고 말 간단한 노드는 인라인으로 정의한다.
3. **그래프 구성.** 노드 인스턴스와 입력 매핑(`in:`)을 작성한다. 분기·순회·합류·재성형·승인이 필요한 지점에 유틸 노드를 배치한다.
4. **정의 제시.** 완성한 YAML 전문을 사용자에게 보여주고 승인받은 뒤 `.pipelines/<이름>.yaml`로 저장한다.
5. **컴파일.** 승인 직후 compile 워크플로를 이어서 수행한다. 사용자 프로젝트 `.gitignore`에 `.pipelines/runs/`가 없으면 추가를 제안한다.

## compile 워크플로

1. **validate.** `references/validate-checklist.md`의 전 항목을 정의에 적용한다. 하나라도 실패하면 산출물을 만들지 않고 위반 목록(노드 id, 항목, 수정 방법)을 보고한다.
2. **스냅샷.** 정의 + 참조된 모든 노드 타입 YAML을 병합해 `.claude/skills/<이름>/graph.yaml`로 저장한다. 인라인·유틸 노드도 포함해 **이 파일만으로 그래프 전체가 재구성 가능**해야 한다.
3. **스킬 생성.** `references/compile-template.md`의 골격대로 `.claude/skills/<이름>/SKILL.md`를 작성한다. frontmatter의 `compiled-from`에 `.pipelines/<이름>.yaml @<정의 파일 shasum-256 앞 12자리>`를 기록한다.
4. **보고.** 산출 경로, 노드 수, 사용 kind 목록, 호출법(`/<이름> [입력]`)을 보고한다.

## list 워크플로

`.pipelines/*.yaml`을 읽어 이름, 설명, 노드 수를 표로 보고한다. 각 항목에 대해 `.claude/skills/<이름>/SKILL.md`의 `compiled-from` 해시와 현재 정의의 shasum을 대조해 `미컴파일 | 최신 | 재컴파일 필요`를 표시한다. 파일을 생성·수정하지 않는다.

## 참조 파일

| 파일 | 읽는 시점 |
|---|---|
| `references/pipeline-schema.md` | 정의 YAML 작성·해석 |
| `references/util-nodes.md` | 유틸 노드 배치와 시맨틱 확인 |
| `references/validate-checklist.md` | compile 1단계 검증 |
| `references/compile-template.md` | 컴파일 산출물 작성 |

## 안전 경계

- 쓰기는 `.pipelines/**`와 `.claude/skills/**` 안으로 제한한다.
- 이 스킬은 파이프라인을 실행하지 않는다 — 노드의 command·API를 호출하는 것은 컴파일된 스킬(사용자가 별도 호출)의 몫이다.
- validate를 통과하지 못한 정의로 산출물을 만들지 않는다.
- 기존 `.claude/skills/<이름>/`을 덮어쓸 때는 compiled-from이 같은 정의를 가리킬 때만 조용히 갱신하고, 다른 스킬이면 사용자 확인을 받는다.
