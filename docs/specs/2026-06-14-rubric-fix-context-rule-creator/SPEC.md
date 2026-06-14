---
scope:
  include:
    - plugins/project-init/skills/context-rule-creator/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# rubric-fix-context-rule-creator

## 무엇을 만들 것인가

`context-rule-creator` 스킬의 세 가지 루브릭 지적(S-README · R-PLACEHOLDER · T-KEYWORDS)을 해소한다.

- `plugins/project-init/skills/context-rule-creator/README.md` 신규 작성 — 계약·포인터 수준의 짧은 사람 대상 문서(무엇·언제·호출 형식).
- `SKILL.md` 본문 내 `{{...}}` 리터럴 placeholder 잔재 제거 — 메커니즘 설명은 산문 또는 코드펜스 예시로만 표현.
- `SKILL.md` frontmatter `description` 필드에 트리거 동의어·자연어 키워드 보강 — WHAT/WHEN 구조와 동작은 불변.

## 목적 (왜)

루브릭 품질 게이트를 통과해 스킬의 자동·수동 평가 점수를 높이고, 트리거 매칭 표면을 넓혀 사용자가 다양한 표현으로 스킬을 호출할 수 있게 한다. README 추가와 placeholder 제거는 단일 출처 원칙을 지키면서 스킬 신뢰성을 높인다.

## 완료 조건

항상 모든 조건이 독립적으로 검증 가능해야 한다.

- **S-README**: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/context-rule-creator/SKILL.md` 재실행 시 `S-README` 항목 `passed=true`.
- **R-PLACEHOLDER**: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/context-rule-creator/SKILL.md` 재실행 시 `R-PLACEHOLDER` 항목 `passed=true`.
- **T-KEYWORDS**: rubric 모델 재평가 시 `T-KEYWORDS` 항목 PASS(근거: description에 "컨텍스트 지침 생성", "task-model", "task-ops", "sub-룰 파일", "컨텍스트 관리", "context rule" 등 자연어 동의어가 포함되어 트리거 매칭 표면이 명확히 확장됨).
- **불변식**: 스킬의 트리거 의미·동작·공개 계약이 보존된다 — 기존 호출 방식, 생성 절차(1~8단계), 출력 파일명(`task-model.md`·`task-ops.md` 고정), 백엔드 선택 메커니즘, 이벤트 카탈로그가 수정 전후 의미상 동일하다.

## 범위

포함:
- `plugins/project-init/skills/context-rule-creator/SKILL.md`
- `plugins/project-init/skills/context-rule-creator/README.md` (신규)

비-목표 / 제외:
- 다른 스킬 파일 일체
- `rules/**` 카테고리 지침
- 플러그인 메타(plugin.json 등)
- 루브릭 자체(`skill-rubric` 플러그인) 수정
- `templates/` 내용 변경 (placeholder 잔재가 SKILL.md 본문에만 있는지 확인 후, templates는 대상 외로 유지)
- 루브릭 verbatim 정책 변경은 하지 않는다 — 스킬을 고치되 루브릭은 고치지 않는다.

## 검증

이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약

- 루브릭은 verbatim — 스킬을 고치되 루브릭(`skill-rubric` 플러그인)은 수정하지 않는다.
- `SKILL.md`의 동작·공개 계약 의미 불변 — 생성 절차, 출력 파일명, 백엔드 선택 로직, 이벤트 카탈로그, 허용 도구 목록이 의미상 변하지 않아야 한다.
- no-code-duplication — `README.md`는 계약·포인터 수준으로 짧게 작성하고, `SKILL.md` 본문 내용을 복제하지 않는다.
- `SKILL.md` 내 `{{...}}` 제거 시, 본문의 실제 동작 서술(예: "`{{name}}` 치환" 설명)은 산문("name 필드 값으로 치환") 또는 코드펜스 예시로만 표현한다 — 리터럴 placeholder가 본문 prose에 남지 않아야 한다.
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/context-rule-creator/SKILL.md` 로 규칙 항목(S-README · R-PLACEHOLDER) PASS 확인.

## 위험

- **T-KEYWORDS 트리거 과확장**: 키워드 보강이 `T-SCOPE` 악화(과도하게 넓은 트리거)를 유발하지 않게 — description에 추가하는 키워드는 이 스킬이 실제로 담당하는 범위(컨텍스트 sub-룰 파일 생성)와 명확히 연관된 표현만 사용한다.
- **R-PLACEHOLDER 오제거**: `SKILL.md` 내 `{{...}}` 리터럴이 템플릿 동작 설명 문맥(prose)에 나타나는 경우, 그것을 "산출물에 들어가는 실제 placeholder"로 오해해 불필요하게 많은 곳을 고칠 위험 — 루브릭이 지적하는 "본문 잔재"는 치환되지 않고 prose에 리터럴로 남은 경우만 해당하므로 코드펜스 예시나 표(표 셀 내 `{{...}}`) 맥락은 보존 여부를 주의해서 판단한다.
- **README 과작성**: README를 길게 쓰면 SKILL.md 내용을 복제하는 no-code-duplication 위반이 발생 — 계약·호출 포인터 수준(5~10줄 이내)으로 제한한다.
