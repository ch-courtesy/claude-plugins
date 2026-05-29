---
scope:
  include:
    - ".github/workflows/claude-review.yml"
    - ".github/workflows/codex-review.yml"
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# PR 리뷰 워크플로 extra-context 디렉터리 경로 가드

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
PR 리뷰 워크플로(claude-review·codex-review)의 리뷰어 추가-context 수집 블록이, 리뷰어가 요청한 경로가 **파일(blob)일 때만** 내용을 가져오도록 가드를 보강한다. 디렉터리(git tree)·트레일링슬래시 등 비-blob 경로는 건너뛰어, 디렉터리 요청 시 파일 리다이렉트 실패로 리뷰 워크플로가 비정상 종료되지 않게 한다.

배경: 현재 가드는 절대경로·상위참조만 거르고, 존재 확인이 디렉터리(tree)에도 성공으로 판정되어, 리뷰어가 디렉터리 경로를 요청하면 그 경로를 파일로 취급하다 워크플로가 실패한다(PR #238에서 실제 발생).

## 수용 기준 (EARS)
<!-- 각 기준은 verify에서 fail 가능해야 함. 구현 방법·파일·클래스명은 피한다. -->
- **AC1 (Event-driven):** 리뷰어가 추가 context로 디렉터리(또는 비-blob) 경로를 요청하면, 시스템은 그 경로의 내용을 가져오지 않고 건너뛰어야 한다.
- **AC2 (Unwanted behavior):** 만약 요청 경로가 파일이 아니면(디렉터리·트레일링슬래시 등), 시스템은 그 경로로 인해 리뷰 워크플로를 비정상 종료(non-zero exit)시키지 않아야 한다.
- **AC3 (Event-driven):** 리뷰어가 추가 context로 실제 파일(blob) 경로를 요청하면, 시스템은 그 파일 내용을 정상적으로 수집해야 한다.
- **AC4 (Ubiquitous):** 시스템은 두 PR 리뷰 워크플로(claude·codex)에 동일한 가드를 적용해야 한다.

## 범위
포함:
- `.github/workflows/claude-review.yml`·`.github/workflows/codex-review.yml`의 추가-context 수집 가드 보강.

비-목표 / 제외:
- 리뷰 프롬프트·verdict 판정 로직 변경.
- 추가 context가 없을 때의 기존 흐름(1차 verdict로 진행) 변경.
- 리뷰어가 디렉터리를 요청하는 동작 자체의 억제.

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 기존 절대경로(`/*`)·상위참조(`*..*`) 가드는 유지한다.
- WHAT/HOW 방어선: 구현 방법(예: 객체 타입 검사 방식)은 강제하지 않고 blob-only 동작만 요구한다.

## 위험 (있을 때만)
- 두 워크플로가 동일 패턴을 공유하므로, 한쪽만 고치면 다른 쪽에 같은 실패가 잔존한다 → 범위에 두 파일 모두 포함해 완화.
