---
name: repair-hook
description: 소비 프로젝트의 기존 `.claude/hooks/` 훅 구조를 `shared/hook-standard` 15항목(검사기 10 + 모델 5) 기준으로 평가하고 사용자 승인을 받은 항목만 직접 수정한 뒤 재평가까지 끝낸다. 사용자가 기존 훅의 수정·보수·고치기·리페어·표준화·구조 정리를 요청하거나 훅 BLOCKER·MAJOR 해소가 필요할 때는 물론, 수정 없이 훅 품질 점검·표준 준수 평가·등급 확인만 원할 때도 활성화된다 — 평가-전용 요청이면 평가·등급 보고까지만 수행하고 수정 승인 단계로 넘어가지 않는다. 표준 도입 전 플랫 구조를 만나면 2계층 레이아웃 이행안을 제시한다. 호출 `Skill(skill="repair-hook", args="[<훅 디렉터리 경로>]")`.
allowed-tools:
  - Read
  - Glob
  - Edit
  - Write
  - AskUserQuestion
  - Bash(python3 *hook_checker.py*:*)
  - Bash(git rev-parse:*)
  - Bash(chmod +x:*)
  - Bash(mkdir -p:*)
  - Bash(mv:*)
---

# repair-hook

소비 프로젝트의 기존 훅 디렉터리를 평가하고, 사용자 승인을 받은 BLOCKER·MAJOR
항목만 직접 수정한 뒤 재평가로 결과를 확인한다. 훅 구조 표준 15항목 기준의 단일
출처는 `../../shared/hook-standard/standard.md`다 — 이 스킬은 자체 사본을 두지
않는다.

## 절차

### 1. 입력 해석

`args`로 평가 대상 훅 디렉터리 경로를 받는다. 생략하면 기본값
`.claude/hooks/`다. 경로는 소비 프로젝트 저장소 루트 기준으로 해석하고, 대상
디렉터리가 없으면 오류를 알리고 중단한다.

### 2. 규칙 검사 실행 (결정적 10항목)

`../../shared/hook-standard/checker-invocation.md`의 호출 계약(절대경로 고정·실행
형식·결과 해석)대로 검사기를 실행하고 stdout의 JSON을 수집한다. 결함이 발견된
훅 구조도 평가 자체가 성공하면 종료 코드 0이므로 다음 단계로 진행한다.

### 3. 모델 검사 (의미적 5항목)

`../../shared/hook-standard/standard.md`의 "5. 모델 판정 항목" 절을 읽고, 검사
대상 파일을 `Glob`으로 열거한 뒤(대상 디렉터리의 `**/*.sh`와 저장소 루트의
`.claude/settings*.json`) 핸들러·lib 스크립트와 settings 등록 내용을 직접 읽어
5개 모델 항목(M-NONBLOCKING·M-DESTRUCTIVE·M-MATCHER-SCOPE·M-DISPATCH·
M-JQ-FALLBACK)을 판정한다. 확신이 없으면 보수적으로 FAIL한다.

### 4. 병합·등급

검사기 10 + 모델 5 결과를 합쳐 등급을 매긴다(`standard.md`의 등급표 그대로):
BLOCKER 1개 이상이면 F, 아니면 MAJOR 개수로 S/A/B/C를 가른다. MINOR는 등급을
가르지 않으나 보고에는 포함한다.

### 5. 분기 — 통과 vs 수정 필요

- **BLOCKER 0건, MAJOR 0건**이면 수정 작업 없이 통과 사실(등급·MINOR 목록)만
  보고하고 종료한다.
- 사용자가 평가·등급 산출만 요청했으면(평가-전용) BLOCKER·MAJOR가 있어도
  6단계로 넘어가지 않고 등급과 지적 목록만 보고하고 종료한다.
- BLOCKER 또는 MAJOR가 하나라도 있으면 6단계로 진행한다.

### 6. 수정안 도출과 승인

BLOCKER·MAJOR 항목마다 그 evidence에 대응하는 구체적 수정 내용을 도출하고,
적용 전 변경 diff(현재 내용 → 수정안)를 사용자에게 제시한다. 구조화된 사용자
질문 기능으로 적용 여부 승인을 받는다 — 기능을 쓸 수 없는 환경에서만 간결한
직접 질문으로 대체한다. MINOR 항목은 참고용으로만 함께 보고하고 수정안을
만들지 않는다(자동 수정 대상 아님).

표준 비준수 레이아웃(플랫 구조 등 — 기능 스크립트가 `.claude/hooks/` 직속에
흩어진 형태)을 만나면, `standard.md`의 2계층 레이아웃으로의 이행안을 하나의
수정안으로 제시한다: 파일 이동 계획(기능 스크립트 → `lib/<command>/`), 이벤트
핸들러 신설·위임 배선, settings 등록 경로 갱신을 묶어 diff로 보인다.

### 7. 적용

사용자가 승인한 항목만 반영한다. 파일 내용 수정은 `Edit`, 새 핸들러·디렉터리
생성은 `Write`·`mkdir -p`, 파일 이동은 `mv`, 실행권한 부여는 `chmod +x`로
수행한다. 거부된 항목은 수정하지 않고 그대로 둔다.

### 8. 재평가와 보고

변경을 반영한 대상에 대해 2–4단계를 다시 실행해 BLOCKER·MAJOR 해소 여부를
확인한다. 갱신된 등급, 해소된 항목, 잔존 지적(거부되었거나 재평가에서도 남은
BLOCKER·MAJOR, 그리고 MINOR 전체)을 보고한다. 잔존 지적은 보고만 하고 같은
이터에서 추가로 반복 수정하지 않는다(무한 루프 방지).

## 규칙

- 기존 파일은 diff 제시 후 명시적 승인이 있을 때만 수정한다. 사용자가 거부하면
  해당 항목은 미해결로만 보고하고 수정하지 않는다.
- 훅 구조 표준 15항목 기준과 검사기의 단일 출처는
  `../../shared/hook-standard/`다. 다른 플러그인을 호출하거나 그 결과에 런타임
  의존하지 않는다.
- 모든 대상의 BLOCKER·MAJOR가 0건이면 수정 없이 통과만 보고한다.
- 이 표준은 스킬 산출물의 계약이다 — 플러그인 자신의 `hooks/`(hooks.json)
  표면에는 적용하지 않는다.

## references

| 파일 | 용도 | 읽는 시점 |
|------|------|-----------|
| `../../shared/hook-standard/standard.md` | 훅 구조 표준 15항목 기준 (단일 출처) | 3·4단계 — 모델 검사·등급 |
| `../../shared/hook-standard/checker-invocation.md` | 검사기 호출 계약 (단일 출처) | 2단계 — 규칙 검사 실행 |
| `../../shared/hook-standard/hook_checker.py` | 결정적 10항목 검사기 | 2단계 — 규칙 검사 실행 |
