---
scope:
  include:
    - plugins/project-init/skills/bootstrap/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# bootstrap 스킬에 카파시 65줄 CLAUDE.md 룰 추가 질문 단계

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
bootstrap 스킬의 초기화 흐름에서, 루트 확인 직후(다른 어떤 단계보다 먼저) 사용자에게 "안드레이 카파시의 65줄 CLAUDE.md 룰을 추가할지" 묻는 질문 단계를 추가한다. 사용자가 추가를 선택하면, 스킬에 동봉된 카파시 룰의 한국어 번역본을 생성되는 CLAUDE.md의 최상단에 포함한다. 추가하지 않으면 CLAUDE.md는 질문 추가 이전과 동일하게 생성된다. 룰 본문은 스킬에 정적 자산으로 동봉하며, 질문의 기본(추천) 답은 '추가 안 함'(opt-in)이다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 관찰 가능하고 독립 검증 가능해야 함. -->
1. When bootstrap 초기화가 시작되어 루트 확인이 끝나면, 시스템은 카테고리 선택 등 이후 단계로 진행하기 전에 카파시 65줄 룰 추가 여부를 `AskUserQuestion`으로 한 번 묻는다.
2. 카파시 룰 추가 질문의 추천/기본 선택지는 '추가 안 함'이어야 한다.
3. Where 사용자가 룰 추가를 선택하고 CLAUDE.md가 새로 생성되는 경우, 시스템은 동봉된 카파시 룰 한국어 번역본을 생성되는 CLAUDE.md의 최상단(기존 bootstrap CLAUDE.md 본문보다 앞)에 포함한다.
4. If 사용자가 룰을 추가하지 않기로 하면, CLAUDE.md는 카파시 룰 텍스트 없이 질문 추가 이전과 동일하게 생성된다.
5. 시스템은 카파시 65줄 룰 본문을 스킬 디렉터리 내 정적 자산으로 보유하며, 실행 시 외부 네트워크 접근이나 추가 사용자 입력 없이 그 자산만으로 룰을 삽입할 수 있어야 한다.
6. 동봉 자산은 원본 카파시 CLAUDE.md(4개 섹션 — Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution — 및 마지막 "These guidelines are working if" 판정 기준)의 한국어 번역본이어야 하며, 원본의 섹션 구조와 각 지침 항목을 빠짐없이 보존한다.
7. If CLAUDE.md가 이미 존재하면, 시스템은 기존 파일을 덮어쓰지 않고 bootstrap의 기존 파일 보호 규칙(차이 제시 후 확인)에 따른다.
8. While 사용자가 '추가 안 함'을 선택한 경우, 이후 흐름(카테고리 선택·생성기 호출·요약)은 질문 추가 이전과 동일하게 동작한다.

## 범위
포함:
- bootstrap 스킬의 절차 문서에 신설하는 질문 단계
- 카파시 룰 한국어 번역본 정적 자산 파일(스킬 동봉)

비-목표 / 제외:
- 다른 `*-rule-creator` 스킬 수정
- `rules/` 생성 로직 변경
- root CLAUDE.md 자체 변경
- 카파시 룰 원문에 대한 요약·재구성(번역 외 편집)

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 구현 범위는 `plugins/project-init/skills/bootstrap/`의 SKILL.md 절차와 신설 정적 자산 파일로 한정한다.
- bootstrap의 기존 원칙과 정합 유지: 오케스트레이터가 생성하는 산출 파일은 여전히 CLAUDE.md 하나이며, 카파시 룰 자산은 생성 산출물이 아니라 스킬 동봉 파일이다.
- 정적 자산만으로 동작해야 한다 — 실행 시 네트워크 fetch나 사용자 텍스트 붙여넣기에 의존하지 않는다.
- 동봉 자산의 번역 원본은 `https://raw.githubusercontent.com/multica-ai/andrej-karpathy-skills/refs/heads/main/CLAUDE.md`(2026-05-30 기준 65줄)이다.

## 위험
- 카파시 룰과 기존 bootstrap CLAUDE.md의 상호작용 지침이 모두 'Claude 작업 지침'이라 prepend 시 톤·항목이 중복·상충할 소지가 있다 — 중복 시 정리 방침(섹션 경계 명시 등)을 구현에서 정한다.
- 원본이 향후 갱신되면 동봉 번역본과 표류할 수 있다 — 동봉본은 작성 시점 스냅샷이며 자동 동기화하지 않는다.
