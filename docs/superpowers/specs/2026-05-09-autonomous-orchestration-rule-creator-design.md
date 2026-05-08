# `autonomous-orchestration-rule-creator` 설계 스펙

작성일: 2026-05-09
대상 플러그인: `plugins/project-init/`
신규 스킬 위치: `plugins/project-init/skills/autonomous-orchestration-rule-creator/`

전제(Layer 1): `plugins/project-init/skills/autonomous-loop-rule-creator/`가 설치돼 `<project>/.loops/loop.sh`와 단일 task 인프라가 존재함. 본 스킬은 그 원자를 합성하는 상위 레이어.

## 1. 목적

대상 프로젝트에 **goal-driven 멀티 task 자율 수행 환경**을 한 번의 스킬 호출로 설치한다. 산출물은 다음을 모두 충족해야 한다.

- **분해 보조**: AI Planner가 GOAL.md에서 PLAN.yaml(DAG) 초안을 생성, 사람이 검토·편집하는 게이트
- **결정론적 실행**: yq + 위상 정렬 + polling으로 task 스케줄링. AI 의사결정 없음 → drift 없음
- **부분 회복**: 한 task의 ESCALATION이 의존 가지만 정지시키고 독립 가지는 계속 진행
- **단일 PR 집계**: 모든 task DONE 후 goal 브랜치로 순차 머지, 충돌은 사람에게 surface
- **자원 캡**: PLAN.yaml의 정적 캡 + 환경변수의 동적 우선
- **격리**: 각 task가 자기 워크트리 (Layer 1 그대로 사용). goal 단위 추가 락으로 동시 goal 충돌도 차단

본 시스템은 단일 task Ralph loop의 단순함을 보존하기 위해 **레이어로 분리**된다. Layer 1(`autonomous-loop`)을 단독 사용할 수 있고, Layer 2(`autonomous-orchestration`)는 Layer 1 위에 합성 책임만 추가한다.

## 2. 채택·기각 패턴

| 패턴 | 채택? | 이유 |
|---|---|---|
| AI Planner 루프 + 사람 검토 게이트 (A1) | **채택** | 분해는 AI 강점, 사람의 마지막 검증으로 잘못된 분해 차단 |
| 사용자 수동 PLAN.yaml 작성 (A2) | **부분 채택** | A1을 건너뛰고 사용자가 직접 PLAN.yaml을 두면 Planner 단계 생략. 명시적으로 invoke 안 함, GOAL.md 옆에 PLAN.yaml이 있으면 그대로 execute |
| 결정론적 셸 스케줄러 (B1) | **채택** | yq + 위상 정렬 + polling. drift 없음, 비용 안정, 디버그 쉬움 |
| AI Orchestrator 루프 (B2) | **기각** | drift 두 층 증식. 적응성 이득보다 신뢰성 손실 큼. 향후 변종 템플릿으로 검토 |
| 부분 회복(의존만 정지, 독립 계속) (C1) | **채택** | 작은 실패 하나로 큰 진전을 잃지 않음 |
| Hard halt(전체 정지) (C2) | **기각** | 단순하나 부분 진전 회복 불가 |
| Goal 브랜치 순차 머지 + 충돌 사람 게이트 (D1) | **채택** | 단일 PR 검토. 자동 머지 안 함 → 정직성 가정 보존 |
| Task 브랜치 독립 유지 (D2) | **기각** | N개 PR 병렬 부담. 큰 goal에서 통합 시점 모호 |

## 3. 두 레이어 관계

| | Layer 1: `autonomous-loop` | Layer 2: `autonomous-orchestration` (본 스펙) |
|---|---|---|
| 단위 | task | goal (= task DAG) |
| 헌법 | `rules/autonomous-loop.md` | `rules/autonomous-orchestration.md` |
| 인프라 디렉토리 | `<project>/.loops/` | `<project>/.goals/` |
| 드라이버 | `.loops/loop.sh <task-id>` | `.goals/orchestrator.sh <goal-id> [plan|execute|aggregate]` |
| 워크트리 | `<project>-loops/<task-id>/` | task별: `<project>-loops/<goal-id>/<task-id>/`, planner: `<project>-loops/<goal-id>/_planner/` |
| 브랜치 | `autonomous-loop/<task-id>` | task별: `autonomous-loop/<goal-id>/<task-id>`, goal: `goal/<goal-id>` |
| 런타임 인스턴스 | `.loops/<task-id>/`는 없음 (워크트리에 메타) | `.goals/<goal-id>/`에 GOAL/PLAN/STATUS/aggregation |
| 스킬 | `autonomous-loop-rule-creator` | `autonomous-orchestration-rule-creator` |

**호출 관계:** orchestrator.sh는 각 task에 대해 `.loops/loop.sh <goal-id>/<task-id>` 형태로 Layer 1 드라이버를 호출. Layer 1은 task-id의 슬래시를 그대로 워크트리·브랜치 네임스페이스로 해석.

**Layer 1 변경 필요?** 매우 작음. `loop.sh`가 task-id에 슬래시가 들어와도 워크트리 경로(`<project>-loops/<task-id>/` → 슬래시 그대로)와 브랜치명에 그대로 사용하면 됨. 락 파일 이름은 슬래시를 안전 문자로 치환. 이 한 가지 호환성만 Layer 1 스펙에 추가.

## 4. 산출물 트리

### 4.1 스킬이 생성 (대상 프로젝트 안)

```
<project root>/
├── rules/
│   └── autonomous-orchestration.md       # 헌법: orchestrator + planner 운영 규칙
└── .goals/
    ├── README.md                         # goal 모드 사용법
    ├── GOAL.template.md                  # 새 goal의 GOAL.md 시드
    ├── PLAN.template.yaml                # PLAN.yaml DAG 스키마
    ├── PLANNER.template.md               # AI Planner 루프의 PROMPT 시드
    ├── orchestrator.sh                   # 결정론적 셸 스케줄러
    ├── locks/                            # goal 단위 락 (gitignored)
    │   └── .gitkeep
    └── archive/                          # 완료 goal의 PLAN/STATUS/aggregation 보관
        └── .gitkeep
```

`.gitignore`에 추가될 라인:
- `.goals/locks/`

전제 의존: `<project>/rules/autonomous-loop.md`, `<project>/.loops/loop.sh`. 본 스킬은 Layer 1 부재 시 사용자에게 안내 후 종료.

### 4.2 런타임 — goal 인스턴스 (사용자/Planner가 생성)

```
<project>/.goals/<goal-id>/                # 메인 브랜치에 추적
├── GOAL.md                                # 사용자 작성: 목표·수용 기준·성공 지표
├── PLAN.yaml                              # Planner 또는 사용자 작성: DAG
├── STATUS.md                              # orchestrator가 갱신: 매 task의 상태
└── aggregation/
    ├── merge-log.md                       # 머지 진행 로그
    └── conflicts.md                       # 충돌 발생 시 작성
```

### 4.3 런타임 — 워크트리 (sibling, Layer 1 위치)

```
<parent>/<project>-loops/<goal-id>/
├── _planner/                               # Planner Ralph 루프 (PLAN.yaml 생성용)
│   ├── CLAUDE.md                           # Planner 헌법 복사본
│   └── .loop/                              # Planner의 메모리 파일
└── <task-id>/                              # 각 task. Layer 1 단일 task와 동일 구조
    ├── CLAUDE.md                           # task 헌법 (rules/autonomous-loop.md 복사)
    └── .loop/
        ├── PROMPT.md                       # 작업 정의 (orchestrator가 PLAN.yaml에서 합성)
        ├── PLAN.md / NOTES.md / HANDOFF.md / RUN_LOG.md / iterations/
        └── ESCALATION.md
```

## 5. PLAN.yaml 스키마

```yaml
# Goal 단위 메타
goal_id: <kebab-case>
description: <한 줄 요약>
created: <YYYY-MM-DD>

# 자원 캡 (정적). 환경변수가 우선
max_parallel: 3                       # 동시 실행 task 수
max_total_minutes: 480                # goal 전체 시계 캡
max_total_iterations: 200             # 모든 task 이터수 합

# 집계 정책
aggregation:
  strategy: merge                     # merge|independent (현재 merge만 지원)
  base_branch: main                   # 머지 기준 브랜치

# Task 정의
tasks:
  - id: <kebab-case>                  # task-id (goal 안에서 유일)
    description: |
      이 task가 해결하는 것 (PROMPT.md 본문 합성에 사용)
    depends_on: []                    # 의존하는 task id 목록
    
    scope:                            # Layer 1 PROMPT.md frontmatter와 동일 형식
      include:
        - src/**
      exclude:
        - rules/**
        - .loops/**
        - .goals/**
    verify: pnpm test --filter=<id>   # 수용 검증 명령
    
    max_iterations: 30                # task 단위 캡 (Layer 1)
    wall_clock_minutes: 90            # task 단위 시계 캡
    
  - id: api-impl
    description: |
      ...
    depends_on: [schema-design]
    scope:
      include: [src/api/**]
    verify: pnpm test --filter=api
```

**검증 규칙 (Planner 루프의 verify이자 orchestrator의 사전 검사):**
- 모든 task에 `id`·`description`·`scope.include`·`verify` 존재
- `depends_on`이 가리키는 모든 id가 존재
- DAG에 사이클 없음 (위상 정렬 가능)
- task id는 kebab-case, 파일시스템 안전
- task scope에 `.loops/`·`.goals/`·`rules/` 포함되지 않음 (자기 수정 금지)

## 6. STATUS.md 형식

orchestrator가 매 polling 주기마다 갱신:

```markdown
# Goal: <goal-id> Status

업데이트: <ISO timestamp>

## 진행 요약
- 총 task: 7
- DONE: 3
- 진행 중: 2
- ready (대기): 1
- blocked (의존 미충족): 1
- escalated: 0
- skipped (의존 실패로 정지): 0

## Task별 상태
- [x] schema-design — DONE (이터 12, 23분, 머지 가능)
- [-] api-impl — RUNNING (이터 5, 워크트리: <path>)
- [-] db-migration — RUNNING (이터 3)
- [ ] integration-tests — READY (의존 충족, 다음 polling에 launch 예정)
- [ ] perf-tuning — BLOCKED (api-impl 대기)
- [ ] docs — BLOCKED (api-impl, integration-tests 대기)

## 최근 이벤트 (시간 역순)
- 14:23 api-impl 이터 5 진행
- 14:21 schema-design DONE
- ...
```

사람용·디버깅용 단일 진실. orchestrator는 매 polling에 덮어씀.

## 7. Orchestrator 동작 (`.goals/orchestrator.sh`)

### 7.1 호출 인터페이스

```bash
./.goals/orchestrator.sh <goal-id> <subcommand>
```

서브커맨드:
- `plan` — Planner 루프를 시작 (GOAL.md만 있고 PLAN.yaml 없을 때)
- `execute` — DAG 실행 (PLAN.yaml 존재 가정)
- `aggregate` — DONE 후 goal 브랜치로 머지
- `status` — STATUS.md 출력
- `stop` — 모든 진행 중 task 중단

환경변수:
- `GOAL_MAX_PARALLEL` — `max_parallel` 우선 덮어쓰기
- `GOAL_MAX_TOTAL_MINUTES` — `max_total_minutes` 우선
- `LOOP_WORKTREE_BASE` — Layer 1 그대로 상속

### 7.2 plan 서브커맨드

```bash
[전제: GOAL.md 존재, PLAN.yaml 부재]
1. Planner 루프 워크트리 생성: <project>-loops/<goal-id>/_planner
2. 헌법 복사: rules/autonomous-orchestration.md → _planner/CLAUDE.md
3. Planner PROMPT 시드: .goals/PLANNER.template.md → _planner/.loop/PROMPT.md
   (placeholder를 GOAL.md 내용으로 치환)
4. 메모리 파일 시드 (PLAN.md, NOTES.md, HANDOFF.md, RUN_LOG.md)
5. .git/info/exclude에 CLAUDE.md, .loop/ 추가
6. .loops/loop.sh를 _planner 워크트리 모드로 호출:
   cd <project>-loops/<goal-id>/_planner
   loop.sh <goal-id>/_planner
7. Planner DONE → _planner/PLAN.yaml.draft가 생성됨
8. 사용자에게 출력:
   "Plan 초안: <project>-loops/<goal-id>/_planner/PLAN.yaml.draft
    검토 후 .goals/<goal-id>/PLAN.yaml로 복사:
       cp <draft path> .goals/<goal-id>/PLAN.yaml
       $EDITOR .goals/<goal-id>/PLAN.yaml
    완료 후 execute 호출:
       ./.goals/orchestrator.sh <goal-id> execute"
9. 종료. 자동으로 PLAN.yaml을 PLAN.yaml로 옮기지 않는다 — 사람의 검토 게이트.
```

Planner의 verify는 PLAN.yaml.draft의 구조 검증(yq로 파싱·schema 검사·사이클 검사). 통과하면 DONE 작성.

### 7.3 execute 서브커맨드

```bash
[전제: GOAL.md, PLAN.yaml 존재]
1. PLAN.yaml 파싱 (yq) → tasks·deps·caps 로드
2. STATUS.md 초기화 또는 복원 (재시작 시 진행 상태 회복)
3. goal 단위 락 확보: .goals/locks/<goal-id>.lock
   (이미 있으면 거부 — 같은 goal 이중 실행 방지)
4. 메인 루프:
   while true:
     a. STATUS.md 갱신
     b. 각 진행 중 task의 워크트리에서 DONE/ESCALATION 검사
        - DONE 발견: STATUS에 DONE 마킹, 의존자 ready 평가
        - ESCALATION 발견: 7.5의 부분 회복 정책 적용
     c. ready task 중 (총 진행 중 < max_parallel)인 동안 launch:
        - 아직 워크트리 없으면: orchestrator가 워크트리 생성 + PROMPT.md 합성
          (PLAN.yaml의 task 정의 → PROMPT.md frontmatter·본문 합성)
        - loop.sh <goal-id>/<task-id> & 으로 background 실행
     d. 종료 조건 검사:
        - 모든 task가 DONE/SKIPPED → execute 정상 종료, 자동으로 aggregate 단계 제안
        - 모든 task가 RUNNING/BLOCKED 아니고 진행 가능한 ready 없음 → 데드락
        - max_total_minutes 초과 → halt
        - max_total_iterations 초과 → halt
     e. 1초 sleep (polling 주기)
5. 락 해제 (trap)
```

### 7.4 task 워크트리 생성 (orchestrator가 PLAN.yaml에서 합성)

```bash
TASK_ID=<task-id>
TASK_NS=<goal-id>/<task-id>
WT=<project>-loops/<TASK_NS>/

# Layer 1 loop.sh의 첫 호출 모드를 트리거하기 위해 PROMPT.md를 미리 합성
git worktree add "$WT" -b "autonomous-loop/$TASK_NS"
cp rules/autonomous-loop.md "$WT/CLAUDE.md"
mkdir -p "$WT/.loop/iterations"

# PROMPT.md 합성 — PLAN.yaml의 해당 task 정의 + Layer 1 PROMPT.template.md 본문
synthesize_prompt() {
  yq -r ".tasks[] | select(.id == \"$TASK_ID\") | ..." PLAN.yaml > "$WT/.loop/PROMPT.md"
  # 본문에 placeholder 치환
}

cp .loops/templates/{PLAN,NOTES,HANDOFF,RUN_LOG}.template.md "$WT/.loop/"
{
  echo "CLAUDE.md"
  echo ".loop/"
} >> "$WT/.git/info/exclude"

# Layer 1 드라이버에 위임
.loops/loop.sh "$TASK_NS" &
```

이후 `loop.sh`는 워크트리·메타 파일이 이미 존재함을 보고 첫 이터를 바로 시작 (Layer 1의 §8.2.1 분기는 워크트리 부재 시에만 시드하고 종료하므로 워크트리 존재 시 §8.2.2 분기로 진입).

### 7.5 부분 회복 정책 (C1 상세)

ESCALATION 발견 시:
1. 그 task를 STATUS.md에서 ESCALATED로 마킹
2. 의존성 그래프에서 그 task의 직간접 후행 task를 모두 SKIPPED로 마킹 (실행 안 함)
3. 그 task와 후행이 아닌 task는 영향 없음, 계속 진행
4. 모든 비-후행 task가 DONE이 되면 execute 종료
5. 사용자에게 출력:
   ```
   Goal <goal-id>: 7개 task 중 4개 DONE, 1개 ESCALATED, 2개 SKIPPED
   ESCALATED: api-impl
   SKIPPED (api-impl 의존): integration-tests, docs
   
   처리:
     1. 워크트리 들어가서 ESCALATION.md 읽고 수정:
        cd <project>-loops/<goal-id>/api-impl
     2. ESCALATION.md 삭제 후 재시작:
        ./.goals/orchestrator.sh <goal-id> execute
   ```
6. 사용자가 재시작하면 ESCALATED → READY로 전환, SKIPPED는 의존 충족 시 다시 BLOCKED→READY

### 7.6 aggregate 서브커맨드

```bash
[전제: STATUS.md 모든 task가 DONE 또는 SKIPPED]
1. goal/<goal-id> 브랜치 생성: git switch -c goal/<goal-id> main
2. PLAN.yaml의 task를 위상 정렬 순서로 머지:
   for task in topological_order:
     if status == "DONE":
       git merge "autonomous-loop/<goal-id>/<task-id>" --no-ff
       if 충돌:
         git merge --abort
         conflicts.md에 충돌 보고 작성:
           - 충돌 task·파일·hunk
           - 어느 두 가지가 충돌했는지
           - 권장 해결 절차
         사용자에게 안내 후 exit (사용자가 수동 머지 후 다시 aggregate 호출)
     elif status == "SKIPPED":
       merge-log에 "skipped" 기록, 머지 안 함
3. 모두 성공 시:
   - merge-log에 최종 보고
   - 사용자에게 PR 생성 권장 메시지
   - SKIPPED task 목록을 함께 출력 (사용자가 그 task를 별도 처리할지 결정)
4. archive 복사:
   cp <project>/.goals/<goal-id>/{GOAL.md,PLAN.yaml,STATUS.md} → .goals/archive/<goal-id>/
   cp <project>/.goals/<goal-id>/aggregation/* → .goals/archive/<goal-id>/aggregation/
```

자동 머지하지 않는다 — `aggregate`는 명시적 사용자 호출. execute 종료 시 "aggregate를 호출하시겠습니까?"는 안내만 하고 실행 안 함.

### 7.7 stop 서브커맨드

```bash
1. .goals/locks/<goal-id>.lock 읽어 PID 식별
2. 해당 orchestrator 프로세스에 SIGTERM
3. 진행 중 task의 RUNNING 락에서 PID 식별, 각 loop.sh에 SIGTERM
4. 각 워크트리에 ESCALATION.md 자동 작성: "사용자 stop 요청"
5. STATUS.md 갱신
```

### 7.8 의도적 비-범위

- 자동 머지 (항상 사람 검토)
- task 자동 재시작 (ESCALATION은 항상 사람 결정)
- PLAN.yaml 동적 수정 (실행 중 plan 변경 안 함, drift 방지)
- 다중 goal 동시 실행 (한 번에 한 goal — 향후 확장)
- 분산·원격 실행

## 8. Planner Ralph 루프

`.goals/PLANNER.template.md`가 시드 PROMPT. orchestrator의 plan 서브커맨드가 워크트리에 복사 + GOAL.md 내용 placeholder 치환.

### 8.1 Planner의 임무

- 입력: GOAL.md (목표·수용 기준·성공 지표)
- 출력: PLAN.yaml.draft (구조 검증 통과)
- 제약:
  - task는 5~15개 범위 권장
  - 각 task는 단일 책임 (한 verify 명령으로 검증 가능)
  - DAG에 사이클 금지
  - scope는 명시적 화이트리스트
  - `.loops/`·`.goals/`·`rules/`는 어떤 task의 scope에도 포함하지 않음

### 8.2 Planner verify

```bash
yq '.tasks | length' PLAN.yaml.draft >= 1  # task 1개 이상
yq '.tasks[].id' PLAN.yaml.draft           # 모든 task에 id
# ... (스키마 검사)
detect-cycles                              # 사이클 검사
```

verify 통과 → Planner 루프가 DONE 작성.

### 8.3 Planner의 메모리 파일

Layer 1과 동일 구조 (PLAN.md/NOTES.md/HANDOFF.md/RUN_LOG.md). 단 task가 "PLAN.yaml.draft를 잘 만드는 것"이므로:
- PLAN.md: 분해 단계의 마일스톤 (예: "도메인 식별", "의존성 추적", "수용 기준 매핑")
- NOTES.md: 분해 시 발견한 제약 (예: "DB 스키마 변경은 마이그레이션 task에 모음")
- HANDOFF.md: 다음 Planner 이터에 보내는 편지
- RUN_LOG.md: 매 이터의 분해 시도 요약

## 9. 헌법 (`rules/autonomous-orchestration.md`)

자체완결적. Layer 1 헌법(`rules/autonomous-loop.md`)을 참조하지 않음 (다른 레이어이므로). 단 동일한 첫 원칙 정신을 공유.

### 9.1 절 구성

1. 제1 원칙 (orchestrator·planner 모두 적용)
   - PLAN.yaml은 사람의 승인 없이 실행 단계에서 수정되지 않는다 — drift 방지
   - 자동 머지 금지 — 충돌은 항상 사람 결정
   - task 재시작은 항상 사람의 명시 호출
   - goal 단위 자원 캡은 sacred — orchestrator가 수정 안 함
   
2. Plan 생성 (planner 전용)
   - 분해는 단일 책임 원칙
   - 의존은 진짜 의존만 (concurrency 위장 금지)
   - 모든 scope는 명시적
   - 분해 후 사람 게이트로 넘긴다 — 자동 진행 안 함

3. DAG 실행 (orchestrator 전용)
   - 위상 정렬 외 일정 변경 안 함
   - ESCALATION은 부분 회복 정책으로 처리
   - STATUS.md는 진실 — 갱신을 누락 안 함
   - 동시 실행 캡 강제

4. 집계 (aggregate 전용)
   - 자동 머지 금지
   - 충돌 시 사람에게 surface
   - 위상 정렬 순서로만 머지

5. 금지 행동
   - PLAN.yaml 실행 중 수정
   - SKIPPED task를 임의로 RUNNING으로 전환
   - ESCALATED task의 자동 재시도
   - merge-log·conflicts.md 위장

6. 사용자 의사소통
   - STATUS.md는 항상 사실 그대로
   - 진전·문제·결정 요청은 명시

## 10. 사용자 워크플로

### 10.1 새 goal 시작

```bash
# 1. goal 디렉토리·GOAL.md 생성
mkdir -p .goals/auth-system-rewrite
cp .goals/GOAL.template.md .goals/auth-system-rewrite/GOAL.md
$EDITOR .goals/auth-system-rewrite/GOAL.md
# - 목표 / 수용 기준 / 성공 지표 채움

# 2. Plan 생성 (AI Planner)
./.goals/orchestrator.sh auth-system-rewrite plan
# - Planner Ralph 루프가 PLAN.yaml.draft 생성
# - 출력: "<draft path> 검토 후 .goals/<goal-id>/PLAN.yaml로 복사"

# 3. 사람 검토·편집 (필수)
cp <draft path> .goals/auth-system-rewrite/PLAN.yaml
$EDITOR .goals/auth-system-rewrite/PLAN.yaml
# - task 분해 검증, 의존성 점검, scope 좁히기

# 4. 실행
./.goals/orchestrator.sh auth-system-rewrite execute

# 5. 모니터링
./.goals/orchestrator.sh auth-system-rewrite status
tail -f .goals/auth-system-rewrite/STATUS.md
tail -f ../<project>-loops/auth-system-rewrite/*/.loop/RUN_LOG.md

# 6. 완료 후 집계
./.goals/orchestrator.sh auth-system-rewrite aggregate

# 7. PR 생성
gh pr create --base main --head goal/auth-system-rewrite
```

### 10.2 ESCALATION 처리

```bash
# 어느 task 실패했는지 확인
./.goals/orchestrator.sh auth-system-rewrite status

# 워크트리 들어가서 ESCALATION.md 읽기
cat ../<project>-loops/auth-system-rewrite/api-impl/.loop/ESCALATION.md

# 사람이 결정 후 PROMPT.md·NOTES.md 수정, ESCALATION 해제
cd ../<project>-loops/auth-system-rewrite/api-impl
$EDITOR .loop/NOTES.md
rm .loop/ESCALATION.md

# 재시작 (cd 메인 프로젝트로)
cd <project>
./.goals/orchestrator.sh auth-system-rewrite execute
# - ESCALATED → READY 전환, SKIPPED → BLOCKED 전환 후 재평가
```

### 10.3 수동 PLAN.yaml 작성 (Planner 우회)

```bash
mkdir -p .goals/small-refactor
cp .goals/GOAL.template.md .goals/small-refactor/GOAL.md
cp .goals/PLAN.template.yaml .goals/small-refactor/PLAN.yaml
$EDITOR .goals/small-refactor/{GOAL.md,PLAN.yaml}

# plan 단계 건너뛰고 바로 execute
./.goals/orchestrator.sh small-refactor execute
```

### 10.4 stop·재시작

```bash
# 긴급 정지
./.goals/orchestrator.sh auth-system-rewrite stop
# - 모든 진행 task에 ESCALATION.md 자동 작성

# 검토 후 재시작 (필요 시 ESCALATION.md 정리)
./.goals/orchestrator.sh auth-system-rewrite execute
```

## 11. 동시성·자원 캡

### 11.1 Goal 단위 동시 실행

`.goals/locks/<goal-id>.lock`로 같은 goal 이중 실행 차단 (Layer 1과 같은 패턴).  
서로 다른 goal은 동시 실행 가능. 각 goal이 자기 worktrees·status를 가짐.

### 11.2 Goal 내부 task 동시 실행

PLAN.yaml의 `max_parallel` 또는 환경변수 `GOAL_MAX_PARALLEL`로 캡. 환경변수 우선.  
task 락은 Layer 1의 `.loops/locks/<task-ns>.lock` 그대로 사용 (네임스페이스가 슬래시 포함이므로 락 파일명은 슬래시를 `-`로 치환).

### 11.3 자원 충돌

- API rate limit: 모든 goal·task가 같은 키 공유. 시스템 전체 동시성을 사용자가 관리. 권장: `GOAL_MAX_PARALLEL=3` × goal 1개 동시 = 동시 3 task.
- 디스크: goal당 N개 워크트리. 사용자 자각.
- 머지 충돌: 같은 파일을 여러 task가 건드리면 aggregate 단계에서 충돌. PLAN.yaml의 scope를 적절히 분할해 줄이기.

## 12. 스킬 구조

```
plugins/project-init/skills/autonomous-orchestration-rule-creator/
├── SKILL.md
├── templates/
│   └── orchestrator.md            # 단일 템플릿 (현재). 향후 변종 추가 가능
└── assets/
    ├── GOAL.template.md
    ├── PLAN.template.yaml
    ├── PLANNER.template.md
    ├── orchestrator.sh
    └── goals-README.md            # `.goals/README.md` 시드
```

### 12.1 SKILL.md

`context-rule-creator/SKILL.md`와 동일한 패턴. `on_create`가 다음 수행:

- 전제 검사: `<project>/rules/autonomous-loop.md`와 `<project>/.loops/loop.sh` 존재 확인. 부재 시 사용자에게 "먼저 `autonomous-loop-rule-creator`를 실행하세요" 안내 후 종료
- `rules/autonomous-orchestration.md`로 템플릿 본문 기록
- assets의 다음 파일 복사:
  - `GOAL.template.md` → `.goals/GOAL.template.md`
  - `PLAN.template.yaml` → `.goals/PLAN.template.yaml`
  - `PLANNER.template.md` → `.goals/PLANNER.template.md`
  - `orchestrator.sh` → `.goals/orchestrator.sh` (chmod +x)
  - `goals-README.md` → `.goals/README.md`
- `.goals/locks/.gitkeep`, `.goals/archive/.gitkeep` 생성
- `.gitignore`에 `.goals/locks/` 추가
- 기존 파일 존재 시 덮어쓰지 않고 사용자에게 diff 확인

### 12.2 템플릿 (`templates/orchestrator.md`) frontmatter

```yaml
---
label: 결정론적 orchestrator + AI Planner + 부분 회복 + goal 브랜치 집계
description: PLAN.yaml DAG 기반 멀티 task 자율 수행. AI는 분해에만, 실행은 결정론
recommended: true
on_create: |
  1. 전제 검사: rules/autonomous-loop.md, .loops/loop.sh 존재 확인. 부재 시 안내 후 종료
  2. assets의 5개 파일을 .goals/ 아래 지정 경로로 복사
  3. orchestrator.sh chmod +x
  4. .goals/locks/.gitkeep, .goals/archive/.gitkeep 생성
  5. .gitignore에 `.goals/locks/` 추가 (이미 있으면 skip)
  6. 사용자 안내 메시지:
     "오케스트레이션이 설치되었습니다.
      새 goal 시작:
        mkdir .goals/<goal-id>
        cp .goals/GOAL.template.md .goals/<goal-id>/GOAL.md
        $EDITOR .goals/<goal-id>/GOAL.md
        ./.goals/orchestrator.sh <goal-id> plan        # AI Planner
        # 또는 PLAN.yaml을 직접 작성 후
        ./.goals/orchestrator.sh <goal-id> execute
      자세한 내용은 .goals/README.md 참조."
---

# autonomous-orchestration — 멀티 task 자율 수행 운영 규칙

[본문에 헌법 §1~§6이 그대로 들어감]
```

### 12.3 bootstrap 통합

`*-rule-creator` 접미사로 자동 열거. 단:
- 전제로 `autonomous-loop-rule-creator`가 먼저 설치돼야 함을 사용자에게 명시
- bootstrap의 카테고리 선택 단계에서 사용자가 명시적으로 체크해야 생성 (기본 false)

## 13. Layer 1 변경 요구사항

본 스펙이 동작하려면 Layer 1에 다음 작은 변경이 필요:

1. **task-id 슬래시 허용**: `loop.sh`가 `<goal-id>/<task-id>` 형태의 슬래시 포함 task-id를 받아도 워크트리 경로(`<project>-loops/<goal-id>/<task-id>/`)·브랜치명(`autonomous-loop/<goal-id>/<task-id>`)으로 그대로 사용
2. **락 파일명 안전화**: 락 파일은 `.loops/locks/<task-ns sanitized>.lock` (슬래시 → `-`) 형태로 저장
3. **워크트리 존재 시 시드 스킵**: 이미 메타 파일이 있으면 시드 안 하고 바로 실행 (orchestrator가 합성한 PROMPT.md를 보존)

이 변경들은 Layer 1을 단독 사용하는 경우(슬래시 없는 task-id)에 영향 없음. Layer 2 호환성 추가만.

## 14. 검증 기준

이 설계가 구현됐다고 인정되려면:

1. `bootstrap` 흐름에서 `autonomous-orchestration` 카테고리 선택 시 §4.1 트리가 정확히 생성된다 (Layer 1 부재 시 안내 후 종료)
2. `orchestrator.sh <goal-id> plan`이 GOAL.md만 있고 PLAN.yaml 부재 시 Planner 워크트리를 sibling 위치에 생성하고 PLAN.yaml.draft 생성 후 사용자에게 검토 안내 후 종료한다
3. `orchestrator.sh <goal-id> execute`가 PLAN.yaml의 위상 정렬을 따라 ready task만 launch하고 max_parallel을 강제한다
4. ESCALATION 발견 시 의존 후행만 SKIPPED로 마킹하고 독립 가지는 계속 진행한다
5. `orchestrator.sh <goal-id> aggregate`가 위상 정렬 순서로 goal/<goal-id> 브랜치에 머지하고 충돌 시 자동 머지 안 하고 conflicts.md를 작성한다
6. STATUS.md는 매 polling에 갱신되어 사람이 진행 상황을 파악할 수 있다
7. 같은 goal 이중 실행이 락으로 차단된다
8. 다른 goal은 동시 실행 가능하다 (각자 자기 락·워크트리)
9. PLAN.yaml의 자원 캡(`max_parallel`, `max_total_minutes`)이 환경변수로 우선 덮어쓰기 가능하다
10. Layer 1의 task-id 슬래시 호환성이 동작한다 (워크트리 경로·브랜치명·락 파일)
11. 헌법(`rules/autonomous-orchestration.md`)이 자체완결적이며 자율-루프-지침 등 외부 문서를 참조하지 않는다
12. archive(`.goals/archive/<goal-id>/`)에 GOAL/PLAN/STATUS/aggregation의 최종 상태가 보관된다

## 15. 향후 확장

- AI Orchestrator 변종 (B2): 적응적 plan 수정. drift 위험을 감수할 수 있는 사용자용
- 분산 실행: orchestrator가 원격 머신에 task를 위임 (현재 단일 머신 가정)
- Plan 중간 수정 워크플로: 사용자가 진행 중 PLAN.yaml을 명시 편집 + orchestrator의 안전한 재해석
- 다중 goal 동시 실행 cap·우선순위
- Goal 간 의존성 (goal A의 DONE을 goal B가 입력으로)
- 비-git 프로젝트 지원 (Layer 1과 함께)
- GitHub Issue 연동: GOAL.md → issue, ESCALATION → issue comment, aggregate → PR 자동 생성
