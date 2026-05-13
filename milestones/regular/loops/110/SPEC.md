---
scope:
  include:
    - "plugins/autopilot/skills/loop/references/**"
    - "tests/autopilot/test-loop-sh.sh"
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-loop-sh.sh && test -z \"$(grep -rln 'autonomous-loop' plugins/autopilot/skills/loop/)\" && test -z \"$(grep -rln -F '.loop/' plugins/autopilot/skills/loop/)\""
ears_language: ko
request_review: true
test_sweep_paths:
  - "tests/autopilot/test-loop-sh.sh"
---

# autopilot/loop: 워커 메모리·SPEC 경로 milestones 단일 contract 일원화 + legacy `autonomous-loop` 분기 제거 (constitution·verify 완전 통합)

## 무엇을 만들 것인가

`autopilot:loop` 스킬을 단일 contract(`feat/<task-id>[-<slug>]` 브랜치 + `milestones/<m>/loops/<id>/` 디렉토리 정본)로 일원화한다. legacy `autonomous-loop/<task-id>` 분기·`.loop/` 디렉토리 의존성을 모든 layer에서 제거한다.

워커 instruction 정본인 헌법(`constitution.md`)·운영 가이드(`operational-guide.md`)·agent 양식(`agent-prompts.md`)·트러블슈팅(`troubleshooting.md`)·에스컬레이션 템플릿(`escalation-template.md`)의 메타 파일 경로 표기·SPEC 위치 표기·legacy/신규 병기 문구를 모두 단일 contract로 재서술한다. 헌법은 워크트리 셋업 시점에 그대로 워크트리의 CLAUDE.md로 cp되어 워커 행동을 직접 지배하므로, 헌법의 경로 표기는 실제 코드 동작과 단어 단위로 일치해야 한다.

워커는 메타 파일 5종(PLAN·NOTES·HANDOFF·RUN_LOG·ESCALATION)을 워크트리 안의 `milestones/<m>/loops/<id>/` 경로에 직접 작성하며, 시스템은 매 이터레이션 종료 직후 그 5종의 변경분만 격리해 `chore(loop): meta iter <N>` 메시지로 feat 브랜치에 자동 commit한다 (변경 없으면 commit 0). iter 실행 raw 로그는 워크트리-local `.iterations/N.log`로 이동해 어떤 git 브랜치에도 commit되지 않는다. PR 생성 단계의 SPEC 경로 하드코딩도 단일 contract에 맞춰 일원화한다.

검증 명령은 단순 grep을 넘어 워커 instruction 정합성(constitution이 가리키는 경로 = 실제 코드가 사용하는 경로)과 워커 메모리 위치 실태(iter 종료 후 메타 파일이 실제로 새 경로에서만 발견)를 fail-가능한 형태로 검사한다. 본 SPEC은 #76의 동일 작업 범위를 포함하되, #76 워커 iter 4 DONE이 사실상 미충족이었던 구조적 결함(constitution 미갱신·verify 좁음)을 EARS·검증 양쪽으로 보강해 재발을 차단한다.

## 수용 기준 (EARS)

1. `loop start <task-id>`를 호출할 때, `feat/<task-id>` 또는 `feat/<task-id>-<slug>` 브랜치가 부재하면, 시스템은 즉시 abort하고 `autopilot:spec` 스킬 호출을 안내하는 die 메시지를 출력한다.
2. `loop start <task-id>`를 호출할 때, `feat/<task-id>` 또는 `feat/<task-id>-<slug>` 브랜치가 정확히 하나 존재하면, 시스템은 그 브랜치를 워크트리 base로 사용한다.
3. `loop start <task-id>`의 어떤 경로에서도 시스템은 `autonomous-loop/<task-id>` 형식 브랜치를 새로 생성하지 않는다.
4. 워커가 이터레이션 동안 `milestones/<m>/loops/<id>/{PLAN,NOTES,HANDOFF,RUN_LOG,ESCALATION}.md` 중 하나 이상에 변경을 가하면, 시스템은 그 이터 종료 직후 그 5개 파일의 변경분만 staging해 `chore(loop): meta iter <N>` 메시지로 feat 브랜치에 commit한다.
5. 워커가 이터레이션 동안 메타 파일 5개에 어떤 변경도 가하지 않으면 시스템은 그 이터에 메타 commit을 발행하지 않는다.
6. 시스템은 이터레이션의 raw 실행 로그를 워크트리 안의 `.iterations/<N>.log` 경로에만 기록하고, 어떤 git 브랜치에도 add·commit하지 않는다.
7. `loop start <task-id>`가 워크트리를 생성한 직후, 그 워크트리 루트에 `.loop/` 디렉토리는 존재하지 않는다.
8. `loop cleanup <task-id>`를 호출할 때, 시스템은 워크트리 안의 메타 파일을 메인 작업트리로 cp하지 않으며, feat 브랜치를 자동 삭제하지 않는다.
9. `grep -rln 'autonomous-loop' plugins/autopilot/skills/loop/` 명령이 빈 결과를 반환한다.
10. `grep -rln -F '.loop/' plugins/autopilot/skills/loop/` 명령이 빈 결과를 반환한다.
11. 헌법(`plugins/autopilot/skills/loop/references/constitution.md`)이 워커에게 지시하는 메타 파일 위치 표기가 `milestones/<m>/loops/<c>/` 경로로 통일되며, `.loop/`로 시작하는 메타 파일 경로 표기는 헌법 본문 어디에도 등장하지 않는다.
12. PR 생성 단계(`plugins/autopilot/skills/loop/references/pr-phase.sh`)의 SPEC 파일 경로 변수가 워크트리 안의 `milestones/<m>/loops/<id>/SPEC.md`를 가리키며, `.loop/SPEC.md` 하드코딩은 없다.
13. 워커가 이터레이션을 1회 이상 거쳐 DONE에 도달한 feat 브랜치를 검사하면, 그 브랜치의 commit log에 `chore(loop): meta iter` 패턴의 commit이 워커 메타 갱신 횟수만큼 등장하며, 모든 메타 파일은 `milestones/<m>/loops/<id>/` 경로에서만 발견되고 워크트리 루트의 `.loop/`에는 메타 파일이 존재하지 않는다.
14. `bash tests/autopilot/test-loop-sh.sh` 명령이 0 exit으로 종료한다.

## 범위

포함:
- `plugins/autopilot/skills/loop/references/loop.sh`
  - `cmd_start`의 legacy `autonomous-loop/<id>` 분기·`BRANCH="autonomous-loop/$task_id"` 기본값·NEW_CONTRACT 미감지 시 새 브랜치 생성 경로·관련 주석 제거
  - 워크트리 시드 단계의 `.loop/` 디렉토리 생성·메타 템플릿 cp 위치를 `<WT>/milestones/<m>/loops/<id>/`로 이동
  - 이터 종료 직후 메타 파일 5종의 변경분만 pathspec 격리해 `chore(loop): meta iter <N>` 메시지로 commit하는 로직 신설 (변경 없으면 commit 0)
  - iter raw log 경로를 `<WT>/.loop/iterations/<N>.log`에서 `<WT>/.iterations/<N>.log`로 이동, `.git/info/exclude` 등록 갱신
  - `cmd_cleanup`의 `cleanup_new_contract=0` 분기(legacy archive cp + autonomous-loop 브랜치 자동 삭제) 제거, `cleanup_new_contract` 플래그 자체 제거
  - 자동 ESCALATION 작성 위치를 `<WT>/.loop/ESCALATION.md`에서 `<WT>/milestones/<m>/loops/<id>/ESCALATION.md`로 이동
- `plugins/autopilot/skills/loop/references/pr-phase.sh`
  - SPEC 경로 변수가 `$WT/.loop/SPEC.md` 하드코딩 대신 `$WT/milestones/${TASK_ID%%/*}/loops/${TASK_ID#*/}/SPEC.md`로 단일 contract 사용
- `plugins/autopilot/skills/loop/references/constitution.md`
  - 헤더의 `autonomous-loop` 표기 정리
  - §2 입력·출력 절의 `.loop/{PLAN,NOTES,HANDOFF,RUN_LOG}.md`·`.loop/ESCALATION.md`·`.loop/SPEC.md` 표기를 모두 `milestones/<m>/loops/<c>/` 경로로 갱신
  - §3.1·§3.2.6·§3.5·§5.2·§5.3·§7·§11.1·§11.2·§11.3·§11.4·§12의 모든 `.loop/...` 메타 경로 표기를 갱신
  - 합법적 잔존이 없도록 `grep -F '.loop/'` 0건 보장
- `plugins/autopilot/skills/loop/references/operational-guide.md`
  - 디렉토리 트리 표기의 `.loop/` 노드 제거·신규 contract 기준 재서술
  - 트러블슈팅 예시 명령에서 `.loop/ESCALATION.md`·`.loop/NOTES.md`·`.loop/SPEC.md` 경로 갱신
  - `autonomous-loop/...` 브랜치 예시 갱신
- `plugins/autopilot/skills/loop/references/agent-prompts.md`
  - 워크트리 SPEC 경로 안내(L33·L114 등)의 신규/legacy 병기를 신규 contract 단일 경로로 정합
- `plugins/autopilot/skills/loop/references/troubleshooting.md`
  - ESCALATION 위치 안내·SPEC 위치 contract-별 병기 제거
- `plugins/autopilot/skills/loop/references/escalation-template.md`
  - spec-gap 카테고리 안내의 SPEC 경로 병기 제거
- `tests/autopilot/test-loop-sh.sh`
  - 회귀 + 신규 케이스 (메타 commit 발생/미발생/경로·iter 로그 위치·`.loop/` 비생성·grep 검사·workTree HEAD 메타 파일 검사·constitution `.loop/` 부재 검사·pr-phase.sh SPEC 경로 패턴 검사)

비-목표:
- 이미 머신에 존재하는 `autonomous-loop/*` 브랜치·워크트리 자동 마이그레이션·자동 정리
- 메인 작업트리에 archive된 과거 메타 파일(예: `milestones/regular/loops/{65,69,71,75,78,79,task-status-on-spec,76}/...md`) 삭제·이동
- `tests/autopilot/test-skill-install.sh:66-68`의 `autonomous-loop-rule-creator` 문자열 (별개 project-init 스킬명)
- `docs/superpowers/{plans,specs}/2026-05-*autonomous-loop-*.md` 등 historical 설계 문서
- 슬러그 도출·feat 브랜치 분기 로직 (`autopilot:spec` step 9.5에 위치, 변경 없음)
- `autopilot:spec`·`autopilot:dispatch` 스킬 본체 변경 (Layer B 범위)
- 메타 파일 외 파일(코드 변경)의 commit 정책 변경 — 워커 commit은 기존 그대로 워커 책임
- iter raw 로그의 외부 보존·전송·압축
- `feat/regular/76-...` feat 브랜치 처리 방향 (cherry-pick·참조·폐기) — 별도 결정

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```
bash tests/autopilot/test-loop-sh.sh && \
test -z "$(grep -rln 'autonomous-loop' plugins/autopilot/skills/loop/)" && \
test -z "$(grep -rln -F '.loop/' plugins/autopilot/skills/loop/)"
```

`tests/autopilot/test-loop-sh.sh`는 위 14개 EARS를 모두 fail 가능한 형태로 커버한다 — 특히 신규 케이스로 다음을 명시 검증:
- feat 브랜치 부재 시 `loop start`가 비-0 exit + spec 스킬 안내 메시지 (EARS 1)
- feat 브랜치 존재 시 워크트리가 그 브랜치를 base로 체크아웃 (EARS 2)
- `loop start` 후 `git branch | grep autonomous-loop`가 빈 결과 (EARS 3)
- 워커가 메타 파일 수정 → 이터 종료 후 feat 브랜치 HEAD에 `chore(loop): meta iter <N>` 패턴 commit 1개 추가 (EARS 4)
- 워커가 메타 파일 미수정 → 같은 이터에 메타 commit 0건 추가 (EARS 5)
- `<WT>/.iterations/<N>.log` 존재 + `git -C "$WT" status --porcelain`에 그 경로가 untracked로 노출되지 않음 (EARS 6)
- 워크트리 생성 직후 `<WT>/.loop/` 디렉토리 부재 (EARS 7)
- `loop cleanup` 후 `milestones/<m>/loops/<id>/`에 메인 트리로 cp된 메타 파일 추가 없음, feat 브랜치 `git branch`에 보존 (EARS 8)
- `grep -rln 'autonomous-loop' plugins/autopilot/skills/loop/` 빈 결과 (EARS 9)
- `grep -rln -F '.loop/' plugins/autopilot/skills/loop/` 빈 결과 (EARS 10)
- `grep -F '.loop/' plugins/autopilot/skills/loop/references/constitution.md` 빈 결과 (EARS 11)
- `grep -E 'SPEC_FILE.*\.loop' plugins/autopilot/skills/loop/references/pr-phase.sh` 빈 결과 + `grep -E 'SPEC_FILE.*milestones.*loops' plugins/autopilot/skills/loop/references/pr-phase.sh` 1개 이상 (EARS 12)
- DONE feat 브랜치의 `git log --pretty=%s | grep '^chore(loop): meta iter'` 매칭 + 워크트리 HEAD에 `find <WT>/.loop -type f` 빈 결과 + 메타 파일이 `find <WT>/milestones/<m>/loops/<id> -name PLAN.md -o -name NOTES.md ...` 매칭 (EARS 13)

## 제약

- bash 4.x 호환 — loop.sh 현행 컨벤션 유지
- `autopilot:spec` step 9.5의 슬러그·feat 브랜치 분기 로직은 그대로 활용 (변경 안 함)
- 메타 commit pathspec 격리: `-- "milestones/<m>/loops/<id>/PLAN.md" "milestones/<m>/loops/<id>/NOTES.md" "milestones/<m>/loops/<id>/HANDOFF.md" "milestones/<m>/loops/<id>/RUN_LOG.md" "milestones/<m>/loops/<id>/ESCALATION.md"`로 다른 파일이 메타 commit에 섞이지 않도록 격리
- 메타 commit message는 `chore(loop): meta iter <N>` 고정 (`<N>`은 1부터의 정수 이터레이션 번호)
- 워커는 메타 파일 5종을 git에 직접 add·commit하지 않음 — 메타 commit 발행은 loop.sh의 단독 책임
- 본 SPEC frontmatter `test_sweep_paths`에 `tests/autopilot/test-loop-sh.sh` 명시 — 본 SPEC의 sweep 화이트리스트는 처음부터 선언 (#76 ESCALATION 재발 차단)
- verify 명령 안의 grep 패턴은 fixed-string 모드(`-F`)로 `.loop/` 정확 검사 — 정규식 메타문자 충돌 방지
- SPEC §검증은 단순 verify 명령 통과만이 아니라 워커 instruction(constitution)·실제 메타 위치까지 검사하는 신규 케이스를 test-loop-sh.sh에 의무화 (#76 실패 교훈)
- `tests/autopilot/test-skill-install.sh:66-68`의 `autonomous-loop-rule-creator` 문자열은 별개 project-init 스킬명이므로 본 변경에서 건드리지 않음

## 위험

- constitution.md는 워커 instruction의 정본이므로 잘못 갱신 시 모든 워커 동작에 영향. 갱신 후 자체 검토 시 `.loop/` 잔존 0건과 새 경로 표기 일관성을 다중 검색으로 확인 필요. 특히 §2 입력·출력·§11.1·§11.2 등 메타 파일 경로가 다수 등장하는 절은 갱신 후 단어 단위 검사.
- 머신에 남아있는 구식 `autonomous-loop/*` 워크트리는 `loop cleanup` 표준 경로로 정리 불가. 사용자는 `git worktree remove --force` + `git branch -D autonomous-loop/<id>`로 수동 정리해야 함. 본 SPEC은 의도적으로 마이그레이션 자동화를 제공하지 않음 (신규 start에만 적용 방침).
- 메타 commit 빈도가 이터레이션 횟수와 동일해 PR commit log에 메타 commit이 다수 노출됨. `chore(loop): meta iter <N>` message convention과 path filter(`-- ':!milestones/**'`)로 reviewer가 분리 가능하지만 일부 리뷰 도구에서는 노이즈로 보일 수 있음.
- `<WT>/milestones/<m>/loops/<id>/` 디렉토리는 feat 브랜치 base에 이미 SPEC.md commit으로 존재하므로 워커가 그 경로에 메타 파일을 새로 쓰면 자연스럽게 tracked 상태가 됨. 다만 `.iterations/`는 워크트리 루트 바로 아래에 위치해 워크트리-local untracked로만 살아남아야 함 — `.git/info/exclude` 등록을 누락하면 commit 격리가 깨지므로 워크트리 시드 단계의 exclude 등록 갱신은 본 변경의 필수 항목.
- `cleanup_new_contract` 플래그 제거로 cmd_cleanup 분기 단순화 — `cmd_cleanup`이 호출되는 모든 워크트리는 이제 feat 브랜치를 PR base로 보존하는 단일 경로. 만약 호출 시점의 워크트리가 어떤 이유로 feat 브랜치가 아닌 다른 브랜치에 체크아웃되어 있다면(외부에서 수동 변경) cleanup 동작이 비정상화될 수 있음 — 사전 검증 로직(현재 브랜치가 `feat/`로 시작하는지 확인)은 유지·강화.
- verify 명령의 `grep -F '.loop/'` 0건 기준은 `.loop/`가 합법적으로 등장하는 다른 컨텍스트(예: 변수명·comment의 정확한 ".loop/")까지 차단할 수 있음. 해당 시 inline 주석으로 의도된 사용을 표시하거나 패턴을 좁혀야 함 — 단 현재 코드베이스에서 `.loop/`의 합법적 다른 사용처는 식별되지 않음.
- 본 SPEC이 #76 동일 작업을 재구현한다 — `feat/regular/76-loop-sh-legacy-autonomous-loop-id-feat-milestones-m-loops-id` 브랜치의 6 commits이 본 작업 산출물과 중복됨. cherry-pick·참조·폐기 결정은 본 SPEC 범위 밖이며 별도 결정 필요.
- 워커가 헌법을 갱신할 때 자기 자신이 따르는 instruction을 갱신하는 self-referential 변경 — 이터 #1의 워커는 갱신 전 헌법으로 동작하므로 갱신 작업이 이터 #1 안에 완료되어야 다음 이터부터 새 instruction 적용. 만약 헌법 갱신이 다중 이터에 걸치면 이터 간 instruction 불일치로 인한 작업 일관성 위협 가능.
