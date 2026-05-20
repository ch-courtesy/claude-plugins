# spec step 9.5 — feat 브랜치 + SPEC.md commit + default 브랜치 자동 ff-merge (자동, main 작업트리 무손상)

SPEC.md 작성과 자체 검토가 끝나면, sibling `autopilot:loop`이 worktree base로 사용할 `feat/<task-id>-<slug>` 브랜치를 main에서 분기·생성하고 SPEC.md를 그 브랜치에 commit한다. 직후 동일 호출에서 default 브랜치(main)·feat 브랜치를 원격 default 브랜치(`origin/main`) 최신 위로 정렬해 default 브랜치에도 SPEC.md commit이 fast-forward 형태로 반영되고 원격 저장소에 즉시 push되게 한다. main 작업트리 상태(staged/unstaged/untracked)는 호출 이전과 동일하게 유지되어야 하며, 전체 흐름이 끝나면 호출 시점의 원래 브랜치로 복귀한다.

이 단계를 단계 10의 사용자 최종 검토 *전*에 수행해 SPEC.md가 이미 git history(local + remote default)에 반영된 상태에서 사용자가 결정을 내리도록 한다. 사용자가 단계 10에서 "변경" 옵션을 선택하면 단계 7/8 재진입 후 본 단계의 commit을 amend하거나 새 commit을 쌓는다 (자동 처리, 후속 §9.5.4 재실행 포함).

본 문서만 읽고도 단계를 끝까지 수행할 수 있게 자기완결적으로 기술한다.

## 9.5.1 슬러그화 규칙 (결정적)

SPEC §1 제목(첫 H1, `# ` 다음 텍스트)에서 `<slug>`를 도출:

1. ASCII 소문자로 변환
2. `[a-z0-9-]`가 아닌 모든 문자를 `-`로 치환 (UTF-8 멀티바이트는 바이트별 치환)
3. 연속된 `-`를 단일 `-`로 압축
4. 시작·끝의 `-` 제거

결과가 빈 문자열이면 fallback 브랜치(`feat/<c>` 단독)·fallback 디렉토리(`milestones/<m>/loops/<c>/`)를 만들지 않는다 — 단일 컨벤션이며 sibling pr-phase 도 동일 이유로 abort. 빈 slug 발생 시 §9.5.3 실패 처리로 분기해 사용자에게 §1 H1 제목 수정(step 7 재진입)을 요청한다. 같은 SPEC 제목은 항상 같은 slug 를 만든다.

구현 예 (bash) — **본 코드 조각이 슬러그 도출의 단일 출처(single source of truth)**이며 안전장치(`references/test-spec-loop-contract.sh`)가 이 위치를 검사한다.

H1 제목 추출은 BSD sed (macOS) 와 GNU sed 의 `{...}` 블록 + `q` 구문 차이로 인해 awk 기반으로 작성한다 — 기존 `sed -n '/^---$/,/^---$/!{/^# /{s/^# //p; q;}}'` 패턴은 BSD sed 에서 `extra characters at the end of } command` 로 실패한다:

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

awk 동작: `fm` 플래그가 frontmatter `---` 라인을 토글하므로 frontmatter 내부의 `# ...` 라인은 무시되고 frontmatter 종료 후 첫 H1 (`# ` prefix) 의 본문만 추출·종료한다. frontmatter 가 없는 SPEC.md 도 그대로 첫 H1 을 추출한다. 슬러그 정규화에 쓰이는 trailing `sed -e ...` 는 in-place 가 아닌 단순 치환 호출이라 BSD·GNU 양립한다.

## 9.5.2 브랜치 생성·commit 절차

본 단계의 모든 경로 참조는 진입점 §8.1 에서 결정된 slug-bearing 디렉토리 — `milestones/<m>/loops/<c>-<slug>/SPEC.md` — 와 정합하게 동일 `<slug>` 를 사용한다. 브랜치 이름의 `<slug>` 와 디렉토리 이름의 `<slug>` 는 반드시 같다. `<slug>` 가 빈 문자열이면 §9.5.1 의 빈-slug 실패 처리로 사전 분기되므로 본 단계는 항상 non-empty `<slug>` 를 가정한다 (단일 컨벤션 — fallback 없음).

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

§9.5.2 절차(브랜치 생성·SPEC.md commit) 중 어떤 단계라도 실패하면:
- 부분 결과 정리: 생성된 feat 브랜치가 있으면 `git branch -D "$branch"`로 삭제 (단, 그 브랜치에 다른 commit이 없을 때만; 의심스러우면 사용자에게 알리고 수동 정리 안내).
- 원래 브랜치 복귀: `git checkout "$orig_branch"`.
- 사용자에게 명시적으로 실패 사유와 복구 방법 안내. SPEC.md는 `milestones/<m>/loops/<c>-<slug>/SPEC.md` 에 그대로 남기되, loop 진행은 다음 단계에서 사용자가 결정.
- **빈 slug 케이스 (§9.5.1)**: 슬러그화 결과가 빈 문자열이면 본 §9.5.2 진입 전에 abort 한다. SPEC.md 는 step 8 의 §8.1 단일 경로 가정에 의해 빈 slug 에서는 작성되지 않으며, 사용자에게 §1 H1 제목 수정을 요청해 step 7 재진입한다 (단일 컨벤션 — fallback 없음).

§9.5.4 절차(원격 default 브랜치 동기화·fast-forward merge·원격 push) 중 실패 분기:

- **rebase 충돌** (`git rebase origin/main` 단계에서 conflict marker 발생 또는 비-zero exit):
  1. `git rebase --abort`로 rebase 중단 — 작업트리·인덱스는 rebase 직전 상태(feat 브랜치 HEAD = SPEC commit)로 자동 복구된다.
  2. `git checkout "$orig_branch"`로 호출 시점 원래 브랜치 복귀 — default 브랜치는 절대 전환 안 됨 (전환은 rebase 성공 후에만 일어나므로 충돌 단계에서는 default 브랜치 작업트리가 손대지지 않음, AC8).
  3. 사용자에게 충돌 사실과 함께 **수동 복구 방법** 안내: feat 브랜치 SPEC commit은 그대로 살아 있으며 (`git log feat/<c>-<slug>` 로 확인 가능), 사용자가 직접 rebase 충돌을 해소하거나 `feat/<c>-<slug>` 를 PR로 올리는 별도 흐름으로 전환 가능. 강제 push 시도 금지.

- **ff-merge 거부** (§9.5.4 step 3 `git merge --ff-only "$branch"` 가 비-zero exit — default 브랜치가 origin/main 보다 앞서 있거나, 호출 이전 staged·local commit 으로 default HEAD 와 feat 가 diverge):
  1. **이 분기 시점의 상태 전제**: `--ff-only` 가 fail 했으므로 merge commit 은 생성되지 않았다 — default 브랜치 HEAD·작업트리는 step 3 진입 시점과 동일하게 보존돼 있다 (로컬 변경 없음, 원격과의 일관성도 깨지지 않음). 따라서 push 거부 분기처럼 `git reset --hard origin/main` 형태의 "로컬 되돌림" 안내를 출력하지 않는다 — 되돌릴 로컬 변경이 없다.
  2. `git checkout "$orig_branch"` 로 호출 시점 원래 브랜치 복귀. 원격 default·feat push 는 시도 자체를 하지 않는다 (강제 push 금지 원칙과 별개로, step 4·5 에 도달하지 않음).
  3. 사용자에게 ff-merge 가 거부된 사실과 **그 근본 원인 후보**(default 브랜치가 origin/main 보다 앞선 로컬 commit·미push 변경 보유, 또는 base 가 diverge) 와 **수동 복구 방법** 안내: default 브랜치 상태를 `git log main..origin/main` / `git log origin/main..main` 으로 점검하고, 정렬 후 다음 spec 호출에서 자동 재실행 또는 PR 흐름으로 전환. SPEC.md commit 은 feat 브랜치에 그대로 살아 있다.

- **main push 거부** (§9.5.4 step 4 `git push origin main` 이 non-fast-forward·protected branch·권한 부족 등으로 reject — step 3 ff-merge 는 이미 성공해 로컬 main HEAD 가 feat SPEC commit 까지 fast-forward 적용된 *후*, 원격 main push 가 거부된 시점):
  1. **`--force`·`--force-with-lease` 등 강제 push 절대 시도 안 함** — 본 단계의 모든 push는 일반 push 만 허용. push 명령은 단 한 번만 시도하고 실패하면 즉시 abort.
  2. **이 분기 시점의 상태 전제**: 로컬 main HEAD 는 SPEC commit 까지 적용됐지만 `origin/main` 은 step 1 의 fetch 시점 그대로다 — 즉 로컬 main 과 원격 main 이 분기된 상태로 일관성이 깨졌다. (이 전제는 ff-merge 거부·feat push 거부 분기와 다른 점이다.) 원격 feat push (step 5) 는 시도 자체를 하지 않는다.
  3. 사용자에게 push 거부 사실과 함께 명시적으로 알리고, `git reset --hard origin/main` 으로 로컬 main 을 원격에 맞춰 되돌리거나 PR 흐름으로 전환할 수 있음을 안내한다 (단일 사용자 메시지 지점). feat 브랜치 SPEC commit 은 보존. SPEC.md disk 사본도 보존.
  4. `git checkout "$orig_branch"`로 호출 시점 원래 브랜치 복귀.

- **feat push 거부** (§9.5.4 step 5 `git push origin <branch>` 가 protected branch·권한 부족·서버 일시 오류 등으로 reject — step 4 main push 는 이미 성공한 *후*, feat 브랜치만 push 가 거부된 시점):
  1. **`--force`·`--force-with-lease` 등 강제 push 절대 시도 안 함** — 일반 push 만 허용, 단 한 번 시도 후 실패 시 즉시 abort.
  2. **이 분기 시점의 상태 전제**: step 4 가 이미 성공했으므로 `origin/main = local main = feat SPEC commit` 이 동기 완료된 상태다 — 로컬 main 과 원격 main 사이에 분기가 없으며, 따라서 `git reset --hard origin/main` 같은 "로컬 되돌림" 안내는 부적절하다 (되돌릴 분기가 없다). feat 브랜치도 로컬·원격 모두 같은 SHA (단지 원격에 ref 가 등록 안 됐을 뿐) 인 경우가 일반적이다.
  3. 사용자에게 feat push 거부 사실과 함께 명시적으로 알리고, **필요 복구는 `git push origin <branch>` 재시도** 임을 안내한다 (서버 일시 오류·네트워크 회복 후, 단일 사용자 메시지 지점). 거부 사유가 권한·protected branch 라면 권한 설정·브랜치 보호 규칙 확인 후 재시도. main 동기화는 이미 완료됐으므로 다음 spec 호출에서는 본 단계가 no-op 으로 끝나며, feat ref 등록만 별도로 처리해도 무방하다. SPEC.md disk 사본 보존.
  4. `git checkout "$orig_branch"`로 호출 시점 원래 브랜치 복귀.

- **fetch 실패** (`git fetch origin` 자체가 네트워크·인증 문제로 실패): §9.5.4 전체를 abort하고 `git checkout "$orig_branch"`로 복귀. SPEC.md commit 은 feat 브랜치에 그대로 남으며, 원격 동기화는 사용자가 네트워크 복구 후 수동 재시도 또는 다음 spec 호출에서 자동 재실행.

모든 §9.5.4 실패 분기에서 공통:
- `git status --porcelain` 결과가 §9.5.2 step 1 의 스냅샷과 동일한지 검증. 다르면 사용자에게 경고와 함께 어떤 파일이 추가/수정됐는지 표시.
- 사용자에게 **자동 흐름이 어디까지 진행됐는지** 명시적으로 보고 (feat 브랜치 SPEC commit O/X, default 브랜치 ff-merge 적용 O/X, 원격 default push O/X, 원격 feat push O/X).

## 9.5.4 default 브랜치 자동 fast-forward merge·원격 push 절차

§9.5.2 가 성공해 feat 브랜치에 SPEC.md commit 이 만들어진 직후, 같은 호출 안에서 default 브랜치(`main`)·feat 브랜치를 원격 default 브랜치(`origin/main`) 최신 위로 정렬·동기화한다. 모든 단계는 비-zero exit 발생 시 즉시 §9.5.3 의 해당 분기로 이행한다 (강제 push 시도 금지, abort + 원상태 복구 우선).

본 단계 진입 시점의 사전 조건:
- `$orig_branch` = §9.5.2 step 2 에서 캡처한 호출 시점 원래 브랜치 이름.
- `$branch` = `feat/<c>-<slug>` (§9.5.2 에서 생성·SPEC commit 적용된 브랜치).
- 현재 HEAD = `$orig_branch` (§9.5.2 step 8 에서 복귀 완료).
- default 브랜치 작업트리는 호출 이전과 동일 (§9.5.2 의 명시적 경로 staging 으로 보존됨).

절차 (총 6 단계, AC1–AC9 매핑):

1. **(AC1) 원격 default 브랜치 fetch**: `git fetch origin main`. 네트워크·인증·remote 부재로 비-zero exit 시 §9.5.3 «fetch 실패» 분기. 성공 시 `origin/main` ref 가 원격 최신 commit 을 가리킨다.

2. **(AC2) feat 브랜치를 origin/main 위로 rebase**: `git checkout "$branch"` 후 `git rebase origin/main`. rebase 가 conflict marker 없이 0 exit 으로 끝나야 한다. conflict 또는 비-zero exit 시 §9.5.3 «rebase 충돌» 분기 (rebase --abort + orig branch 복귀). SPEC.md 만 들어 있는 commit 이라 conflict 가능성은 낮으나, 동시 `--milestone` 작업 또는 base 분기 시점 이후의 원격 변경과 SPEC 디렉토리가 겹치면 발생 가능.

3. **(AC3) default 브랜치로 전환 후 feat 브랜치를 fast-forward merge**: `git checkout main` 후 `git merge --ff-only "$branch"`. `--ff-only` 플래그가 핵심 — fast-forward 가 불가능한 경우 (default 브랜치가 origin/main 보다 앞서 있거나, 호출 이전 staged 변경이 default HEAD 와 diverge 등) 비-zero exit 으로 fail 하고, **이 시점에 merge commit 이 생성되지 않으므로 default 브랜치 HEAD 는 그대로 유지된다**. 비-zero exit 시 §9.5.3 «ff-merge 거부» 분기로 처리 (default 브랜치 HEAD·작업트리 보존 + 사용자 안내 + orig branch 복귀). step 2 가 성공했으면 feat 브랜치 = origin/main + (SPEC commit) 이고 default 브랜치 = origin/main 또는 그 이전이므로 일반적으로 fast-forward 가능.

4. **(AC4) 원격 default 브랜치 push**: `git push origin main`. push 가 거부되면 §9.5.3 «main push 거부» 분기로 이행 — `--force` 금지. 일반 push 성공 시 0 exit, `origin/main` 이 default 브랜치 HEAD 와 같아진다.

5. **(AC4) 원격 feat 브랜치 push**: `git push origin "$branch"`. 같은 SHA 가 이미 default 브랜치 push 로 원격에 도달했으므로 사실상 ref 등록 수준의 push 이지만, sibling `autopilot:loop` 이 feat 브랜치를 원격에서 fetch·worktree base 로 사용할 수 있게 필수. 거부 시 §9.5.3 «feat push 거부» 분기.

6. **(AC7·AC8) 원래 브랜치 복귀·작업트리 검증**: `git checkout "$orig_branch"` 로 호출 시점 원래 브랜치 복귀. 직후 `git status --porcelain` 결과가 §9.5.2 step 1 의 스냅샷과 동일한지 검증. 다르면 사용자에게 경고 (staged·unstaged·untracked 변동이 있다면 어떤 파일인지 표시) 하되, default 브랜치 HEAD 와 feat 브랜치 HEAD 는 이미 원격에 push 되었으므로 disk 상태 차이는 호출 이전 작업트리의 untracked 변경이 step 8 §8.1 의 SPEC.md write 결과로 추적 상태가 바뀌었을 가능성이 가장 높음.

본 단계는 사용자 재확인 없이 (AC4 의 "사용자 재확인 없이") 자동 실행된다 — 단계 10 의 사용자 최종 검토는 본 단계 *후*에 일어나므로 사용자는 SPEC.md 가 이미 default 브랜치 + 원격에 push 된 상태를 전제로 결정한다.

## 9.5.5 self-referential 호출 면제

본 §9.5.4 절차를 정의·도입하는 SPEC 을 작성·수락하는 *현재* spec 호출 자체에는 본 §9.5.4 새 동작을 적용하지 않는다. 이는 다음 일반 규약을 따른 것이다: **spec 호출이 정의·도입하는 새 contract 는 그 호출의 산출물(경로·브랜치·동작)에 선행 적용하지 않으며, 새 contract 는 해당 SPEC 이 default 브랜치에 merge 된 후의 다음 spec 호출부터 적용된다**. 따라서 현재 호출은 §9.5.2 까지만 (feat 브랜치 분기·SPEC commit·원래 브랜치 복귀) 수행하고, default 브랜치 ff-merge·원격 push 는 본 SPEC 이 merge 된 후의 다음 spec 호출부터 적용된다.
