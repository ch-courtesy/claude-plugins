# Changelog

이 저장소의 **사용자 가시(behavior-changing) 변경**을 기록합니다. 버전의 단일 출처(SoT)는 각 플러그인의 `plugin.json`이며(`rules/engineering/versioning.md`), 본 파일은 변경이 머지될 때마다 누적합니다. 분류: 새 기능 / 변경(호환) / 변경(깨짐) / 버그 수정 / 보안.

## autopilot 0.56.1

### 버그 수정
- **forge review-loop 의 rework 가 detached 구현 워크트리에서도 feat 브랜치를 대상으로 동작 + 재구현 실패 escalate 에 유발 finding 표면화 (갭 X+Z)** — `rl_implement_loop` 이 종전에는 `git worktree list` 에서 **feat 브랜치가 체크아웃된 워크트리만** 찾았는데, 구현 워크트리는 `worktree add --detach` 로 만들어져 어떤 로컬 브랜치에도 체크아웃돼 있지 않아 매치 0 → 항상 실패 → escalate 했다(리뷰 finding 이 있어도 rework 가 진행되지 못함). 이제 feat 브랜치 체크아웃 워크트리를 못 찾으면 **feat 브랜치(로컬 ref)가 존재하는지 확인 후** 그 브랜치를 체크아웃한 전용 임시 워크트리를 만들어 그 안에서 loop 를 secondary 모드로 수행한다(끝나면 정리). ref 가 없으면 거짓 성공 대신 비-0(에스컬레이션)으로 엉뚱한 체크아웃 push 금지 불변식을 보존한다. 또한 재구현 실패로 escalate 할 때 reason 에 **rework 를 유발한 PR 인라인 finding(must) 요약**을 포함해, 오케스트레이터가 'false escalation' 으로 오진해 정당한 차단을 수동 머지로 덮는 일을 막는다. 회귀 가드(review-loop selftest)가 (a) detached 워크트리에서 feat 브랜치 확보 후 rework 수행, (b) feat ref 부재 시 비-0, (c) escalate reason 에 유발 finding 포함을 단언한다.

## autopilot 0.56.0

### 버그 수정
- **loop 워크트리 base 를 로컬 체크아웃 HEAD 가 아닌 origin/<default-branch> 기준으로 (stale base 방지)** — `loop.sh` 가 워크트리를 만들 때 부모 체크아웃의 `HEAD` 를 그대로 base 로 잡던 것을, caller 가 주입한 base ref(기본값 = fetch 한 `origin/<default-branch>` tip)로 시작하도록 고쳤다. 공유 체크아웃이 origin 보다 뒤처져 있어도 워커가 stale 트리에서 작업하지 않아, 직전 머지가 이동·삭제한 파일을 옛 위치로 보고 SPEC scope(현재 경로)와 어긋나던 wrong-layout 편집·중간 rebase 충돌과 수동-ff 운영 부담을 제거한다. caller 는 `--base-ref REF`(CLI) 또는 `AUTOPILOT_BASE_REF`(env)로 base 를 override 할 수 있다(미지정 시 origin 기본). origin 미가용(fetch 실패, airgap)이면 종전대로 로컬 HEAD 로 fallback 하되 경고 로그를 남겨 가시화한다. BASE_SHA(게이트 diff 기준)도 base SHA 로 박제돼 scope·oscillation 게이트가 origin tip 기준으로 정합된다. 회귀 가드(`tests/test-loop-base-ref.sh`)가 (a) stale 로컬→origin tip, (b) 주입 ref 사용, (c) fetch 실패 fallback+경고를 단언한다.

## autopilot 0.55.0

### 변경(호환)
- **자가개선 blocked-수집을 `using-autopilot`로 승격(always-on, 단일 소유자) + 카테고리→행동 매핑·재귀 상한** — blocked 신호를 자가-진단·수정 등록으로 잇는 자가개선 수집이 실행 경로(단일 `execute-task` / 무인 `workflow-task` 드레인)와 무관하게 **항상 발동**하도록 통합했다. 종전에는 `using-autopilot`엔 always-on 가이던스만, `workflow-task`엔 operational이나 드레인-전용으로 이원화돼 **단일 `execute-task`에서 막힌 태스크는 자동 자가-수정이 안 됐다**. 이제 `using-autopilot` 「자가개선 정책」이 (a) 카테고리 enum, (b) 카테고리→행동 매핑(`spec-gap`→해당 SPEC scope 보정 / `tool-defect`→`fix`로 새 수정 스펙 등록 / `ops`→운영 정리), (c) 재귀 상한을 **단일 정의**한다. `execute-task`·`workflow-task`는 blocked의 `category`를 **표면화만** 하고, 그 category를 읽은 오케스트레이팅 세션이 양 경로에서 동일 정책대로 행동한다(코드 강제가 아니라 가이던스). 자가개선이 생성한 fix 태스크 본문에는 `자가개선-비활성` 마커를 부여하고, 단일·드레인 양 경로가 이를 존중해 그 태스크가 다시 blocked돼도 추가 자가개선을 트리거하지 않는다(**depth-1 재귀 상한**). 회귀 가드(`tests/autopilot/test-self-improvement-policy.sh`)가 단일 경로 category 표면화·카테고리 매핑 명문화·비활성 플래그 존중의 정적 존재를 단언한다.

## autopilot 0.54.0

### 변경(호환)
- **작성 스킬(feature·fix)이 DoD-요구 회귀 테스트 경로를 scope.include에 포함하도록 방법론 보강** — feature·fix 양쪽 `task-body-template.md`(작성 규칙)와 `self-review.md`(축6 scope.include 점검)에 "완료 조건이 회귀 가드 테스트 추가/수정을 요구하면 그 테스트 파일·디렉터리 경로를 `scope.include` 에 포함한다"는 규칙·점검을 추가했다. loop scope 게이트(`diff_vs_scope`)는 scope 밖 파일 작성을 halt 하므로, 작성된 SPEC 이 회귀 테스트 경로를 scope 밖에 두면 헌법 Iron Law(production 전 RED 테스트)와 맞물려 TDD 를 시작도 못 하고 구조적으로 blocked(`spec-gap`)됐다. 작성 단계에서 scope 를 DoD 와 정합시켜 이 spurious blocked 를 근본 제거한다. 더불어 `plugins/` 변경 SPEC 은 `plugin.json`·`CHANGELOG.md` 도 scope 에 넣길 권장하는 한 줄을 덧붙였다(강제 아님). 두 회귀 가드 테스트(`test-feature-skill.sh` S10·S11, `test-fix-skill.sh` S10·S10b)가 규칙·점검의 존재를 단언한다.

## autopilot 0.53.0

### 변경(깨짐)
- **forge 머지 엔진에서 프로젝트-소유 버전 범프 게이트 제거(정책-불간섭)** — 머지 엔진(`forge/lib/merge.sh`)이 plugins/ 변경 시 `plugin.json` 버전 범프를 단언하던 게이트(`mg_version_gate`와 보조 함수군·`WATCH_DIRS`·`version-gate` 서브커맨드·`blocked: version-bump` 종착)와, 그 게이트를 충족시키려 존재하던 통합 엔진(`forge/lib/integration.sh`)의 병렬 동일-버전 자동 재범프(`in_ensure_version_ahead`)·버전-전용 충돌 결정적 해소(`in_conflict_version_only`·`in_resolve_version_conflict`·`in_reapply_bump`)를 제거했다. 버전 범프는 컨슈밍 프로젝트 소유 정책(`rules/engineering/versioning.md`)이므로 범용 플러그인이 이를 집행하는 것은 계층 역전이며, 게이트 구현이 `plugin.json`·`plugins/`를 하드코딩해 다른 형태(`package.json`·`pyproject.toml`)의 프로젝트에서 오작동하는 비이식성 결함이었다. 이제 머지 경로는 정책-중립 게이트(PR 존재·승인·ff-only)만 유지하고 버전 정책에 간섭하지 않는다. `plugin.json` 충돌은 일반 rebase 충돌 전략으로 귀결된다. 버전 강제가 필요하면 컨슈밍 프로젝트가 자기 CI로 도입한다(플러그인은 강제하지 않음).

## autopilot 0.52.0

### 변경(깨짐)
- **구 파이프라인 스킬 `spec`·`repair`·`dispatch` 제거** — 신 파이프라인(`feature`/`fix`→`create-task`→`execute-task`/`workflow-task`)이 구 파이프라인을 기능적으로 대체 완료(진입 스킬 `using-autopilot`는 이미 `feature`/`fix`로 라우팅)함에 따라 세 스킬을 제거했다. 단순 삭제는 런타임을 연쇄로 깨뜨리므로(생존 스킬이 이들 내부의 공유 리소스를 참조), 삭제에 앞서 공유 리소스를 중립 위치로 이전했다: 통합/리뷰/머지 엔진(`integration.sh`·`merge.sh`·`review-loop.sh`·`lib-integration.sh`)을 `skills/dispatch/references/` → `forge/lib/`로(forge·execute-task·workflow-task가 forge 경유로 재사용), 적대 렌즈 페르소나 카탈로그(`personas.md`)를 `skills/spec/references/` → `plugins/autopilot/references/`로(loop·review가 단일 출처로 참조). `forge.sh` 앵커(`FG_REF`)와 loop·review의 모든 런타임/테스트 경로를 새 위치로 갱신했다. 매니페스트(`plugin.json`·`marketplace.json`) description을 생존 스킬 구성으로 재서술했다. 재사용 엔진의 동작·계약은 불변(이전만 수행).

## project-init 0.22.0

### 변경(깨짐)
- **`context-rule-creator` 스킬 제거** — 컨텍스트 카테고리(`rules/context/task-model.md`·`task-ops.md`)를 생성하던 `project-init:context-rule-creator` 생성기를 제거했다. bootstrap·매니페스트·hooks·테스트는 `*-rule-creator/` 동적 스캔 방식이라 코드 수정 없이 카테고리 목록에서 자동으로 빠진다. 끊긴 참조 정리로 형제 스킬 2곳(`engineering-rule-creator`·`review-rule-creator`)의 비유 설명문을 비유 대상 없이 직접 기술하도록 재서술하고, codex 매니페스트의 `longDescription`·`defaultPrompt`에서 context-rule 언급을 제거했다.

## autopilot 0.51.5

### 버그 수정
- **태스크-백엔드 materialize 가 frontmatter-first 가 아니라 모든 변경이 scope halt 되던 문제 수정** — loop scope 게이트(`read_scope_yaml`/`diff_vs_scope`)는 SPEC.md 1번째 줄이 `---`인 frontmatter-first 를 가정하나, 태스크-백엔드 계열 `be_materialize`(filesystem·github)는 `# <title>` 을 1번째 줄에 prepend 해 `scope.include` 가 비고 → `diff_vs_scope` 가 변경된 모든 파일을 "전부 위반"으로 halt 시켰다. 또 filesystem `fs_body` 가 본문의 모든 `^---$` 를 frontmatter 구분자로 소비해, 본문이 자체 scope frontmatter 를 담아도 `set_body`↔`get_body`·materialize 왕복에서 그 `---` 가 소실됐다. 이제 `fs_body` 는 처음 2개 `---` 만 구분자로 쓰고 이후 본문의 `---` 를 보존하며, materialize 는 공통 헬퍼(`tb_emit_spec`)로 제목을 prepend 하지 않고 본문 frontmatter 블록 **뒤에** `# <title>` 을 주입한다 → 결과 SPEC.md 는 frontmatter-first(게이트 동작) + 제목 포함 + 본문 제목 중복 없음. frontmatter 없는 구형 본문은 폴백(`# title` prepend)으로 처리한다.

### 새 기능
- **feature·fix 산출물을 구 spec 스킬과 내용 동등한 frontmatter-first 스펙 문서로 통일** — feature·fix `task-body-template` 이 scope/ears frontmatter + 스펙 섹션(무엇을 만들 것인가/목적/완료 조건(EARS)/범위/검증/제약/위험) 구조가 됐다(fix 는 진단 섹션을 목적 다음에 유지). `# 제목` H1·`depends_on` 은 본문에 두지 않고 백엔드가 단일 저장한다(중복 회피). 완료 조건 5문장 패턴은 feature·fix 각자의 `ears-patterns.md` 자체 사본으로 두어 spec 스킬을 참조하지 않는다(플러그인 자기완결). 두 스킬의 유일한 차이는 내용을 채우는 방법(feature=대화형 인터뷰, fix=무인 정적분석)이며 산출물 구조·규약은 동일하다.

## autopilot 0.51.4

### 버그 수정
- **병렬 동일-버전 범프 시 충돌 미발생으로 재범프 안 돼 버전게이트 blocked 수정** — 두 태스크를 병렬 실행하며 둘 다 `plugin.json`을 **같은 버전**으로 범프하면, 먼저 머지된 쪽이 베이스를 그 버전으로 올려 늦은 쪽이 base와 **동률**이 되고, 머지 버전게이트가 "plugins/ 를 건드리지만 plugin.json 버전이 오르지 않았습니다"로 blocked되어 **수동 재범프**가 필요했다(#461·#462). 기존 충돌 기반 재적용(`in_resolve_version_conflict`)은 rebase 충돌 발생을 전제하는데, 동일-버전 범프는 version 변경이 이미 동일해 **git 충돌이 없어** 발동하지 않았고, 동률 매니페스트는 base와 완전히 동일해 변경 diff에도 잡히지 않았다. 이제 `integration.sh` DONE 통합 경로가 base sync·push 후 `in_ensure_version_ahead`로, 브랜치가 **워치 디렉토리에서 건드린 플러그인 루트의 매니페스트**(diff가 아니라 `ls-tree`로 발견)가 base보다 앞서지 않으면(`<=`) 새 베이스보다 한 단계 앞서게 **재범프 commit을 append**(history 재작성 아님 → 기존 원격 브랜치/PR이 있어도 **ff-safe**, force 금지)하고 원격 작업 브랜치로 직접 push한다. 격리는 #452와 동일하게 전용 분리(detached) 워크트리에서 수행해 공유 체크아웃을 건드리지 않는다. 버전이 이미 앞서면 **no-op**(불변)이며, 충돌 기반 재적용 경로는 그대로 보존된다.

## autopilot 0.51.3

### 버그 수정
- **forge integrate 재실행 시 stale 원격 브랜치/PR 로 인한 non-ff push 실패 수정** — 직전에 실패·blocked 된 태스크를 재실행하면, 1차 시도가 남긴 **stale 원격 작업 브랜치 + 열린 PR** 위로 새 커밋을 push 하려다 `non-fast-forward` 로 거부되어("integration: push 실패(force 금지)") 통합이 막혔다(수동으로 원격 브랜치 삭제 + PR close 필요). 이제 `integration.sh` 의 DONE 통합 경로가 push 전에 stale 잔여를 점검해, 원격 작업 브랜치가 현재 로컬 작업 커밋과 **non-ff 비호환**이고 **현재 실행 소유**(① 결정적 작업 브랜치명 `feat/<rid>-<slug>` 원격 존재 + ② 그 위 열린 PR 이 신뢰 봇(App bot) 작성이며 `*-formal-review` 마커 보유)로 식별되면 PR close + 원격 브랜치 삭제로 정리한 뒤 진행한다. **force 금지 유지**(브랜치 삭제는 history 재작성이 아님). 두 소유 신호가 모두 충족될 때만 정리하고, ff 호환이거나 외부 소유 동명 브랜치는 **건드리지 않는다**(오삭제 방지).

## autopilot 0.51.1

### 버그 수정
- **loop 워커에 rules 인덱스 자체 주입 — versioning 등 카테고리 지침 비일관 적용 수정** — loop 구현 워커는 `claude --print`(일회성)로 실행되어 SessionStart 훅(project-init의 `rules-index.sh`)이 돌지 않아, 소비 프로젝트의 `<project-rules-index>`(예: `plugins/` 변경 시 `plugin.json` 버전 범프 지침)가 워커에 닿지 않았다. 그 결과 versioning 적용이 비결정적이어서 통합 버전게이트 blocked가 산발했다(#463, #450 잔여). 이제 `loop.sh`가 직접 워크트리 `rules/`를 훑어 동일한 `<project-rules-index>` 블록(경로 + 첫 H1 한 줄 목적)을 생성해 병합 워커 지침(CLAUDE.md/AGENTS.md)에 인라인한다. **project-init 무의존**(크로스플러그인 헬퍼 없이 autopilot 내부 소유)이며 `rules/`가 없으면 **no-op**(블록 없음·에러 없음) — 플러그인 자기완결 유지.

## autopilot 0.51.0

### 새 기능
- **정적분석 버그 작성자 `fix` 스킬 신설** — `feature`(대화형 인터뷰 작성자)의 정적분석 짝으로, 버그·증상·실패 신호에서 코드·로그를 **읽고 추론**해 무인으로 근본 원인을 가설로 좁혀 태스크 본문(진단 섹션 포함)을 뜨고 등록 프리미티브 `create-task`로 등록을 위임한다(작성만 책임 — write 동사·파일 미생성, 본문=SoT). 진단은 정적 분석으로만 하고(실행·재현·디버거 금지) 근본 원인을 확정이 아닌 가설로 프레이밍하며 증거를 `파일:줄`로 싣고, 모호하면 `[NEEDS CLARIFICATION]` 마커를 남긴다. 완성→`backlog` / 미해결→`in_design`(create-task 소유 전이), 미해결분은 `feature` 인터뷰 재개로 완성한다. 플러그인 자기완결(진단·작성 방법론을 `references/`에 자체 소유 — spec·repair·`rules/` doc-link 없음). SPEC-파일 계열 `repair`는 개명·경계 개정 없이 그대로 보존된다(fix는 그 진단 방법론을 참고하되 별도 스킬). **호출** — `Skill(skill="fix", args="<버그/증상/실패 신호>")`.
- **workflow-task 드레인자 중앙 fix 호출** — 무인 자율 주행 1패스 드레인 중 워커(`execute-task`)가 `blocked`로 떨어진 버그·실패 신호를 드레인자가 중앙에서 수거해 `fix`를 자율 맥락으로 호출하고, 등록된 수정 태스크는 `backlog`에 들어가 **다음 틱 드레인에 흡수**된다(틱 기반 의존 해결 활용). 드레인 요약 JSON에 `failed_ids`(이번 패스 blocked 태스크 id 배열)를 추가해 이 수거의 입력으로 노출한다. 순수 헤드리스(cron→`.sh`) 경로는 `failed_ids`만 노출하고 수거는 스킬 주재 호출에서 수행한다.

## autopilot 0.50.2

### 새 기능
- **feature 인터뷰 재개(resume) 모드** — 이미 등록된 `in_design`(미해결 항목 잔존) 태스크의 본문을 인터뷰로 이어서 완성하고, 완료 시 create-task(등록 프리미티브)의 본문 갱신(set_body)으로 `backlog`로 전이한다. 대화형(자율 분석 아님).

## autopilot 0.50.1

### 버그 수정
- **forge integrate 가 공유 체크아웃을 오염시키던 문제 수정** — `in_base_sync` 가 작업 브랜치를 공유 체크아웃에서 `git checkout`·rebase 한 뒤 복원하지 않아, execute-task 실행마다 저장소 메인 워킹디렉토리가 `feat/<id>` 브랜치로 남고 수동 복구가 필요했다(병렬 실행 시 서로의 브랜치를 덮어쓰는 경쟁). 이제 **전용 분리(detached) 임시 워크트리**를 만들어 그 안에서 rebase 를 수행하고 끝나면 제거한다 — 공유 체크아웃을 전혀 건드리지 않으므로 **병렬에서도 안전**하고, 같은 브랜치가 이미 다른 곳에 체크아웃돼 있어도(`--detach`) 실패하지 않는다.

## autopilot 0.50.0

### 새 기능
- **작성/등록 분리 — 인터뷰 작성자 `feature` 스킬 신설, `create-task`를 등록 프리미티브로 정립** — 기존 `create-task`가 명확화 인터뷰 작성 + 등록을 함께 수행해 작성 로직이 스킬마다 흩어지던 문제를 풀었다. 인터뷰 작성부를 새 **`feature`** 스킬로 분리(경량 참조 4종 `clarification`/`decomposition-gate`/`self-review`/`task-body-template`을 `feature`로 이동)해, `feature`가 인터뷰로 태스크 본문(=SPEC)을 떠서 `create-task`로 등록을 위임한다. **`create-task`는 등록 프리미티브**로 정립 — 외부 작성자(`feature`·향후 `fix`)가 만든 본문을 받아 등록하고 등록-후 상태 전이(완성→backlog / 미해결 잔존→in_design)를 소유하며, 본문 갱신은 `set_body`(0.49.0 신설)에 위임한다(인터뷰·작성 로직 미보유). `using-autopilot`은 **기능 의도를 `feature`로 라우팅**하고, 버그·증상·실패는 전용 작성자(`fix`)가 생기기 전까지 **현행대로 `create-task`로** 보낸다(미존재 스킬로 라우팅하지 않음). 파일 산출 없음(백엔드 본문=SoT). spec 스킬은 불변.

## autopilot 0.49.0

### 새 기능
- **task-backend에 `set_body` 동사 신설 — 기존 태스크 본문(=SPEC) 갱신 수단** — 어댑터에 본문 쓰기 프리미티브가 없어(`get_body` 읽기 전용) 이미 등록된 in_design 태스크의 SPEC을 갱신할 수 없던 공백을 메웠다. `set_body --task-id <id> --body <s>` → `{"task_id"}` 를 contract.md 동사표에 `get_body`의 쓰기 짝으로 추가하고 3개 백엔드(filesystem/github-project/beads)에 구현했다. 본문만 교체하고 status·frontmatter·`depends_on` 등 메타는 보존한다(filesystem: frontmatter 뒤 본문 영역만 교체; github: 이슈 본문 교체하되 라벨=status·전용 코멘트 lease는 본문과 독립이라 보존하고 `depends_on` 마커는 재부착; beads: `bd update --description`로 status·`bd dep`와 무관하게 본문만). 작성/등록 분리(#445)·인터뷰 재개(#443)의 본문 갱신 의존성을 푼다.

## autopilot 0.48.12

### 버그 수정
- **loop 워커가 프로젝트 지침을 잃던 문제 수정** — `loop`이 워크트리의 `CLAUDE.md`/`AGENTS.md`를 플러그인 `constitution.md`로 덮어써, 워커가 소비 프로젝트의 벤더 지침(`rules/` 인덱스 → versioning 등)을 보지 못했다. 이제 워크트리의 원본 프로젝트 지침을 보존하고 그 뒤에 `constitution`을 병합해, 워커가 프로젝트 지침(예: `plugins/` 변경 시 `plugin.json` 버전 범프)과 loop 헌법을 모두 받는다. 플러그인은 특정 프로젝트 규칙을 하드코딩하지 않는다.

## project-init 0.21.0

### 새 기능
- **Codex 완전 동등성 확장** — 저장소 Codex marketplace를 추가하고 기존 plugin-bundled SessionStart hook을 Claude/Codex가 함께 사용하며, 두 런타임이 같은 공유 스킬·템플릿·rules index 구현을 사용하도록 런타임별 차이를 얇은 어댑터로 격리했다.

### 변경(호환)
- **런타임 중립 질문 계약** — 공통 스킬 절차 본문에서 직접 런타임 도구명 의존을 제거하고, 구조화 질문 기능이 없는 표면에서는 동일 선택지를 간결한 직접 질문으로 제시하되 스킬별 명시적 누락 응답 계약은 보존하도록 명시했다.

## autopilot 0.48.10

### 버그 수정
- **자동 생성 PR 본문의 로컬 임시 SPEC 경로 누출·dispatch 오표기 제거** — `integration.sh` 의 공용 `in_pr_body`(dispatch·execute-task 공유)가 execute-task 실행에서 (1) `SPEC:` 줄에 `.task-work/<id>/SPEC.md` 같은 **로컬 절대·임시 materialize 경로**를 박아 리뷰어 환경에 없는 경로로 워커 파일시스템 레이아웃을 누출하던 것과, (2) 실제 실행 주체가 execute-task인데도 본문을 "**dispatch** 가 자동 생성"·"**dispatch-run**"으로 **오표기**하던 결함을 고쳤다. 이제 originator를 spec 경로의 임시 materialize 마커(`.task-work/`)로 판정해 execute-task 경로에서는 임시 SPEC 경로를 박지 않고(생략) 주체를 정확히 표기(`execute-task 가 자동 생성`)하며 추적성은 `task-run`·이슈 참조(`Refs #n`)로 표현한다. 리뷰 트리거 마커(제목 `🤖 [자동 리뷰]`, 본문 "자동 적대 리뷰" 식별 줄, `Refs #n`)는 보존되고, dispatch 경로의 기존 본문 표현(`SPEC:`·`dispatch-run:`)은 회귀 없이 그대로다.

## autopilot 0.48.9

### 새 기능
- **using-autopilot에 자가개선 트리거 추가 — task 스킬 비정상 동작을 create-task 수정 스펙으로 라우팅** — `using-autopilot` 스킬이 기존 "새 코드 변경 신호 → create-task" 라우팅에 더해, **autopilot 자기 도구의 비정상 동작**을 새 신호 유형으로 같은 진입점(`create-task`)에 라우팅한다. task 스킬(`create-task`/`execute-task`/`workflow-task` 및 그 엔진 loop·forge·merge·review) 사용 중 잘못된/근거 약한 `blocked`, 오지 않을 상태 무의미 대기, 모순된 상태 전이, 예기치 못한 실패·오보고 등을 관찰하면, 단순 우회·수동 처리로 끝내지 말고 **자가개선 판단을 시작**한다: (1) 적대적 진단으로 실제 결함인지 판정(가능하면 결정적 재현·검증), (2) 실제 결함이면 그 수정을 `create-task`로 자기완결 스펙으로 떠 등록(본문=SPEC), (3) 등록 스펙은 평소 실행 경로(`execute-task`/`workflow-task`)로 처리. 정당한 우회(일회성 환경 이슈·사용자 명시 지시)는 예외이고, 무한 재귀(자기 수정의 자기 수정) 방지를 위해 관찰된 구체적 비정상 1건에 한정한다. 사람이 매번 "버그인지 보고 고쳐라"라고 지시하지 않아도 autopilot이 자기 도구의 결함을 탐지→판단→수정 스펙 등록으로 잇는 자가개선이 지침으로 강제된다. `SKILL.md`(frontmatter description·트리거 절·Red flag 행)와 사람용 `README.md`를 동일 계약으로 동기화했고, 기존 라우팅·예외와 모순 없이 가산되며 플러그인 자기완결·`REQUIRED RUNTIME CONTRACT` 라인은 보존된다.

## autopilot 0.48.8

### 버그 수정
- **create-task 백엔드 config 영속화의 direct(로컬) 경로가 사용자 staged 변경을 무단 삭제하지 않음** — `persist-backend-config.sh`의 origin 없는 direct 경로는 config-only 머지로 `<base>`를 전진시킨 뒤, 현재 체크아웃이 `<base>`이면 인덱스를 새 HEAD에 동기화하려고 `git read-tree "$MERGE"`(단일 트리 인자)를 호출했는데, 이 명령은 **인덱스를 통째로 그 트리로 교체**하므로 호출 시점에 사용자가 `git add`로 stage 해둔 변경이 **조용히·비가역적으로 사라지던** 결함을 고친다(스크립트 헤더의 "워킹트리·스테이징 비파괴" 계약 위반). 시나리오는 드물지만(origin 없는 로컬 repo + `<base>` 체크아웃 + staged 변경 보유 + 그 시점 헬퍼 실행) silent data loss이므로 수정한다. 머지는 config-only 이므로 이제 인덱스의 **config 항목만** `git update-index --add --cacheinfo`로 새 HEAD에 동기화하고, 다른 staged 변경과 워킹트리 파일은 그대로 보존한다. config 커밋 자체는 기존대로 plumbing(commit-tree)로 만들어 워킹트리·스테이징을 건드리지 않으며, origin 있는(PR) 경로·멱등성·config-only 보장 등 기존 동작은 불변이다.

## autopilot 0.48.7

### 버그 수정
- **신뢰봇 승인 마커 정규식을 `login` 필드 단독에 적용 — `[bot]`·`github-actions` 계열 봇 영영 미매치 결함 수정** — PR 승인 경로 b(강등 승인 마커) 매칭이 신뢰봇 로그인 정규식 `REVIEW_BOT_LOGINS_RE`(기본 `(\[bot\]$|^github-actions$|courtesy-bot)`)을 `login\t본문` **결합 한 줄**에 grep 해, 앵커 패턴 `\[bot\]$`(줄 끝 `[bot]` 요구)와 `^github-actions$`(줄 전체 일치 요구)가 탭 뒤 본문 때문에 **절대 매치되지 않던** 결함(`courtesy-bot` 같은 비앵커 부분문자열만 우연히 동작)을 고친다. 그 결과 봇 로그인이 `*[bot]`·`github-actions`이고 App 토큰 self-approve 불가로 `verdict=approve` 마커를 COMMENT 형태로 남기는(문서화된 App-token 경로) 환경에서, 공식 `reviewDecision==APPROVED`(경로 a)가 없으면 승인 신호(경로 b)를 영영 감지하지 못해 폴링 상한까지 헛대기 후 잘못 `blocked`로 종착하던 이식성 결함이 사라진다. 이제 `execute-task.sh`(`et_approval_gh`)·`merge.sh`(`mg_approval_gh`)·`review-loop.sh`(`rl_review_fetch_gh`) 세 경로 모두 미해결 `[blocking]` 인라인 게이트(`et_blocking_inline_gh`)와 동일 컨벤션으로, awk 가 현재 head 의 `verdict=approve` 마커를 가진 리뷰의 **login 만** 추출해 그 login 에만 봇 정규식을 적용한다 — 앵커가 실제로 성립한다. 위조 마커 거부(신뢰봇 로그인만 인정)·`head_sha==현재 head`·`verdict=approve` 검사 의미와 승인 경로 a(`reviewDecision==APPROVED`) 동작은 불변이다.

## autopilot 0.48.6

### 버그 수정
- **forge 백엔드(GitHub 등) 가용 시 로컬 머지 금지 — PR 서버사이드 머지로만 통합** — dispatch·execute-task 공용 머지 경로(`merge.sh` `mg_merge_finish`)가 백엔드 가용 여부와 무관하게 항상 로컬 머지(`git checkout <base>`+`merge --ff-only`+`push`)로 통합해, 기본 브랜치가 다른 워크트리(공유 최상위 체크아웃 등)에 점유돼 있으면 `fatal: '<base>' is already checked out at ...` 로 머지가 실패하고 수동 `gh pr merge`(서버사이드)로 우회해야 하던 결함(관측: #423/PR428·#426/PR429)을 고친다. 또한 forge 경로가 PR을 만들어 리뷰까지 받고도 정작 머지는 PR을 통하지 않고 로컬로 main에 직접 push하던 모순을 제거한다. 이제 `mg_merge_finish`가 백엔드 가용 여부로 통합을 라우팅한다: **forge 백엔드 가용(PR 존재)** 이면 호스트의 PR 기반 서버사이드 머지(`pr merge --auto --merge` 예약 → 실패 시 `--merge` 즉시 폴백)로만 통합하고 로컬 `git checkout <base>`/ff push 경로를 **절대 타지 않는다**(따라서 멀티-워크트리 `already checked out` 결함 소멸). **백엔드/origin 미가용(direct)** 은 기존 로컬 ff-only(checkout+ff+push)를 그대로 유지한다. PR 존재·승인(`reviewDecision==APPROVED` + 현재 head 미해결 `[blocking]` 0)·버전 범프 게이트와 직렬화 락·force 미사용은 서버사이드 경로에서도 머지 **전에** 그대로 적용되며, 서버사이드 머지 실패는 조용한 성공이 아니라 `blocked`로 종착한다. 또한 `pr merge --auto`는 머지가 *예약*만 돼도 0을 반환하므로(필수 체크가 나중에 실패하면 실제 머지 안 됨), 발행 성공을 곧 완료로 보지 않고 **실제 PR `state==MERGED`를 폴링 확인**(`MERGE_CONFIRM_WAIT_MAX`/`MERGE_CONFIRM_POLL_INTERVAL`)한 경우에만 `phase=merged`로 전이한다 — 상한 내 미머지면 예약만 된 것으로 보아 `blocked`로 종착(미머지 PR이 done 처리돼 사라지는 것 방지). 폴링은 직렬화 락 밖에서 수행한다. 서버사이드(예약 가능) 경로에선 워커가 원격 작업 브랜치를 직접 삭제하지 않고(예약 머지 취소 방지) 호스트 자동삭제·dispatch sweep에 맡긴다. `forge/contract.md` 머지 계약에 반영.

## autopilot 0.48.5

### 변경(호환)
- **execute-task PR 경로가 review 라운드 반환코드로 분기해 '오지 않을 승인 무의미 대기'를 제거** — 단일 동기 드라이버인 execute-task의 PR(forge) 승인 폴링이 매 반복 `$FORGE_CMD review`를 호출하면서도 그 반환코드를 무시(`|| true`)하고 실제 승인 상태만 봐서, 리워크가 필요한 미해결 `[blocking]` 지적으로 미승인일 때 리워크를 구동하지 못하고 오지 않을 승인을 `APPROVAL_WAIT_MAX`까지 헛되이 폴링하다 timeout→blocked로 끝나던 갭(관측: PR #424)을 메운다. 이제 forge github 어댑터(`fg_review`)가 dispatch `review-loop.sh`의 `round`(=`rl_round`)를 호출해 반환코드(`0`=재작업 재푸시·`10`=에스컬레이션/라운드상한/핑퐁·`20`=대기·`30`=approve)를 그대로 표면화하고, execute-task PR 경로가 이 코드로 분기한다: `30`→머지 진행(merge.sh가 미해결 `[blocking]` 가산 게이트를 머지 직전 재검증), `0`→재푸시 진전이므로 루프 계속(재리뷰), `10`·기타 비-0→리워크로 해소 불가이므로 폴링 상한을 더 기다리지 않고 즉시 `blocked`로 사유와 함께 종료, `20`→깨끗한 코드가 비동기 봇 승인만 기다리는 경우로 기존 `APPROVAL_WAIT_MAX` 폴링 대기 유지. dispatch `review-loop.sh`/`merge.sh`의 계약·동작은 변경 없이 재사용(소비만)하며, direct(PR 없음) 경로는 기존 `run-direct` 동기 리뷰로 불변이다.

## autopilot 0.48.4

### 버그 수정
- **execute-task 승인 게이트가 현재 head 미해결 `[blocking]` 인라인 스레드를 머지 차단 조건으로 포함** — PR(forge) 경로 승인 폴링이 승인을 `reviewDecision==APPROVED`(또는 신뢰봇 `verdict=approve` 마커)만으로 판정해, 봇이 형식 승인과 미해결 `[blocking]` 인라인을 동시에 남기면 머지로 진행되던 갭(PR #420 회귀)을 메운다. 이제 승인 = 호스팅 승인 신호 **AND** 현재 head에 신뢰봇이 남긴 미해결 `[blocking]` 인라인 없음으로, APPROVED여도 미해결 `[blocking]`가 있으면 머지하지 않고 그 스레드가 resolved(또는 head 변경으로 해소)될 때까지 폴링 상한(`APPROVAL_WAIT_MAX`) 내에서 대기하고, 상한까지 미해결이면 `blocked`로 종착한다. blocking 인라인 조회 실패는 보수적(default-deny=대기)으로 처리하되 폴링 상한과 결합돼 영구 멈춤이 없다. 게이트는 스레드를 **스스로 resolve하지 않으며**(자동 해제 없음) 폴링으로 관찰만 한다. 컨벤션(`BLOCKING_TAG`·`isResolved==false`·신뢰봇 로그인·`commit.oid==head`)은 dispatch `merge.sh`/`review-loop.sh`와 동일하며 그 경로 동작은 불변.

## autopilot 0.48.3

### 버그 수정
- **execute-task 승인 폴링의 `APPROVAL_WAIT_MAX`에 숫자 유효성 검증 추가** — PR 경로 승인 폴링 루프는 종료를 `(( waited >= APPROVAL_WAIT_MAX ))`로 판정하는데, 간격(`APPROVAL_POLL_INTERVAL`)과 달리 상한에는 비숫자/빈값 보정이 없어, `APPROVAL_WAIT_MAX`가 비숫자로 override되면 산술 비교가 `0>=0`으로 평가돼 첫 확인 직후 즉시 오종료(또는 빈값 산술 오류 시 무한 멈춤)할 수 있던 결함을 고쳤다. 이제 `APPROVAL_POLL_INTERVAL`과 동일하게 비숫자/빈값을 기본값(360초)으로 보정한다. `0`은 "대기 없이 1회 확인"으로 안전하게 허용한다(상한 0은 영구 멈춤을 유발하지 않음). 승인 판정 로직·폴링 구조는 불변.

## autopilot 0.48.2

### 변경(호환)
- **create-task가 백엔드 선택 SoT(`.autopilot/task-backend.json`)를 메인까지 영속화** — `adapter init`이 백엔드 선택 config를 워크트리에 쓰기만 하고 커밋·머지하지 않아, 파일이 untracked 로컬 상태로 남고 새 체크아웃·CI·다른 세션에서는 "백엔드 미설정"이 되던 갭을 메운다. create-task는 init 직후 전용 헬퍼(`skills/create-task/persist-backend-config.sh`)로 config 파일 **단독**을 담은 최소 변경을 메인에 올린다(origin 있으면 config-only 브랜치 push→PR→저장소 auto-merge 경로, 없으면 로컬 메인 merge). 이미 메인에 동일 내용이 추적되고 있으면 중복 PR/커밋 없이 멱등적으로 건너뛴다. config 커밋은 plumbing으로 만들어 사용자의 더티 워킹트리를 건드리지 않으며, `.autopilot/`는 워치 디렉토리(`plugins/`)가 아니므로 config PR엔 plugin.json 범프를 넣지 않는다. 메인 영속화가 확인된 경우에만 `status:"persisted"`로 보고하고, `gh` 미가용(`pending`)이나 auto-merge 예약 실패(`pr_created`)처럼 메인 머지가 완료되지 않은 경우엔 그 사실을 명확한 status와 non-zero exit로 반환한다(조용한 부분 실패 금지).

## autopilot 0.48.1

### 버그 수정
- **execute-task가 비동기 봇 승인을 기다리지 않고 조기 차단되던 문제 수정** — PR(forge) 경로에서 호스팅 리뷰 봇(GitHub Actions Claude/Codex PR 리뷰, 승인 게시까지 관측 ~2.5분)이 APPROVED를 달기 전에 승인 검사가 끝나 태스크가 잘못 `blocked(not-approved)`로 종착하던 결함을 고쳤다. 이제 execute-task는 머지 전 실제 PR 승인 상태(`reviewDecision==APPROVED` 또는 신뢰 봇의 현재 head `verdict=approve` 마커)를 sleep+폴링으로 상한(`APPROVAL_WAIT_MAX`, 기본 360초; 간격 `APPROVAL_POLL_INTERVAL`, 기본 20초) 내에서 기다리고, 상한까지 미게시일 때만 차단한다. review 라운드의 단순 0 반환을 승인으로 오해하지 않는다. direct(PR 없음) 경로의 기존 동작과 dispatch의 공유 머지 게이트(`merge.sh`)는 변경하지 않는다.

## autopilot 0.48.0

### 새 기능
- **태스크 중심 3-skill family 신설 (create-task/execute-task/workflow-task)** — spec/loop/dispatch를 대체하는 태스크 1급 워크플로. `create-task`는 명확화 인터뷰로 의도를 태스크 본문(목표·배경·제안·검증 계획·완료 기준 = SPEC, 별도 SPEC 파일 없음)으로 떠 선택된 백엔드(filesystem `.tasks/`·github-project Issue/Project·beads `.beads/`)에 등록한다. `execute-task`는 등록된 단일 태스크의 전체 생애(본문 materialize→랄프 루프 구현→origin 호스트별 리뷰·ff-only 머지→done)를 소유하며 heartbeat lease로 크래시 워커를 회수 가능하게 한다. `workflow-task`는 `list_ready`(의존 충족분만)로 준비 태스크를 모아 execute-task를 flow 평면 병렬 fan-out하는 **DAG 없는 1회 드레이너**로, 의존 순서는 백엔드가 틱 간에 해결해 무인 폴링 에이전트가 backlog를 주기적으로 드레인하기에 안전하다. 백엔드 어댑터(`task-backend/`)·forge 어댑터(`forge/`, origin→github PR/gitlab MR 확장점/로컬 direct)는 플러그인 최상위 공유로 두고, 백엔드 선택은 벤더-중립 `.autopilot/task-backend.json`이 SoT. 새 family는 **플러그인 자기완결**(컨슈밍 프로젝트 `rules/` 비의존, 구 spec/loop/dispatch SKILL.md 비링크)이며 검증된 엔진(랄프 루프·dispatch 워커 헬퍼·flow)은 런타임으로 재사용한다. 기존 6-skill family는 그대로 병행 운영(이후 deprecate 예정).

## autopilot 0.47.0

### 변경(호환)
- **Claude Code + Codex 멀티 벤더 지원** — Codex plugin manifest를 추가하고, 공통 스킬의 질문·계획·스킬 호출·서브에이전트 계약을 런타임 기능 기반으로 정리했다. hooks는 Claude/Codex plugin root를 해석하며, loop는 `AUTOPILOT_WORKER_VENDOR=claude|codex`로 기존 `claude --print` 또는 공식 `codex exec` worker를 선택한다.

## autopilot 0.42.0

### 변경(호환)
- **`dispatch` fan-out 드라이버를 단일 `flow` 드라이버로 통합** — 기존 세 드라이버(`strong-parallel`=내장 dynamic Workflow / `background` / `foreground-batch`)와 자동 감지·override·안전 강등 사슬·`DRIVER` sticky 마커를 제거하고, 준비된 SPEC의 스트리밍 fan-out·동시성 상한·실패 이행 격리·저널 resume·결과 전달을 `flow` 스킬의 공개 계약으로 구동한다. 워커는 flow의 서브프로세스 에이전트(`wf.agent`+`SubprocessAgentCaller`, 벤더 중립)로 spawn한다. Claude Code 전용 내장 Workflow 의존을 제거해 다양한 벤더에서 동작하고 환경 의존 복잡도를 없앤다. `start` 인터페이스는 불변. `python3` 3.9+ 미가용 시 폴백 없이 hard-abort. 운영자 노브 `DISPATCH_DRIVER`·`DISPATCH_NO_STRONG_PARALLEL`·`DISPATCH_NO_BACKGROUND`는 더 이상 동작을 가르지 않으며 `driver`/`status`는 항상 `flow`를 보고한다.

## skill-rubric 0.1.0

### 새 기능
- **`skill-rubric` 플러그인 추가** — 토스 기술블로그 '스킬 품질 루브릭' 6개 섹션 30개 항목(규칙 17 + 모델 13)으로 SKILL.md를 평가해 등급(S/A/B/C/F)과 지적 목록을 산출하는 `rubric` 스킬. 결정적 17항목은 Python 검사기(`rule_checker.py`)가 정규식·카운트·syntax 검사로 판정하고(frontmatter YAML 파싱·유효성은 `yq`(mikefarah)에 위임), 의미적 13항목은 스킬을 실행하는 에이전트가 판정한다. `Skill(skill="rubric", args="<SKILL.md 경로 | all>")`로 단일·전체 평가, 마크다운 리포트 + JSON 산출. 루브릭은 verbatim 적용(본문 XML 태그 = BLOCKER).

## autopilot 0.41.0

### 새 기능
- **`autopilot:flow` 스킬 추가** — Workflow Replica 하니스(Python 표준 라이브러리만으로 동작하는 독립 DAG 오케스트레이터)의 진입점. 내장 dynamic Workflow 도구가 미가용인 환경에서도 임의 `depends_on` DAG를 스트리밍 fan-out·동시성 상한·실패 이행 격리·저널 resume·결과 전달로 실행한다. CLI 러너(`flow run <정의.py>` / `flow selftest` / `flow deps`), 기계 판독 JSON 출력.
