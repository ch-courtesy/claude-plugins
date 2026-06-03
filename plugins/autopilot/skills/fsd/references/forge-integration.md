# forge 통합 지침

자율 루프(`autopilot:loop`)는 **스펙 파일 → 로컬 자율 구현 → DONE/BLOCKED 파일**의 순수 로컬 실행기다. 변경 제안(PR)·리뷰·머지·통합 후 정리 같은 **forge 연동은 루프 코어에 없다.** 이 지침은 그 연동 책임을 누가, 어떤 계약으로 수행하는지의 단일 출처다.

(task 저장소 매핑·이슈 동기화는 `rules/context.md`, task 상태 정합은 `task-state-alignment.md`가 단일 출처다. 본 지침은 forge(변경 제안·리뷰·머지) 연동만 다룬다.)

## 책임 경계

| 단계 | 주체 |
|---|---|
| 스펙으로부터 자율 구현, 이터 게이트, 완료/차단 판정 | `autopilot:loop` 코어 |
| 완료 신호(`.loop/DONE`) / 차단 신호(`.loop/BLOCKED`) 생성 | 루프 코어 |
| DONE 감지 → base sync → push → PR 생성·재사용 | **호출 레이어 (사용자·오케스트레이터)** |
| 리뷰 폴링·자동 fix·승인·머지·머지 후 정리 | **호출 레이어** |
| task 상태 전이·이슈 동기화 | `rules/context.md`·`task-state-alignment.md` |

루프 코어는 forge 도구(`gh` 등)를 호출하지 않는다. 코어가 끝나면 작업 공간(`<spec_dir>/.worktree/`)과 그 커밋이 남고, 통합은 호출 레이어가 이어받는다.

## 신호 계약

루프 코어가 호출 레이어에 넘기는 것은 두 파일이다.

- **`.worktree/.loop/DONE`**: 완료. 본문에 완료 요약. 작업 공간의 git 커밋이 통합 대상이다.
- **`.worktree/.loop/BLOCKED`**: 차단. 첫 줄 `category:`(`config-gap`·`spec-gap`·`architecture-gap`·`environment-gap`·`gate-violation`·`other`), 본문에 사유·시도·필요 결정. 호출 레이어는 PR/통합을 시도하지 않고 사람 판단으로 넘긴다.

호출 레이어는 `loop.sh status`/`logs`로 상태를 폴링해 DONE/BLOCKED를 감지한다.

## DONE 이후 통합 흐름 (호출 레이어 권장 절차)

1. **base sync**: 작업 공간 브랜치를 default branch에 rebase. 충돌 시 중단하고 사람에게 위임. force push 금지.
2. **push**: 작업 공간 브랜치를 원격에 push. force push 금지.
3. **PR 생성·재사용**: 동일 head 브랜치의 open PR이 있으면 재사용, 없으면 생성. reviewer·label·assignee는 정책에 따라(기본 미설정). PR body 자동 영역은 fence 안에만 쓴다.
4. **리뷰·머지**: 리뷰 정책에 따라 폴링·대응. 승인 또는 owner 종료 신호 시 머지.
5. **정리**: 머지 후 `loop.sh cleanup <spec-path>`로 작업 공간·임시 브랜치 제거.

이 절차의 구체 명령·자동화는 프로젝트가 별도 도구(스킬·CI·스크립트)로 구현하며, 본 지침은 책임 경계와 신호 계약만 고정한다.

## 보안

호출 레이어가 forge 인증(토큰·자격증명)을 보유한다. 루프 작업 공간·스펙에는 secrets를 두지 않는다(루프는 `--dangerously-skip-permissions`로 무인 실행됨).
