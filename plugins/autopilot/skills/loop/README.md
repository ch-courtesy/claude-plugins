# loop

**무엇** — 스펙 파일 하나(절대 경로가 정체성)를 받아 스펙 디렉토리 아래 전용 워크트리(`<spec_dir>/.worktree`)에서
자율적으로 구현하는 최소 실행기(랄프 루프). 매 이터는 새 `claude --print` 프로세스이고, terminal 의도는
워커가 `.loop/signals/` 디렉토리에 파일을 만들어 표현한다.

**언제** — 검증 가능한 완료 조건이 적힌 SPEC 한 건을 격리 작업 공간에서 사람 개입 없이 구현시키고 싶을 때.
spec·repair 가 떠 둔 SPEC 을 dispatch 가 SPEC 1건당 워커로 위임하는 흐름의 단일-SPEC 실행 단위.

**호출** — `Skill(skill="loop", args="<subcommand> [<args>]")` (subcommand: `start`/`status`/`stop`/`list`/`cleanup`/`logs`).

상세(subcommand 계약·신호 계약·driver 동작·references 표·규칙)는 **`SKILL.md`가 단일 출처**다.
워커 헌법은 `references/constitution.md`, 셸 driver 는 `references/loop.sh` 가 SoT 다.
이 README 는 입구 요약이며 그 내용을 복제하지 않는다.
