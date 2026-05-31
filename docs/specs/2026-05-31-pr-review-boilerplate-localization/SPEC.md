# PR 리뷰 요약 보일러플레이트 한국어화

## 무엇을 만들 것인가

Claude·Codex PR 자동 리뷰가 PR에 게시하는 **리뷰 요약/래퍼 텍스트**를 한국어로 표시한다.

이 텍스트들은 모델이 생성하는 출력이 아니라 리뷰 워크플로의 게시 단계에 하드코딩된 고정 영어 문구다. 따라서 리뷰 언어 설정과 무관하게 항상 영어로 노출되며, 지적 사항(finding) 없이 approve되는 흔한 경우 PR에는 이 영어 문구만 남는다. 이것이 "리뷰가 한국어를 쓰지 않는다"는 인상의 실제 원인이다.

모델이 채우는 지적 사항 필드(title·body·suggestion)는 이미 한국어로 출력되고 있으므로 본 변경의 대상이 아니다.

보일러플레이트는 모델이 직접 응답하는 텍스트가 아니므로 장황한 문장 대신 **짧은 한국어 라벨**로 표현한다. 대상 문구와 정식 한국어 카피:

| 현재 (영어) | 한국어 카피 (간결) |
|---|---|
| `## Claude PR Review` / `## Codex PR Review` | `## Claude PR 리뷰` / `## Codex PR 리뷰` |
| `_Approved by automated review. Findings, if any, are posted as inline comments._` | `_승인 — 지적 사항은 인라인 코멘트 참조._` |
| `Verdict: \`approve\`` | `결과: 승인` |
| `Approved — no blocking findings.` | `승인 — 차단 지적 없음` |
| `Claude/Codex review found no blocking findings, but formal approval could not be submitted by this workflow token.` | `승인 가능 — 단, 토큰 권한으로 정식 승인 미제출` |
| `Claude/Codex review output could not be parsed against the schema: <reason>` | `리뷰 출력 파싱 실패: <사유>` |

## 수용 기준

> 본 섹션의 EARS 수용 기준이 인수 바의 단일 출처다. 검증을 실행하는 진입 명령은 프로젝트 규칙(`rules/`)에서 온다.

1. WHEN PR이 지적 사항 없이 approve 판정으로 리뷰될 때, THE 리뷰 요약 코멘트는 섹션 헤더와 승인 안내 문구를 한국어로 표시해야 한다.
2. WHEN approve 판정 요약이 모델 summary 없이 생성될 때, THE 요약은 한국어 기본 라벨("승인 — 차단 지적 없음")을 사용해야 한다.
3. IF 정식 승인 제출이 워크플로 토큰 권한으로 실패하면, THEN THE 요약은 그 사유를 한국어 라벨로 표시해야 한다.
4. IF 모델 출력이 스키마 파싱에 실패하면, THEN THE fallback 요약은 파싱 실패 사유를 한국어로 표시해야 한다.
5. THE verdict 표시 줄은 라벨과 표시 값을 한국어로 표시하되, 숨김 마커의 verdict enum 값(`verdict=approve` 등)은 변경하지 않아야 한다.
6. THE 동일한 한국어화는 Claude·Codex 두 리뷰 워크플로 모두에 적용되어야 한다.
7. THE 모델이 채우는 지적 사항 필드(title·body·suggestion)는 본 변경으로 수정되지 않아야 한다.
8. THE 한국어 보일러플레이트는 리뷰 언어 설정값과 무관하게 항상 한국어로 표시되어야 한다.

## 범위

### 포함
- 두 리뷰 워크플로의 게시 단계에 하드코딩된, PR에 노출되는 모든 영어 보일러플레이트 문구의 한국어화.
- approve 경로 요약, summary 없을 때의 기본 라벨, 승인 토큰 실패 안내, 파싱 실패 fallback 요약, verdict 표시 줄.

### 제외
- 모델 프롬프트의 출력 언어 지시문 변경.
- 리뷰 언어 설정 변수의 동작 변경.
- 모델이 채우는 지적 사항 필드.
- 숨김 HTML 마커(`<!-- ... -->`) 및 verdict enum 값.

## 검증

EARS 수용 기준이 인수 바의 단일 출처다. 검증을 실행하는 진입 명령은 프로젝트 규칙(`rules/`)에 정의되며 본 문서는 진입 명령을 싣지 않는다.

## 제약

- 숨김 HTML 마커와 verdict enum 값은 변경하지 않는다 — 리뷰 멱등성 판정과 승인 게이팅 로직이 이 값들에 의존한다.
- 보일러플레이트는 한국어로 직접 고정한다 — 리뷰 언어 설정과 독립적으로 항상 한국어.
- 보일러플레이트는 짧은 한국어 라벨 형태를 유지한다(장황한 완전 문장 지양).

## 위험

- 숨김 마커나 verdict enum 값을 실수로 변경하면 리뷰 멱등성·승인 게이팅이 깨질 수 있다 → 범위에서 명시적으로 제외하고 제약으로 못박았다.
- 두 워크플로에 동일 변경을 적용할 때 한쪽만 누락하면 일관성이 깨진다 → AC6이 양쪽 적용을 인수 바로 강제한다.
