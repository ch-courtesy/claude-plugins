---
scope:
  include: ["plugins/autopilot/skills/loop/references/loop.sh"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; F=plugins/autopilot/skills/loop/references/loop.sh; test -f \"$F\" && bash -n \"$F\" && grep -qE \"task_status_is_done\\(\\)\" \"$F\" && grep -qE \"task_label_present\\(\\)|task_has_label\\(\\)\" \"$F\" && grep -qE \"^[[:space:]]*LOOP_DONE_LABEL=\" \"$F\" && grep -qE \"ensure_label_exists\\(\\)|task_ensure_label_exists\\(\\)\" \"$F\"'"
ears_language: ko
---

# loop.sh의 done·blocked 신호 검출·발행 매체 교체 + label name 자동 관리

## 무엇을 만들 것인가

autopilot 드라이버 `loop.sh`에서 done 신호와 blocked 신호의 *검출*과 *발행* 매체를 추상 어휘의 단일 의존(검출 키)으로 단일화한다. 완료 신호의 검출 키는 task 식별자에 부속된 label(예: `loop:done`)이고, 정지 신호의 검출 키는 task 상태 field 값(예: `Blocked`)이다. 양쪽 모두 인간 가독·로그를 위한 신호 발행은 함께 유지하되, 드라이버의 판정 분기는 label·status에만 의존한다.

본 child는 다음을 추가하거나 교체한다:

- **task_status_is_done() 함수의 정식 재구성** — milestone 진행 동안 적용된 hotfix(comment prefix 마지막 매치 기반)는 임시 조치이며, 본 child가 정식으로 label 검출로 교체한다. comment 기반 검색은 더 이상 단일 검출 키가 아니다.
- **task_label_present() 헬퍼 함수** — task 식별자가 주어졌을 때 그 task에 특정 label이 붙어 있는지를 boolean으로 반환하는 추상 헬퍼.
- **LOOP_DONE_LABEL 상수** — 완료 label의 이름(예: `loop:done`). 프로젝트 수준에서 고정되며 드라이버가 부재 시 자동 생성·재사용한다.
- **ensure_label_exists() 헬퍼 함수** — task storage에 해당 label이 존재하는지 확인하고, 없으면 만든다. 사용자가 별도 입력하지 않아도 드라이버가 self-bootstrap한다.
- **신호 발행 부분의 이중 발행** — 워커가 완료 시 `[done]` 신호 발행(가독·로그)과 `loop:done` label 추가(검출 키) 두 동작을 모두 수행하도록 헌법·SKILL.md가 지시하는데, 드라이버는 검출 시점에 label만 본다. 본 child가 그 검출 경로를 단일화한다.
- **blocked 검출** — task_status_is_blocked()는 이미 status field와 comment OR 결합. 본 child가 단일 의존(status field만)으로 단순화한다. 단, project status 자동 전이가 미구현인 환경(`AUTOPILOT_PROJECT_ITEM_ID` 미설정)을 위한 graceful degradation은 헬퍼 호출의 best-effort로 유지하되 판정 키는 label·status 단일 의존을 깨지 않는다.
- **comment 기반 검출 코드 제거** — 0.2.0 호환 잔존 `$WT/DONE` 파일 체크와 hotfix의 comment prefix 검색은 본 child의 새 단일 검출 경로(label·status)가 동작하기 시작하면 제거한다. 호환을 위한 OR 결합은 milestone 종료 후 사용자가 결정할 수 있도록 frontmatter 또는 환경 변수로 분리.

## 수용 기준 (EARS)

1. `plugins/autopilot/skills/loop/references/loop.sh`가 존재할 때, 시스템은 bash 문법 검사(`bash -n`)에서 0 exit으로 통과한다.
2. `loop.sh`에 `task_status_is_done()` 함수가 정의되어 있을 때, 시스템은 그 함수가 task 식별자를 인자로 받아 task에 `LOOP_DONE_LABEL` 값과 일치하는 label이 붙어 있을 때만 0(done)을 반환하도록 구현한다.
3. `loop.sh`에 `task_label_present()` 헬퍼 함수가 정의될 때, 시스템은 그 함수가 task 식별자와 label 이름을 받아 label 존재 여부를 0/1로 반환한다.
4. `loop.sh`에 `LOOP_DONE_LABEL=` 상수가 정의될 때, 시스템은 그 값이 단일 위치에서 결정되어 프로젝트 수준에서 고정된다(다른 모듈에 분산 정의 금지).
5. `loop.sh`에 `ensure_label_exists()` 헬퍼 함수가 정의될 때, 시스템은 task storage에 해당 label이 없으면 자동 생성하고, 있으면 그대로 재사용한다.
6. 본 child가 `loop.sh`를 재작성하는 동안, 시스템은 sibling child(헌법·SKILL.md·기타 references)의 파일을 수정하지 않는다.

## 범위

포함:

- `plugins/autopilot/skills/loop/references/loop.sh`의 done·blocked 신호 검출 경로를 label·status 단일 의존으로 재구성
- 새 헬퍼 함수 추가: `task_status_is_done`(정식), `task_label_present`, `ensure_label_exists`
- 새 상수 `LOOP_DONE_LABEL` 정의 및 label 자동 생성·재사용 로직
- comment 기반 검출 코드(hotfix·0.2.0 호환 잔존) 제거 또는 단일 검출 키 외부로 분리

비-목표 / 제외:

- 헌법 본문 변경 — sibling child-a 담당
- SKILL.md 어휘 변경 — sibling child-b 담당
- 보조 references *.md 정리 — sibling child-d 담당
- phase script(`pr-phase.sh`·`rebase-phase.sh`·`review-fix-phase.sh`·`cleanup-phase.sh`) 변경 — task storage 호출이 없어 본 milestone scope 외
- `rules/context.md` 변경 — 본 milestone의 명시 비-목표
- adapter 인터페이스 신설 — 본 milestone의 명시 비-목표. 헬퍼 함수명·매개변수 수준의 추상화는 허용하되 다중 구현을 분기하는 dispatcher·인터페이스 객체는 만들지 않는다.
- 기존 [done]·[blocked] prefix comment 히스토리 마이그레이션

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```bash
bash -c 'set -e; F=plugins/autopilot/skills/loop/references/loop.sh; test -f "$F" && bash -n "$F" && grep -qE "task_status_is_done\(\)" "$F" && grep -qE "task_label_present\(\)|task_has_label\(\)" "$F" && grep -qE "^[[:space:]]*LOOP_DONE_LABEL=" "$F" && grep -qE "ensure_label_exists\(\)|task_ensure_label_exists\(\)" "$F"'
```

## 제약

- `feedback_no_self_apply_during_spec` 메모리 룰: 본 SPEC.md를 작성하는 *현재* spec 호출에는 새 검출 contract를 선행 적용하지 않는다.
- `feedback_self_referential_verification` 메모리 룰: 워커는 verify·worktree source(직접 변경한 `loop.sh`)만 검사하고 runtime artifact(자기 task의 issue label·다른 task의 검출 동작)는 검사 대상에서 제외한다. 본 child는 자기 task의 완료 검출이 *자기 자신을 통해* 작동하는 self-referential 함정에 가장 취약한 child다.
- 본 child는 wave 2에 속하며 wave 1의 child-a 산출물(헌법의 어휘 정의)을 입력으로 사용한다.
- `LOOP_DONE_LABEL`의 기본값(예: `loop:done`)은 단일 위치에서 결정되며 프로젝트 수준에서 고정. 사용자가 환경 변수로 override할 수 있도록 fallback 패턴을 따른다(예: `: "${LOOP_DONE_LABEL:=loop:done}"`).

## 위험

- **self-referential 함정 (최대 위험)**: 본 child가 `loop.sh`의 done 검출 로직을 수정하는 동안, 워커 자신의 task 완료가 자기 변경한 검출 로직으로 판정된다. 워커가 verify 통과 후 완료 신호(label·comment) 발행을 정확히 따라야 자기 task의 완료가 인식된다. milestone 진행 동안 적용된 hotfix(comment prefix 마지막 매치)는 본 child가 정식 label 검출로 교체하기 *전*까지는 유효해야 하므로, 본 child의 워커는 자기 변경의 부분적 적용(예: 새 헬퍼는 추가했지만 호출 사이트는 아직 안 옮긴 상태)이 자기 검출을 깨뜨리지 않도록 변경을 단일 commit으로 묶거나 호환 OR 결합을 유지한 채로 종료해야 한다.
- **adapter 유혹**: "이참에 label 검출 헬퍼를 task storage adapter 인터페이스로 추상화하자"는 유혹. 비-목표에 명시 금지. 헬퍼 함수명은 추상이지만 본문 구현은 단일 GitHub 호출(`gh issue view --json labels`)을 그대로 사용한다.
- **label 자동 생성 권한 부족**: task storage에 label 생성 권한이 없는 환경에서 `ensure_label_exists`가 실패할 수 있다. 그 경우 best-effort로 stderr 경고 + 검출 1(false) 반환. 본 SPEC §검증은 함수 정의의 grep만 보므로 runtime 실패는 본 verify 범위 밖.
- **하위 호환**: 기존 워커가 발행한 `[done]` prefix comment만 있고 label이 없는 task는 본 child 적용 후 영원히 done 판정 안 됨. PRD §제약 "소급 마이그레이션 없음"에 따라 의도된 동작. 본 milestone 이전 issue는 수동 처리.
