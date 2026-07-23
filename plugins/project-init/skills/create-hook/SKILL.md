---
name: create-hook
description: 소비 프로젝트에 새 Claude Code 훅을 작성해 달라는 요청에서 활성화된다 — "훅 만들어줘", "PreToolUse/SessionStart 훅 추가", "이벤트 핸들러 작성", "settings.json에 훅 등록", "도구 호출 전에 X 실행되게 해줘", "세션 시작할 때 Y 주입해줘" 같은 신호에서 사용. 인터뷰로 이벤트·기능·차단 여부를 확정해 표준 구조(핸들러 디스패처 + lib/<command>/ + settings 등록)의 훅을 설계·작성한다. 기존 훅의 수리·점검 요청이면 쓰지 않는다(repair-hook 몫). 플러그인 자신의 hooks/(hooks.json) 표면 생성에는 쓰지 않는다.
allowed-tools:
  - AskUserQuestion
  - Read
  - Glob
  - Write
  - Edit
  - Bash(mkdir -p:*)
  - Bash(chmod +x:*)
  - Bash(python3 *hook_checker.py*:*)
  - Bash(git rev-parse:*)
---

# create-hook

소비 프로젝트에 Claude Code 훅(이벤트 핸들러 + 기능 command + settings 등록)을
인터뷰 기반으로 설계·작성한다. `../../shared/hook-standard/` 표준을 작성 단계에
내장해 검사기 BLOCKER·MAJOR 0 산출물을 낸다.

## 절차

### 1. 훅 목적 인터뷰

다음 네 가지를 구조화된 사용자 질문 기능(없는 환경에서는 간결한 직접 질문)으로 확정한다.

- **이벤트** — 어느 이벤트에 걸 것인가. 선택지: `PreToolUse` · `PostToolUse` ·
  `UserPromptSubmit` · `Notification` · `Stop` · `SubagentStop` · `PreCompact` ·
  `SessionStart` · `SessionEnd`.
- **기능(command)** — 훅이 수행할 일과 그 이름(kebab-case). `lib/<command>/` 디렉터리명이 된다.
- **차단 여부** — 조건 위반 시 도구 호출·진행을 차단하는가(exit 2 + stderr 사유),
  관찰·주입만 하는 비차단인가(항상 exit 0).
- **대상 디렉토리** — 훅을 설치할 소비 프로젝트의 훅 디렉토리
  (기본 제안: 저장소 루트의 `.claude/hooks/`).

### 2. 표준 확인

`../../shared/hook-standard/standard.md`를 읽는다 — 2계층 레이아웃(핸들러 디스패처 +
`lib/<command>/`), 스크립트 계약(POSIX sh · jq 우선 sed 폴백 · 비차단 exit 0 ·
차단 exit 2 · 실행권한 · `${CLAUDE_PROJECT_DIR}` placeholder 등록), 판정 항목의
단일 출처다. 이 스킬은 표준을 복제하지 않고 이 문서를 따른다.

### 3. 기존 상태 조사

대상 디렉토리와 그 부모의 `settings.json`·`settings.local.json`을 읽고 확인한다.

- 확정한 이벤트의 핸들러 파일(이벤트명 kebab-case + `.sh`)이 **이미 존재하면**,
  새 핸들러를 만들지 않고 기존 핸들러에 새 command 디스패치 호출을 추가한다(4단계).
- 같은 `lib/<command>/`가 이미 존재하면 사용자에게 알리고 command 이름 변경 또는
  덮어쓰기(6단계 diff 승인 경유) 여부를 묻는다.
- settings 에 해당 이벤트 등록이 이미 있는지 확인한다 — 이벤트당 핸들러 1개 원칙을 지킨다.

### 4. 설계

표준(2단계)에 맞춰 산출물을 설계한다.

- **핸들러** — `.claude/hooks/<이벤트명 kebab-case>.sh`. stdin JSON을 1회 읽어
  변수에 담고 자기 이벤트의 lib command 들에 위임하는 디스패처. 로직 인라인 금지.
  기존 핸들러가 있으면 신규 파일 대신 디스패치 한 줄 추가 편집으로 설계한다.
- **기능 스크립트** — `.claude/hooks/lib/<command>/<command>.sh` + 그 기능이 쓰는
  참조 파일을 같은 디렉터리에 응집. POSIX sh, jq 폴백, 비차단이면 모든 실패 경로가
  exit 0(graceful passthrough), 차단이면 명시적 의도에서만 exit 2 + stderr 사유.
- **settings 등록** — 이벤트당 핸들러 1개를 `${CLAUDE_PROJECT_DIR}` placeholder
  경로로 등록(절대·상대경로 하드코딩 금지). matcher 는 필요한 도구만 걸러내게 좁힌다.

### 5. 파일 작성

- 새 디렉터리는 `mkdir -p`로 만들고, 설계대로 파일을 생성한 뒤 모든 `.sh`에 `chmod +x`.
- **기존 파일을 덮어쓰거나 편집하게 되면**(기존 핸들러 디스패치 추가·settings 갱신 포함)
  변경 diff 를 먼저 제시하고 **명시적 승인**이 있을 때만 쓴다. 승인이 없으면 그 파일은
  보존하고 7단계 요약에 생략으로 기록한다.

### 6. 검사 (결정적 10 + 모델 5)

`../../shared/hook-standard/checker-invocation.md`의 호출 계약(절대경로 고정·실행
형식·결과 해석)대로 대상 훅 디렉토리에 `hook_checker.py`를 실행하고, stdout JSON에서
BLOCKER·MAJOR 0 을 확인한다. 발견되면 해당 파일을 수정한 뒤 **1회만 재검**한다 —
재검에서도 남으면 반복하지 않고 잔존 지적으로 7단계에 넘긴다(무한 루프 방지).

이어서 `standard.md`의 모델 판정 5항목(M-NONBLOCKING · M-DESTRUCTIVE ·
M-MATCHER-SCOPE · M-DISPATCH · M-JQ-FALLBACK)을 생성한 스크립트를 읽고 직접
판정한다 — 검사기 JSON에는 포함되지 않는다.

### 7. 완료 요약

생성·편집·보존(승인 거절로 생략)된 파일을 구분해 요약하고, 등록된 이벤트·command·
차단 여부와 검사 결과(등급·잔존 지적)를 보고한다.

## 규칙

- 표준·검사기의 단일 출처는 `../../shared/hook-standard/`다 — 사본을 만들지 않는다.
- `standard.md`는 2단계에서 읽는다 — 사전에 읽지 않는다.
- 기존 파일은 사용자 명시 동의 없이 덮어쓰거나 편집하지 않는다.
- 이 스킬은 소비 프로젝트의 `.claude/hooks/`만 다룬다 — 플러그인 `hooks/`(hooks.json)
  표면은 만들지 않는다.

## references

| 파일 | 용도 | 읽는 시점 |
|------|------|-----------|
| `../../shared/hook-standard/standard.md` | 훅 구조·스크립트 계약 표준 (단일 출처) | 2단계 — 표준 확인 |
| `../../shared/hook-standard/checker-invocation.md` | 검사기 호출 계약 (단일 출처) | 6단계 — 검사 |
| `../../shared/hook-standard/hook_checker.py` | 결정적 10항목 검사기 | 6단계 — 검사 |
