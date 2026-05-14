---
scope:
  include: ["plugins/autopilot/skills/loop/SKILL.md"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "head -10 plugins/autopilot/skills/loop/SKILL.md | grep -E '^allowed-tools:.*Monitor'"
ears_language: ko
request_review: true
---

# autopilot:loop SKILL.md allowed-tools Monitor 추가

## 무엇을 만들 것인가
loop 스킬이 본문에 명시된 동작("자동 Monitor 가설")을 수행할 때 사용자 권한 prompt 없이 Monitor 도구를 호출할 수 있도록 스킬 메타데이터에 자동 허용 선언을 추가한다. 본문은 변경하지 않고 메타데이터만 보강한다.

## 수용 기준 (EARS)
- 시스템은 loop 스킬의 메타데이터에 Monitor 도구의 자동 허용을 선언한다.
- 메타데이터가 sibling spec 스킬과 동일한 키 형식을 사용할 때, 시스템은 그 값에 Monitor를 포함한다.
- loop 스킬을 invoke한 세션에서 Monitor 도구가 호출되는 경우, 시스템은 별도 권한 prompt 없이 호출이 진행되도록 허용한다.

## 범위
포함:
- loop 스킬 메타데이터 파일 (frontmatter 영역만)

비-목표 / 제외:
- loop 본문의 동작 변경
- loop가 호출하는 그 외 도구(Bash 하위 룰·Skill·Agent 등)의 자동 허용 보강 (별도 backlog)
- spec·다른 sibling 스킬의 frontmatter 수정

## 검증
이 명령이 0 exit으로 끝나야 합니다:
head -10 plugins/autopilot/skills/loop/SKILL.md | grep -E '^allowed-tools:.*Monitor'

## 제약
스킬 메타데이터는 YAML 1.2 호환 한 줄 키-값 형식. 기존 `name`·`description` 키 순서·형식을 유지하며 sibling 스킬과 동일한 키 이름·값 형식을 사용한다.
