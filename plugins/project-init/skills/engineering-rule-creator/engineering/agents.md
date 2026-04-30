# 에이전트 협업 지침

큰 작업은 단일 에이전트가 한 세션에 처리하지 않습니다. **오케스트레이션 패턴**으로 세 역할(오케스트레이터·작업·검증)을 명확히 분리하여, 한 에이전트가 끝낸 작업을 다른 에이전트가 이어받을 수 있게 합니다.

## 전제 — 태스크 관리

이 모델은 프로젝트의 **태스크 관리 메커니즘**을 전제로 합니다. 구체 구현(GitHub Projects, 파일시스템 디렉토리, 다른 이슈 트래커 등)은 무관하지만, 다음이 가능해야 합니다.

- 태스크 식별자(`<id>`)
- 상태 어휘 — `Backlog` → `In Design` → `In Progress` → `Review` → `Done` (+ `Blocked`)
- 태스크 본문 — 목표·배경·제안·검증 계획·완료 기준(DoD) 섹션을 담을 수 있는 형태
- 태스크별 append-only 로그 — 시각·작성자가 자동 기록되면 좋음
- 핸드오프·결정·차단·검증 같은 **의미 카테고리**를 로그 항목에서 식별 가능한 형태 (prefix·label·별도 필드 등 — 어떻게든)

태스크 관리 자체의 규칙은 프로젝트의 컨텍스트 관리 지침에서 다룹니다. 이 문서는 그 위에 **분해·역할·게이트** 층을 더합니다.

## 세 역할

세 역할은 **권한이 분리**됩니다 — 같은 에이전트 인스턴스가 둘 이상의 역할을 겸하지 않습니다.

### 오케스트레이터 에이전트

큰 작업의 계획·분해·위임·통합을 담당합니다.

- **하는 것**: parent 태스크 작성(목표·배경·DoD), 분해(기능 의존성 기준), sub-태스크 draft, parent 브랜치 분기, sub-태스크 위임, parent 통합 PR 생성, parent Status 전이(`In Progress`/`Review`).
- **안 하는 것**: 코드 직접 수정, 검증 수행, 사용자 승인 없는 분해 위임, parent를 `Done`으로 전이.

### 작업 에이전트

위임받은 1 sub-태스크를 한 세션에 끝냅니다.

- **하는 것**: 받은 sub-태스크의 제안·검증 계획 작성, parent 브랜치 ← main rebase, sub 브랜치 분기, 코드 변경(자기 sub 범위), 자체 검증, commit·push, PR 생성(base: parent 브랜치).
- **안 하는 것**: 자기 sub 범위 밖 변경, parent 태스크 본문 수정, force-push, 자체 PR 머지, sub-태스크 분해(너무 크면 차단 기록으로 환송).

### 검증 에이전트

작업 에이전트의 결과물을 독립 검증하고, 통과 시 sub-태스크 PR을 머지합니다.

- **하는 것**: DoD 점검, inline review, approve 또는 차단, sub-태스크 PR 머지, sub-태스크 Status 전이(`Done` 또는 `In Progress` 환송).
- **안 하는 것**: 코드 변경(오타·import 누락·lint 자동수정도 금지 — 모두 환송), parent 통합 PR 머지, 모든 sub Done이 아닌 상태에서의 통합.

## 에이전트 정의·호출

각 역할이 어디에 정의되고 어떻게 트리거되는지. 정의 파일의 시스템 프롬프트는 위 "세 역할" 절의 책임·금지 항목을 그대로 반영합니다.

### 오케스트레이터

| 항목 | 값 |
|---|---|
| 정의 위치 | **메인 에이전트**(사용자와 직접 대화 중인 Claude 세션)가 그대로 수행. 별도 커스텀 에이전트 정의 파일을 두지 않음 |
| 트리거 | 사용자의 자유 텍스트 요청 시점부터 |
| 도구 권한 | 메인 세션이 가진 도구 전체. 다만 오케스트레이션 흐름 수행 중에는 코드 수정(Edit/Write)을 **자율 금지** — 분해·위임·통합 외 작업을 끼워 넣지 않음 |
| 사용하는 서브에이전트 | `work-agent` (Task 도구의 `subagent_type`) |

오케스트레이터를 별도 서브에이전트로 분리하지 않는 이유 — 게이트 1(분해 승인)과 게이트 2(통합 PR 머지)가 모두 사용자와의 직접 상호작용이라, 사용자와 이미 대화 컨텍스트를 공유하는 메인 세션이 자연스럽게 그 역할을 맡음. 별도 에이전트로 빼면 invocation 비용이 들고 사용자 대화의 연속성이 끊깁니다.

### 작업 에이전트

| 항목 | 값 |
|---|---|
| 정의 위치 | `.claude/agents/work-agent.md` |
| 트리거 | 오케스트레이터가 Task 도구로 (`subagent_type: work-agent`) |
| 도구 권한 | 파일 읽기·쓰기(Edit/Write), 셸(git·gh·빌드·테스트), Task(검증 에이전트가 Mode B인 경우만) |
| 격리 | worktree 또는 dev container 권장 |
| 머지 권한 | 없음 (PR 생성까지만) |

### 검증 에이전트

구현 모드 두 가지 중 **프로젝트 시작 시 명시**해야 합니다. default 없음. 모드는 프로젝트 단위로만 전환하며 PR 단위 override는 허용하지 않습니다 — 같은 프로젝트의 PR이 일관된 기준·동일 트리거로 검증돼야 감사 추적과 게이트의 신뢰성이 유지되기 때문. 특정 PR이 모드 외 처리를 필요로 한다면 모드 변경이 아니라 검증 에이전트의 차단·환송 절차나 사용자 명시 예외 승인으로 다룹니다.

#### Mode A — claude-code-action workflow

| 항목 | 값 |
|---|---|
| 정의 위치 | `.github/workflows/<name>.yml` (`anthropics/claude-code-action@v1` 사용) |
| 트리거 | PR `opened` / `synchronize` 이벤트 (자동) |
| 도구 권한 | 셸(gh CLI 등), 파일 읽기. Edit/Write는 미부여 |
| 시크릿 | `ANTHROPIC_API_KEY` |
| 적합 상황 | 팀 협업, PR 이벤트 자동화 |

워크플로우 스켈레톤:

```yaml
name: verify
on:
  pull_request:
    types: [opened, synchronize]
jobs:
  verify:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
    steps:
      - uses: anthropics/claude-code-action@v1
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        with:
          prompt: |
            <검증 에이전트의 시스템 프롬프트 — 위 "세 역할 / 검증 에이전트" 절을 그대로 반영>
```

#### Mode B — 로컬 서브에이전트

| 항목 | 값 |
|---|---|
| 정의 위치 | `.claude/agents/verifier.md` |
| 트리거 | 작업 에이전트가 Task 도구로 (`subagent_type: verifier`) — 또는 PR 생성 stop hook |
| 도구 권한 | 셸(gh CLI), 파일 읽기. Edit/Write는 미부여 |
| 격리 | 로컬 (worktree 권장) |
| 적합 상황 | 솔로 개발, 빠른 iteration, GitHub Actions 미사용 |

검증 에이전트의 책임은 모드와 무관하게 동일합니다. 모드는 **누가 언제 트리거하는가**와 **셋업 비용**만 다릅니다.

#### 모드 공통 — 차단 카운트의 영속화

검증 에이전트는 stateless 호출(특히 Mode A)이므로 재시도 카운트를 자체 보유하지 않습니다. 대신 sub-태스크의 **차단 기록 누적 수**를 매 호출마다 읽어 카운트로 사용합니다.

## 태스크 본문 섹션 책임

| 섹션 | 책임 | 작성 시점 |
|---|---|---|
| 목표 | 오케스트레이터 | parent·sub 생성 시 |
| 배경 | 오케스트레이터 | parent·sub 생성 시 |
| 제안 | 작업 에이전트 | sub-태스크 받은 직후 |
| 검증 계획 | 작업 에이전트 | sub-태스크 받은 직후 |
| 완료 기준(DoD) | 오케스트레이터 | parent·sub 생성 시 |

오케스트레이터가 정의하는 것은 "What/Done", 작업 에이전트가 채우는 것은 "How". 검증 에이전트는 **DoD를 1차 기준**으로 보고 검증 계획은 참고 자료로 사용합니다(self-referential 회피).

## 분해 원칙

- **기준 = 기능 의존성**(semantic). A의 산출물이 B의 입력이면 sequence, 기능적 독립이면 parallel. 파일 집합 겹침은 결정 기준이 **아닙니다** — 머지 충돌은 두 번째 머저(작업 에이전트)가 rebase로 해결합니다.
- **트리 깊이 2 고정**: `parent → sub-태스크`. 그 이상의 깊이 금지. 더 깊이 필요해 보이면 깊이를 늘리지 말고 **parent 자체를 더 좁게 다시 정의**(가로로 풀기). 일반 태스크 트리 권장(보통 2~3)보다 더 엄격하게 2로 고정하는 이유는 깊이 3 이상에서 분해·검증·머지 경로의 조합이 지수적으로 늘어 흐름 신뢰성이 떨어지기 때문.
- **분해 권한은 오케스트레이터 단독**: 작업 에이전트가 받은 sub가 너무 크다고 판단하면 분해하지 않고 **차단 기록**으로 환송합니다. 오케스트레이터가 재분해 또는 parent 재정의 → 사용자 재승인 → 재위임.

## 브랜치 구조

```
main
 └ feat/<parent-id>-<slug>                 ← parent 통합 브랜치
    ├ feat/<parent-id>/<sub-id>-<sub-slug>  ← sub-태스크 브랜치
    ├ feat/<parent-id>/<sub-id>-<sub-slug>
    └ ...
```

| 패턴 | 의미 |
|---|---|
| `feat/<id>-<slug>` | parent 통합 브랜치 |
| `feat/<parent-id>/<sub-id>-<slug>` | sub-태스크 브랜치 |

필터링:

| 목적 | glob |
|---|---|
| 모든 작업 브랜치 | `feat/*` |
| 특정 parent의 sub만 | `feat/<parent-id>/*` |
| 모든 sub만 (parent 제외) | `feat/*/*` |
| parent만 (sub 제외) | `feat/*-*` |

parent 브랜치에는 항상 slug가 붙기 때문에(`<id>-<slug>` 형태) `feat/<id>-<slug>` ref와 `feat/<id>/...` directory는 git refs namespace에서 충돌하지 않습니다.

### main 동기화

작업 에이전트는 sub-태스크 시작 전 parent 브랜치를 main 기준으로 rebase합니다. 작은 충돌을 자주 해소해 통합 시점에 폭발하지 않게 합니다. 그래도 parent 통합 PR 시점에 충돌이 남으면 작업 에이전트(대표)에게 환송합니다.

## 머지 경로

| PR | base | 검증 | 머지 |
|---|---|---|---|
| sub-태스크 PR | parent 브랜치 | 검증 에이전트 | **검증 에이전트** (자동머지 예외) |
| parent 통합 PR | `main` | 검증 에이전트 | **사용자** (게이트 2) |

검증 에이전트의 sub-태스크 PR 머지는 일반적인 자동머지 금지 규칙의 **명시된 예외**입니다. parent 통합 PR과 그 외 일반 작업 PR은 여전히 사용자 명시 지시 필요.

## 두 사용자 게이트

| 게이트 | 시점 | 사용자가 보는 것 |
|---|---|---|
| 게이트 1 | parent `In Design → In Progress` 직전 | 목표·배경·DoD·분해 구조 (제안·검증 계획은 비어 있음) |
| 게이트 2 | parent 통합 PR 머지 시점 | 통합 결과·DoD 충족 여부 |

게이트 1에서 제안·검증 계획이 비어 있는 것은 의도된 설계입니다 — 그 두 섹션은 작업 에이전트의 영역이며, 게이트 1은 "What/Done과 분해 자체"가 적절한지만 확인합니다.

## 차단·재시도

- 검증 에이전트가 차단을 결정하면 sub-태스크 Status를 `In Progress`로 환송하고 **차단 기록**에 사유를 남깁니다.
- 같은 sub-태스크의 **차단 기록 누적 ≥ 3**이면 자동으로 `Blocked` Status로 전이하고 parent 태스크에 에스컬레이션 기록을 남깁니다. 사용자가 분해 재조정 또는 직접 개입.
- 카운트는 sub-태스크 로그에서 차단 기록 수를 세서 결정합니다 — 검증 에이전트는 stateless이므로 카운트를 태스크에 영속화합니다.

## 권한 매트릭스

|  | 코드 수정 | 브랜치 생성 | rebase | PR 생성 | PR 리뷰 | PR 머지 | sub Status | parent Status |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 오케스트레이터 | ✗ | parent 브랜치 | ✗ | parent 통합 PR | ✗ | ✗ | ✗ | →`In Progress`(승인 후), →`Review` |
| 작업 에이전트 | ✓ (자기 sub) | sub 브랜치 | parent ← main | sub-태스크 PR | ✗ | ✗ | →`In Progress`, →`Review` | ✗ |
| 검증 에이전트 | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ (sub PR 한정) | →`In Progress`(환송), →`Done` | ✗ |
| 사용자 | — | — | — | — | — | ✓ (parent 통합 PR) | — | →`In Progress`(승인), →`Done` |

## 흐름 요약

```
사용자 → 오케스트레이터: 자유 텍스트 요청
오케스트레이터: parent 태스크 (In Design) + sub-태스크 draft (목표·배경·DoD만)
오케스트레이터 → 사용자: "분해안 검토 요청"                                ← 게이트 1
사용자: 명시 승인
오케스트레이터:
  1) main에서 feat/<parent-id>-<slug> 분기
  2) parent Status: In Progress
  3) sub-태스크에 핸드오프 기록으로 위임 (sequence/parallel)
작업 에이전트:
  1) parent 브랜치 ← main rebase
  2) feat/<parent-id>/<sub-id>-<slug> 분기
  3) 제안·검증 계획 작성 (태스크 본문 갱신)
  4) sub Status: In Progress → 실행 → 자체검증 → commit → push
  5) PR 생성 (base: parent 브랜치)                                       ← 검증 트리거
검증 에이전트:
  DoD 점검 → approve → PR 머지 → sub Status: Done
  (차단 시 In Progress 환송 / 차단 기록 누적 ≥ 3 시 Blocked + 에스컬레이션)
모든 sub Done → 오케스트레이터:
  1) parent 브랜치 → main PR 생성
  2) parent Status: Review
검증 에이전트: parent 통합 PR 검토 → approve
사용자: parent 통합 PR 머지 → parent Status: Done                          ← 게이트 2
```
