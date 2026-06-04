---
scope:
  include:
    - plugins/autopilot/skills/dispatch/**
    - plugins/autopilot/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
  exclude:
    - rules/**
    - CLAUDE.md
    - plugins/autopilot/skills/loop/**
    - plugins/autopilot/skills/spec/**
    - plugins/autopilot/skills/fsd/**
    - plugins/autopilot/skills/review/**
ears_language: ko
---

# Dispatch integration loop-to-branch bridge

## 무엇을 만들 것인가

dispatch 통합 모드(기본 활성)가 loop 구현 결과를 작업 브랜치로 잇는 누락된 단계를 메운다. 현재 forge·direct 두 서브모드 모두 `feat/<run-id>-<slug>` 브랜치의 **이름만** 계산하고, 그 브랜치에 loop 결과 커밋이 이미 있다고 가정한 채 checkout(forge)·ff-only 머지(direct)를 시도한다. 그러나 loop은 결과를 자기 워크트리에만 커밋하고 dispatch run-id 기반 브랜치를 만들지 못하므로, 첫 통합에서 대상 브랜치가 없어 실패한다(phase=blocked). 통합이 기본 켜짐이라 정상 DONE SPEC도 PR·머지에 닿기 전에 깨진다.

이 갭을 메운다: dispatch 통합이 **loop의 공개 인터페이스로 구현 결과를 얻어** `feat/<run-id>-<slug>` 작업 브랜치를 만들고(없을 때 생성), 그 위에서 기존 통합 흐름(forge: base 동기화→push→PR / direct: ff-only 머지)을 잇는다.

## 목적 (왜)

통합 모드가 기본 활성인데 핵심 다리가 끊겨 있어 정상 구현조차 통합 단계에서 차단된다(Codex가 PR #317 리뷰에서 integration.sh 의 checkout 단계로 지적한 실제 버그). 이 다리를 연결해 통합 모드를 실제로 동작하게 만든다.

## 완료 조건

1. 통합이 작업 브랜치(`feat/<run-id>-<slug>`)를 push·머지 대상으로 쓰기 전에, 그 브랜치가 없으면 **loop 구현 결과를 가리키는 커밋에서 새로 만든다**. 이미 있으면 그대로 쓴다(재실행 멱등). 어떤 경로에서도 force(강제)로 브랜치를 옮기지 않는다.
2. 통합이 loop 구현 결과의 위치(작업 트리/커밋)를 **loop의 공개 인터페이스**(`loop paths`/`loop status --json`)로만 얻는다 — loop 내부 신호 파일·워크트리 경로를 직접 열어 읽지 않는다.
3. 브랜치 생성 단계는 forge 서브모드와 direct 서브모드가 **같은 공통 헬퍼**를 거친다(두 경로에 중복 구현이 없다).
4. 정상 구현 완료(loop DONE) 시, 작업 브랜치가 처음부터 없던 상태에서도 통합이 phase=blocked 로 떨어지지 않고 forge 서브모드는 push·PR 단계까지, direct 서브모드는 머지 단계까지 전진한다.
5. `bash plugins/autopilot/skills/dispatch/references/integration.sh selftest` 가 ALL PASS 하며, 그 안에 **"대상 작업 브랜치가 없는 상태에서 loop 결과 커밋으로 브랜치가 생성되어 통합이 전진한다"** 를 관찰하는 케이스가 포함된다(브랜치 부재를 실제로 모사 — 현재처럼 checkout 을 무조건 성공시키지 않는다).
6. `bash plugins/autopilot/skills/dispatch/references/dispatch.sh selftest`, `bash .../merge.sh selftest`, `bash .../lib-integration.sh selftest` 가 모두 ALL PASS 한다(통합 스케줄러·머지·상태 헬퍼 무손상).
7. 통합 경로의 어떤 git 호출에도 force/`-f` 인자가 없다(selftest 의 mock git 이 force 인자를 보면 즉시 실패하도록 강제되어 있고, 그 가드가 통과한다).
8. `plugins/autopilot/.claude-plugin/plugin.json` 과 `.claude-plugin/marketplace.json` 의 autopilot version 이 동일하게 한 단계 올라가 있고, 두 파일 모두 `jq .` 로 유효하게 파싱된다.
9. 항상 `plugins/autopilot/skills/{loop,spec,fsd,review}/` 와 `rules/`, `CLAUDE.md` 는 변경되지 않는다(공개 인터페이스만 소비·보존).

## 범위

포함:
- `dispatch/references/integration.sh`(및 필요한 경우 형제 모듈)에 loop 결과→작업 브랜치 생성 다리 추가, forge·direct 서브모드 공통 헬퍼화
- 그 다리가 loop 공개 인터페이스(`loop paths`/`status --json`)로 결과 위치를 얻도록 연결
- dispatch 통합 selftest 보강(브랜치 부재 모사 + 생성·전진 검증)
- `plugin.json`·`marketplace.json` 버전 범프(둘 다, 일치)

비-목표 / 제외:
- `loop`·`spec`·`fsd`·`autopilot:review` 스킬 정의 파일 수정 — **보존**(공개 인터페이스만 소비)
- 통합 모드의 리뷰·승인·머지 정책 변경(이 작업은 "브랜치 이식" 한 단계만 메운다)
- 외부 CI 리뷰 워크플로·`rules/` 변경

## 검증

이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약

- force(강제) push·branch·rebase·merge 를 어떤 경로에서도 쓰지 않는다(머지는 ff-only).
- 작업 브랜치명·slug 는 `rules/engineering/branch-and-slug.md`(`feat/<id>-<slug>`)를 단일 출처로 따른다.
- 통합 모듈은 loop·spec·fsd 스킬의 **공개 인터페이스만** 소비하고 그 정의 파일을 수정하지 않는다.
- 셸 스크립트는 bash 3.2+ 호환을 유지한다.
- 버전 정합: `plugin.json`(단일 출처)과 루트 `marketplace.json`(미러)을 함께 올린다. 버전 범프 규율은 `rules/engineering/versioning.md` 를 따른다.
- `SKILL.md` 편집이 필요하면 `superpowers:writing-skills` 관례를 따른다.

## 위험

- loop 공개 인터페이스가 결과 커밋 식별자를 직접 주지 않고 작업 트리 경로만 줄 수 있다 — 그 경우 공개 경로에서 결과 커밋을 읽는 것까지가 "공개 인터페이스 소비"의 경계이며, loop 내부 신호·메타 파일을 직접 열지 않는다(완료 조건 2가 고정).
- 브랜치가 이미 존재하는 재실행에서 force 로 옮기면 원격 PR head 와 어긋난다 — 완료 조건 1·7이 force 금지·멱등을 고정한다.
