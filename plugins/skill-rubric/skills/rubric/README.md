# rubric

SKILL.md 파일을 토스 기술블로그 '[스킬 품질 루브릭](https://toss.tech/article/skill-quality-rubric)'
30항목(규칙 17 + 모델 13)으로 평가해 등급(S/A/B/C/F)과 지적 목록을 산출하는 스킬.

## 호출

```
Skill(skill="rubric", args="<SKILL.md 경로 | all>")
```

- 경로 하나를 주면 그 SKILL.md만 평가한다.
- `all`이거나 인자가 없으면 저장소의 모든 SKILL.md를 평가한다.

## 구성

- `SKILL.md` — 오케스트레이션 절차(규칙 검사 실행 → 모델 검사 → 병합·등급 → 리포트)
- `references/rule_checker.py` — 결정적 규칙 17항목 검사기(Python; frontmatter YAML 파싱은 `yq`(mikefarah)에 위임)
- `references/rubric-definitions.md` — 의미적 모델 13항목 판정 기준
- `references/output-schema.json` — JSON 리포트 스키마

규칙 검사기는 단독 실행도 된다:

```
python3 references/rule_checker.py <SKILL.md 경로 | all [repo_root]>
```

의존성: `yq`(mikefarah, frontmatter YAML 파싱)와 `bash`(스크립트 syntax 검사). yq가 없으면
종료 코드 5로 끝난다. 이 저장소의 다른 스킬 검증 테스트와 동일한 의존성이다.

## 정책

루브릭은 토스 글 그대로(verbatim) 적용한다. 본문에 대문자 XML 태그를 쓰는 스킬은
`S-NO-XML` BLOCKER로 F가 되며, 이는 의도된 정책이다.
