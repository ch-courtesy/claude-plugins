---
scope:
  include:
    - plugins/autopilot/skills/dispatch/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# rubric-fix-dispatch

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리는 제약으로. -->
dispatch 스킬의 두 루브릭 지적을 해소한 산출물을 만든다:

1. **S-NO-XML 해소**: `plugins/autopilot/skills/dispatch/SKILL.md` 본문(코드펜스 밖)에서 대문자 XML 태그를 모두 제거한다. 꺾쇠 placeholder는 백틱/코드펜스 또는 비-꺾쇠 표기로, 강조·주의-강제 태그는 마크다운 강조(굵게·머리말·인용)로 치환한다. 원래의 주의 강제력과 의미 효과를 보존한다.
2. **S-README 해소**: `plugins/autopilot/skills/dispatch/README.md`를 신규 작성한다. 내용은 스킬 무엇·언제·호출 방법을 계약·포인터 수준으로 짧게 담는다. SKILL.md 본문 내용을 복제하지 않는다.

## 목적 (왜)
토스 스킬 품질 루브릭 30항목 중 S-NO-XML·S-README가 FAIL로 판정됐다. 대문자 XML 태그 제거로 스킬 파일이 루브릭 규칙 게이트를 통과하게 하고, README 추가로 사람 독자가 스킬 진입점을 빠르게 파악할 수 있게 한다. 두 수정 모두 트리거 정확도·동작 계약에 영향을 주지 않으면서 품질 기준을 충족시킨다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

- **[S-NO-XML]** 항상: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/autopilot/skills/dispatch/SKILL.md` 재실행 시 S-NO-XML 항목이 `passed=true`이다.
- **[S-README]** 항상: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/autopilot/skills/dispatch/SKILL.md` 재실행 시 S-README 항목이 `passed=true`이다.
- **[불변식]** 항상: 스킬의 트리거 의미·서브커맨드 목록(start/list/status/driver/concurrency/stop/watch/sweep)·공개 호출 인터페이스(`Skill(skill="dispatch", args="<subcommand> [<args>]")`)·절차 의미가 보존된다.

## 범위
포함:
- `plugins/autopilot/skills/dispatch/SKILL.md`
- `plugins/autopilot/skills/dispatch/README.md` (신규 생성)

비-목표 / 제외:
- `plugins/autopilot/skills/dispatch/references/` 내 헬퍼 파일(`dispatch.sh`, `subagent-prompt.md` 등) — 이번 수정 대상이 아님
- `rules/**` — 룰 파일 수정 없음
- 다른 스킬 폴더 — 이번 SPEC의 범위 밖
- 루브릭 자체(`skill-rubric` 플러그인) — verbatim 보존, 완화하지 않음
- "루브릭 S-NO-XML 정책 자체"는 바꾸지 않는다 — 스킬을 정책에 맞춘다

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 루브릭은 verbatim — 스킬을 고치되 루브릭 규칙·정책은 수정하지 않는다.
- SKILL.md 동작·공개 계약 의미 불변 — 서브커맨드 동작, 트리거, 호출 인터페이스를 바꾸지 않는다.
- no-code-duplication — README·references 분리 시 단일 출처 유지; README는 SKILL.md 본문을 복제하지 않고 포인터·계약 수준으로만 쓴다.
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/autopilot/skills/dispatch/SKILL.md`로 S-NO-XML·S-README 항목 PASS 확인.

## 위험
- **강조 보존 위험**: dispatch SKILL.md는 "헤드리스 동기 완주 강제", "거짓 성공 금지", "블랙박스 경계" 같은 안전-불변식 강조에 대문자 XML 태그를 사용한다. 이를 마크다운 강조(굵게·머리말·인용)로 치환하면 LLM의 주의 강제력이 약해질 수 있다 — 원래 강조 의도를 동등한 마크다운 강조로 반드시 보존해야 한다.
- **키워드 보강이 트리거 과확장을 유발할 위험**: S-NO-XML 수정 과정에서 문구를 바꿀 때 트리거 키워드가 확장돼 의도치 않은 스킬 활성화가 생길 수 있다 — 기존 트리거 키워드 의미를 유지하는 최소 치환만 한다.
- **README 과설계 위험**: README에 SKILL.md 내용을 재서술하면 단일 출처 위반이 된다 — 계약·포인터 수준(무엇·언제·호출)만 담고 구현 세부 사항은 SKILL.md를 링크로 포인팅한다.
