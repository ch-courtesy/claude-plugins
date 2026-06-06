# forge 통합 지침

자율 루프(`autopilot:loop`)는 **스펙 파일 → 로컬 자율 구현 → DONE/BLOCKED 파일**의 순수 로컬 실행기다. 변경 제안(PR)·리뷰·머지·통합 후 정리 같은 **forge 연동은 루프 코어에 없다.** 이 지침은 그 연동 책임을 누가, 어떤 계약으로 수행하는지의 단일 출처다.

(task 저장소 매핑·이슈 동기화는 `rules/context.md`, task 상태 정합은 `task-state-alignment.md`가 단일 출처다. 본 지침은 forge(변경 제안·리뷰·머지) 연동만 다룬다.)

## 책임 경계

| 단계 | 주체 |
|---|---|
| 스펙으로부터 자율 구현, 이터 게이트, 완료/차단 판정 | `autopilot:loop` 코어 |
| 완료 신호(`.loop/DONE`) / 차단 신호(`.loop/BLOCKED`) 생성 | 루프 코어 |
| DONE 감지 → base sync → push → PR 생성·재사용 | **`dispatch` 통합 모드(기본 ON)** |
| 리뷰·머지(ff-only)·머지 후 정리 | **`dispatch` 통합 모드** |
| task 상태 전이·이슈 동기화 | `rules/context.md`·`task-state-alignment.md` |

루프 코어는 forge 도구(`gh` 등)를 호출하지 않는다. 코어가 끝나면 작업 공간(`<spec_dir>/.worktree/`)과 그 커밋이 남고, 통합(리뷰·머지)은 **`dispatch` 통합 모드**가 이어받는다. `fsd` 는 리뷰·머지·통합을 직접 수행하지 않고 `dispatch start`(통합 모드 ON)에 완전위임하며, dispatch run 상태를 `dispatch status` 공개 인터페이스로 관측만 한다(완전자율: 외부 승인 보류·사람 개입 없음).

## 신호 계약

루프 코어가 호출 레이어에 넘기는 것은 두 파일이다.

- **`.worktree/.loop/DONE`**: 완료. 본문에 완료 요약. 작업 공간의 git 커밋이 통합 대상이다.
- **`.worktree/.loop/BLOCKED`**: 차단. 첫 줄 `category:`(`config-gap`·`spec-gap`·`architecture-gap`·`environment-gap`·`gate-violation`·`other`), 본문에 사유·시도·필요 결정. 호출 레이어는 PR/통합을 시도하지 않고 사람 판단으로 넘긴다.

호출 레이어는 `loop.sh status`/`logs`로 상태를 폴링해 DONE/BLOCKED를 감지한다.

## DONE 이후 통합 흐름 (dispatch 통합 모드가 소유)

1. **base sync**: 작업 공간 브랜치를 default branch에 정합. force push 금지.
2. **push**: 작업 공간 브랜치를 원격에 push. force push 금지.
3. **PR 생성·재사용 (forge 서브모드)**: 동일 head 브랜치의 open PR이 있으면 재사용, 없으면 생성. forge 미구성(direct 서브모드)이면 PR 없이 로컬 ff-only 머지로 직행한다.
4. **리뷰·머지**: dispatch 통합 모드가 리뷰(forge 서브모드)·`--ff-only` 머지를 수행한다. 완전자율 direct 서브모드는 분리 승인 신원 없이 ff-only 머지하므로 외부 승인 보류·사람 개입 지점이 없다.
5. **정리**: 머지 후 dispatch·loop 의 공개 cleanup 인터페이스로 작업 공간·임시 브랜치 제거.

이 절차는 **`dispatch` 통합 모드**가 자기 run 안에서 수행한다. `fsd` 는 이를 직접 하지 않고 `dispatch start`에 완전위임하며, 본 지침은 책임 경계와 신호 계약만 고정한다.

## 보안

forge 인증(토큰·자격증명)은 dispatch 통합을 돌리는 호출 호스트가 보유한다(상세는 `operational-guide.md`). 루프 작업 공간·스펙에는 secrets를 두지 않는다(루프는 `--dangerously-skip-permissions`로 무인 실행됨).
