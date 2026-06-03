---
scope:
  include:
    - rules/orchestration/approved-spec-merge.md
    - docs/specs/2026-06-02-workflow-spec-layout-merge-gate/SPEC.md
    - docs/specs/2026-06-03-consolidate-forge-integration-rule-into-fsd-skill/SPEC.md
  exclude:
    - milestones/**
    - CLAUDE.md
ears_language: ko
---

# approved-spec-merge 룰 제거

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
`rules/orchestration/approved-spec-merge.md` 룰을 레포에서 제거하고, 이 파일을 '활성 단일출처'로 인용하던 과거 SPEC 기록을 제거 사실에 맞게 정리한다. 이 룰은 승인된 SPEC을 구현 위임 제안 전에 main에 머지하라는 호출측 타이밍·우선순위 정책으로, 머지 절차 자체는 보유하지 않고 다른 룰에 위임하던 얇은 정책 레이어였다. 제거 후 동일 디렉터리의 task-state-alignment 룰과 머지 절차 룰은 그대로 유지된다.

## 목적 (왜)
<!-- 이 변경을 왜 하는가(목표·동기)를 1–3문장으로. -->
이 타이밍 정책은 빠져도 시스템 불변식을 깨지 않고 기본 핸드오프 동작으로 자연히 회귀하는 '필수 아님' 룰로 판정됐다. 활성 룰·스킬·프로젝트 헌법 어디서도 이 파일을 인용하지 않으므로, 제거해 룰 표면을 줄이고 같은 디렉터리에 남는 필수 룰(task-state-alignment)만 카테고리에 남긴다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- 항상, `rules/orchestration/approved-spec-merge.md` 파일은 레포에 존재하지 않는다.
- 항상, `rules/orchestration/` 디렉터리에는 `task-state-alignment.md`가 존재하며, 프로젝트 헌법의 카테고리 디렉터리 로딩이 그 파일을 오류 없이 읽는다(디렉터리·카테고리 유지).
- 활성 코드 표면(`rules/`, `CLAUDE.md`, `plugins/`)에서 `approved-spec-merge` 문자열을 검색하면 일치 건수가 0이다.
- 머지 절차의 단일출처인 `rules/engineering/branch-and-slug.md`의 내용이 변경되지 않은 동안, 머지 *절차*는 그대로 보존된다(이 변경은 타이밍 정책만 제거한다).
- 정리 대상 과거 SPEC 2건에서 `approved-spec-merge.md`를 '활성 단일출처'로 가리키던 인용 줄이 제거 사실을 반영한 stale 주석(파일 제거됨, 타이밍은 기본 핸드오프로 회귀)으로 갱신돼 있고, 그 인용 줄 밖의 본문·완료 조건 로직은 변경되지 않는다.

## 범위
포함:
- `rules/orchestration/approved-spec-merge.md` 파일 삭제.
- `docs/specs/2026-06-02-workflow-spec-layout-merge-gate/SPEC.md`에서 `approved-spec-merge.md`를 타이밍 vs 기계 분리의 활성 미러링 출처로 인용하던 줄(2곳) stale 주석 갱신.
- `docs/specs/2026-06-03-consolidate-forge-integration-rule-into-fsd-skill/SPEC.md`에서 `approved-spec-merge.md`를 forge-integration 교차참조·siblings 열거로 인용하던 줄(4곳) stale 주석 갱신.

비-목표 / 제외:
- `rules/orchestration/task-state-alignment.md`는 수정하지 않는다(필수 gap-filler 룰, 유지).
- `rules/engineering/branch-and-slug.md`는 수정하지 않는다(머지 절차 단일출처 보존).
- `rules/orchestration/` 디렉터리 자체는 제거하지 않는다(잔존 룰로 유지).
- 제거된 타이밍 정책을 대체할 새 메커니즘을 만들지 않는다 — 기본 핸드오프로의 회귀가 의도된 결과다.
- 과거 SPEC의 인용 줄 밖 본문·완료 조건은 재작성하지 않는다(역사 기록 보존).

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 이 변경은 repo-root `rules/`·`docs/specs/`만 건드리며 `plugins/` 아래 플러그인 자원을 바꾸지 않으므로, plugin.json·루트 marketplace.json의 SemVer 범프 대상이 아니다.
- 과거 SPEC 기록은 인용 줄만 stale 처리하고 각 SPEC의 자체 완료 조건을 깨지 않는 선에서만 갱신한다.

## 위험 (있을 때만)
- 정리 대상 과거 SPEC이 자신의 완료 조건에서 `approved-spec-merge.md`를 검증 대상으로 삼고 있으면 stale 처리가 그 조건을 무너뜨릴 수 있다 → 인용 줄(서술 참조)만 주석화하고 완료 조건 로직은 손대지 않아 회피한다.
