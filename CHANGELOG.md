# Changelog

이 저장소의 **사용자 가시(behavior-changing) 변경**을 기록합니다. 버전의 단일 출처(SoT)는 각 플러그인의 `plugin.json`이며(`rules/engineering/versioning.md`), 본 파일은 변경이 머지될 때마다 누적합니다. 분류: 새 기능 / 변경(호환) / 변경(깨짐) / 버그 수정 / 보안.

## skill-rubric 0.1.0

### 새 기능
- **`skill-rubric` 플러그인 추가** — 토스 기술블로그 '스킬 품질 루브릭' 6개 섹션 30개 항목(규칙 17 + 모델 13)으로 SKILL.md를 평가해 등급(S/A/B/C/F)과 지적 목록을 산출하는 `rubric` 스킬. 결정적 17항목은 Python 검사기(`rule_checker.py`)가 정규식·카운트·syntax 검사로 판정하고(frontmatter YAML 파싱·유효성은 `yq`(mikefarah)에 위임), 의미적 13항목은 스킬을 실행하는 에이전트가 판정한다. `Skill(skill="rubric", args="<SKILL.md 경로 | all>")`로 단일·전체 평가, 마크다운 리포트 + JSON 산출. 루브릭은 verbatim 적용(본문 XML 태그 = BLOCKER).

## autopilot 0.41.0

### 새 기능
- **`autopilot:flow` 스킬 추가** — Workflow Replica 하니스(Python 표준 라이브러리만으로 동작하는 독립 DAG 오케스트레이터)의 진입점. 내장 dynamic Workflow 도구가 미가용인 환경에서도 임의 `depends_on` DAG를 스트리밍 fan-out·동시성 상한·실패 이행 격리·저널 resume·결과 전달로 실행한다. CLI 러너(`flow run <정의.py>` / `flow selftest` / `flow deps`), 기계 판독 JSON 출력.
