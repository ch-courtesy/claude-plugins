# thinktank 1.2.0 정량 검증 측정 runbook

## 개요

이 runbook은 brainstorm·roundtable 스킬의 1.2.0 릴리스 게이트를 구성하는
정량 검증 측정 절차를 기술한다. 하니스(`tests/thinktank/measure-session.sh`)와
고정 시나리오 픽스처를 사용해 재현 가능한 게이트 판정을 수행한다.

---

## 경로 구조

| 항목 | 경로 |
|---|---|
| 하니스 | `tests/thinktank/measure-session.sh` |
| roundtable 픽스처 | `tests/thinktank/fixtures/roundtable/scenario-01.md` |
| brainstorm 픽스처 | `tests/thinktank/fixtures/brainstorm/scenario-01.md` |
| 측정 기록 디렉토리 | `tests/thinktank/measurements/` |

---

## 표준 측정 절차

### 1단계 — 하니스 셀프테스트 확인

측정 시작 전 하니스가 정상 동작하는지 확인한다.

```bash
bash tests/thinktank/measure-session.sh --selftest
```

성공 시: `SELFTEST PASSED` 출력, exit 0.
실패 시: 하니스 수정 후 재실행. 측정 진행 불가.

### 2단계 — 픽스처 해시 계산

측정 기록에 기재할 픽스처 해시를 계산한다.

```bash
# roundtable 픽스처 해시
shasum -a 256 tests/thinktank/fixtures/roundtable/scenario-01.md

# brainstorm 픽스처 해시
shasum -a 256 tests/thinktank/fixtures/brainstorm/scenario-01.md
```

### 3단계 — 측정 세션 구동

저장소에 커밋된 고정 픽스처를 입력으로 Claude 스킬 세션을 구동한다.
세션은 측정 시점 기본 Claude 모델로 실행한다.

- roundtable: `tests/thinktank/fixtures/roundtable/scenario-01.md` 내용을 roundtable 스킬에 입력
- brainstorm: `tests/thinktank/fixtures/brainstorm/scenario-01.md` 내용을 brainstorm 스킬에 입력

세션 산출물(`.roundtable/*.md` 또는 `.brainstorm/*.md` 형식의 measurement record)을
`tests/thinktank/measurements/` 경로에 저장한다.

### 4단계 — 하니스로 게이트 판정

저장된 측정 기록에 하니스를 실행해 게이트 판정을 수행한다.

```bash
# roundtable 게이트 판정
bash tests/thinktank/measure-session.sh \
  --skill roundtable \
  --record tests/thinktank/measurements/roundtable-pilot-<날짜>.md \
  --judge

# brainstorm 게이트 판정
bash tests/thinktank/measure-session.sh \
  --skill brainstorm \
  --record tests/thinktank/measurements/brainstorm-pilot-<날짜>.md \
  --judge
```

성공 시: 각 지표 `GATE_PASS:` 출력, exit 0.
실패 시: `GATE_FAIL:` 출력 및 non-zero exit — 임계치 미달 지표 확인 후 재측정.

### 5단계 — 측정 기록 작성

측정 기록 파일(`tests/thinktank/measurements/<skill>-pilot-<날짜>.md`)에
아래 메타데이터를 필수 포함한다.

```markdown
## 측정 메타데이터

- skill: <roundtable|brainstorm>
- model-id: <사용된 Claude 모델 ID>
- fixture-path: tests/thinktank/fixtures/<skill>/scenario-01.md
- fixture-hash: sha256:<해시값>
- threshold-<지표명>: <임계치>
- decision-mode: <1회 충족|N회 안정 충족>
- measured-at: <YYYY-MM-DD>
- gate-status: <active|shadow>
- gate-pass-count: <통과 횟수>
- pilot-run-count: <파일럿 실행 횟수>
- measured-variance: <분산 요약>
```

---

## 게이트 임계치 (파일럿 실측 3회 기반)

### roundtable 임계치 (gate-status: active)

| 지표 | 임계치 | decision-mode |
|---|---|---|
| dissent-forcing-triggered | yes | 1회 충족 |
| rebuttal-exchange | ≥1 왕복 | 1회 충족 |
| core-claim | ≥1 개 | 1회 충족 |

### brainstorm 임계치 (gate-status: active)

| 지표 | 임계치 | decision-mode |
|---|---|---|
| core-fact | ≥1 개/세션 | 1회 충족 |
| independent-sources | ≥2 | 1회 충족 |
| park-recondition 충족률 | 100% (fail-loud 강제) | 1회 충족 |
| elimination-reason 충족률 | 100% (fail-loud 강제) | 1회 충족 |

파일럿 분산: 3회 측정 모두 동일 판정 — 분산 없음. `decision-mode: 1회 충족` 채택.

---

## 측정 기록 무효화 규칙

다음 중 하나가 발생하면 기존 측정 기록은 게이트 근거로 사용할 수 없으며 **재측정**이 필요하다.

1. **픽스처 변경**: `fixture-hash`가 기록값과 달라진 경우
2. **임계치 변경**: `threshold-*` 값이 기록값과 달라진 경우
3. **판정 방식 변경**: `decision-mode`가 기록값과 달라진 경우
4. **모델 교체**: `model-id`가 기록값과 달라진 경우 (모델 교체 시 재검증 절차 참조)

재측정 후 새 측정 기록 파일을 생성하고 기존 파일을 `[INVALIDATED]` 접두사로 표시하거나 삭제한다.

---

## 모델 교체 시 재검증 절차

사용 모델이 변경되면 임계치가 여전히 유효한지 재검증해야 한다.

### 트리거 조건

- `model-id`가 기존 측정 기록과 다른 Claude 모델로 측정을 실행하려는 경우

### 재검증 단계

1. **픽스처 고정 확인**: 동일 픽스처(fixture-hash 동일)를 사용한다.
2. **파일럿 3회 재실행**: 새 모델로 표준 측정 절차(1단계~5단계)를 3회 반복한다.
3. **분산 분석**: 3회 판정이 모두 일치하면 기존 임계치 유지. 판정이 엇갈리면 아래 절차 진행.
4. **분산 과대 시**: 시나리오 조정 후 파일럿 1회 재실행 (재파일럿 1회 상한).
   그래도 흔들리는 지표는 `gate-status: shadow` (기록 전용)로 강등하고 사유를 기록.
5. **임계치 재제안**: 파일럿 분산 근거를 바탕으로 구현자가 새 임계치를 제안한다.
6. **사용자 승인**: CHANGELOG 1.2.0 섹션의 `- 게이트 승인:` 라인을 갱신하고
   사용자 승인을 받은 뒤 게이트 활성화 커밋을 생성한다.
7. **측정 기록 갱신**: 새 `model-id`·`fixture-hash`·임계치로 측정 기록을 재작성한다.

### 스킬별 안정 지표 최소 요건

모델 교체 후에도 각 스킬에 `gate-status: active` 지표가 최소 1개 남아야 한다.
특정 스킬의 active 지표가 전부 shadow로 강등되면 사용자 보고·승인 후
시나리오·지표를 재설계하고 파일럿을 처음부터 재실행한다.

---

## 계약 가드 테스트 회귀 확인

측정 후 문서 계약 가드 테스트가 회귀하지 않았는지 확인한다.
이 테스트는 하니스(`measure-session.sh`)를 포함하지 않는다.

```bash
for f in tests/thinktank/test-*.sh; do bash "$f" || exit 1; done && echo OK
```

---

## shadow 강등 정책

| 조건 | 처리 |
|---|---|
| 파일럿 3회 판정 일치 | gate-status: active 유지 |
| 파일럿 3회 판정 엇갈림 → 시나리오 조정 후 재파일럿 1회 | 재파일럿 통과 시 active |
| 재파일럿 후에도 엇갈림 | gate-status: shadow 강등, shadow-reason 기록 |
| 스킬 내 active 지표 0개 | 사용자 보고 후 시나리오·지표 재설계 |

---

## 커밋 순서 (2단 구조)

1. **인프라 커밋**: 문서 변경·구조화 마커·픽스처·하니스·파일럿 실측 기록 포함
2. **게이트 활성화 커밋**: CHANGELOG 1.2.0 섹션에 `- 게이트 승인:` 라인 기록 후 생성

> 게이트 활성화 커밋은 사용자 승인 마커가 CHANGELOG에 기록된 뒤에만 만든다.
