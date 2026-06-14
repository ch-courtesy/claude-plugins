---
scope:
  include:
    - plugins/autopilot/skills/using-autopilot/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# rubric-fix-using-autopilot

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리는 제약으로. -->
`using-autopilot` 스킬의 루브릭 검사 실패 항목(S-NO-XML, S-README)을 해소한다.

- **S-NO-XML**: `SKILL.md` 본문(코드펜스 밖)에 존재하는 대문자 XML 태그(`<EXTREMELY-IMPORTANT>` 등)를 제거하고, 원래 주의-강제·의미 효과를 마크다운 강조(굵게·머리말·인용·수평선 등)로 보존한 형태로 치환한다. 꺾쇠 placeholder가 있으면 백틱 또는 비-꺾쇠 표기로 전환한다.
- **S-README**: 스킬 폴더(`plugins/autopilot/skills/using-autopilot/`)에 사람 대상 `README.md`를 신규 작성한다. 내용은 "이 스킬이 무엇인지·언제 활성화되는지·어떻게 호출하는지"를 계약·포인터 수준으로 짧게 기술하고, `SKILL.md` 본문 내용을 복제하지 않는다.

## 목적 (왜)
루브릭 품질 게이트(S-NO-XML, S-README)를 통과시켜 스킬이 검증 가능한 기준을 충족하도록 한다. XML 태그 제거는 마크다운 렌더러에서 태그가 노출되거나 파서가 오동작하는 위험을 없애고, 강조 보존은 LLM이 주의-강제 의도를 잃지 않도록 신뢰성을 유지한다. README 추가는 스킬 발견 가능성과 사람 가독성을 높이되 단일 출처 원칙을 깨지 않는다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

1. **S-NO-XML 통과**: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/autopilot/skills/using-autopilot/SKILL.md` 재실행 시 `S-NO-XML` 항목이 `passed=true`로 보고된다.

2. **S-README 통과**: 위 `rule_checker.py` 재실행 시 `S-README` 항목이 `passed=true`로 보고된다.

3. **불변식 — 트리거·동작·계약 보존**: 언제나, `SKILL.md`의 트리거 목록(기능 추가·동작 수정·지침 작성·SPEC 구현·새로 만들기), 예외 목록, 합리화 구멍 차단 로직, 파이프라인 설명, `spec` 스킬 라우팅 계약의 의미가 수정 전과 동일하게 유지된다. 기존 호출·서브커맨드·절차 의미는 변하지 않는다.

## 범위
포함:
- `plugins/autopilot/skills/using-autopilot/SKILL.md` — S-NO-XML 수정 대상
- `plugins/autopilot/skills/using-autopilot/README.md` — S-README 신규 작성 대상

비-목표 / 제외:
- 다른 스킬 파일 (`plugins/autopilot/skills/` 하위 `using-autopilot` 외 경로)
- `rules/**` — 카테고리 지침은 수정하지 않는다
- 플러그인 메타(`plugins/autopilot/plugin.json` 등)
- 루브릭 자체(`skill-rubric` 플러그인 파일, 루브릭 verbatim 정책) — 루브릭을 완화하거나 수정하지 않는다; 스킬만 고친다

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- **루브릭 verbatim**: 루브릭 자체는 수정하지 않는다. 스킬이 루브릭 기준에 맞게 수정된다.
- **SKILL.md 동작·공개 계약 의미 불변**: 트리거·예외·라우팅 로직·파이프라인 설명 등 동작 의미를 바꾸지 않는다. 표현(마크다운 형식)만 바꾼다.
- **단일 출처 유지(no-code-duplication)**: `README.md`는 계약·포인터 수준으로 쓰고 `SKILL.md` 본문 내용을 복제하지 않는다.
- **수정 후 규칙 항목 PASS 확인**: 수정 완료 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/autopilot/skills/using-autopilot/SKILL.md` 를 실행해 S-NO-XML, S-README 항목이 PASS인지 확인한다.

## 위험
- **강조 약화 위험**: `<EXTREMELY-IMPORTANT>` 같은 XML 강조 태그를 마크다운으로 치환할 때 LLM 주의-강제력이 약해질 수 있다. 굵게·머리말·인용·수평선 조합으로 원래의 강조 의도를 명시적으로 보존해야 한다.
- **트리거 오염 위험**: 꺾쇠 placeholder(`<자연어 task 설명>` 등)를 백틱으로 전환하는 과정에서 트리거 예시 텍스트가 의도치 않게 변형될 수 있다. 의미 변경 없이 형식만 바꾼다.
- **README 과설계 위험**: README를 너무 상세하게 쓰면 SKILL.md와 내용이 중복된다. 계약 포인터(무엇·언제·어떻게 호출) 수준으로만 기술하고 구현 세부는 SKILL.md에 위임한다.
