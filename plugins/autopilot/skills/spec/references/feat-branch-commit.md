# spec step 9.5 — feat 브랜치 + SPEC.md commit (자동, main 작업트리 무손상)

SPEC.md 작성과 자체 검토가 끝나면, sibling `autopilot:loop`이 worktree base로 사용할 `feat/<task-id>-<slug>` 브랜치를 main에서 분기·생성하고 SPEC.md를 그 브랜치에 commit한다. main 작업트리 상태(staged/unstaged/untracked)는 변경되지 않아야 한다.

이 단계를 단계 10의 사용자 최종 검토 *전*에 수행해 SPEC.md가 이미 git history에 반영된 상태에서 사용자가 결정을 내리도록 한다. 사용자가 단계 10에서 "변경" 옵션을 선택하면 단계 7/8 재진입 후 본 단계의 commit을 amend하거나 새 commit을 쌓는다 (자동 처리).

본 문서만 읽고도 단계를 끝까지 수행할 수 있게 자기완결적으로 기술한다.

## 9.5.1 슬러그화 규칙 (결정적)

SPEC §1 제목(첫 H1, `# ` 다음 텍스트)에서 `<slug>`를 도출:

1. ASCII 소문자로 변환
2. `[a-z0-9-]`가 아닌 모든 문자를 `-`로 치환 (UTF-8 멀티바이트는 바이트별 치환)
3. 연속된 `-`를 단일 `-`로 압축
4. 시작·끝의 `-` 제거

결과가 빈 문자열이면 fallback 브랜치(`feat/<c>` 단독)·fallback 디렉토리(`milestones/<m>/loops/<c>/`)를 만들지 않는다 — SPEC 116 EARS AC4 단일 컨벤션 위반이며 sibling pr-phase 도 동일 이유로 abort. 빈 slug 발생 시 §9.5.3 실패 처리로 분기해 사용자에게 §1 H1 제목 수정(step 7 재진입)을 요청한다. 같은 SPEC 제목은 항상 같은 slug 를 만든다.

구현 예 (bash) — **본 코드 조각이 슬러그 도출의 단일 출처(single source of truth)**이며 안전장치(`references/test-spec-loop-contract.sh`)가 이 위치를 검사한다:

```bash
title=$(sed -n '/^---$/,/^---$/!{/^# /{s/^# //p; q;}}' "milestones/<m>/loops/<c>/SPEC.md")
slug=$(printf '%s' "$title" \
  | LC_ALL=C tr '[:upper:]' '[:lower:]' \
  | LC_ALL=C tr -c 'a-z0-9-' '-' \
  | sed -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')
```

## 9.5.2 브랜치 생성·commit 절차

본 단계의 모든 경로 참조는 진입점 §8.1 에서 결정된 slug-bearing 디렉토리 — `milestones/<m>/loops/<c>-<slug>/SPEC.md` — 와 정합하게 동일 `<slug>` 를 사용한다. 브랜치 이름의 `<slug>` 와 디렉토리 이름의 `<slug>` 는 반드시 같다. `<slug>` 가 빈 문자열이면 §9.5.1 의 빈-slug 실패 처리로 사전 분기되므로 본 단계는 항상 non-empty `<slug>` 를 가정한다 (SPEC 116 단일 컨벤션, EARS AC4 — fallback 없음).

1. `git status --porcelain`으로 main 작업트리 상태 스냅샷 캡처. unstaged·untracked가 있으면 그 사실을 인지 (다음 단계의 git 동작이 영향 안 주도록 명시적 경로 사용).
2. 현재 브랜치 이름 보존: `orig_branch=$(git rev-parse --abbrev-ref HEAD)`.
3. 브랜치 이름 결정 (§8.1 과 동일 `<slug>`): `branch="feat/<c>-<slug>"`. (빈 slug 케이스는 §9.5.1 에서 이미 abort 되어 본 단계 진입 자체가 없다.)
4. `git show-ref --verify --quiet "refs/heads/$branch"`로 충돌 확인. 이미 존재하면 사용자에게 알리고 `AskUserQuestion`으로 (덮어쓰기 / 새 이름 / 종료) 선택.
5. `git checkout -b "$branch" main`으로 main에서 명시적으로 분기. base를 명시하지 않으면 호출 시점 HEAD에서 분기되어 비-main 브랜치에서 호출 시 엉뚱한 base로 feat 브랜치가 만들어진다. main 작업트리의 다른 변경은 그대로 따라옴 (이를 의도). SPEC.md만 add·commit하므로 다른 파일은 새 commit에 들어가지 않는다.
6. SPEC.md 경로를 §8.1 의 slug-bearing 경로(`milestones/<m>/loops/<c>-<slug>/SPEC.md`)로 두고 `git add <spec_path>` 로 명시적으로 SPEC.md만 staging (`git add .` 절대 금지).
7. `git commit -m "feat(spec): <c> — <title>" -- "<spec_path>"`로 SPEC만 commit. `-- <pathspec>` 형식이 다른 staged 파일을 commit에서 격리.
8. `git checkout "$orig_branch"`로 원래 브랜치 복귀.
9. 복귀 후 `git status --porcelain` 결과가 step 1과 동일한지 검증. 다르면 사용자에게 경고.

## 9.5.3 실패 처리

위 절차 중 어떤 단계라도 실패하면:
- 부분 결과 정리: 생성된 feat 브랜치가 있으면 `git branch -D "$branch"`로 삭제 (단, 그 브랜치에 다른 commit이 없을 때만; 의심스러우면 사용자에게 알리고 수동 정리 안내).
- 원래 브랜치 복귀: `git checkout "$orig_branch"`.
- 사용자에게 명시적으로 실패 사유와 복구 방법 안내. SPEC.md는 `milestones/<m>/loops/<c>-<slug>/SPEC.md` 에 그대로 남기되, loop 진행은 다음 단계에서 사용자가 결정.
- **빈 slug 케이스 (§9.5.1)**: 슬러그화 결과가 빈 문자열이면 본 §9.5.2 진입 전에 abort 한다. SPEC.md 는 step 8 의 §8.1 단일 경로 가정에 의해 빈 slug 에서는 작성되지 않으며, 사용자에게 §1 H1 제목 수정을 요청해 step 7 재진입한다 (SPEC 116 단일 컨벤션 — fallback 없음).
