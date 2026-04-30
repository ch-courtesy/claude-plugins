# 에이전트 협업 지침

큰 작업은 단일 에이전트가 한 세션에 처리하지 않습니다. **오케스트레이션 패턴**으로 분해·위임·검증·통합을 명확히 분리하여, 한 에이전트가 끝낸 작업을 다른 에이전트가 이어받을 수 있게 합니다.

## 세 가지 역할

세 역할은 **권한이 분리**됩니다 — 같은 에이전트 인스턴스가 둘 이상의 역할을 겸하지 않습니다.

### 오케스트레이터 에이전트

큰 작업의 계획·분해·위임·통합을 담당합니다.

- **하는 것**: parent issue 작성(목표·배경·DoD), 분해(기능 의존성 기준), sub-issue draft, parent branch 분기, sub-issue 위임, parent 통합 PR 생성, parent Status 전이(`In Progress`/`Review`).
- **안 하는 것**: 코드 직접 수정(`Edit`/`Write` 금지), 검증 수행, 사용자 승인 없는 분해 위임, parent를 `Done`으로 전이.

### 작업 에이전트

위임받은 1 sub-issue를 한 세션에 끝냅니다.

- **하는 것**: 받은 sub-issue의 제안·검증 계획 작성, parent branch ← main rebase, sub branch 분기, 코드 변경(자기 sub 범위), 자체 검증, commit·push, PR 생성(base: parent branch).
- **안 하는 것**: 자기 sub 범위 밖 변경, parent issue 수정, force-push, 자체 PR 머지, 분해 결정(받은 sub가 너무 크면 `[blocked]` 환송).

### 검증 에이전트

작업 에이전트의 결과물을 독립 검증하고, 통과 시 sub-issue PR을 머지합니다.

- **하는 것**: DoD 점검, inline review, approve 또는 차단, sub-issue PR `gh pr merge`, sub-issue Status 전이(`Done` 또는 `In Progress` 환송).
- **안 하는 것**: 코드 변경(오타·import 누락·lint 자동수정도 금지 — 모두 환송), parent 통합 PR 머지, 모든 sub Done이 아닌 상태에서의 통합.

## 검증 에이전트 구현 모드 (프로젝트별 명시 필수)

다음 중 **하나를 프로젝트 시작 시 명시**해야 합니다. default 없음. 모드는 프로젝트 단위로만 전환하며 PR 단위 override는 허용하지 않습니다.

| | Mode A: claude-code-action | Mode B: 로컬 서브에이전트 |
|---|---|---|
| 트리거 | PR open/synchronize 이벤트 (자동) | 작업 에이전트의 `Task` 호출 또는 stop hook |
| 셋업 | workflow YAML + Anthropic API key secret | 별도 셋업 없음 |
| 격리 | CI runner | 로컬 (worktree 권장) |
| 적합 | 팀 협업, PR 이벤트 자동화 | 솔로 개발, 빠른 iteration |

검증 에이전트의 책임은 모드와 무관하게 동일합니다. 모드는 **누가 언제 트리거하는가**만 다릅니다.

## issue body 섹션 책임

| 섹션 | 책임 | 작성 시점 |
|---|---|---|
| 목표 | 오케스트레이터 | parent·sub 생성 시 |
| 배경 | 오케스트레이터 | parent·sub 생성 시 |
| 제안 | 작업 에이전트 | sub-issue 받은 직후 |
| 검증 계획 | 작업 에이전트 | sub-issue 받은 직후 |
| 완료 기준(DoD) | 오케스트레이터 | parent·sub 생성 시 |

오케스트레이터가 정의하는 것은 "What/Done", 작업 에이전트가 채우는 것은 "How". 검증 에이전트는 **DoD를 1차 기준**으로 보고 검증 계획은 참고 자료로 사용합니다(self-referential 회피).

## 분해 원칙

- **기준 = 기능 의존성**(semantic). A의 산출물이 B의 입력이면 sequence, 기능적 독립이면 parallel. 파일 집합 겹침은 결정 기준이 **아닙니다** — 머지 충돌은 두 번째 머저(작업 에이전트)가 rebase로 해결합니다.
- **트리 깊이 2 고정**: `parent → sub-issue`. `sub-sub-issue` 금지. 더 깊이 필요해 보이면 깊이를 늘리지 말고 **parent 자체를 더 좁게 다시 정의**(가로로 풀기).
- **분해 권한은 오케스트레이터 단독**: 작업 에이전트가 받은 sub가 너무 크다고 판단하면 분해하지 않고 `[blocked]` comment로 환송합니다. 오케스트레이터가 재분해 또는 parent 재정의 → 사용자 재승인 → 재위임.

## 브랜치 구조

```
main
 └ feat/<parent#>-<slug>                 ← parent 통합 브랜치
    ├ feat/<parent#>/<sub#>-<sub-slug>   ← sub-issue 브랜치
    ├ feat/<parent#>/<sub#>-<sub-slug>
    └ ...
```

| 패턴 | 의미 |
|---|---|
| `feat/<#>-<slug>` | parent 통합 브랜치 |
| `feat/<parent#>/<sub#>-<slug>` | sub-issue 브랜치 (parent# path 하위) |

필터링:

| 목적 | glob |
|---|---|
| 모든 작업 브랜치 | `feat/*` |
| 특정 parent의 sub만 | `feat/<parent#>/*` |
| 모든 sub만 (parent 제외) | `feat/*/*` |
| parent만 (sub 제외) | `feat/*-*` |

parent branch에는 항상 slug가 붙기 때문에(`<#>-<slug>` 형태) `feat/<#>-<slug>` ref와 `feat/<#>/...` directory는 git refs namespace에서 충돌하지 않습니다.

### main 동기화

작업 에이전트는 sub-issue 시작 전 parent branch를 main 기준으로 rebase합니다. 작은 충돌을 자주 해소해 통합 시점에 폭발하지 않게 합니다. 그래도 parent 통합 PR 시점에 충돌이 남으면 작업 에이전트(대표)에게 환송합니다.

## 머지 경로

| PR | base | 검증 | 머지 |
|---|---|---|---|
| sub-issue PR | parent branch | 검증 에이전트 | **검증 에이전트** (자동머지 예외) |
| parent 통합 PR | `main` | 검증 에이전트 | **사용자** (게이트 2) |

검증 에이전트의 sub-issue PR 머지는 일반적인 자동머지 금지 규칙의 **명시된 예외**입니다. parent 통합 PR과 그 외 일반 작업 PR은 여전히 사용자 명시 지시 필요.

## 두 사용자 게이트

| 게이트 | 시점 | 사용자가 보는 것 |
|---|---|---|
| 게이트 1 | parent `In Design → In Progress` 직전 | 목표·배경·DoD·분해 구조 (제안·검증 계획은 비어 있음) |
| 게이트 2 | parent 통합 PR 머지 시점 | 통합 결과·DoD 충족 여부 |

게이트 1에서 제안·검증 계획이 비어 있는 것은 의도된 설계입니다 — 그 두 섹션은 작업 에이전트의 영역이며, 게이트 1은 "What/Done과 분해 자체"가 적절한지만 확인합니다.

## 차단·재시도

- 검증 에이전트가 차단을 결정하면 sub-issue Status를 `In Progress`로 환송하고 `[blocked]` prefix comment에 사유를 기록합니다.
- 같은 sub-issue의 **`[blocked]` comment 누적 ≥ 3**이면 자동으로 `Blocked` Status로 전이하고 parent issue에 에스컬레이션 comment를 남깁니다. 사용자가 분해 재조정 또는 직접 개입.
- 차단 카운트는 sub-issue comments에서 `[blocked]` prefix 수를 세서 결정합니다 — 워크플로우는 stateless이므로 카운트를 issue에 영속화합니다.

## 권한 매트릭스

|  | Edit/Write | branch 생성 | rebase | pr review | pr merge | sub Status | parent Status |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 오케스트레이터 | ✗ | parent branch, parent 통합 PR | ✗ | ✗ | ✗ | ✗ | →`In Progress`(승인 후), →`Review` |
| 작업 에이전트 | ✓ (자기 sub) | sub branch | parent ← main | ✗ | ✗ | →`In Progress`, →`Review` | ✗ |
| 검증 에이전트 | ✗ | ✗ | ✗ | ✓ | ✓ (sub PR 한정) | →`In Progress`(환송), →`Done` | ✗ |
| 사용자 | — | — | — | — | ✓ (parent 통합 PR) | — | →`In Progress`(승인), →`Done` |

## 흐름 요약

```
사용자 → 오케스트레이터: 자유 텍스트 요청
오케스트레이터: parent issue (In Design) + sub-issue draft (목표·배경·DoD만)
오케스트레이터 → 사용자: "분해안 검토 요청"                                ← 게이트 1
사용자: 명시 승인
오케스트레이터:
  1) main에서 feat/<parent#>-<slug> 분기
  2) parent Status: In Progress
  3) sub-issue [handoff] 위임 (sequence/parallel)
작업 에이전트:
  1) parent branch ← main rebase
  2) feat/<parent#>/<sub#>-<slug> 분기
  3) 제안·검증 계획 작성 (issue body 갱신)
  4) sub Status: In Progress → 실행 → 자체검증 → commit → push
  5) PR 생성 (base: parent branch)                                       ← 검증 트리거
검증 에이전트:
  DoD 점검 → approve → gh pr merge → sub Status: Done
  (차단 시 In Progress 환송 / [blocked] ≥ 3 시 Blocked + 에스컬레이션)
모든 sub Done → 오케스트레이터:
  1) parent branch → main PR 생성
  2) parent Status: Review
검증 에이전트: parent 통합 PR 검토 → approve
사용자: parent 통합 PR 머지 → parent Status: Done                          ← 게이트 2
```

## context.md와의 관계

이 문서는 컨텍스트 관리 지침(`rules/context.md`)에서 정의한 issue·comment·Status 메커니즘을 **전제**로 합니다. 핸드오프(`[handoff]`), 결정(`[decision]`), 차단(`[blocked]`), 검증(`[verification]`) prefix 컨벤션은 모두 context.md를 따릅니다. 이 문서는 그 위에 **분해·역할·게이트** 층을 더합니다.

context.md의 일반 깊이 권장(2~3)보다 오케스트레이션 흐름은 더 엄격하여 깊이 2 고정입니다.
