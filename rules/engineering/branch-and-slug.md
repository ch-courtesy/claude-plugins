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

## SPEC 산출 경로 해석

spec 스킬이 SPEC 본문을 저장할 per-spec 디렉토리의 **위치(베이스)와 디렉토리 네이밍**을 결정하는 규칙입니다. 이 경로 해석 규칙과 기본값 표현의 **단일 출처는 이 절**이며, spec 스킬 문서·그 외 소비자는 규칙을 중복 정의하지 않고 이 절을 참조합니다.

1. **외부 선언 우선** — 세션 시작 시 이미 로드된 프로젝트 지침(`CLAUDE.md` 및 `rules/`)에서 사람이 읽고 grep 가능한 **약속된 키 한 줄** `spec-path:` 선언을 찾습니다. 선언이 있으면 그 값을 per-spec 디렉토리 경로 템플릿으로 사용합니다. 자유 텍스트를 해석해 경로를 추론하지 않으며, 오직 `spec-path:` 한 줄만 인식합니다.
2. **선언 값** — `spec-path:` 값은 베이스 디렉토리뿐 아니라 **per-spec 디렉토리 네이밍**까지 표현할 수 있는 경로 템플릿입니다. `<YYYY-MM-DD>`(작성일)·`<slug>`(제목 파생) placeholder를 포함할 수 있고 spec 스킬이 치환합니다. placeholder가 없어 디렉토리가 유일해지지 않으면, 서로 다른 SPEC이 같은 디렉토리를 공유하지 않도록 유일성을 보장하는 것은 선언자의 책임입니다.
3. **선언이 여러 곳** — `CLAUDE.md`의 `spec-path:` 선언이 `rules/`의 선언보다 **우선**합니다.
4. **선언이 없으면 기본값** — `docs/specs/<YYYY-MM-DD>-<slug>/`를 per-spec 디렉토리로 사용합니다. 이 기본값은 별도 하드코딩이 아니라 **이 절의 선언으로 표현되는 값**이며, 본문은 그 안의 `SPEC.md`입니다 → `docs/specs/<YYYY-MM-DD>-<slug>/SPEC.md`.
5. **고정 불변식** — 외부 선언 유무·값과 무관하게 각 SPEC은 자신의 전용 per-spec 디렉토리를 가지며 본문은 그 디렉토리 안의 `SPEC.md`입니다(베이스 바로 아래의 맨몸 파일이 아닙니다). 외부 선언은 디렉토리의 위치(베이스)와 per-spec 네이밍까지 바꿀 수 있으나, 이 불변식(per-spec 디렉토리 + 그 안 `SPEC.md`)은 보존됩니다.
6. **빈 slug** — 기본 네이밍(`<날짜>-<slug>`)을 쓰는 경우 제목 파생 slug가 비면 fallback 디렉토리 없이 abort하고 제목 수정을 요청합니다(위 slug 규칙과 동일).
7. **디렉토리 생성** — 해석된 per-spec 디렉토리가 없으면 만듭니다. 기본값(`docs/specs/...`)이 아닌 선언 경로에 대해서도 생성이 권한 때문에 차단되지 않아야 합니다. 권한의 최소성은 **경로가 아니라 연산 차원**에서 성립합니다 — `mkdir -p` 디렉토리 생성 연산으로만 한정하며(파일 쓰기·삭제 등 다른 명령은 이 권한으로 수행되지 않습니다), 경로는 외부 선언으로 임의 지정될 수 있으므로(위 1·2항) 경로 범위로는 제한하지 않습니다.

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
