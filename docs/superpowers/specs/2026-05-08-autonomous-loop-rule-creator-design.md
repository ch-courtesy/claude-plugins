# `autonomous-loop-rule-creator` 설계 스펙

작성일: 2026-05-08
대상 플러그인: `plugins/project-init/`
신규 스킬 위치: `plugins/project-init/skills/autonomous-loop-rule-creator/`

## 1. 목적

대상 프로젝트에 **랄프 루프 기반 자율 수행 환경**을 한 번의 스킬 호출로 설치한다. 산출물은 다음을 모두 충족해야 한다.

- **무인 진전**: 사람이 자리를 비워도 작업이 수용 기준을 향해 단조 이동
- **수렴**: 무작위 변경이 아니라 마일스톤 단위로 진전
- **비용 한계**: 이터레이션·시계 캡으로 폭주 차단
- **회복성**: 중단 후에도 디스크 상태로 재개
- **감사성**: 매 이터의 입력·변경·결정·근거가 추적
- **정직성**: 평가 기준 약화·가짜 완료 방지 (헌법 + 드라이버 객관 게이트)
- **범위 보존**: 작업 경계·하네스 자체 보호
- **안전 정지**: 폭주 시 OS 수준에서 즉시 정지 가능, 환경 오염 최소화

## 2. 채택·기각 패턴

| 패턴 | 채택? | 이유 |
|---|---|---|
| 외부 셸 루프 (`while + claude --print`) | **채택** | 프로세스 경계 분리, 콜드 스타트 보장, 드라이버/워커 책임 분리 |
| Stop 훅 기반 (Anthropic `ralph-wiggum` 플러그인) | **기각** | `settings.json` 영구 변경, 세션 라이프사이클 결합, 콜드 스타트 위배, 비용 폭주 가시성 낮음 |
| `claude --bare` 격리 | **기각** | OAuth/keychain 사용자에게 인증 실패 (API key 미보유 환경 가정) |
| Stop 훅 외 격리 (scratch CWD + `--system-prompt-file` + `--add-dir`) | **채택** | API key 없이도 격리 가능. 잔여 위험은 사용자 레벨 CLAUDE.md/settings로 한정 |
| 드라이버 측 사이드카 JSON 합성 (`recent.md` 자동 생성) | **기각** | 드라이버 추출은 잡음 비율 높음. 모델 큐레이션 마크다운으로 대체 |
| 모델 큐레이션 메모리 파일 (PLAN/NOTES/HANDOFF/RUN_LOG) | **채택** | 신호 큐레이션은 모델 책임, 사람도 검증·교정 가능 |
| Git worktree 격리 (안 3) | **기각 (현 단계)** | 설치 부담 큼. 향후 변종 템플릿으로 추가 가능 |

## 3. 산출물 트리 (스킬이 대상 프로젝트에 생성)

```
<project root>/
├── rules/
│   └── autonomous-loop.md            # 헌법 SSOT
└── .loops/
    ├── README.md                     # 새 task 생성·운영 가이드
    ├── PROMPT.template.md            # 새 task의 PROMPT.md 시드 (YAML frontmatter 포함)
    ├── loop.sh                       # 외부 드라이버
    └── templates/                    # task 인스턴스용 메모리 파일 스텁
        ├── PLAN.template.md
        ├── NOTES.template.md
        ├── HANDOFF.template.md
        ├── RUN_LOG.template.md
        └── ESCALATION.template.md
```

스킬은 task 인스턴스 디렉토리(`.loops/<task-id>/`)는 생성하지 않는다. 사용자가 README의 절차로 만들거나, `loop.sh`가 첫 호출 시 누락된 파일을 `.loops/templates/`에서 시드한다.

### 3.1 task 인스턴스 트리 (사용자 또는 `loop.sh`가 생성)

```
.loops/<task-id>/
├── PROMPT.md                 # 작업 정의 + 이터 프로토콜. 불변
├── PLAN.md                   # 마일스톤 체크박스. 모델 갱신
├── NOTES.md                  # 학습 누적 (실패 접근·발견 제약·작동 패턴). 모델 갱신
├── HANDOFF.md                # 직전 이터 → 다음 이터 편지. 모델 매 이터 덮어쓰기
├── RUN_LOG.md                # 한 줄 요약 누적. 모델 매 이터 append
├── iterations/
│   └── <n>.log               # 매 이터 stdout 캡처 (사후 디버깅)
├── failures/                 # (선택) 큰 실패 포스트모템. 모델 자율 생성
├── fixtures/                 # (선택) 확정 작동 코드 조각
└── ESCALATION.md             # 정지 사유 (있을 때만)
```

## 4. 메모리 파일 모델

랄프 루프의 핵심 가정: **기억은 LLM이 아닌 파일에 있다.** 매 이터레이션은 콜드 스타트이며, 직전 추론 과정은 다음 이터가 보지 못한다 — 결과물(코드·테스트·메모리 파일)만 본다.

### 4.1 파일별 역할

| 파일 | 역할 | 갱신 빈도 | 갱신 주체 |
|---|---|---|---|
| `PROMPT.md` | 작업 정의 + 이터 프로토콜 (불변) | 절대 안 함 | 사용자 (생성 시 1회) |
| `PLAN.md` | 마일스톤 체크박스로 권위 있는 진전 추적 | 진전 시마다 | 모델 |
| `NOTES.md` | 큐레이션 학습 — 실패 접근·발견 제약·작동 패턴 | 실패·발견 시마다 | 모델 |
| `HANDOFF.md` | 다음 이터에 보내는 편지 — 무엇을 했고·뭐가 막혔고·다음 단계 | 매 이터 종료 직전 (덮어쓰기) | 모델 |
| `RUN_LOG.md` | 한 줄 요약 누적 — 시각·시도·결과·다음 단계 | 매 이터 종료 직전 (append) | 모델 |
| `iterations/<n>.log` | stdout 캡처 (사후 디버깅용) | 매 이터 | 드라이버 |

**모든 큐레이션은 모델 책임이다.** 드라이버가 자동 추출하지 않는다 — 자동 추출은 잡음 비율이 높아 다음 이터의 신호를 흐린다.

### 4.2 매 이터 라이프사이클

PROMPT.md에 박힌 절차:

```
[새 세션 시작 — 콜드 스타트]
1. PLAN.md 읽기              ─ 어디까지 왔는지
2. NOTES.md 읽기             ─ 피해야 할 것·발견된 제약
3. HANDOFF.md 읽기           ─ 직전 상태
4. RUN_LOG.md 끝 부분 읽기   ─ 최근 흐름
5. git log --oneline -20     ─ 코드 변화 추적
6. 작업 수행 (가장 작은 유용한 단계 하나)
7. 검증 명령 실행 → 실패 시 NOTES.md에 추가
8. PLAN.md 체크박스 갱신 (진전 있을 때)
9. HANDOFF.md 덮어쓰기 + RUN_LOG.md 한 줄 append
10. git commit (자기 분류 prefix 포함)
11. 완료 판정 통과 → DONE 작성·종료 / 막힘 → ESCALATION.md 작성·종료 / 그 외 → 그냥 종료
[다음 이터가 위 상태를 그대로 읽음]
```

## 5. 자기 분류 — git commit prefix

JSON 사이드카는 사용하지 않는다. 자기 분류 신호는 git commit message의 첫 토큰:

- `fix:root` — 근본 원인 수정
- `fix:symptom` — 증상 우회 (근본 원인 미확인 또는 범위 외)
- `feat` — 새 기능
- `refactor` — 동작 변경 없는 구조 개선
- `test` — 테스트 추가 (기존 수정 아님)
- `chore` — 빌드·설정 등 부수 작업

이유: git 히스토리가 자연스러운 시간축이고 크래시 안전이다. 드라이버는 `git log --pretty=format:%s -N`로 streak·분포 측정.

## 6. 헌법 (`rules/autonomous-loop.md`)

자율-루프-지침 문서를 흡수해 자체완결적으로 작성한다. 산출물 본문에서 그 문서를 참조하지 않는다 (원본은 소스 머티리얼이며 흡수 후 흔적이 남지 않는다).

### 6.1 절 구성

1. 제1 원칙 (절대 규칙) — 평가 기준·테스트·아키텍처·작업 범위·의존성·보안 6대 불가침
2. 이터레이션 모델 — 콜드 스타트, 디스크 상태가 진실, 입력·출력 정의
3. 작업 흐름 — 수용 기준 확인·계획·5단계 이터레이션·자기 분류·완료 판정
4. 이터레이션 상한·조기 정지 — 상한 N회·동일 에러 3회·진동·fix:symptom 누적·예산 임계치
5. 에스컬레이션 — 트리거·보고 양식·후 정지
6. 관찰성·로깅 — 매 이터 기록·의사결정 근거 명시·불확실성 표시
7. 금지 행동 — 12가지 (테스트 약화·suppressor 신규·force push·secrets·위장 등)
8. 근본 원인 추구 — 표면 vs 근본·증상 우회는 명시적·"일단 동작" 부정
9. 의사소통 — 정직·간결·완료 정의 준수
10. 하네스 자체에 대한 태도 — 우회 대신 보고
11. 메모리 파일 운영 — PLAN/NOTES/HANDOFF/RUN_LOG 큐레이션 의무
12. 종료 신호 — DONE / ESCALATION.md 진실성 의무
13. 체크리스트 — 시작·이터 후·완료 전

### 6.2 객관 게이트 표시

§7(금지 행동)의 다음 항목은 헌법 self-police에 더해 드라이버가 객관 검증한다:

- 테스트 약화 → 드라이버: `tests/**` 해시 비교
- 의존성 변경 → 드라이버: manifest 해시
- 작업 범위 밖 수정 → 드라이버: scope diff 검사
- suppressor 신규 → 드라이버: grep 검사
- 비밀키 하드코딩 → 드라이버: gitleaks (있을 때)
- force push → 헌법 + git 권한 (사용자 환경 가정)

## 7. PROMPT.md 템플릿

PROMPT.md는 YAML frontmatter + 본문으로 구성. **frontmatter는 드라이버가 파싱**(scope·verify를 객관 게이트에 사용), **본문은 모델이 읽음**.

모델은 frontmatter를 데이터로 인식하고 본문 지시를 따른다. 드라이버는 `yq` 또는 단순 sed 파싱으로 frontmatter 추출. 의존성: `yq` 권장 (없으면 fallback 안내).

```markdown
---
scope:
  include:
    - src/**
    - tests/**
  exclude:
    - rules/**
    - .loops/**
verify: <실행 가능한 명령. 예: pnpm test --filter=auth. 0 exit이면 검증 통과>
---

# 자율 루프 마스터 프롬프트

당신은 자율 루프의 한 이터레이션입니다.
기억은 LLM이 아닌 파일에 있습니다. 매 이터는 콜드 스타트입니다.

## 작업 정의 (불변)

### 무엇을 만들 것인가
{{task_description}}

### 수용 기준
{{acceptance_criteria}}

### 범위
포함:
{{scope_in}}

비-목표 / 제외:
{{scope_out}}

### 검증
{{verify_command}}

## 시작 전 (이 순서로 읽는다)

1. **PLAN.md** — 권위 있는 작업 계획·진전 상태
2. **NOTES.md** — 이전 시도의 교훈 (실패 접근·발견된 제약·작동 패턴)
3. **HANDOFF.md** — 직전 이터의 상태·다음 단계 추천
4. **RUN_LOG.md** 끝 부분 — 최근 흐름
5. `git log --oneline -20` — 최근 커밋 확인

## 한 이터레이션 규칙

- 완료를 향한 가장 작은 유용한 단계 하나만 수행
- NOTES.md의 "실패한 접근"을 반복하지 않음 — 같은 가설을 다시 시도하려면 왜 이번엔 다른지 NOTES에 명시
- 변경 후 검증 명령을 실행하고, 실패 시 그 원인을 NOTES.md에 추가
- 진전이 있으면 PLAN.md 체크박스 갱신

## 종료 전 (이 순서로)

1. **HANDOFF.md 덮어쓰기** — 다음 이터가 5분 안에 컨텍스트를 잡도록:
   - 이번에 무엇을 했는지
   - 무엇이 막혔거나 막힐 수 있는지
   - 다음 단계 추천 (구체적으로)
2. **RUN_LOG.md에 한 줄 추가** — 시각·시도·결과·다음 단계
3. **git commit** — 자기 분류 prefix로 시작:
   `fix:root` / `fix:symptom` / `feat` / `refactor` / `test` / `chore`
4. **완료 판정 통과 → DONE 파일 작성·종료**
5. **진전 불가능 → ESCALATION.md 작성·종료** (양식: 작업·이터·트리거·상태·문제·시도·가설·필요한 결정)

## 절대 안 됨

- `rules/autonomous-loop.md`, `PROMPT.md` 수정
- 거짓 DONE / ESCALATION.md
- 작업 범위 밖 파일 수정
- 자기 분류 누락한 채 commit
- NOTES.md의 "실패한 접근" 재시도 (정당한 사유 없이)
```

`{{...}}` placeholder는 사용자가 새 task 생성 시 채운다.

## 8. 드라이버 (`loop.sh`)

### 8.1 호출 인터페이스

```bash
.loops/loop.sh <task-id> [--max-iterations N] [--wall-clock-minutes N]
```

`<task-id>`는 `.loops/<task-id>/` 디렉토리 이름. 누락된 메모리 파일이 있으면 빈 스텁으로 시드.

### 8.2 매 이터 호출 (cwd = `.loops/<task-id>/`)

```bash
cat PROMPT.md | claude \
  --print \
  --no-session-persistence \
  --dangerously-skip-permissions \
  --system-prompt-file ../../rules/autonomous-loop.md \
  --add-dir ../.. \
  --output-format json \
  > "iterations/$n.log"
```

### 8.3 격리 메커니즘

- cwd = `.loops/<task-id>/` → 프로젝트 hooks 비활성 (settings 위로 안 올라감), auto-memory 자체 버킷
- `--system-prompt-file rules/autonomous-loop.md` → 헌법 강제 주입
- `--no-session-persistence` → 콜드 스타트 보장
- `--add-dir <project root>` → 프로젝트 코드 접근 명시
- `--print` → 한 번 응답 후 종료 (프로세스 경계)
- `--dangerously-skip-permissions` → 무인 운영. 격리 디렉토리 가정으로 정당화

**잔여 위험 (수용):** 사용자 레벨 `~/.claude/CLAUDE.md` / `~/.claude/settings.json` / auto-memory는 차단 불가. 사용자가 본인 환경을 통제한다고 가정. README에 "루프 시작 전 `~/.claude/` 검토 권장" 명시.

### 8.4 객관 게이트 (매 이터 검사)

| 가드 | 메커니즘 | 위반 시 |
|---|---|---|
| 이터 상한 | 카운터 ≤ `--max-iterations` (기본 30) | halt + 에스컬레이션 자동 작성 |
| 시계 캡 | 누적 시간 ≤ `--wall-clock-minutes` (기본 120) | halt |
| DONE 파일 | 존재 검사 | 정상 종료 |
| ESCALATION.md | 존재 검사 | halt (사람 처리 대기) |
| 테스트 약화 | `find tests/ -type f -exec sha256sum {} \;` 시작 시점 vs 매 이터 | halt |
| 의존성 동결 | `package.json`/`requirements.txt`/`Cargo.toml` 등 매니페스트 해시 | halt |
| Scope 위반 | `git diff --name-only` vs PROMPT.md frontmatter의 `scope.include`/`scope.exclude` (yq 파싱) | halt + diff stash |
| Suppressor 신규 | `git diff` grep `noqa\|@ts-ignore\|eslint-disable\|#pragma warning disable` | halt |
| Secrets | `gitleaks detect --staged` (있을 때) | halt |
| fix:symptom streak | `git log --pretty=format:%s -2 \| grep -c '^fix:symptom'` ≥ 2 | halt + 에스컬레이션 |
| 진동 | 최근 4 커밋의 변경 파일 셋 비교 — 두 상태 토글 검출 | halt |

### 8.5 매 이터 의사 코드

```bash
n=$(($(ls iterations/*.log 2>/dev/null | wc -l) + 1))
START_HASH_TESTS=$(hash_tests)
START_HASH_DEPS=$(hash_deps)

# PROMPT.md frontmatter 파싱 (scope·verify)
SCOPE_INCLUDE=$(yq '.scope.include[]' PROMPT.md)
SCOPE_EXCLUDE=$(yq '.scope.exclude[]' PROMPT.md)
VERIFY_CMD=$(yq '.verify' PROMPT.md)

# 메모리 파일 시드 (없으면 .loops/templates/에서)
seed_memory_files

# 호출
cat PROMPT.md | claude \
  --print --no-session-persistence --dangerously-skip-permissions \
  --system-prompt-file ../../rules/autonomous-loop.md \
  --add-dir ../.. --output-format json \
  > "iterations/$n.log"

# 게이트 검사
[[ -f DONE ]] && exit 0
[[ -f ESCALATION.md ]] && exit 1
[[ "$(hash_tests)" != "$START_HASH_TESTS" ]] && halt "tests modified"
[[ "$(hash_deps)" != "$START_HASH_DEPS" ]] && halt "deps modified"
out_of_scope=$(diff_vs_scope) && [[ -n "$out_of_scope" ]] && halt "out of scope: $out_of_scope"
new_suppressors=$(grep_new_suppressors) && [[ -n "$new_suppressors" ]] && halt "new suppressors"
fix_symptom_streak=$(git log --pretty=format:%s -2 | grep -c '^fix:symptom') && [[ $fix_symptom_streak -ge 2 ]] && halt "fix:symptom streak"
oscillation=$(detect_oscillation) && [[ -n "$oscillation" ]] && halt "oscillation"
[[ $n -ge $MAX_ITERS ]] && halt "max iterations"
[[ $(elapsed_minutes) -ge $WALL_CLOCK ]] && halt "wall clock"
```

`halt()` 동작: 진행 중 변경을 git stash + 표준 형식의 자동 ESCALATION.md 작성 + exit 1.

### 8.6 의도적 비-범위

- 다중 task 동시 실행 (한 번에 한 task)
- 분산 실행·재시도
- 토큰 사전 추정·달러 캡 (`--max-budget-usd`는 OAuth에 무의미)
- 단순 셸. 복잡도 증가가 필요하면 향후 안 3 변종(슈퍼바이저·worktree)으로 분기

## 9. 스킬 구조 (`plugins/project-init/skills/autonomous-loop-rule-creator/`)

```
autonomous-loop-rule-creator/
├── SKILL.md
├── templates/
│   └── ralph-loop.md            # 단일 템플릿 (현재). 향후 변종 추가 가능
└── assets/
    ├── PROMPT.template.md
    ├── loop.sh
    ├── loops-README.md           # `.loops/README.md` 시드
    ├── PLAN.template.md
    ├── NOTES.template.md
    ├── HANDOFF.template.md
    ├── RUN_LOG.template.md
    └── ESCALATION.template.md
```

### 9.1 SKILL.md

`context-rule-creator/SKILL.md`와 동일한 템플릿 셀렉트 패턴. 차이는 `on_create`가 단일 파일 생성 외 다음을 수행:

- `rules/autonomous-loop.md`로 템플릿 본문 기록 (rule-creator 표준)
- `assets/`의 다음 파일을 대상 프로젝트의 지정 경로로 복사:
  - `PROMPT.template.md` → `.loops/PROMPT.template.md`
  - `loop.sh` → `.loops/loop.sh` (chmod +x)
  - `loops-README.md` → `.loops/README.md`
- `.loops/templates/` 아래에 task 인스턴스용 메모리 파일 스텁 배치 (사용자가 `cp -r` 또는 `loop.sh`가 시드)
- `.gitignore`에 `.loops/*/iterations/*.log` 추가 (선택: 사용자가 stdout 캡처를 git에서 제외하고 싶을 때)
- 기존 파일 존재 시 덮어쓰지 않고 사용자에게 diff 확인

### 9.2 템플릿 (`templates/ralph-loop.md`) frontmatter

```yaml
---
label: 랄프 루프 (외부 셸 드라이버, 객관 게이트)
description: 매 이터 콜드 스타트 + 4대 메모리 파일 + git commit 자기 분류
recommended: true
on_create: |
  1. assets/PROMPT.template.md를 .loops/PROMPT.template.md로 복사
  2. assets/loop.sh를 .loops/loop.sh로 복사하고 chmod +x
  3. assets/loops-README.md를 .loops/README.md로 복사
  4. assets/PLAN.template.md, NOTES.template.md, HANDOFF.template.md, RUN_LOG.template.md, ESCALATION.template.md를
     .loops/templates/ 아래로 복사
  5. .gitignore에 `.loops/*/iterations/*.log` 라인 추가 (이미 있으면 skip)
  6. 사용자에게 다음 안내 메시지 출력:
     "자율 루프가 설치되었습니다. 새 task 시작:
        mkdir .loops/<task-id>
        cp .loops/PROMPT.template.md .loops/<task-id>/PROMPT.md
        $EDITOR .loops/<task-id>/PROMPT.md   # 작업 정의 채움
        ./.loops/loop.sh <task-id>"
---

# autonomous-loop — 자율 루프 운영 규칙

[본문에 헌법 §1~§13이 그대로 들어감]
```

본문은 `rules/autonomous-loop.md`로 기록되는 헌법 본체. SKILL.md는 본문을 알 필요 없음.

### 9.3 bootstrap 통합

이 스킬은 `*-rule-creator` 접미사를 가지므로 `bootstrap`이 자동 열거. 단:

- 자율 루프는 모든 프로젝트의 기본값으로 적합하지 않다 → `bootstrap`의 카테고리 선택 단계에서 사용자가 명시적으로 체크해야 생성됨 (이미 `bootstrap`의 동작 — "전체 / 일부 / 없음" 선택)
- 권장 가이드라인: README나 `bootstrap` 안내문에 "자율 루프는 장시간 무인 작업이 필요할 때만 추가" 명시

## 10. 새 task 시작 절차 (사용자 워크플로)

`.loops/README.md`에 안내:

```bash
# 1. task 디렉토리 생성
mkdir -p .loops/auth-refactor

# 2. PROMPT.md 시드 후 작업 정의 채움
cp .loops/PROMPT.template.md .loops/auth-refactor/PROMPT.md
$EDITOR .loops/auth-refactor/PROMPT.md
# - {{task_description}}, {{acceptance_criteria}}, {{scope_in}}, {{scope_out}}, {{verify_command}} 채움

# 3. 빈 메모리 파일 시드 (loop.sh가 자동 시드하기도 함)
cp .loops/templates/{PLAN,NOTES,HANDOFF,RUN_LOG}.template.md .loops/auth-refactor/

# 4. 루프 시작
./.loops/loop.sh auth-refactor

# 5. 진행 모니터링 (별도 터미널)
tail -f .loops/auth-refactor/RUN_LOG.md
ls -la .loops/auth-refactor/iterations/

# 6. 정지: Ctrl+C, 또는 DONE/ESCALATION.md가 생기면 자동 종료
```

## 11. 향후 확장

- 변종 템플릿: 워크트리 격리(안 3) / 수용-테스트 앵커(안 4) / 다중 task 병렬
- 메모리 파일 자동 회전: NOTES.md 100줄 초과 시 `failures/`로 분할 (드라이버 또는 모델)
- API key 사용 환경: `--bare` + `--max-budget-usd` 옵션 추가 (조건부)
- GitHub Issue 에스컬레이션: ESCALATION.md → `gh issue create` 자동화 (선택 훅)

## 12. 검증 기준 (스킬 완성도)

이 설계가 구현됐다고 인정되려면:

1. `bootstrap` 호출 흐름에서 `autonomous-loop` 카테고리 선택 시 위 트리가 정확히 생성된다
2. 생성된 `loop.sh`가 빈 task 디렉토리에서 호출돼도 메모리 파일 시드 후 첫 이터를 돌릴 수 있다
3. 생성된 PROMPT.md placeholder가 모두 사용자가 채울 수 있는 형태로 명시된다
4. 헌법(`rules/autonomous-loop.md`)이 자체완결적이며 자율-루프-지침 등 외부 문서를 참조하지 않는다
5. 드라이버의 객관 게이트 9종(테스트 약화·의존성·scope·suppressor·secrets·fix:symptom streak·진동·이터 상한·시계 캡)이 모두 구현·테스트된다
6. 사용자 레벨 CLAUDE.md/settings 잔여 위험이 README에 명시된다
