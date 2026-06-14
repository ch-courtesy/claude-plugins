---
scope:
  include:
    - plugins/autopilot/skills/spec/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# rubric-fix-spec

## 무엇을 만들 것인가

`autopilot:spec` 스킬(`plugins/autopilot/skills/spec/SKILL.md`)과 스킬 폴더에 다음 변경을 가한다:

- SKILL.md 본문(코드펜스 밖)의 대문자 XML 태그를 마크다운 강조(굵게·머리말·인용)로 교체한다.
- `{{...}}` 형태의 리터럴 placeholder 잔재를 제거하거나 코드펜스 안 예시 또는 비-꺾쇠 서술로 이전한다.
- description의 트리거 표현을 적정 범위로 좁힌다(라우팅 의도는 보존).
- 본문이 참조를 2단계 이상 연쇄하는 경우 1단계로 평탄화한다(내용 중복 없이).
- 스킬 폴더에 사람 대상 `README.md`를 신규 추가한다(무엇·언제·호출 계약·포인터 수준).

## 목적 (왜)

`autopilot:spec` 스킬이 토스 스킬 품질 루브릭 30항목 평가에서 S-NO-XML·S-README·R-PLACEHOLDER·T-SCOPE·R-NESTED 항목에 FAIL을 받았다. 이 지적을 해소해 루브릭 품질 게이트를 통과하고, description 트리거 정확도를 높여 오발동 위험을 줄이며, 단일 출처 원칙을 유지하면서 스킬의 신뢰성을 높인다. 스킬의 동작·공개 계약·호출 방법은 변경하지 않는다.

## 완료 조건

- 항상, `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/autopilot/skills/spec/SKILL.md` 재실행 시 S-NO-XML 항목이 `passed=true`이다.
- 항상, 위 rule_checker.py 재실행 시 S-README 항목이 `passed=true`이다(`plugins/autopilot/skills/spec/README.md` 존재 확인 포함).
- 항상, 위 rule_checker.py 재실행 시 R-PLACEHOLDER 항목이 `passed=true`이다.
- rubric 모델 재평가 시 T-SCOPE 항목이 PASS이다(근거: description이 "어떤 작업이든 시작하기 전"처럼 무제한 범위 표현을 쓰지 않고, 명확화 인터뷰·SPEC 문서 작성·구현 스킬 추천의 진입점 라우팅 의도가 구체 트리거 조건으로 표현된다).
- rubric 모델 재평가 시 R-NESTED 항목이 PASS이다(근거: SKILL.md 본문이 어떤 정보를 얻으려 할 때 references → 또 다른 references를 다시 타는 2단계 연쇄 없이, 1단계 직접 참조로 해당 정보의 단일 출처를 가리킨다).
- 항상, 위 변경 후에도 스킬의 호출 시그니처(`Skill(skill="spec", args="...")`)·서브커맨드(`--resume`)·절차(1–7단계)·외부 상태 비생성 계약이 이전과 동일하게 유지된다(불변식).

## 범위

포함:
- `plugins/autopilot/skills/spec/SKILL.md`
- `plugins/autopilot/skills/spec/references/**` (R-NESTED 평탄화 시 필요한 참조 파일)
- `plugins/autopilot/skills/spec/README.md` (신규 추가)

비-목표 / 제외:
- 다른 스킬 폴더(`plugins/autopilot/skills/spec/` 외 모든 스킬)
- `rules/**` (프로젝트 규칙 파일 일체)
- 플러그인 메타(`plugin.yaml`, `AGENTS.md` 등 스킬 외 파일)
- 루브릭 자체(`skill-rubric` 플러그인 및 `rule_checker.py` 포함) — 루브릭 verbatim 정책은 바꾸지 않는다.
- S-NO-XML 등 루브릭 평가 기준 자체의 완화·수정.

## 검증

이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약

- 루브릭은 verbatim이다 — 스킬을 고치되 루브릭(`rule_checker.py` 포함)은 수정하지 않는다.
- SKILL.md의 동작·공개 계약 의미(호출 방법·서브커맨드·절차·외부 상태 비생성)는 변경하지 않는다.
- no-code-duplication: README와 references 분리 시 내용을 복제하지 않는다 — README는 계약·포인터 수준으로만, 세부 내용은 SKILL.md 또는 references가 단일 출처를 유지한다.
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/autopilot/skills/spec/SKILL.md` 로 규칙 항목(S-NO-XML·S-README·R-PLACEHOLDER) PASS를 확인한다.

## 위험

- S-NO-XML 치환 시 강조·주의-강제용 XML 태그를 마크다운 강조로 바꾸면 LLM의 주의 강제력이 약해질 수 있다 — 강조 보존(굵게·인용·머리말 선택)이 필요하다.
- T-SCOPE 수정 시 트리거 키워드 보강이 오히려 트리거 과확장으로 이어져 T-SCOPE가 악화될 수 있다 — 키워드는 진입점 라우팅 의도를 반영한 최소 범위로 한정한다.
- R-NESTED 평탄화 시 참조 연쇄를 제거하면서 중요한 위임 관계가 손실될 수 있다 — 내용 중복 없이 1단계 직접 참조로만 재연결한다.
- README 추가 시 SKILL.md의 핵심 내용을 중복 서술하면 no-code-duplication 위반이 된다 — README는 무엇·언제·호출 계약·포인터만 담는다.
