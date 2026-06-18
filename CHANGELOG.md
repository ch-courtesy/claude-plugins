# Changelog

이 저장소의 **사용자 가시(behavior-changing) 변경**을 기록합니다. 버전의 단일 출처(SoT)는 각 플러그인의 `plugin.json`이며(`rules/engineering/versioning.md`), 본 파일은 변경이 머지될 때마다 누적합니다. 분류: 새 기능 / 변경(호환) / 변경(깨짐) / 버그 수정 / 보안.

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
