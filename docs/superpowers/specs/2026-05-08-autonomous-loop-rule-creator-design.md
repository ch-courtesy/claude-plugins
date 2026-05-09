# `autonomous-loop-rule-creator` 설계 스펙

작성일: 2026-05-08
대상 플러그인: `plugins/project-init/`
신규 스킬 위치: `plugins/project-init/skills/autonomous-loop-rule-creator/`

본 스펙은 **단일 task 자율 수행 원자**를 다룬다 (Layer 1). 멀티 task 합성·DAG 스케줄링·집계는 별도 레이어인 `autonomous-orchestration-rule-creator`(Layer 2)가 본 원자를 호출해 처리한다 — `2026-05-09-autonomous-orchestration-rule-creator-design.md` 참조.

Layer 2 호환을 위해 Layer 1이 충족해야 하는 요구사항:
- task-id에 슬래시(`<goal-id>/<task-id>`) 허용 — 워크트리 경로·브랜치명에 그대로 사용
- 락 파일명은 슬래시를 `-`로 치환해 안전화
- 워크트리에 메타 파일이 이미 있으면 시드 스킵 (Layer 2가 합성한 PROMPT.md 보존)

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
| Sibling git worktree 격리 (워크트리 + 워크트리 내 CLAUDE.md) | **채택** | 프로젝트 트리 밖 워크트리는 CLAUDE.md walk-up 경로에서 벗어나 프로젝트 CLAUDE.md를 완전 차단. 동시 실행도 자연스럽게 격리 |
| 드라이버 측 사이드카 JSON 합성 (`recent.md` 자동 생성) | **기각** | 드라이버 추출은 잡음 비율 높음. 모델 큐레이션 마크다운으로 대체 |
| 모델 큐레이션 메모리 파일 (PLAN/NOTES/HANDOFF/RUN_LOG) | **채택** | 신호 큐레이션은 모델 책임, 사람도 검증·교정 가능 |
| 자기 분류 = git commit prefix | **채택** | git 히스토리가 자연스러운 시간축, 크래시 안전, 드라이버가 `git log` 파싱으로 streak 측정 |
| 동시 실행 (워크트리 격리 + `MAX_CONCURRENT` 락) | **채택** | 워크트리 자동 격리로 race 없음. 공유 자원(API rate)만 캡으로 관리 |

## 3. 산출물 트리

스킬이 대상 프로젝트에 직접 생성하는 파일과, 드라이버가 런타임에 sibling 위치에 만드는 워크트리의 두 영역으로 나뉜다.

### 3.1 스킬이 생성 (대상 프로젝트 안)

```
<project root>/
├── rules/
│   └── autonomous-loop.md            # 헌법 SSOT (워크트리의 CLAUDE.md로 복사되는 원본)
└── .loops/
    ├── README.md                     # 새 task 생성·워크트리 라이프사이클·동시 실행 가이드
    ├── PROMPT.template.md            # 새 task의 PROMPT.md 시드 (YAML frontmatter 포함)
    ├── loop.sh                       # 외부 드라이버 — subcommand 기반 (prepare/start/status/stop/list/cleanup/logs)
    ├── templates/                    # 워크트리 메모리 파일 스텁
    │   ├── PLAN.template.md
    │   ├── NOTES.template.md
    │   ├── HANDOFF.template.md
    │   ├── RUN_LOG.template.md
    │   └── ESCALATION.template.md
    ├── locks/                        # 워크트리별 RUNNING 락 (gitignored)
    │   └── .gitkeep
    └── <task-id>/                    # task별 통합 디렉토리 (prepare에서 생성, cleanup 후 아카이브)
        ├── PROMPT.md                 # prepare가 생성, start가 워크트리로 복사
        └── (cleanup 후) PLAN/NOTES/HANDOFF/RUN_LOG.md  # 아카이브
```

추가로 `.gitignore`에 다음 라인이 추가된다:
- `.loops/locks/` (런타임 락파일 비추적)

### 3.2 드라이버가 런타임 생성 (sibling 위치, 프로젝트 트리 밖)

```
<parent>/                             # <project>의 부모 디렉토리
├── <project>/                        # 메인 프로젝트 (위 §3.1)
└── <project>-loops/                  # ← sibling. 프로젝트 트리 밖 → CLAUDE.md walk-up 차단
    └── <task-id>/                    # git worktree (autonomous-loop/<task-id> 브랜치)
        ├── CLAUDE.md                 # 헌법 — loop.sh가 rules/autonomous-loop.md에서 복사
        ├── .loop/                    # 메타 파일 — 워크트리의 .git/info/exclude로 비추적
        │   ├── PROMPT.md             # 작업 정의 + 이터 프로토콜. 불변. 사용자 작성
        │   ├── PLAN.md               # 마일스톤 체크박스. 모델 갱신
        │   ├── NOTES.md              # 학습 누적. 모델 갱신
        │   ├── HANDOFF.md            # 직전 이터 → 다음 이터 편지. 모델 매 이터 덮어쓰기
        │   ├── RUN_LOG.md            # 한 줄 요약 누적
        │   ├── iterations/
        │   │   └── <n>.log           # 매 이터 stdout 캡처
        │   ├── failures/             # (선택) 큰 실패 포스트모템
        │   ├── fixtures/             # (선택) 확정 작동 코드 조각
        │   └── ESCALATION.md         # 정지 사유 (있을 때만)
        └── (프로젝트 파일들 — autonomous-loop/<task-id> 브랜치 체크아웃)
```

**워크트리 위치 환경 변수:** `LOOP_WORKTREE_BASE` 미지정 시 기본 `<project>/../<project-name>-loops/`. 사용자가 환경 변수로 변경 가능 (예: `~/.claude-loops/<project>/`).

**격리 보장:** 워크트리 cwd는 프로젝트 트리 밖이므로 CLAUDE.md auto-discovery walk-up이 `<project>/CLAUDE.md`에 도달하지 않는다. 워크트리 자체의 `CLAUDE.md`만 헌법으로 로드되고, 잔여 walk-up은 `~/.claude/CLAUDE.md` 사용자 레벨까지만 (수용).

**워크트리 정리:** DONE 후 사용자가 `git merge autonomous-loop/<task-id>` 후 `git worktree remove <worktree-path>`. 또는 `git worktree prune`. 자동 정리는 안 한다 — 사람의 검토를 거치도록.

## 4. 메모리 파일 모델

랄프 루프의 핵심 가정: **기억은 LLM이 아닌 파일에 있다.** 매 이터레이션은 콜드 스타트이며, 직전 추론 과정은 다음 이터가 보지 못한다 — 결과물(코드·테스트·메모리 파일)만 본다.

### 4.1 파일별 역할 (모두 워크트리의 `.loop/` 아래)

| 파일 | 역할 | 갱신 빈도 | 갱신 주체 |
|---|---|---|---|
| `.loop/PROMPT.md` | 작업 정의 + 이터 프로토콜 (불변) | 절대 안 함 | 사용자 (생성 시 1회) |
| `.loop/PLAN.md` | 마일스톤 체크박스로 권위 있는 진전 추적 | 진전 시마다 | 모델 |
| `.loop/NOTES.md` | 큐레이션 학습 — 실패 접근·발견 제약·작동 패턴 | 실패·발견 시마다 | 모델 |
| `.loop/HANDOFF.md` | 다음 이터에 보내는 편지 — 무엇을 했고·뭐가 막혔고·다음 단계 | 매 이터 종료 직전 (덮어쓰기) | 모델 |
| `.loop/RUN_LOG.md` | 한 줄 요약 누적 — 시각·시도·결과·다음 단계 | 매 이터 종료 직전 (append) | 모델 |
| `.loop/iterations/<n>.log` | stdout 캡처 (사후 디버깅용) | 매 이터 | 드라이버 |
| `<worktree>/CLAUDE.md` | 헌법 (시스템 프롬프트로 주입) | 워크트리 생성 시 1회 | 드라이버 (rules/autonomous-loop.md에서 복사) |
| `<worktree>/DONE` | 완료 신호 (있을 때만) | 완료 시 1회 | 모델 |

**`.loop/` 디렉토리와 `CLAUDE.md`는 워크트리의 `.git/info/exclude`로 비추적**. 머지 시 메인 브랜치를 오염시키지 않음.

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

0. **Iron Laws** — TDD·verification·root cause 3대 강제 원칙. 위반 시 즉시 정지
1. 제1 원칙 (절대 규칙) — 평가 기준·테스트·아키텍처·작업 범위·의존성·보안 6대 불가침. **워크트리 안에서 동작하나, 메인 브랜치 머지 시점의 변경 책임도 동일**
2. 이터레이션 모델 — 콜드 스타트, 디스크 상태가 진실, 워크트리 안에서 모든 작업 수행
3. 작업 흐름 — 수용 기준 확인·계획·**6단계** 이터레이션 (RED-GREEN 포함)·자기 분류·완료 판정·**Self-Review 4축**
4. 이터레이션 상한·조기 정지 — 상한 N회·동일 에러 3회·진동·fix:symptom 누적·**3+ fix 실패→architecture 재검토**·예산 임계치
5. 에스컬레이션 — 트리거·보고 양식·후 정지
6. 관찰성·로깅 — 매 이터 기록·의사결정 근거 명시·불확실성 표시·**다층 시스템 진단 로깅**
7. 금지 행동 — 12가지 (테스트 약화·suppressor 신규·force push·secrets·위장 등) + 워크트리 밖 파일 수정 금지·`CLAUDE.md`/`.loop/` 수정 금지
8. **근본 원인 추구 (4 Phase)** — Root Cause Investigation → Pattern Analysis → Hypothesis & Testing → Implementation
9. 의사소통 — 정직·간결·완료 정의 준수
10. 하네스 자체에 대한 태도 — 우회 대신 보고
11. 메모리 파일 운영 — PLAN/NOTES/HANDOFF/RUN_LOG 큐레이션 의무. 모두 `.loop/` 아래에 위치 + **이터 내 Agent 도구 위임 가이드**
12. 종료 신호 — DONE / **DONE_WITH_CONCERNS** / ESCALATION.md (카테고리). 진실성 의무. 워크트리 루트의 `DONE` 또는 `.loop/ESCALATION.md`만 인정
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

- `CLAUDE.md` (워크트리 루트의 헌법), `.loop/PROMPT.md` 수정
- 워크트리 밖 파일 수정 (모든 작업은 워크트리 안에서)
- 거짓 `DONE` (워크트리 루트) / 거짓 `.loop/ESCALATION.md`
- 작업 범위(scope) 밖 파일 수정
- 자기 분류 prefix 누락한 채 commit
- NOTES.md의 "실패한 접근" 재시도 (정당한 사유 없이)
```

`{{...}}` placeholder는 사용자가 새 task 생성 시 채운다.

## 8. 드라이버 (`loop.sh`)

### 8.1 subcommand 인터페이스

```bash
./.loops/loop.sh prepare <task-id>
./.loops/loop.sh start   <task-id> [--max-iterations N] [--wall-clock-minutes N] [--watch]
./.loops/loop.sh status  [<task-id>]
./.loops/loop.sh stop    <task-id>
./.loops/loop.sh list
./.loops/loop.sh cleanup <task-id> [--force]
./.loops/loop.sh logs    <task-id> [--tail] [--iter N]
```

환경 변수:
- `LOOP_WORKTREE_BASE` — 워크트리 부모 디렉토리. 기본 `<project>/../<project-name>-loops/`
- `MAX_CONCURRENT` — 동시 실행 가능한 loop 수. 기본 3

subcommand 없이 호출하면 사용법 안내 후 exit 1.

### 8.2 워크트리 라이프사이클

**8.2.1 prepare (PROMPT.md 시드 생성):**

```bash
# .loops/<task-id>/PROMPT.md 생성 (이미 있으면 abort)
mkdir -p ".loops/$TASK_ID"
cp ".loops/PROMPT.template.md" ".loops/$TASK_ID/PROMPT.md"
```

사용자는 이 파일의 placeholder를 채운 뒤 `start`를 실행한다.

**8.2.2 start (검증 후 워크트리·락 생성 + 이터레이션 루프):**

1. `.loops/<task-id>/PROMPT.md` 존재 확인 → 없으면 `prepare`를 먼저 실행하도록 안내
2. PROMPT.md의 `{{...}}` placeholder 미채움 확인 → 있으면 편집 요청 후 abort
3. 동시성 락 획득 (`LOCK_DIR/$TASK_ID_SAFE.lock`)
4. 워크트리 없으면 생성:
   - `git worktree add` + 브랜치 생성
   - 헌법·메모리 파일 시드 (`.loops/<task-id>/PROMPT.md`를 워크트리로 복사)
   - `.git/info/exclude` 갱신
5. 이터레이션 루프 진입 (이미 워크트리가 있으면 생성 단계 스킵)

**8.2.3 DONE 처리:**

DONE 신호 감지 시 사용자에게 `cleanup` 실행 안내 후 종료. 메타 파일 archive는 `cleanup`이 담당.

**8.2.4 ESCALATION 처리:**

워크트리는 그대로 유지. 사람이 들어가서 수정·재시작 가능. 메타 파일 archive 복사 안 함 (작업 진행 중).

**8.2.5 cleanup (DONE 후 정리):**

1. 실행 중 확인 (락 파일 검사) → 실행 중이면 abort (--force 없이)
2. 워크트리 존재 확인
3. DONE 파일 확인 → 없으면 abort (--force 없이)
4. 메타 파일 archive: `<worktree>/.loop/{PLAN,NOTES,HANDOFF,RUN_LOG}.md` → `.loops/<task-id>/`
5. `git worktree remove` + `git branch -d`

### 8.3 동시성 제어

`start` 실행 시:

```bash
LOCK_DIR="$PROJECT_ROOT/.loops/locks"
TASK_ID_SAFE="$(echo "$TASK_ID" | tr '/ ' '--')"

running=$(find "$LOCK_DIR" -name "*.lock" -type f 2>/dev/null | wc -l)
if [[ $running -ge ${MAX_CONCURRENT:-3} ]]; then
  echo "이미 $running 개 loop이 동작 중 (최대: ${MAX_CONCURRENT:-3}). 거부."
  exit 2
fi

LOCK="$LOCK_DIR/$TASK_ID_SAFE.lock"
if [[ -f "$LOCK" ]]; then
  echo "task $TASK_ID가 이미 동작 중. 기존 종료 후 재실행."
  exit 3
fi
echo $$ > "$LOCK"
trap "rm -f $LOCK" EXIT
```

락 파일은 PID 보관. crashed 프로세스의 stale 락은 `stop` 또는 수동 rm으로 정리.

### 8.4 매 이터 호출 (cwd = `<worktree>/`)

```bash
cd "$WT"
cat .loop/PROMPT.md | claude \
  --print \
  --no-session-persistence \
  --dangerously-skip-permissions \
  --system-prompt-file CLAUDE.md \
  --add-dir . \
  --output-format json \
  > ".loop/iterations/$n.log"
```

### 8.5 격리 메커니즘

- **cwd = 워크트리 (프로젝트 트리 밖)** → CLAUDE.md walk-up이 프로젝트 CLAUDE.md에 도달하지 않음
- **워크트리에 `CLAUDE.md` 존재 (헌법 복사본)** → 워크트리의 closest CLAUDE.md로 자동 발견됨
- **`--system-prompt-file CLAUDE.md`** → 헌법 명시 주입 (auto-discovery 의존성 제거)
- **`.git/info/exclude`로 `CLAUDE.md`·`.loop/` 비추적** → 머지 시 메인 브랜치를 오염시키지 않음
- **`--no-session-persistence`** → 콜드 스타트 보장
- **`--add-dir .`** → 워크트리 안에서 도구 접근
- **`--print`** → 한 번 응답 후 종료 (프로세스 경계)
- **`--dangerously-skip-permissions`** → 무인 운영. 워크트리 격리로 정당화

**잔여 위험 (수용):** 사용자 레벨 `~/.claude/CLAUDE.md` / `~/.claude/settings.json` / auto-memory는 차단 불가 (워크트리 위치와 무관). 사용자가 본인 환경을 통제한다고 가정. README에 "루프 시작 전 `~/.claude/` 검토 권장" 명시.

### 8.6 객관 게이트 (매 이터 검사, 워크트리 안에서 평가)

| 가드 | 메커니즘 | 위반 시 |
|---|---|---|
| 이터 상한 | 카운터 ≤ `--max-iterations` (기본 30) | halt + 에스컬레이션 자동 작성 |
| 시계 캡 | 누적 시간 ≤ `--wall-clock-minutes` (기본 120) | halt |
| DONE 파일 | 워크트리 루트의 `DONE` 존재 검사 | 정상 종료 + archive |
| ESCALATION.md | `.loop/ESCALATION.md` 존재 검사 | halt (사람 처리 대기) |
| 테스트 약화 | 워크트리의 `tests/**` 해시 비교 | halt |
| 의존성 동결 | 워크트리의 매니페스트 해시 | halt |
| Scope 위반 | `git diff --name-only` vs PROMPT.md frontmatter의 `scope.include`/`scope.exclude` (yq 파싱) | halt + diff stash |
| Suppressor 신규 | `git diff` grep `noqa\|@ts-ignore\|eslint-disable\|#pragma warning disable` | halt |
| Secrets | `gitleaks detect --staged` (있을 때) | halt |
| fix:symptom streak | `git log --pretty=format:%s -2 \| grep -c '^fix:symptom'` ≥ 2 | halt + 에스컬레이션 |
| 진동 | 최근 4 커밋의 변경 파일 셋 비교 — 두 상태 토글 검출 | halt |

각 가드는 워크트리 안에서 평가되므로 **다른 워크트리(다른 task)와 독립**. 동시 실행 시 한 task의 게이트 검사가 다른 task에 영향 주지 않는다.

### 8.7 매 이터 의사 코드

```bash
# (워크트리 존재·락 확보 가정)
cd "$WT"
n=$(($(ls .loop/iterations/*.log 2>/dev/null | wc -l) + 1))
START_HASH_TESTS=$(hash_tests)
START_HASH_DEPS=$(hash_deps)

# PROMPT.md frontmatter 파싱 (scope·verify)
SCOPE_INCLUDE=$(yq '.scope.include[]' .loop/PROMPT.md)
SCOPE_EXCLUDE=$(yq '.scope.exclude[]' .loop/PROMPT.md)
VERIFY_CMD=$(yq '.verify' .loop/PROMPT.md)

# 호출
cat .loop/PROMPT.md | claude \
  --print --no-session-persistence --dangerously-skip-permissions \
  --system-prompt-file CLAUDE.md \
  --add-dir . --output-format json \
  > ".loop/iterations/$n.log"

# 게이트 검사
[[ -f DONE ]] && { archive_meta_files; exit 0; }
[[ -f .loop/ESCALATION.md ]] && exit 1
[[ "$(hash_tests)" != "$START_HASH_TESTS" ]] && halt "tests modified"
[[ "$(hash_deps)" != "$START_HASH_DEPS" ]] && halt "deps modified"
out_of_scope=$(diff_vs_scope) && [[ -n "$out_of_scope" ]] && halt "out of scope: $out_of_scope"
new_suppressors=$(grep_new_suppressors) && [[ -n "$new_suppressors" ]] && halt "new suppressors"
fix_symptom_streak=$(git log --pretty=format:%s -2 | grep -c '^fix:symptom')
[[ $fix_symptom_streak -ge 2 ]] && halt "fix:symptom streak"
oscillation=$(detect_oscillation) && [[ -n "$oscillation" ]] && halt "oscillation"
[[ $n -ge $MAX_ITERS ]] && halt "max iterations"
[[ $(elapsed_minutes) -ge $WALL_CLOCK ]] && halt "wall clock"
```

`halt()` 동작: 진행 중 변경을 워크트리 안에서 git stash + 표준 형식의 자동 ESCALATION.md 작성 + exit 1.

### 8.8 의도적 비-범위

- 슈퍼바이저 프로세스(stream-json 실시간 소비)
- 분산 실행
- 토큰 사전 추정·달러 캡 (`--max-budget-usd`는 OAuth에 무의미)
- 자동 머지 — 항상 사람의 검토 후 머지
- 단순 셸. 복잡도 증가가 필요하면 향후 슈퍼바이저 변종으로 분기

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
  - 메모리 파일 스텁 5종 → `.loops/templates/`
- `.loops/locks/.gitkeep`, `.loops/archive/.gitkeep` 생성 (디렉토리 추적용)
- `.gitignore`에 다음 라인 추가 (이미 있으면 skip):
  - `.loops/locks/`
  - `<project-name>-loops/` (sibling 워크트리 디렉토리. 부모 git에서 무시 — git 자체 추적은 안 되지만 실수 방지)
- 기존 파일 존재 시 덮어쓰지 않고 사용자에게 diff 확인

### 9.2 템플릿 (`templates/ralph-loop.md`) frontmatter

```yaml
---
label: 랄프 루프 (sibling 워크트리, 객관 게이트, 동시 실행 지원)
description: 매 이터 콜드 스타트 + 4대 메모리 파일 + git commit 자기 분류 + 워크트리 격리
recommended: true
on_create: |
  1. assets/PROMPT.template.md를 .loops/PROMPT.template.md로 복사
  2. assets/loop.sh를 .loops/loop.sh로 복사하고 chmod +x
  3. assets/loops-README.md를 .loops/README.md로 복사
  4. assets/{PLAN,NOTES,HANDOFF,RUN_LOG,ESCALATION}.template.md를 .loops/templates/ 아래로 복사
  5. .loops/locks/.gitkeep, .loops/archive/.gitkeep 생성
  6. .gitignore에 다음 라인 추가 (이미 있으면 skip):
     - .loops/locks/
     - ../<project-name>-loops/   # sibling 워크트리 위치 — 사용자가 LOOP_WORKTREE_BASE로 변경 시 조정 필요
  7. 사용자에게 다음 안내 메시지 출력:
     "자율 루프가 설치되었습니다.
      sibling 워크트리는 ../<project-name>-loops/<task-id>/ 에 생성됩니다.
      LOOP_WORKTREE_BASE 환경 변수로 위치 변경 가능.

      새 task 시작:
        ./.loops/loop.sh <task-id>           # 첫 호출: 워크트리 + 메타 파일 생성
        $EDITOR ../<project-name>-loops/<task-id>/.loop/PROMPT.md   # 작업 정의 채움
        ./.loops/loop.sh <task-id>           # 두 번째 호출: 루프 시작

      동시 실행: MAX_CONCURRENT 환경 변수로 조정 (기본 3).
      자세한 내용은 .loops/README.md 참조."
---

# autonomous-loop — 자율 루프 운영 규칙

[본문에 헌법 §1~§13이 그대로 들어감]
```

본문은 `rules/autonomous-loop.md`로 기록되는 헌법 본체. SKILL.md는 본문을 알 필요 없음.

### 9.3 bootstrap 통합

이 스킬은 `*-rule-creator` 접미사를 가지므로 `bootstrap`이 자동 열거. 단:

- 자율 루프는 모든 프로젝트의 기본값으로 적합하지 않다 → `bootstrap`의 카테고리 선택 단계에서 사용자가 명시적으로 체크해야 생성됨 (이미 `bootstrap`의 동작 — "전체 / 일부 / 없음" 선택)
- 권장 가이드라인: README나 `bootstrap` 안내문에 "자율 루프는 장시간 무인 작업이 필요할 때만 추가" 명시

## 10. 사용자 워크플로 (`.loops/README.md`에 안내)

### 10.1 새 task 시작

```bash
# 1. 첫 호출 — 워크트리 + 메타 파일 생성
./.loops/loop.sh auth-refactor
# 출력: "워크트리 생성: ../<project>-loops/auth-refactor"
#       "다음 파일을 채워 주세요: ../<project>-loops/auth-refactor/.loop/PROMPT.md"

# 2. PROMPT.md에 작업 정의 채움
$EDITOR ../<project>-loops/auth-refactor/.loop/PROMPT.md
# - YAML frontmatter: scope.include / scope.exclude / verify
# - 본문 placeholder: {{task_description}}, {{acceptance_criteria}}, ...

# 3. 두 번째 호출 — 실제 루프 시작
./.loops/loop.sh auth-refactor

# 4. 진행 모니터링 (별도 터미널)
tail -f ../<project>-loops/auth-refactor/.loop/RUN_LOG.md
ls -la ../<project>-loops/auth-refactor/.loop/iterations/

# 5. 정지: Ctrl+C, 또는 DONE/ESCALATION.md가 생기면 자동 종료
```

### 10.2 DONE 후 머지

```bash
# 워크트리에서 검토
cd ../<project>-loops/auth-refactor
git log autonomous-loop/auth-refactor

# 메인 프로젝트로 돌아와 머지 (또는 PR 생성)
cd <project>
git merge autonomous-loop/auth-refactor
# 또는: gh pr create --base main --head autonomous-loop/auth-refactor

# 워크트리 정리
git worktree remove ../<project>-loops/auth-refactor
git branch -d autonomous-loop/auth-refactor   # 또는 -D
```

archive 메타 파일은 `.loops/archive/auth-refactor/`에 보관됨 — 나중에 회고·재학습용.

### 10.3 동시 실행

```bash
# 두 task 병렬 실행
./.loops/loop.sh auth-refactor &
./.loops/loop.sh schema-migration &

# 진행 모니터링 (집계)
tail -f ../<project>-loops/*/.loop/RUN_LOG.md

# 동시 실행 캡 조정 (기본 3)
MAX_CONCURRENT=5 ./.loops/loop.sh new-task &

# 모든 워크트리 목록
git worktree list

# 모든 RUNNING 락 확인
ls .loops/locks/
```

### 10.4 ESCALATION 처리

```bash
# 정지된 task의 보고서 읽기
cat ../<project>-loops/<task-id>/.loop/ESCALATION.md

# 사람이 결정 후 워크트리에서 수정·재시작
cd ../<project>-loops/<task-id>
$EDITOR .loop/PROMPT.md   # 명세 조정
$EDITOR .loop/NOTES.md    # 학습 보강
rm .loop/ESCALATION.md    # 보고 해제
cd <project>
./.loops/loop.sh <task-id>   # 재시작
```

## 11. 동시 실행 모델

### 11.1 자동 격리 (워크트리로 인해 무료)

| 자원 | 격리 | 비고 |
|---|---|---|
| 작업 파일 (코드·테스트) | ✅ 워크트리별 | git worktree가 working tree 분리 |
| Git 브랜치·커밋 | ✅ `autonomous-loop/<task-id>` 별 | 히스토리 인터리빙 없음 |
| 메타 파일 | ✅ `<worktree>/.loop/` 별 | 교차 오염 없음 |
| Iteration 카운터 | ✅ 워크트리별 | 충돌 없음 |
| auto-memory 버킷 | ✅ cwd 키 → 워크트리별 독립 | 자동 |
| 객관 게이트 평가 | ✅ 워크트리 안에서 | 한 task의 변경이 다른 task의 게이트에 영향 없음 |

### 11.2 명시적 관리 자원

| 자원 | 충돌 방식 | 대응 |
|---|---|---|
| Anthropic API rate limit | 동시 요청 폭증 → 429 | `MAX_CONCURRENT` 캡 (기본 3). 락 디렉토리로 강제 |
| 디스크 (워크트리 + node_modules 등) | N개 worktree = N개 working copy | 사용자 자각. `pnpm` 등 hardlink 도구 권장 |
| CPU (테스트·빌드 병렬) | 자연 분배 | 테스트 러너의 병렬 옵션 조정 가능 |
| 사용자 모니터링 | 분산 | `tail -f ../<project>-loops/*/.loop/RUN_LOG.md` 집계 |

### 11.3 동시성 락

`.loops/locks/<task-id>.lock` 파일에 PID 기록. trap으로 EXIT 시 자동 정리. crashed 프로세스의 stale lock은 README의 정리 절차로 사용자가 처리.

같은 task-id 이중 실행은 락 검사로 차단.

### 11.4 한 task의 두 단계 동시 진행

같은 task에서 두 번째 `loop.sh` 호출을 시도하면 락이 있어 거부됨 (exit 3). 한 task = 한 워크트리 = 한 진행자 원칙.

## 12. 향후 확장

- 변종 템플릿: 슈퍼바이저(stream-json 실시간 소비) / 수용-테스트 앵커(verify 통과를 종료 조건으로 자물쇠) / 멀티 작업 의존 그래프
- 메모리 파일 자동 회전: NOTES.md 100줄 초과 시 `failures/`로 분할 (드라이버 또는 모델)
- API key 사용 환경: `--bare` + `--max-budget-usd` 옵션 추가 (조건부)
- GitHub Issue 에스컬레이션: ESCALATION.md → `gh issue create` 자동화 (선택 훅)
- 워크트리 자동 정리: DONE된 task의 워크트리를 사용자 동의 하에 자동 remove
- 비-git 프로젝트 지원: 현재 설계는 git worktree 가정. git 미사용 프로젝트는 단순 디렉토리 복사 변종 필요

## 13. 검증 기준 (스킬 완성도)

이 설계가 구현됐다고 인정되려면:

1. `bootstrap` 호출 흐름에서 `autonomous-loop` 카테고리 선택 시 §3.1의 트리가 정확히 생성된다
2. `loop.sh`가 워크트리 부재 시 `git worktree add`로 sibling 위치(`<project>/../<project-name>-loops/<task-id>/`)에 워크트리를 생성하고 헌법·메모리 스텁을 시드한 후 사용자에게 PROMPT.md 작성을 안내하고 종료한다
3. `loop.sh`가 워크트리 존재 시 동시성 락(`MAX_CONCURRENT`·task별)을 검사한 후 매 이터를 워크트리 cwd에서 실행한다
4. 워크트리에 자기만의 `CLAUDE.md`가 존재하고 `.git/info/exclude`로 비추적되어, 이후 머지에 들어가지 않는다
5. 생성된 PROMPT.md template의 YAML frontmatter(scope·verify)가 `yq`로 파싱 가능하고 placeholder가 모두 사용자가 채울 수 있는 형태로 명시된다
6. 헌법(`rules/autonomous-loop.md`)이 자체완결적이며 외부 소스 문서를 참조하지 않는다
7. 드라이버의 객관 게이트 9종(테스트 약화·의존성·scope·suppressor·secrets·fix:symptom streak·진동·이터 상한·시계 캡)이 모두 구현·테스트된다
8. DONE 시 `.loop/` 메타 파일이 `<project>/.loops/archive/<task-id>/`로 영속화되고 사용자에게 머지 절차가 안내된다
9. ESCALATION.md 작성 시 워크트리는 보존되고 archive 복사는 일어나지 않는다
10. 두 task가 동시에 실행될 때 각자의 워크트리·브랜치·메타 파일·iteration 카운터가 격리되어 race가 발생하지 않는다
11. 같은 task-id 이중 실행이 락으로 차단된다
12. 사용자 레벨 CLAUDE.md/settings 잔여 위험이 README에 명시된다
13. 헌법에 Iron Laws 절(§0)이 있고 TDD/verification/root cause 3대 명령이 명시된다
14. 헌법 §3.2가 6단계로 RED-GREEN 명시한다
15. 헌법 §4.2 조기 정지 조건에 "3회 이상의 fix 실패"가 포함된다
16. 헌법 §6.1에 다층 시스템 진단 로깅 항목이 있다
17. 헌법 §8이 4 phase로 구조화된다 (Root Cause → Pattern → Hypothesis → Implementation)
18. 헌법 §3.4 완료 판정이 4-Level Verifier (existence·substantive·wired·runtime)로 명시된다
19. 헌법 §5.2 ESCALATION 양식에 카테고리 필드 (5종)이 있고 ESCALATION.template.md에 카테고리 가이드가 포함된다
20. loop.sh가 `--watch` 플래그를 지원하며 ESCALATION.md 감지 시 polling으로 재개 신호를 대기하는 durable wake 모드를 제공한다
21. 헌법 §3.5에 Self-Review 4축 체크리스트 (Completeness·Quality·Discipline·Testing)가 있다
22. 헌법 §12에 DONE_WITH_CONCERNS 신호(HANDOFF.md `## 의심점` 섹션) 매커니즘이 명시되고 HANDOFF.template.md에 해당 섹션이 포함된다
23. 헌법 §11.6에 이터 내 Agent 도구 위임 가이드(권장·금지 케이스, 브리프 품질)가 있다
24. `loop.sh prepare <task-id>`가 `.loops/<task-id>/PROMPT.md`를 생성하고, 이미 존재하면 abort한다
25. `loop.sh start <task-id>`가 PROMPT.md 존재 확인 + placeholder 검증 후 워크트리 생성 + 락 획득 + 이터레이션을 수행한다
26. `loop.sh cleanup <task-id>`가 DONE 파일 없이는 abort하고(--force 없이), DONE 확인 후 메타 파일을 `.loops/<task-id>/`로 archive한 뒤 워크트리와 브랜치를 제거한다
