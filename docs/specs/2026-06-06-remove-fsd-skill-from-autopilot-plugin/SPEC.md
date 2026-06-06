---
scope:
  include:
    - plugins/autopilot/skills/fsd/**
    - plugins/autopilot/skills/using-autopilot/**
    - plugins/autopilot/skills/spec/SKILL.md
    - plugins/autopilot/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
    - rules/context.md
  exclude:
    - CLAUDE.md
    - docs/specs/**
    - plugins/autopilot/skills/dispatch/**
    - plugins/autopilot/skills/loop/**
    - plugins/autopilot/skills/review/**
ears_language: ko
---

# Remove fsd skill from autopilot plugin

## 무엇을 만들 것인가

autopilot 플러그인에서 **`fsd` 스킬을 통째로 제거**한다. fsd는 "자연어 의도 → spec → intake → start → poll"을 task 단위로 닫던 최상위 오케스트레이터였다. 이 스킬과 그 모든 references(셸 스크립트·문서·task body 표준 포함)를 삭제하고, 플러그인 매니페스트·마켓플레이스에서 등록을 해제하며, fsd를 가리키던 진입점(`using-autopilot`)·`spec` 스킬의 참조를 정리(delink)한다.

autopilot은 fsd 제거 후 **`spec` / `loop` / `dispatch` / `review` 4-skill family**로 좁혀진다. `spec`은 SPEC 문서 산출, `loop`은 단일 SPEC 로컬 자율 실행, `dispatch`는 준비된 SPEC당 서브에이전트가 구현(loop)·리뷰(review)·머지를 소유하는 오케스트레이션, `review`는 다관점 리뷰 생산자로 보존된다.

이 작업의 **최소 범위**는 "fsd 스킬 제거 + 등록 해제 + 깨진 참조 delink"이다. fsd가 수행하던 "spec → dispatch 자동 진입 체인"을 **대체 배선하는 것은 비-목표**(별도 후속 작업)다 — 진입점은 fsd 옵션을 제거하되 spec→dispatch 자동화를 새로 만들지 않는다.

## 목적 (왜)

fsd 오케스트레이션을 트리거/폴링 기반의 새 아키텍처로 재설계하기 위한 **1단계 정리**다. 기존 fsd 파이프라인을 먼저 들어내 표면을 좁히고, 후속에서 대체 진입·구현 경로를 별도로 설계한다. 이 단계는 "제거"에만 집중해 변경 표면을 작게 유지하고, 대체 설계와의 충돌을 피한다.

## 완료 조건

1. 항상 `plugins/autopilot/skills/fsd/` 디렉토리가 존재하지 않는다.
2. 항상 `plugins/autopilot` 트리 어디에도 `fsd` 문자열이 남지 않는다 (`grep -rn fsd plugins/autopilot` 결과 0줄). 매니페스트·`spec`·`using-autopilot` 등 모든 잔존 참조 포함.
3. 항상 `rules/` 트리 어디에도 `fsd` 문자열이 남지 않는다 (`grep -rn fsd rules/` 결과 0줄) — `rules/context.md`의 `task-state-alignment.md` 참조가 제거된 결과.
4. `plugins/autopilot/.claude-plugin/plugin.json`의 `description`이 fsd를 언급하지 않고 **"spec/loop/dispatch/review 4-skill family"**로 기술되며, `version`이 `0.30.0`이고, `jq .`로 유효하다.
5. `.claude-plugin/marketplace.json`의 autopilot 항목 `description`이 fsd를 언급하지 않고 4-skill 구성으로 기술되며, autopilot `version`이 `0.30.0`이고, `jq .`로 유효하다. plugin.json과 marketplace.json의 autopilot description은 기존 관례대로 byte-identical 하게 동기화된다.
6. `using-autopilot/SKILL.md`의 진입 분기가 **spec 단일 경로**로 정리되어, `spec` vs `fsd` 양자택일 서술·`Skill(skill="fsd", ...)` 호출·결정 트리의 fsd 가지·red-flags의 fsd 언급이 남지 않는다. 새 코드 변경을 `spec`으로 라우팅하는 진입점 역할은 보존된다.
7. `spec/SKILL.md`에서 `autopilot:fsd`(상위 자율 오케스트레이터 예시)를 가리키는 언급이 제거되거나 fsd-비종속 일반 서술로 대체되어, spec의 "자율 오케스트레이터 호출 맥락" 규약이 fsd 고유명 없이도 성립한다.
8. 항상 `rules/context.md`가 fsd의 task body 표준(`task-state-alignment.md`)에 의존하지 않는다 — body 머리말 placeholder가 해당 표준과 일치해야 한다는 절(및 그 abort 가드)이 제거되거나, fsd-비종속 서술로 정리된다.
9. 항상 보존 스킬 디렉토리 `plugins/autopilot/skills/{spec,loop,dispatch,review}/`가 존재한다.
10. 항상 보존 스킬 중 selftest를 제공하는 것들이 ALL PASS 한다 — 최소한 `dispatch`(`dispatch.sh`·`integration.sh`·`merge.sh`·`lib-integration.sh`·`review-loop.sh`)·`loop` selftest가 통과한다(무손상 회귀 가드).
11. 항상 보존 스킬·매니페스트·rules 어디에도 삭제된 fsd 스킬을 가리키는 dangling 참조가 없다(완료 조건 2·3의 결과로 보장).

## 범위

포함:
- `plugins/autopilot/skills/fsd/**` 전체 삭제 (`task-state-alignment.md` 포함).
- `plugins/autopilot/.claude-plugin/plugin.json`·`.claude-plugin/marketplace.json`의 fsd 등록 해제, description 4-skill 갱신, version `0.30.0`.
- `using-autopilot/SKILL.md` 진입 분기 spec 단일화 — fsd 가지 제거.
- `spec/SKILL.md`의 fsd 오케스트레이터 참조 delink.
- `rules/context.md`의 `task-state-alignment.md` 참조·의존 절 제거.

비-목표 / 제외:
- **spec → dispatch 자동 진입 체인 대체 배선** — fsd가 하던 "spec 산출 후 자동 구현 위임"을 새로 만들지 않는다(별도 후속 작업).
- `dispatch`·`loop`·`review` 스킬 변경 — **보존**.
- 트리거/폴링 기반 새 오케스트레이션 설계·구현(이 milestone의 후속).
- `CLAUDE.md` 변경.
- `docs/specs/**`의 과거 fsd 관련 SPEC 히스토리 변경(보존).
- `claude-skills/` 듀얼 트리·`.codex-plugin` 매니페스트(미머지 `feat/codex-plugin-manifests` 라인) — 본 SPEC은 main 단일 `skills/` 트리 기준. 듀얼 트리 정합은 그 라인 머지 시 별도 처리.

## 검증

이 SPEC의 인수 바는 위 **완료 조건**이다. 검증 진입 명령은 프로젝트 규칙(`rules/`)이 단일 출처다. 핵심 자동 검증:

```bash
test ! -d plugins/autopilot/skills/fsd
! grep -rn fsd plugins/autopilot && ! grep -rn fsd rules/
jq -e '.version=="0.30.0"' plugins/autopilot/.claude-plugin/plugin.json
jq -e '.plugins[] | select(.name=="autopilot") | .version=="0.30.0"' .claude-plugin/marketplace.json
bash plugins/autopilot/skills/dispatch/references/dispatch.sh selftest
```

## 제약

- **버전 범프는 `rules/engineering/versioning.md`를 따른다.** `plugins`는 워치 디렉토리이므로 같은 머지 안에서 SoT(plugin.json)·미러(marketplace.json)가 함께 올라가야 한다. 현재 0.29.0 → **0.30.0**.
- **`rules/context.md` 수정은 관행("`rules/**` 미수정")의 의도적 예외**다 — fsd task body 표준을 폐기하기로 한 결정에 따라 단일 출처 참조를 제거하기 위함이며, 사용자 선택으로 승인되었다.
- 셸 스크립트·매니페스트는 기존 호환성(bash 3.2+·`jq .` 유효)을 유지한다.
- `SKILL.md` 편집은 `superpowers:writing-skills` 관례를 따른다.

## 위험

- **task body 표준 폐기의 파급** — `rules/context.md`의 body-sync placeholder 표준(단일 출처)이 사라진다. 현재 그 표준을 소비하던 task 생성 경로는 fsd와 함께 제거되므로 즉시 깨지는 소비자는 없으나, 후속에서 새 오케스트레이션이 task body를 만들 때 표준을 다시 정의해야 한다. 후속 작업의 선결 조건으로 남긴다.
- **진입점 축소** — `using-autopilot`가 fsd("끝까지 자동") 경로를 잃고 spec 단일로 좁아진다. "자연어 → 자동 구현"을 원하는 사용자 경험은 후속 재배선 전까지 공백이다. 의도된 단계적 제거이며, 후속 작업이 대체 경로를 제공한다.
- **codex 듀얼 트리 라인과의 충돌** — `feat/codex-plugin-manifests`가 fsd를 포함한 듀얼 트리를 갖는다. 본 SPEC이 main에 머지된 뒤 그 라인은 fsd 삭제를 반영해 리베이스/정합해야 한다(별도).
