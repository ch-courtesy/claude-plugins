# autopilot:prd · dispatch — 다중 task 자율 분해·실행 설계

**Issue**: #63
**Date**: 2026-05-11
**Status**: Design (under review)

## 1. 개요

`autopilot` 플러그인을 4-skill family로 확장한다. 기존 `spec`/`loop`(single-task)에 대칭되는 multi-task 페어 `prd`/`dispatch`를 추가하고, 저장 구조를 `milestones/<m>/{prd,dispatch,loops}/`로 통일한다.

**책임 분담**

| scope | writer | executor + ops |
|---|---|---|
| single-task | `spec` (existing) | `loop` (existing) |
| multi-task | **`prd` (new)** | **`dispatch` (new)** |

**전형적 호출 흐름**

```
1. Skill(skill="prd", args="<m>")
   → milestones/<m>/prd/PRD.md 작성·승인 (9-step 대화)
2. Skill(skill="dispatch", args="<m>")
   → PRD 분해 → DAG 표시 → 사용자 승인 (게이트 ①)
   → child SPEC들 spec 위임 작성 (게이트 ②)
   → DAG 최종 확인 (게이트 ③)
   → wave 단위 병렬 loop 실행, fail-fast
   → 결과 보고
```

**외부 PRD 우회** — Notion·Linear 등에서 작성한 PRD는 `Skill(skill="prd", args="<m> --import <path>")`로 들여와 자체 검토 → 마커 박힘 → `--resume`로 해결 후 dispatch.

## 2. 저장 구조

```
milestones/<m>/                      # commit 대상
├── prd/PRD.md                       # prd 산출물
├── dispatch/
│   ├── DAG.md                       # 분해 plan (dispatch 산출, commit)
│   └── DISPATCH_LOG.md              # 런타임 로그 (gitignore)
└── loops/<c>/SPEC.md                # spec 위임 산출물

<project>-loops/<m>/<c>/             # 워크트리 (loop.sh 관리, gitignore)
├── (repo copy)
├── .loop/{PLAN,NOTES,HANDOFF,RUN_LOG}.md
└── DONE 또는 .loop/ESCALATION.md
```

**`regular` milestone (catch-all)** — ad-hoc 단일 task(큰 milestone에 속하지 않는 일회성 작업)는 `milestones/regular/loops/<id>/SPEC.md`에 저장. PRD 없음. dispatch ops는 가능하지만 `dispatch start regular`는 거부(PRD 부재).

## 3. task-id 규칙

`loop.sh validate_task_id` 그대로 유지(슬래시 허용, `..`·`.` 컴포넌트 금지, `__` 금지, 공백 금지) + 추가 강제:

- 항상 `<milestone>/<task>` 2-컴포넌트
- 단일 컴포넌트 입력 시 `regular/` 자동 prefix
- 3+ 컴포넌트 미지원 (분해 깊이 ≤ 2)

**SPEC 경로** — `milestones/<m>/loops/<c>/SPEC.md`가 단일 진실. v0.1의 `.loops/<id>/SPEC.md`는 v0.2부터 deprecated, fallback 1 minor 버전 유지.

**경로 결정 순서** (loop.sh 분기)
1. task-id 정규화 — 단일 컴포넌트면 `regular/<input>` prefix
2. 새 경로 시도 — `milestones/<m>/loops/<c>/SPEC.md`
3. 부재 시 legacy fallback — `.loops/<원본-task-id>/SPEC.md` (deprecated 경고 출력)
4. 둘 다 부재면 abort

## 4. autopilot:prd 스킬

`spec` 9-step의 mirror. PRD-flavored 차이만 정리:

| 축 | spec | prd |
|---|---|---|
| 단위 | 단일 task | 다중 task로 분해될 큰 task |
| 포맷 | EARS 강제 (Independent-Test) | PRD-friendly 자유 산문 |
| 검증 명령 | 단일 `verify` 정의 | 정의 안 함 (sub-task별로 dispatch가 정의) |
| 마커 거부자 | loop | dispatch |
| 출력 | `milestones/<m>/loops/<c>/SPEC.md` | `milestones/<m>/prd/PRD.md` |

**9-step 흐름**

1. **사전 검사** — task-id 형식, `milestones/<m>/prd/` 충돌
2. **컨텍스트 탐색** — `git log -5`, CLAUDE.md, `rules/`, 기존 milestones
3. **명확화 라운드** — 한 질문씩: 핵심 문제 → 비전·목표 → 성공 기준 → 범위(포함·비-목표) → 제약 → 위험·금지 영역
4. **접근법 비교** (조건부) — 비-자명한 설계 결정 포함 시 2-3 접근법 제시
5. **섹션별 PRD 제시·승인** — 제목 → 문제 → 목표 → 성공 기준 → 범위 → 제약 → 위험 → 분해 힌트(선택)
6. **PRD.md 작성** — `references/prd-template.md` 치환, `mkdir -p milestones/<m>/prd/` 후 기록
7. **자체 검토 5축** — placeholder · 모순 · 범위(decomposable) · 모호성 · 마커 잔존
8. **사용자 최종 검토** — `AskUserQuestion`으로 승인·변경
9. **다음 단계 안내** — `Skill(skill="dispatch", args="<m>")` 또는 마커 잔존 시 `--resume`

**모드**

- **기본** — 새 PRD 대화 작성
- **`--import <path>`** — 외부 PRD 임포트. step 7 자체 검토부터 시작 → 부족 부분 마커 → `--resume` 안내
- **`--resume`** — 마커 박힌 PRD 해결 라운드. 마커 위치 기준 step 4·6 좁힘

**references/**

| 파일 | 역할 |
|---|---|
| `prd-template.md` | PRD 자유 산문 템플릿 (placeholder) |
| `self-review.md` | 5축 체크리스트 (일부 spec과 공유) |

## 5. autopilot:dispatch 스킬 — 분해 단계

**입력 검증** (단계 1) — `milestones/<m>/prd/PRD.md` 존재 + `[NEEDS CLARIFICATION` 마커 0개. 미충족 시 abort + 안내.

**분해 알고리즘** (단계 2)

PRD 헤딩·범위·성공 기준에서 후보 단위 추출 후, 각 단위가 다음 3 조건 동시 충족 검사:

1. **단일 컨텍스트 윈도우 fit** — `spec` 9-step + `loop` 30 iter 안에 끝낼 수 있는가
2. **테스트 폐쇄성** — 자체 verify 명령으로 닫히는가
3. **격리성** — 다른 단위와 같은 파일을 동시 수정하지 않는가

**휴리스틱의 부정확성과 게이트 ① 보정** — 위 3 조건은 PRD 텍스트 정적 분석에 기반하므로 부정확. 단위가 너무 크거나 의존성이 누락될 수 있음. 게이트 ①에서 사용자가 분해 결과를 검토·수정할 수 있게 하여 알고리즘의 한계를 보정한다.

**하드 캡** — 1차 분해 ≤ 8 단위, 재귀 분해(=알고리즘이 1 단위를 더 작은 단위들로 다시 쪼개는 백트래킹) 깊이 ≤ 2, 최종 산출 ≤ 20 단위. 초과 시 abort + 사용자에게 PRD 자체 분해 권고.

**의존성·wave 계산** (단계 3) — 단위 간 dependency(파일·산출물) 추출 → 토포 정렬 → wave 그룹화. cycle 감지 시 즉시 abort + 보고.

**게이트 ① 분해 plan 승인** (단계 4)

```
wave 1 (parallel-safe): [child-a, child-b]
  - child-a: <한 줄> | 파일 [src/a/**] | verify [pytest tests/a]
  - child-b: <한 줄> | 파일 [src/b/**] | verify [pytest tests/b]
wave 2 (depends on wave 1): [child-c]
  - child-c: ...
```

옵션: `(a) 승인` `(b) 분해 수정` (자연어 피드백으로 단계 2 재실행) `(c) 취소`.

**DAG.md 작성** (단계 5) — `mkdir -p milestones/<m>/dispatch/` 후 DAG.md 작성. 승인된 plan + 의존성 + wave 정렬 기록. (`prd` 스킬은 `prd/`만 생성, `dispatch/`는 dispatch가 처음 진입 시 만든다.)

**spec 위임** (단계 6, 게이트 ②) — wave 순서·노드별 `Skill(skill="spec", args="<m>/<c>")` 호출. spec 9-step 그대로 진행. 입력 컨텍스트로 PRD 본문 + 분해 plan 항목 전달.

**최종 확인 게이트 ③** (단계 7) — 모든 SPEC 작성 후 표 재제시: SPEC 경로·verify 명령·의존성. 사용자 최종 승인 → 실행 단계.

## 6. autopilot:dispatch 스킬 — 실행 단계

```
for wave in waves:
  for child in wave:
    loop start <m>/<c>            # 백그라운드, 워크트리·lock은 loop이 처리

  while wave 진행 중:
    각 child의 sentinel 파일 watch:
      <project>-loops/<m>/<c>/DONE                  → 성공
      <project>-loops/<m>/<c>/.loop/ESCALATION.md   → 실패

    누군가 ESCALATION:
      나머지 진행 중 child들에 loop stop  # fail-fast
      DISPATCH_LOG.md 기록
      ESCALATION 카테고리·보고서 사용자 제시
      다음 wave 차단 + 종료 (재계획은 사용자)

    모두 DONE:
      DISPATCH_LOG.md 기록 → 다음 wave

모든 wave 통과: 최종 보고서 + 종료
```

**기존 loop과의 분업** — 워크트리·lock·iteration 상한·헌법 준수는 모두 `loop.sh`가 처리. dispatch는 sentinel 파일(`DONE`·`.loop/ESCALATION.md`) **존재만** 감시. 외부 셸 루프 표준 유지(in-process Stop 훅 사용 안 함).

**보고서 (wave 종료마다 + 전체 종료 시)**

```
wave 1 / 3 (완료, 12분)
| child   | status | iter | exit | 비고          |
|---------|--------|------|------|---------------|
| child-a | DONE   | 5/30 | 0    | clean         |
| child-b | DONE   | 8/30 | 0    | fix:symptom×1 |
```

ESCALATION 시 카테고리(config-gap·spec-gap·architecture-gap·environment-gap·other) + 보고 본문 그대로 제시.

## 7. autopilot:dispatch 스킬 — ops 서브커맨드

`loop`과 대칭. dispatch가 milestone-level ops도 책임 (별도 `milestone` 스킬 없음).

| 명령 | 동작 |
|---|---|
| `dispatch start <m>` (또는 `dispatch <m>`) | 분해+실행. PRD 부재 시 거부. |
| `dispatch status <m>` | 정식 milestone: PRD·DAG·child 진행 상태. regular: child loop 상태만. |
| `dispatch stop <m>` | 진행 중 모든 child loop stop + DISPATCH_LOG 기록. |
| `dispatch list` | 모든 milestone(regular 포함) 목록 + 상태. |
| `dispatch cleanup [<m>]` | 완료 milestone의 워크트리·child loops 정리. PRD/DAG 보존. |
| `dispatch logs <m>` | DISPATCH_LOG.md 출력. |
| `dispatch resume <m>` | 분해 미완 또는 wave 중단 상태 이어가기. |

## 8. 자기완결성 충돌 처리

**문제** — 헌법: 마커 박힌 SPEC은 loop이 거부.

**4중 가드**

1. `prd` step 9 — PRD 마커 잔존 시 `prd --resume` 안내, 정상 종료 안 됨
2. `prd --import` 자체 검토 — 외부 PRD 부족 부분 자동 마커 + `--resume` 강제
3. dispatch 입구 게이트 — PRD 마커 0개 아니면 즉시 abort
4. `spec` step 9 — child SPEC도 동일. 사용자 대화 흐름이라 마커 자동 생성 없음

**`[ASSUMED: ... because ...]` 패턴 미도입** — 단계별 게이트 + spec 위임 모델에서는 마커 자동 생성이 발생하지 않으므로 불필요.

## 9. loop.sh 변경 범위

- SPEC 경로 결정: `milestones/<m>/loops/<c>/SPEC.md` 우선, 없으면 기존 `.loops/<task-id>/SPEC.md`로 fallback (legacy)
- 단일 컴포넌트 task-id 입력 시 `regular/` 자동 prefix
- v0.1 → v0.2: legacy 경로 사용 시 deprecated 경고
- 워크트리 경로 (`<project>-loops/<task-id>/`) 변경 없음

## 10. 테스트 전략

**`prd` 스킬**
- 9-step 흐름 (입력 검증·자체 검토·`--resume`·`--import` 모드)
- 템플릿 placeholder 치환
- `tests/autopilot/test-skill-install.sh` 패턴 추가

**`dispatch` 스킬**
- 분해 휴리스틱 (3 조건 + 하드 캡)
- DAG 토포 정렬 + cycle 감지
- 게이트 3종 (분해 plan·spec 위임·최종 확인)
- sentinel watch (DONE/ESCALATION 파일)
- fail-fast 동작 (다른 child stop)
- ops 서브커맨드 7종

**`loop.sh`**
- SPEC 경로 결정 분기 단위 테스트
- legacy fallback 경고 메시지

**통합**
- `prd → dispatch → spec(mock) → loop(mock)` end-to-end (single happy + 1 fail-fast 시나리오)

## 11. 비-목표 / 향후

- **Devin식 dynamic re-planning 미도입** — 통제 불가 위험. 재계획은 사용자 책임.
- **`[ASSUMED: ... because ...]` 패턴 미도입** — §8 참조.
- **3+ depth nesting 미지원** — 분해 깊이 ≤ 2.
- **외부 통합(GitHub Issue·branch 자동 생성 등)** — 본 스킬 책임 아님. 프로젝트 룰 영역.

## 12. 마이그레이션 (v0.1 → v0.2)

- 기존 `.loops/<id>/SPEC.md` 사용자에게 deprecated 경고 + 자동 이주 도움말 (`.loops/<id>/SPEC.md → milestones/regular/loops/<id>/SPEC.md`)
- 한 minor 버전 동안 fallback 유지, v0.3에서 제거
- 기존 테스트 스위트 경로 일괄 업데이트
