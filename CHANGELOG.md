# Changelog

이 저장소의 **사용자 가시(behavior-changing) 변경**을 기록합니다. 버전의 단일 출처(SoT)는 각 플러그인의 `plugin.json`이며(`rules/engineering/versioning.md`), 본 파일은 변경이 머지될 때마다 누적합니다. 분류: 새 기능 / 변경(호환) / 변경(깨짐) / 버그 수정 / 보안.

## autopilot 0.41.0

### 새 기능
- **`autopilot:flow` 스킬 추가** — Workflow Replica 하니스(Python 표준 라이브러리만으로 동작하는 독립 DAG 오케스트레이터)의 진입점. 내장 dynamic Workflow 도구가 미가용인 환경에서도 임의 `depends_on` DAG를 스트리밍 fan-out·동시성 상한·실패 이행 격리·저널 resume·결과 전달로 실행한다. CLI 러너(`flow run <정의.py>` / `flow selftest` / `flow deps`), 기계 판독 JSON 출력.
