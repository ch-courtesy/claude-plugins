# 소비 프로젝트 훅 구조 표준 (단일 출처)

소비 프로젝트의 `.claude/hooks/` 훅 구조·품질 기준이다. 훅을 작성·수리하는 스킬(`create-hook`·`repair-hook`)이 이 문서를 참조하고 사본을 두지 않는다.

이 표준은 **스킬 산출물의 계약**이다 — 소비 프로젝트에 정책을 강제하는 게이트가 아니다. 플러그인 자신의 `hooks/`(hooks.json) 표면에는 적용되지 않는다.

## 등급 기준

| 등급 | 조건 |
|---|---|
| F | BLOCKER ≥ 1 |
| S | BLOCKER 0, MAJOR 0 |
| A | BLOCKER 0, MAJOR ≤ 2 |
| B | BLOCKER 0, MAJOR ≤ 4 |
| C | BLOCKER 0, MAJOR ≥ 5 |

MINOR 는 등급에 영향을 주지 않는다.

## 1. 2계층 레이아웃

```
.claude/hooks/
├── pre-tool-use.sh          # 이벤트 핸들러 (PreToolUse)
├── session-start.sh         # 이벤트 핸들러 (SessionStart)
└── lib/
    └── <command>/           # 기능(command)별 디렉터리
        ├── <command>.sh     # 기능 스크립트
        └── <참조 파일>       # 그 기능이 쓰는 데이터·템플릿
```

- **핸들러 계층** — `.claude/hooks/` 직속. 등록된 이벤트당 파일 1개, 파일명은 이벤트명의 kebab-case + `.sh`(`PreToolUse` → `pre-tool-use.sh`, `UserPromptSubmit` → `user-prompt-submit.sh`).
- **기능 계층** — `.claude/hooks/lib/<command>/`. 기능별 디렉터리 하나에 스크립트와 그 기능이 쓰는 참조 파일을 응집시킨다.

이벤트명: `PreToolUse` · `PostToolUse` · `UserPromptSubmit` · `Notification` · `Stop` · `SubagentStop` · `PreCompact` · `SessionStart` · `SessionEnd`.

## 2. 역할 분리

- 핸들러는 **디스패처**다. stdin JSON 을 **1회** 읽어(`input="$(cat)"`) 변수에 담고, 자기 이벤트에 속한 lib command 들을 호출하며 그 결과를 종합한다.
- 실제 로직은 **lib command 스크립트에만** 둔다. 핸들러에 로직을 인라인하지 않는다.
- stdin 은 한 번만 읽을 수 있으므로, 여러 command 에 넘길 때는 읽어 둔 변수를 전달한다.

## 3. 스크립트 계약

- **POSIX sh** — 모든 스크립트 셔뱅은 `#!/bin/sh`. bash 전용 문법(배열, `[[ ]]`)을 쓰지 않는다.
- **jq 우선·sed 폴백** — JSON 파싱은 jq 를 쓰되, jq 부재 환경에서 sed/grep 폴백으로 동작을 이어간다.
- **비차단 이벤트는 항상 exit 0** — 실패·파싱 불가·의존 도구 부재는 graceful passthrough 한다(세션을 막지 않는다).
- **차단 의도는 exit 2 + stderr 사유** — 차단은 명시적 의도일 때만, 사유를 stderr 로 남긴다.
- **실행권한** — 모든 `.sh` 에 `chmod +x`.
- **settings 등록** — `.claude/settings.json`(또는 `settings.local.json`)에 이벤트당 핸들러 1개를 `${CLAUDE_PROJECT_DIR}` placeholder 경로로 등록한다(절대경로·상대경로 하드코딩 금지).

## 4. 검사기 판정 항목 (결정적 10)

`hook_checker.py` 가 파일시스템과 settings JSON 만으로 판정한다. 호출 방법은 `checker-invocation.md`.

| id | 섹션 | 항목 | severity |
|---|---|---|---|
| L-EVENT-NAME | 레이아웃 | 직속 파일은 이벤트명 kebab-case 핸들러 | BLOCKER |
| S-EXEC-HANDLER | 스크립트 계약 | 핸들러 실행권한 | BLOCKER |
| G-REGISTERED | settings 정합 | 핸들러 파일마다 등록 존재 | BLOCKER |
| G-FILE-EXISTS | settings 정합 | 등록된 핸들러 파일 실재 | BLOCKER |
| L-NO-STRAY-SCRIPT | 레이아웃 | 기능 스크립트는 `lib/<command>/` 안 | MAJOR |
| S-SHEBANG | 스크립트 계약 | 모든 스크립트 셔뱅 `#!/bin/sh` | MAJOR |
| S-EXEC-LIB | 스크립트 계약 | lib 스크립트 실행권한 | MAJOR |
| G-PLACEHOLDER | settings 정합 | 등록 경로 `${CLAUDE_PROJECT_DIR}` 사용 | MAJOR |
| G-ONE-HANDLER | settings 정합 | 이벤트당 핸들러 1개 | MAJOR |
| L-LIB-STRUCTURE | 레이아웃 | `lib/<command>/` 에 스크립트 존재 | MINOR |

settings 정합은 `settings.json` 과 `settings.local.json` 을 **둘 다** 읽되 병합 우선순위는 구현하지 않는다 — "어느 파일에도 등록이 없음"만 위반으로 본다(과판정 회피).

## 5. 모델 판정 항목 (의미적 5)

검사기로 판정할 수 없는 항목이다. `create-hook`·`repair-hook` 을 실행하는 에이전트가 스크립트 내용을 읽고 판정한다.

| id | 항목 | severity | 판정 기준 |
|---|---|---|---|
| M-NONBLOCKING | 비차단 원칙 준수 | BLOCKER | 비차단 이벤트 핸들러가 오류·의존 부재 상황에서 0 이 아닌 코드로 끝날 경로가 없는가. `set -e`, 파이프 실패, 미검증 명령 실패가 세션을 막지 않는가. |
| M-DESTRUCTIVE | 위험 명령 부재 | BLOCKER | `rm -rf`, `git push --force`, `dd`, 자격증명 유출 등 되돌릴 수 없는 명령을 실행하지 않는가. |
| M-MATCHER-SCOPE | matcher 범위 적정 | MAJOR | settings 의 matcher 가 필요한 도구만 걸러내는가. 전체 도구를 잡아 놓고 스크립트 안에서 걸러내는 과광(over-broad) 패턴이 아닌가. |
| M-DISPATCH | 디스패처 역할 준수 | MAJOR | 핸들러가 stdin 을 1회 읽고 lib command 로 위임하는가. 로직이 핸들러에 인라인돼 있지 않은가. |
| M-JQ-FALLBACK | jq 폴백 실효성 | MINOR | jq 부재 시 폴백 경로가 실제로 같은 값을 뽑는가(주석만 있고 미구현이 아닌가). |
