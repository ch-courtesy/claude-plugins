# dispatch 머지-게이트 웨이브 + 스펙별 review→fix→merge 파이프라인

## 무엇을 만들 것인가

`autopilot:dispatch`가 의존성(`depends_on`) 있는 여러 SPEC을 wave로 묶어 자율 실행기
(`loop`)에 위임할 때, 한 SPEC의 **완료**를 "loop 워크트리가 DONE 신호로 종료"가 아니라
**"작업 결과가 main에 머지됨"**으로 재정의한다. 이를 위해 dispatch에 per-SPEC 통합·리뷰·머지
파이프라인을 자체구현한다: loop DONE → 결과를 작업 브랜치로 push → PR 생성/재사용 → 리뷰
판정 → (변경요청 시) 수정 사항을 SPEC 델타로 만들어 같은 브랜치에서 재구현·재푸시 → 자율
승인 → fast-forward 머지 → 그제서야 그 SPEC을 `done`으로 전이(=의존자 실행 해제).

이 파이프라인은 검증된 참고 설계(아래 "참고 알고리즘")의 동작을 dispatch 맥락으로 이식하되,
상태 저장소는 dispatch의 기존 run 디렉토리(`<project_root>/.dispatch/runs/<run-id>/`)를
per-SPEC 키로 재사용한다. forge·task backend 외부 라이브러리에 의존하지 않고 dispatch
references 안에서 자기완결적으로 구현한다.

## 목적 (왜)

현재 dispatch는 loop가 DONE으로 끝나면 그 SPEC을 `done`으로 보고 의존자를 다음 wave로
푼다. 그러나 그 시점의 코드는 격리된 워크트리(`<spec-dir>/.worktree`)에만 있고 main에
머지되지 않았다. loop는 워크트리를 항상 현재 HEAD에서 분기하므로(`git worktree add
--detach HEAD`), A에 의존하는 B의 loop는 A의 변경이 없는 HEAD에서 시작되어 A의 결과 위에서
빌드할 수 없다 — 의존 웨이브가 의미상 깨진다. 따라서 "loop 완료 = 승인·머지 완료"여야
의존자가 갱신된 main 위에서 올바르게 시작될 수 있다. 머지가 의존자를 푸는 게이트는 본질적으로
dispatch의 웨이브 스케줄링에 속하므로, review/merge 책임을 dispatch가 직접 갖는다.

## 완료 조건

> 아래 각 조건은 관찰 가능·독립 테스트 가능하다. 검증 진입 명령은 이 문서가 아니라 프로젝트
> 규칙(`rules/`)에서 온다. 모든 외부 인터페이스(git·forge CLI·loop·review 생산자)는 주입
> 가능한 명령 변수로 두어 mock으로 독립 검증(self-referential, 실제 PR·머지 미수행)한다.

1. 항상 dispatch는 한 SPEC의 의존자(그 SPEC을 `depends_on` 하는 SPEC)를 그 SPEC이 **main에
   머지된 뒤에만** 실행 큐에 푼다. loop가 DONE으로 끝난 것만으로는 의존자를 풀지 않는다.

2. 리뷰·머지 파이프라인이 구성되어 있으면(통합 모드 활성: 아래 "활성 조건"), loop가 DONE으로
   끝났을 때 dispatch는 그 SPEC의 작업 결과를 작업 브랜치(`feat/<run-id>-<slug>`)로 push하고
   그 head의 open PR을 재사용하거나 없으면 새로 생성한다. push·머지 어디에서도 force(강제)를
   쓰지 않는다. 통합 모드가 비활성이면 loop DONE을 곧 `done`으로 보아 기존 동작을 보존한다.

3. PR이 열려 있고 아직 승인되지 않은 동안, dispatch는 리뷰 생산자(`autopilot:review`의
   `run --task <id>`)를 호출해 단일 판정(`pipeline_verdict`: approve|request_changes|
   unavailable)과 분류된 재작업 브리프(`rework_brief.must_adopt/defer/wont_adopt`)를 받는다.
   판정이 `request_changes`이면 `must_adopt` 항목을 SPEC 델타 문서로 만들어 **같은 head
   브랜치 위에서** loop로 재구현하고 같은 브랜치로 재푸시한다(새 PR을 만들지 않으며 force
   금지). `defer` 항목은 현 PR에 섞지 않고 별도로 기록한다.

4. 리뷰 자동수정은 세 가지 가드로 무한루프를 막는다: (a) 재작업 라운드 수가 상한(기본 3)을
   초과하면 멈추고 에스컬레이션, (b) `must_adopt`가 0인데도 여전히 `request_changes`이면(무진전)
   에스컬레이션, (c) 차단성(`must_adopt`) 지적 집합이 직전 라운드와 동일하면(핑퐁) 에스컬레이션.
   에스컬레이션 시 그 SPEC은 비완료 종착으로 표시되고 자동수정을 멈춘다.

5. 열린 PR의 최신 정식 리뷰가 **사람** 리뷰어의 변경 요청이면, dispatch는 자동수정하지 않고
   즉시 에스컬레이션한다(자동수정은 봇 판정에만 적용). 직전에 처리한 head와 현재 PR head가
   같으면(새 커밋 없음) 멱등 no-op로 아무 동작도 하지 않는다.

6. 리뷰가 `approve`로 수렴하면, 분리된 자율 approver 신원이 PR을 승인하고 dispatch는 승인
   여부를 확인한다. 자동 리뷰 봇(REVIEW_BOT 신원)의 self-approve는 무효로 처리한다(분리된
   approver 신원의 APPROVED 리뷰만 인정).

7. PR이 승인된 상태에서, 머지될 변경이 버전 워치 디렉토리(`plugins/`)를 건드리면 같은 변경
   안에서 패키지 매니페스트(`plugin.json`)의 버전이 올랐는지 확인한다. 오르지 않았으면 머지를
   차단하고 차단 사유를 기록한다(비완료 종착). 버전 게이트를 통과하면(또는 워치 디렉토리 변경이
   없으면) dispatch는 작업 브랜치를 main에 **fast-forward 전용(`--ff-only`)**으로 머지하고
   (머지 커밋·force 금지) base를 push한 뒤, 그 SPEC을 `done`으로 전이한다.

8. 한 SPEC이 `done`(=머지됨)으로 전이된 뒤에만 그 의존자가 실행을 시작하며, 의존자의 loop는
   머지된 의존성을 포함한 갱신된 main 위에서 분기한다.

9. loop가 하드 BLOCKED(spec-gap 외 범주)로 끝나거나, 리뷰가 수렴하지 못해 에스컬레이션되거나,
   머지 게이트가 차단되면, 그 SPEC은 비완료 종착(`failed`/`blocked`)이고 그 **이행적 의존자만**
   `skipped`로 차단되며 의존 관계가 없는 독립 가지는 끝까지 진행한다. (BLOCKED 범주가 spec-gap
   이면 push·PR 없이 스펙 보강 재개 경로를 안내하고 비완료 종착으로 둔다.)

10. 동시에 여러 SPEC이 진행 중인 동안, main 체크아웃과 fast-forward 머지는 **직렬화**되어
    레이스 없이 한 번에 하나씩만 머지된다.

## 활성 조건

통합(리뷰·머지) 모드는 옵트인이다 — `dispatch start`에 통합 모드 플래그(예 `--integrate`)가
주어지거나 forge 구성(approver 신원·forge CLI)이 갖춰졌을 때만 활성화한다. 활성이 아니면
dispatch는 기존대로 loop DONE을 `done`으로 보아 완전한 하위 호환을 유지한다(기존 테스트·사용처
불변). 활성 조건의 정확한 트리거(플래그명·자동 감지 여부)는 기존 dispatch CLI 관례와 일관되게
정한다.

## 범위에 포함

- dispatch references 안에 per-SPEC 통합(push→PR)·리뷰 루프(판정→SPEC 델타→재구현→재푸시·가드)
  ·승인+머지(approval 게이트·버전범프 게이트·ff-only 머지·done 전이) 모듈을 자체구현.
- dispatch 스케줄러의 per-SPEC 라이프사이클 확장(loop DONE 후 통합→리뷰→머지 단계)과 `done`
  의미 재정의(=머지됨), 머지 직렬화, 비완료 종착의 의존자 skip 전파.
- per-SPEC 상태(작업 브랜치·PR 번호·리뷰 라운드·마지막 head·판정)를 run 디렉토리에 보관하는
  가벼운 상태 헬퍼.
- 각 모듈의 mock 기반 self-test와 스케줄러 통합 self-test(머지 게이트로 의존자 해제, 직렬화,
  실패 전파 검증).
- dispatch SKILL.md·드라이버 헤더의 "forge 연동은 호출 레이어 책임" 불변식 개정(통합 모드
  활성 시 dispatch가 통합·리뷰·머지를 소유함을 명시).

## 범위에서 제외

- GitLab MR(`glab`) 어댑터: forge CLI는 주입 가능한 인터페이스(기본 GitHub `gh`)로 두되 GitLab
  어댑터 구현은 후속.
- `loop` 스킬 공개 인터페이스 변경: fix 라운드는 loop의 기존 secondary-worktree 동작(워크트리
  안에서 `loop start` 호출 시 그 워크트리 재사용)을 이용한다 — loop에 새 옵션을 추가하지 않는다.
- 다른 세션에서 제거 중인 `fsd` 스킬의 모듈을 참조·수정·의존하지 않는다(설계 참고만).
- 리뷰 채택 분류 로직 재정의: 채택 분류(must_adopt/defer/wont_adopt)는 `autopilot:review`
  생산자가 `rules/change-adoption.md`·`rules/review.md`를 단일 출처로 수행하며 dispatch는
  결과를 소비만 한다.

## 제약

- bash 3.2+ 호환(연관 배열 미사용). dispatch references의 기존 코드 스타일·헬퍼 패턴을 따른다.
- **force(강제) push·rebase·merge를 어떤 경로에서도 쓰지 않는다.** base 동기화는 rebase(ff
  가능 시)로 하고 충돌 시 중단·사람 위임한다. 머지는 `git merge --ff-only`만 사용한다.
- **버전 범프 게이트**: `plugins/`를 건드리는 머지는 같은 변경에서 `plugin.json` 버전이 올라야
  한다(`rules/engineering/versioning.md` 단일 출처). 이 SPEC 구현이 `plugins/`를 수정하므로,
  통합 시 `plugins/autopilot/plugin.json`과 루트 `.claude-plugin/marketplace.json` 미러의
  SemVer를 함께 올린다.
- 작업 브랜치명·slug는 `rules/engineering/branch-and-slug.md`를 따른다(`feat/<id>-<slug>`,
  slug는 SPEC 제목 H1에서 도출, 빈 slug면 중단).
- 리뷰 생산자 호출은 `autopilot:review`의 공개 인터페이스(`review.sh run --task <id>`)만
  사용한다. loop는 공개 인터페이스(`loop.sh start|status|stop|cleanup`)만 사용하고 내부 신호
  파일·워크트리를 직접 열지 않는다.
- 자가생성 수정 SPEC(델타)은 디스크의 run 디렉토리 하위에 파일로 기록한다(SPEC은 항상 디스크에
  둔다는 프로젝트 규칙 준수).
- dispatch는 자신의 run 디렉토리(`.dispatch/runs/<run-id>/`) 밖 경로를 새로 만들지 않는다
  (작업 브랜치·PR·머지 같은 forge 부수효과 제외). 자가생성 델타 SPEC은 run 디렉토리 하위에 둔다.
- 통합 모드 비활성 시 기존 동작·기존 self-test가 100% 그대로 통과해야 한다(회귀 금지).

## 위험

- **동시성/직렬화**: 여러 loop가 병렬 워크트리에서 도는 동안 머지는 `git checkout main`을
  수반하므로 직렬화하지 않으면 레이스가 난다. 머지 구간을 run 디렉토리 락으로 직렬화한다.
  또한 리뷰 생산자 호출·fix loop는 시간이 길어 스케줄러 폴링 루프를 막지 않도록 per-SPEC를
  한 폴링 틱당 한 스텝씩 멱등 전진시키는 구조(드레인)로 둔다.
- **loop의 HEAD 스냅샷 타이밍**: 의존자 loop는 launch 시점의 HEAD를 스냅샷한다. 의존성 머지가
  로컬 main을 전진시킨 뒤에 의존자를 launch해야 의존자 워크트리가 머지 결과를 포함한다. 머지
  단계가 로컬 main을 ff-only로 전진시키므로, 머지 완료(=done) 이후 launch 순서를 보장한다.
- **fix 라운드 워크트리 경로**: loop는 `--branch`를 지원하지 않으므로, 같은 PR 브랜치 위
  재구현은 그 브랜치를 체크아웃한 워크트리 안에서 loop를 secondary 모드로 호출해 수행한다.
  이 경로를 mock self-test로 고정한다(실제 push/머지 미수행).

## 참고 알고리즘 (검증된 설계 — 이식 대상, 의존 아님)

다른 세션에서 제거 중인 `fsd` 스킬의 다음 모듈이 동일 문제를 풀어 self-test를 통과했다.
이들의 알고리즘을 dispatch 맥락으로 이식한다(코드 의존이 아니라 설계 참고):

- 통합(push→PR): 종료 신호 판정 → base sync(rebase, ff 가능 시) → push → open PR 재사용/생성.
  DONE→Review, spec-gap BLOCKED→스펙 보강 재개, 하드 BLOCKED→에스컬레이션.
- 리뷰 루프: 생산자 1회 호출 → 판정 분기. request_changes면 must_adopt를 SPEC 델타로 →
  같은 브랜치 재구현 → 같은 브랜치 push. 라운드캡(3)·무진전·핑퐁 가드. approve면 머지 진행가능
  전이. unavailable·사람 변경요청이면 에스컬레이션. 한 호출=한 라운드(수렴은 폴링 드레인 소유).
- 승인+머지: approver 신원의 APPROVED 리뷰 확인(리뷰 봇 self-approve 무효) → 버전범프 게이트
  → ff-only 머지(+base push) → done 전이.

환경 변수 계약(주입 가능, 테스트 mock): `LOOP_CMD`, `GIT_CMD`, `FORGE_CMD`(기본 gh),
`DEFAULT_BRANCH`(기본 main), `APPROVER`(자율 승인 신원), `REVIEW_BOT`(self-approve 무효 대상),
`REVIEW_ROUNDS_MAX`(기본 3), `WATCH_DIRS`(기본 plugins/), `REVIEW_PRODUCE_CMD`(기본
`autopilot:review`의 review.sh run --task), `DISPATCH_POLL_SECONDS`, `DISPATCH_WAVE_TIMEOUT_SECONDS`.

## 검증

- 각 신규 모듈의 `selftest`를 mock 인터페이스로 실행해 통합(push·PR)·리뷰(라운드·재푸시·세 가드·
  사람/head 게이트)·승인+머지(approval·버전 게이트·ff-only·force 미사용)를 독립 검증한다.
- 스케줄러 통합 self-test: A←B(B가 A에 의존) 시나리오에서 A가 머지되기 전 B가 launch되지 않고,
  A 머지 후 B가 launch됨을 단언한다. A가 비완료 종착이면 B가 skipped됨을 단언한다. 동시 머지가
  직렬화됨을 단언한다. 통합 모드 비활성 시 기존 동작이 불변임을 단언한다(회귀 금지).
- `git diff`로 어떤 push/머지에도 force 인자가 없고 머지 커밋이 생기지 않음을 확인한다.
  `plugins/` 변경에 버전 범프가 동반됨을 확인한다.
