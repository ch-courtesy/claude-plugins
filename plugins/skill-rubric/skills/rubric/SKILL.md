---
name: rubric
description: "SKILL.md 파일을 토스 '스킬 품질 루브릭' 30항목(규칙 17 + 모델 13)으로 평가해 등급(S/A/B/C/F)과 지적 목록을 산출하고 싶을 때 사용 — 스킬 품질 점검, 스킬 작성 검토, 루브릭 평가, 품질 등급 확인, 신규 스킬 검증 시 활성화. 호출 'Skill(skill=\"rubric\", args=\"<SKILL.md 경로 | all>\")'."
allowed-tools:
  - Read
  - Write(.tmp/**)
  - Bash(python3 *rule_checker.py*:*)
  - Bash(find *:*)
  - Bash(date:*)
  - Bash(git rev-parse:*)
---

# rubric

SKILL.md 파일을 토스 기술블로그 '[스킬 품질 루브릭](https://toss.tech/article/skill-quality-rubric)'
6개 섹션 30개 항목으로 채점해 **등급(S/A/B/C/F)과 지적 목록**을 낸다.

검사는 둘로 나뉜다:
- **규칙 검사 17항목** — `references/rule_checker.py`가 정규식·카운트·syntax 검사로 결정적으로 판정한다.
- **모델 검사 13항목** — 의미적 판정이라 에이전트가 `references/rubric-definitions.md` 기준으로 직접 판정한다.

루브릭은 토스 글 그대로(verbatim) 적용한다. 그 결과 본문에 대문자 XML 태그를 쓰는 스킬은
`S-NO-XML` BLOCKER로 F가 되는데, 이는 의도된 정책이며 버그가 아니다.

## 절차

호출 시 단계를 TodoWrite로 등록하고 순서대로 수행한다.

### 1. 입력 해석

`args`로 평가 대상을 받는다.
- 인자가 없거나 `all`이면 저장소 전체를 평가한다. 저장소 루트는 `git rev-parse --show-toplevel`로 구한다.
- 단일 경로가 오면 그 SKILL.md 하나만 평가한다.

### 2. 규칙 검사 실행 (결정적 17항목)

스킬 디렉터리의 검사기를 실행한다:

```
python3 <스킬경로>/references/rule_checker.py <SKILL.md 경로 | all [repo_root]>
```

stdout의 JSON을 수집한다. `results[].checks`에 규칙 17항목이 `check_type: "rule"`로 담긴다.
검사기 실행이 실패하면(파이썬 부재 등) 오류를 사용자에게 알리고 중단한다.

### 3. 모델 검사 (의미적 13항목)

`references/rubric-definitions.md`를 읽고, 평가 대상 SKILL.md(필요하면 그 `references/`까지)를
직접 읽어 13개 모델 항목을 판정한다. 각 항목은 `check_type: "model"`로 기록하며 evidence에
그 파일의 실제 문장·구조를 근거로 적는다. 확신이 없으면 보수적으로 FAIL한다.

여러 스킬을 평가할 때는 스킬마다 2–3단계를 순차로 반복한다(서브에이전트 분기 없이 단순하게).

### 4. 병합·등급

스킬별로 규칙 17 + 모델 13 결과를 합쳐 등급을 매긴다:

- BLOCKER ≥ 1 → **F**
- BLOCKER 0, MAJOR 0 → **S**
- BLOCKER 0, MAJOR 1–2 → **A**
- BLOCKER 0, MAJOR 3–4 → **B**
- BLOCKER 0, MAJOR 5+ → **C**

MINOR는 등급을 가르지 않지만 개수를 함께 센다.

### 5. 출력

- **JSON**: 규칙+모델을 합친 최종 리포트를 `references/output-schema.json` 형식으로 만들어
  `.tmp/rubric-<타임스탬프>.json`에 Write한다(타임스탬프는 `date +%Y%m%d-%H%M%S`).
- **마크다운 리포트**: 사용자에게 직접 표시한다. 스킬마다 등급 헤더와 지적 표(항목ID·섹션·항목·심각도·유형·결과·근거)를 내고, `all` 모드면 마지막에 전체 요약 표를 덧붙인다.

## 출력 형식 (마크다운)

스킬 1개 블록 예시:

```markdown
### plugins/<plugin>/skills/<skill>/SKILL.md — 등급 **F**

BLOCKER 1 | MAJOR 0 | MINOR 1

| 항목ID | 섹션 | 항목 | 심각도 | 유형 | 결과 | 근거 |
|--------|------|------|--------|------|------|------|
| S-NO-XML | 구조 | 본문에 XML 태그 없음 | BLOCKER | 규칙 | FAIL | 대문자 XML 태그 발견 |
```

`all` 모드 전체 요약:

```markdown
## 전체 요약 (S a / A b / B c / C d / F e)

| 스킬 | 플러그인 | 등급 | BLOCKER | MAJOR | MINOR |
|------|---------|------|---------|-------|-------|
```

## 규칙

- 결정적 17항목은 반드시 `rule_checker.py`로 판정한다 — 손으로 재현하지 않는다.
- 모델 13항목은 `rubric-definitions.md` 기준을 따른다.
- 임시 산출물(JSON 리포트)은 `.tmp/` 아래에만 둔다.
- 루브릭은 verbatim이다. 이 저장소 스킬이 F로 나와도 임의로 완화하지 않는다.
