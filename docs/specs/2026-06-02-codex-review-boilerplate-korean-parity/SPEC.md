---
scope:
  include:
    - .github/workflows/codex-review.yml
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
---

# Codex 리뷰 게시 보일러플레이트 한국어화

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

Codex PR 자동 리뷰가 PR에 게시하는 **리뷰 요약/래퍼 텍스트**(보일러플레이트)를 한국어로 표시한다.

이 문구들은 모델이 생성하는 출력이 아니라 codex 리뷰 워크플로의 게시 단계에 하드코딩된 고정 영어 문구다. Codex 워크플로가 Claude 리뷰와 "동일 게시 구조"로 재작성될 때 영어 보일러플레이트 버전이 그대로 들어와, Claude 리뷰는 한국어 보일러플레이트를 쓰는데 Codex 리뷰만 영어 문구를 노출하는 불일치가 생겼다. 지적 사항(finding)이 없는 흔한 approve 경우 PR에는 이 영어 문구만 남으므로 "Codex 리뷰가 한국어를 쓰지 않는다"는 인상의 실제 원인이다.

대상은 두 게시 단계(정식 리뷰 본문 작성, managed PR 코멘트 작성)의 하드코딩 영어 문구다. 정식 한국어 카피는 같은 위치의 Claude 리뷰 워크플로가 이미 쓰는 카피와 동일하게 맞춘다:

| 현재 (codex, 영어) | 한국어 카피 (claude와 동일) |
|---|---|
| `No findings.` (정식 본문 jq) | `발견 사항 없음.` |
| `Findings:\n` (정식 본문 jq) | `발견 사항:\n` |
| `\n  Suggestion: ` (정식 본문 jq) | `\n  제안: ` |
| `Suggestion: ${finding.suggestion}` (managed 코멘트) | `제안: ${finding.suggestion}` |
| `Verdict: \`${result.verdict}\`` (managed 코멘트) | `결과: \`${result.verdict}\`` |
| `Codex review found no findings, but formal approval could not be submitted by this workflow token.` | `Codex 리뷰에서 지적 사항을 찾지 못했으나, 이 워크플로 토큰 권한으로는 정식 승인을 제출하지 못했습니다.` |
| `No findings. (summary unavailable)` | `발견 사항 없음. (요약 없음)` |
| `No findings.` (managed 코멘트 approvalFailed 분기) | `발견 사항 없음.` |

섹션 헤더 `## Codex PR Review`는 Claude 리뷰(`## Claude PR Review`)와 동일하게 영어 브랜드명으로 유지한다.

모델이 채우는 지적 사항 필드(summary, 각 finding의 title·body·suggestion **본문**)는 이미 한국어로 출력되고 있으므로 본 변경의 대상이 아니다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

1. WHEN Codex 리뷰가 지적 사항과 함께 정식 리뷰 본문을 작성할 때, THE 본문의 목록 헤더는 `발견 사항:`, 각 항목의 제안 라벨은 `제안:`으로 한국어로 표시되어야 한다.
2. WHEN Codex 리뷰 정식 본문에 지적 사항이 하나도 없을 때, THE 본문은 한국어 `발견 사항 없음.`을 표시해야 한다.
3. WHEN Codex 리뷰가 managed PR 코멘트를 작성할 때, THE verdict 표시 줄은 `결과:` 라벨로, 각 finding의 제안 줄은 `제안:` 라벨로 한국어로 표시되어야 한다.
4. WHEN managed PR 코멘트가 모델 summary 없이 작성될 때, THE 코멘트는 한국어 fallback `발견 사항 없음. (요약 없음)`을 사용해야 한다.
5. IF 정식 승인 제출이 워크플로 토큰 권한으로 실패하면, THEN THE managed PR 코멘트는 그 사유를 한국어 안내문으로 표시하고 본문에 한국어 `발견 사항 없음.`을 표시해야 한다.
6. THE 섹션 헤더 `## Codex PR Review`는 영어 브랜드명으로 유지되어야 한다.
7. THE 숨김 HTML 마커, verdict/severity 등 enum 값, 모델이 채우는 지적 사항 필드(summary·title·body·suggestion 본문)는 본 변경으로 수정되지 않아야 한다.
8. THE 한국어 보일러플레이트는 같은 위치의 Claude 리뷰 워크플로가 쓰는 카피와 문구상 동일해야 한다.

## 범위
포함:
- `.github/workflows/codex-review.yml`의 게시 단계(정식 리뷰 본문 작성, managed PR 코멘트 작성)에 하드코딩되어 PR에 노출되는 영어 보일러플레이트 문구의 한국어화.
- 발견 사항 목록 헤더·제안 라벨, 지적 사항 없음 문구, verdict 표시 줄, summary 없을 때 fallback, 승인 토큰 실패 안내문.

비-목표 / 제외:
- 모델 프롬프트(`.github/prompts/codex-pr-review.ko.md`)나 출력 언어 지시문 변경 — 모델 출력은 이미 한국어다.
- 리뷰 언어 설정 변수(`CODEX_REVIEW_LANG`)의 동작 변경.
- 모델이 채우는 지적 사항 필드(summary·title·body·suggestion 본문).
- 숨김 HTML 마커(`<!-- ... -->`) 및 verdict/severity enum 값.
- `claude-review.yml` 등 다른 워크플로 수정 — 본 변경은 Codex 워크플로만 Claude의 기존 한국어 카피에 맞춘다.
- 섹션 헤더 `## Codex PR Review`의 한국어화.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 숨김 HTML 마커와 verdict/severity enum 값은 변경하지 않는다 — 리뷰 멱등성 판정과 승인 게이팅 로직이 이 값들에 의존한다.
- 보일러플레이트는 한국어로 직접 고정한다 — 리뷰 언어 설정과 독립적으로 항상 한국어.
- 한국어 카피는 같은 위치의 Claude 리뷰 워크플로 카피와 문구상 동일하게 유지한다(짧은 한국어 라벨 형태).
- 섹션 헤더는 Claude 리뷰와 동일하게 `## Codex PR Review` 영어로 유지한다.

## 위험
- 숨김 마커나 verdict enum 값을 실수로 변경하면 리뷰 멱등성·승인 게이팅이 깨질 수 있다 → 범위에서 명시적으로 제외하고 제약으로 못박았다.
- 정식 본문(jq)과 managed 코멘트(JS) 두 게시 경로 중 한쪽만 고치면 노출 문구가 불일치한다 → 완료 조건 1·3이 두 경로를 모두 인수 바로 강제한다.
