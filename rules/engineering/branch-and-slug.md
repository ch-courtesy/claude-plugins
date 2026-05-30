# 브랜치·slug·파일명 지침

SPEC 제목에서 slug를 만드는 규칙, SPEC 문서 파일명 규칙, 그리고 SPEC을 feat 브랜치로 commit·동기화하는 규칙의 단일 출처입니다.

- **slug·파일명**: spec 스킬이 SPEC 문서를 `docs/specs/<YYYY-MM-DD>-<slug>/SPEC.md`로 저장할 때 이 규칙으로 slug를 만듭니다.
- **feat 브랜치·commit·원격 동기화**: SPEC 문서를 받아 git에 반영하는 주체(구현 스킬·오케스트레이터·호출자)가 따릅니다. spec 스킬 자체는 더 이상 브랜치를 만들지 않습니다.

## slug 규칙

SPEC 첫 H1(`# `)에서 slug를 만듭니다.

1. ASCII lowercase
2. `[a-z0-9-]` 외 문자를 `-`
3. 연속 `-` 압축
4. 앞뒤 `-` 제거

빈 slug면 fallback 경로/브랜치 없이 abort하고 제목 수정을 요청합니다.

단일 출처 코드:

```bash
title=$(awk '
  /^---$/ { fm = !fm; next }
  !fm && /^# / { sub(/^# /, ""); print; exit }
' "<spec_path>")
slug=$(printf '%s' "$title" \
  | LC_ALL=C tr '[:upper:]' '[:lower:]' \
  | LC_ALL=C tr -c 'a-z0-9-' '-' \
  | sed -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')
```

## SPEC 문서 파일명

각 SPEC은 자신의 디렉토리를 가집니다. spec 스킬의 산출 경로는 `docs/specs/<YYYY-MM-DD>-<slug>/SPEC.md`이며, 문서 본문은 그 디렉토리 안의 `SPEC.md`에 둡니다. `<YYYY-MM-DD>`는 작성일(로컬 날짜), `<slug>`는 위 규칙으로 SPEC 제목에서 파생합니다. 디렉터리가 없으면 만듭니다.

이 per-spec 디렉토리 레이아웃은 그 SPEC의 loop 실행이 만드는 모든 per-spec 아티팩트(워크트리·락·실행 메타·신호)를 같은 스펙 디렉토리 하위에 격리하기 위한 것입니다 — 서로 다른 스펙의 실행이 공통 부모를 공유하지 않습니다. 아래 `<spec_path>`는 이 `docs/specs/<YYYY-MM-DD>-<slug>/SPEC.md` 본문 경로를 가리킵니다.

## feat 브랜치 + commit

SPEC 문서를 git에 반영하는 주체는 `feat/<task-id>-<slug>` 브랜치를 default branch(main)에서 만들고 SPEC 문서만 commit합니다. main 작업트리(staged/unstaged/untracked) 상태는 작업 전후 같아야 하며, 끝나면 원래 브랜치로 복귀합니다.

1. `git status --porcelain` snapshot.
2. `orig_branch=$(git rev-parse --abbrev-ref HEAD)`.
3. `branch="feat/<task-id>-<slug>"`; branch가 이미 있으면 덮어쓰기/새 이름/종료를 묻습니다.
4. `git checkout -b "$branch" main`.
5. `git add <spec_path>`만 실행합니다. `git add .`는 금지합니다.
6. `git commit -m "feat(spec): <task-id> — <title>" -- "<spec_path>"`.
7. `git checkout "$orig_branch"`.
8. status snapshot이 달라지면 경고합니다.

실패 시 생성한 feat branch를 안전하면 삭제하고 원래 브랜치로 복귀합니다. SPEC 파일은 남기되 이후 진행은 사용자 결정에 맡깁니다.

## 원격 동기화

전제: local SPEC commit이 feat branch에 있고 현재 HEAD는 `orig_branch`.

1. `git fetch origin main`; 실패 시 abort, feat commit 보존.
2. `git checkout "$branch"` 후 `git rebase origin/main`; 충돌 시 `git rebase --abort`, 원래 브랜치 복귀, force push 금지.
3. `git checkout main` 후 `git merge --ff-only "$branch"`; 실패 시 merge commit 없음, 원래 브랜치 복귀, push 안 함.
4. `git push origin main`; 거부 시 force 금지. local main은 SPEC commit까지 ff 된 상태이므로 사용자에게 `git reset --hard origin/main` 또는 PR 흐름 전환을 안내합니다.
5. `git push origin "$branch"`; 거부 시 force 금지. main push는 이미 성공했으므로 feat ref push 재시도를 안내합니다.
6. `git checkout "$orig_branch"` 후 status snapshot을 검증합니다.

모든 실패 보고에는 feat commit 여부, default ff-merge 여부, origin main push 여부, origin feat push 여부를 명시합니다. force push는 금지합니다.
