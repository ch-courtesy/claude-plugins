# spec step 9.5 feat branch + SPEC commit (optimized)

SPEC 작성·자체 검토 후 `feat/<task-id>-<slug>` 브랜치를 main에서 만들고 `milestones/<m>/loops/<c>-<slug>/SPEC.md`만 commit한다. 이후 default branch(main)와 feat branch를 `origin/main` 최신 위로 정렬하고 push한다. main 작업트리 staged/unstaged/untracked 상태는 호출 전후 같아야 하며 끝나면 원래 브랜치로 복귀한다.

단계 10 사용자 최종 검토 전에 실행한다. 사용자가 "변경"을 고르면 step 7/8 재진입 후 amend 또는 추가 commit하고 동기화를 재실행한다.

## 9.5.1 slug 규칙

SPEC 첫 H1(`# `)에서 slug를 만든다.

1. ASCII lowercase
2. `[a-z0-9-]` 외 문자를 `-`
3. 연속 `-` 압축
4. 앞뒤 `-` 제거

빈 slug면 fallback 경로/브랜치 없이 abort하고 제목 수정을 요청한다.

단일 출처 코드:

```bash
title=$(awk '
  /^---$/ { fm = !fm; next }
  !fm && /^# / { sub(/^# /, ""); print; exit }
' "milestones/<m>/loops/<c>/SPEC.md")
slug=$(printf '%s' "$title" \
  | LC_ALL=C tr '[:upper:]' '[:lower:]' \
  | LC_ALL=C tr -c 'a-z0-9-' '-' \
  | sed -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')
```

## 9.5.2 local branch + commit

1. `git status --porcelain` snapshot.
2. `orig_branch=$(git rev-parse --abbrev-ref HEAD)`.
3. `branch="feat/<c>-<slug>"`; branch 존재 시 덮어쓰기/새 이름/종료를 묻는다.
4. `git checkout -b "$branch" main`.
5. `git add <spec_path>`만 실행한다. `git add .` 금지.
6. `git commit -m "feat(spec): <c> — <title>" -- "<spec_path>"`.
7. `git checkout "$orig_branch"`.
8. status snapshot이 달라지면 경고.

실패 시 생성한 feat branch를 안전하면 삭제하고 원래 브랜치로 복귀한다. SPEC 파일은 남기되 loop 진행은 사용자 결정.

## 9.5.4 remote sync

전제: local SPEC commit이 feat branch에 있고 현재 HEAD는 `orig_branch`.

1. `git fetch origin main`; 실패 시 abort, feat commit 보존.
2. `git checkout "$branch"` 후 `git rebase origin/main`; 충돌 시 `git rebase --abort`, 원래 브랜치 복귀, force push 금지.
3. `git checkout main` 후 `git merge --ff-only "$branch"`; 실패 시 merge commit 없음, 원래 브랜치 복귀, push 안 함.
4. `git push origin main`; 거부 시 force 금지. local main은 SPEC commit까지 ff 된 상태이므로 사용자에게 `git reset --hard origin/main` 또는 PR 흐름 전환 안내.
5. `git push origin "$branch"`; 거부 시 force 금지. main push는 이미 성공했으므로 feat ref push 재시도 안내.
6. `git checkout "$orig_branch"` 후 status snapshot 검증.

모든 실패 보고에는 feat commit 여부, default ff-merge 여부, origin main push 여부, origin feat push 여부를 명시한다.

## self-referential 면제

이 contract를 도입하는 현재 spec 호출에는 새 동작을 선행 적용하지 않는다. 새 contract는 default branch에 반영된 다음 spec 호출부터 적용한다.
