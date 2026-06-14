---
scope:
  include:
    - plugins/autopilot/skills/review/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# rubric-fix-review

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리는 제약으로. -->
`plugins/autopilot/skills/review` 스킬의 루브릭 3개 지적(S-README, T-KEYWORDS, R-NESTED)을 해소한다.

- **S-README**: 스킬 폴더에 사람 대상 `README.md`를 신규 추가한다. 스킬의 무엇·언제·호출 방법을 계약·포인터 수준으로 담되 `SKILL.md` 본문 내용을 복제하지 않는다.
- **T-KEYWORDS**: `SKILL.md` 상단 `description` 필드에 사용자가 실제로 쓸 자연어 동의어·키워드를 보강한다. 스킬의 WHAT/WHEN 구조와 동작 의미는 바꾸지 않고 트리거 매칭 표면만 넓힌다.
- **R-NESTED**: `SKILL.md` 본문 내에서 references가 또 다른 references를 경유하는 2단계 참조 연쇄를 제거한다. 본문이 필요한 참조를 1단계로 직접 가리키도록 평탄화하되 내용을 중복 복제하지 않는다.

## 목적 (왜)
토스 스킬 품질 루브릭 30항목 게이트를 통과해 스킬의 공식 품질 기준을 충족한다. `description` 키워드 보강으로 LLM 트리거 매칭 정확도를 높이고, README 추가로 사람이 스킬을 빠르게 파악할 수 있게 한다. 참조 평탄화로 단일 출처 원칙을 유지하면서 스킬 본문의 탐색 신뢰성을 높인다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

1. **[S-README]** `plugins/autopilot/skills/review/README.md` 파일이 존재하며, `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/autopilot/skills/review/SKILL.md` 재실행 시 S-README 항목이 `passed=true`이다.

2. **[T-KEYWORDS]** rubric 모델 재평가 시 T-KEYWORDS 항목이 PASS이다(근거: `description` 필드에 "코드 리뷰", "PR 리뷰", "변경 검토", "diff 분석", "머지 전 검증" 등 실제 사용자 표현이 포함되어 트리거 매칭 표면이 충분히 넓어진 것이 확인됨).

3. **[R-NESTED]** rubric 모델 재평가 시 R-NESTED 항목이 PASS이다(근거: `SKILL.md` 본문의 references 테이블이 실제 파일을 1단계로 직접 가리키며, "X를 참조하는 Y를 참조한다"는 2단계 연쇄 문장이 존재하지 않음이 확인됨).

4. **[불변식]** 스킬의 트리거 의미·동작·공개 계약이 보존된다. 항상 서브커맨드(`run`/`status`/`list`) 인터페이스, 4 lens 구조, 판정 값(`approve`/`request_changes`/`unavailable`), `review.sh` 하니스 역할, 불변식/규칙 조항이 수정 전과 동일하게 유지된다.

## 범위
포함:
- `plugins/autopilot/skills/review/SKILL.md` — description 키워드 보강 및 R-NESTED 평탄화 대상
- `plugins/autopilot/skills/review/README.md` — 신규 생성 대상(S-README 해소)
- `plugins/autopilot/skills/review/references/**` — R-NESTED 연쇄 확인을 위한 읽기 대상(내용 변경은 필요한 경우에 한함)

비-목표 / 제외:
- 다른 스킬 폴더(`plugins/autopilot/skills/` 하위 review 외) — 변경 없음
- `rules/**` — 리뷰 9원칙·채택 분류 프레임 등 규칙 파일 자체는 변경하지 않음
- 플러그인 메타(`plugins/autopilot/plugin.json` 등) — 변경 없음
- `skill-rubric` 스킬 자체 및 루브릭 평가 정책 — "루브릭 verbatim 정책은 바꾸지 않는다"
- `references/review.sh`, `references/agent-prompts.md`, `references/output-schema.json` 의 동작 로직 — 행동 변경 없음(읽기만)
- S-NO-XML 등 이번 지적에 포함되지 않은 루브릭 항목 수정

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 루브릭은 verbatim — 스킬을 고치되 루브릭 자체는 수정하지 않는다.
- `SKILL.md`의 동작·공개 계약 의미 불변 — 서브커맨드 인터페이스·4 lens 구조·판정 값·하니스 역할·불변식 조항을 바꾸지 않는다.
- no-code-duplication — `README.md`는 계약·포인터 수준으로 작성하고 `SKILL.md` 본문을 그대로 옮기지 않는다. references 평탄화 시에도 내용을 중복 복제하지 않는다.
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/autopilot/skills/review/SKILL.md` 로 규칙 항목(S-README 포함) PASS 확인.

## 위험
- **T-KEYWORDS 과확장**: `description` 키워드 보강이 트리거 범위를 과도하게 넓혀 T-SCOPE(스코프 과확장) 악화로 이어질 수 있다 — 실제 사용자 표현만 추가하고 스킬 동작과 무관한 범용 키워드는 넣지 않는다.
- **R-NESTED 평탄화 오탈자**: 참조 연쇄를 끊을 때 링크 대상 경로를 잘못 쓰면 broken reference가 생긴다 — 평탄화 후 각 참조 경로가 실제 파일로 해소되는지 확인한다.
- **README 내용 중복**: README에 `SKILL.md` 설명을 재서술하면 no-code-duplication 위반이 된다 — README는 스킬명·목적 한 줄·호출 형식·SKILL.md 포인터로만 구성한다.
