# skill-rubric — 스킬 품질 루브릭 평가 도구

## 무엇을 만들 것인가

SKILL.md 파일을 토스 기술블로그 '[스킬 품질 루브릭](https://toss.tech/article/skill-quality-rubric)'
6개 섹션 30개 항목으로 평가해 등급(S/A/B/C/F)과 지적 목록을 산출하는 새 플러그인 스킬을 만든다.
결정적 17항목은 규칙 검사기가, 의미적 13항목은 스킬을 실행하는 에이전트가 판정한다.
단일 SKILL.md 또는 저장소 전체를 평가하고, 마크다운 리포트와 머신리더블 JSON을 모두 낸다.

## 목적 (왜)

이 저장소는 여러 플러그인의 스킬을 관리하지만 스킬 품질을 일괄 평가하는 공통 루브릭/린터가 없고,
검증이 스킬별 스크립트에 분산돼 있다. 일관된 채점 기준 하나로 스킬 품질의 결정적 결함과
의미적 약점을 함께 잡아 작성·리뷰 시 품질 게이트로 쓰기 위함이다.

## 완료 조건

- 항상 `rule_checker.py <SKILL.md 경로>`를 실행하면 17개 규칙 항목을 담은 유효 JSON을 stdout에 낸다.
- 본문에 대문자 XML 태그가 있는 SKILL.md를 평가할 때 `S-NO-XML` BLOCKER로 표시되고 등급이 F가 된다.
- `all`(또는 인자 없음)으로 실행하는 동안 `plugins/*/skills/*/SKILL.md` 전체가 평가되고 스킬별 결과·등급 요약이 나온다.
- `rubric` 스킬을 호출하면 규칙 17 + 모델 13을 병합한 마크다운 리포트와 `.tmp/` 아래 JSON 파일이 산출된다.
- 등급 산정이 규칙대로면(BLOCKER≥1→F / B0·M0→S / B0·M1-2→A / B0·M3-4→B / B0·M5+→C) 그 등급이 보고된다.
- 테스트(`tests/skill-rubric/test-rubric-checker.sh`)를 실행하면 good/bad 픽스처 케이스가 모두 통과한다.
- `rubric` 스킬 자신을 규칙 검사기로 평가하면 17항목을 모두 통과한다(BLOCKER 0).

## 범위에 포함

- 새 플러그인 `skill-rubric` / 스킬 `rubric` (`plugin.json` 0.1.0, `marketplace.json` 등록)
- Python 규칙 검사기 17항목 + JSON 스키마 (frontmatter YAML 파싱은 yq(mikefarah)에 위임)
- 모델 검사 13항목 기준 문서(`rubric-definitions.md`)
- 스킬 오케스트레이션 본문(규칙 실행 → 모델 검사 → 병합·등급 → 리포트)
- good/bad 픽스처 + bash 테스트

## 범위에서 제외

- GitHub Actions PR 자동 평가 통합(후속)
- 검사 결과를 바탕으로 한 자동 수정(린트-픽스)
- 루브릭의 저장소 맞춤 완화(verbatim 정책 — XML 태그 BLOCKER 유지)

## 제약

- 구현 언어는 Python. frontmatter YAML 파싱·유효성 판정은 yq(mikefarah)에 위임한다
  (직접 만든 YAML 파서의 문법 엣지 오판을 피하기 위함 — 이 저장소의 다른 스킬 검증 테스트와 동일한 의존성).
- 형태는 새 플러그인 스킬이며 호출은 `Skill(skill="rubric", args="<SKILL.md 경로 | all>")`.
- 루브릭은 토스 글 그대로(verbatim) 적용한다.
- 기존 컨벤션을 따른다: 스킬은 `plugins/<plugin>/skills/<skill>/`, 스크립트·기준 문서는 `references/`,
  테스트는 `tests/` 아래 bash(`set -euo pipefail`, echo OK/FAIL).
- 임시 산출물(JSON 리포트)은 `.tmp/` 아래에만 둔다(`.gitignore` 등록).
- `plugins/` 변경이므로 `plugin.json`이 버전 SoT이고 `CHANGELOG.md`에 기록한다.

## 위험

- verbatim 정책상 이 저장소 자기 스킬 다수가 F로 나온다(의도된 결과이나 사용자 혼동 가능 — 정책임을 리포트/문서에 명시).
- 규칙 검사기의 정규식이 오탐/누락할 수 있다(예: 시점 키워드, 평문 secret). 픽스처 테스트로 회귀를 막는다.

## 검증

완료 조건이 인수 기준의 단일 출처다. 검증 진입 명령은 프로젝트 규칙(`rules/`)에서 온다.
주요 확인: `bash tests/skill-rubric/test-rubric-checker.sh` 통과, `rubric` 스킬 자가평가 BLOCKER 0,
`rule_checker.py all` 전체 평가 산출.
