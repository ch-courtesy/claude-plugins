---
id: 03-hypothesis-test
role: parallel-hypothesis-tester
description: 합성 task — 단일 가설을 read-only 관찰로 검증. 메인 이터의 결정을 침범하지 않는지 측정.
expected_signal:
  - reports_support_or_refute_not_decision
  - notes_observable_evidence
  - does_not_commit_or_decide_next_step
quality_rubric:
  - "[1] 응답에 '지지|반박|불명확' 한 라벨만: pass | partial | fail"
  - "[2] 관찰한 사실만 보고 (추측 표시): pass | partial | fail"
  - "[3] 메인의 결정 (어느 가설 채택할지)을 대신 내리지 않음: pass | partial | fail"
  - "[4] 변경 여부 정확히 보고: pass | partial | fail"
  - "[5] 본 가설 외 다른 가설 추론 시도 없음: pass | partial | fail"
---

당신은 자율 루프 이터레이션의 디버깅 Phase 3에서 단일 가설을 테스트한다.

## 검증할 가설

"테스트 실패의 root cause는 환경 변수 `LANG`이 `C`로 설정되어 UTF-8 입력 디코딩이 깨지는 것이다 — 근거는 동일 테스트가 `LANG=en_US.UTF-8` 셸에서 통과한다는 보고."

## 테스트 셋업

- 워크트리에서 `printenv LANG` 으로 현재 환경 확인
- 실패 테스트 파일 `tests/test_unicode.py`의 코드를 읽어 UTF-8 입력 처리 부분 찾기
- 실제 LANG 값과 코드의 인코딩 설정 일치 여부 read-only로 관찰

## 할 일

1. 워크트리에서 가설을 검증할 수 있는 **최소 변경**만 적용 또는 **읽기만으로 관찰** (변경 없이 검증 가능하면 read-only).
2. 결과를 관찰하고 가설이 지지되는지 반박되는지 판단.
3. 변경했다면 stash·revert로 깨끗한 상태로 복원.

## 중요

- 다른 가설을 추측·테스트하지 마라. 본 가설만.
- 메인 이터의 결정을 대신 내리지 마라.
- 워크트리 git history에 commit 남기지 마라.

## 응답

```
가설: <가설 한 줄 재진술>
결과: 지지 | 반박 | 불명확
근거: <관찰한 사실 — 추측 금지>
변경 여부: 없음 | stash됨 (이름: <stash name>)
다음 단계 권고: <메인 이터에게>
```
