#!/usr/bin/env bash
# cleanup-phase.sh — SPEC 123 M3
#
# PR이 MERGED 상태로 전이된 직후 호출되어 워크트리·로컬 feat·원격 feat 브랜치를
# 차례로 정리하고, 추상 상태를 "Done"으로 전이한다.
#
# 사용:
#   bash cleanup-phase.sh <worktree> <branch> <task-id> <project-root>
#
# 동작 (SPEC 123 AC16·AC17):
#   1. 사전 검사: 워크트리에 미커밋 변경 없음 (git status --porcelain 비어 있음)
#   2. git worktree remove <wt>
#   3. git branch -D <branch>            (로컬 feat 삭제)
#   4. git push --delete origin <branch> (원격 feat 삭제)
#   5. 추상 상태 "완료 관련 상태" (Done) 전이 — gh project item-edit
#      (환경변수 LOOP_PROJECT_ID·LOOP_STATUS_FIELD_ID·LOOP_STATUS_DONE_OPTION_ID 부재 시
#       무음 skip하여 phase 자체는 계속 진행)
#   6. 어떤 단계가 비-zero exit이면 stdout에 "ESCALATION cleanup-phase: ..." emit
#      후 비-zero exit (SPEC 123 AC19).

set -euo pipefail

WT="${1:-}"
BRANCH="${2:-}"
TASK_ID="${3:-}"
PROJECT_ROOT="${4:-}"

if [[ -z "$WT" || -z "$BRANCH" || -z "$TASK_ID" || -z "$PROJECT_ROOT" ]]; then
  echo "사용: $0 <worktree> <branch> <task-id> <project-root>" >&2
  exit 2
fi

emit_escalation() { echo "ESCALATION cleanup-phase: $*"; }

[[ -d "$WT" ]] || { emit_escalation "워크트리 없음: $WT"; exit 1; }
[[ -d "$PROJECT_ROOT" ]] || { emit_escalation "project-root 없음: $PROJECT_ROOT"; exit 1; }

# ----- 1. 미커밋 변경 사전 검사 (위험: cleanup 손실 차단) -----
# 워크트리에 staged·unstaged·untracked가 남아 있으면 worktree remove 시 손실 위험.
# untracked는 본 task의 .iterations/·CLAUDE.md·DONE 등 info/exclude로 가려져 있어
# 보통 status에 안 나타난다. 그래도 safety-net으로 staged·unstaged만 검사.
dirty=$( cd "$WT" && git status --porcelain --untracked-files=no 2>/dev/null || true )
if [[ -n "$dirty" ]]; then
  emit_escalation "워크트리에 미커밋 변경 있음 — cleanup 거부\n$dirty"
  exit 1
fi

# ----- 2. worktree remove -----
# autopilot 워크트리는 info/exclude된 ephemeral 파일(.iterations/·DONE·CLAUDE.md)을
# 항상 보유한다. 위 사전 검사로 staged/unstaged 변경 부재를 이미 확인했으므로
# --force로 ephemeral 파일도 함께 정리. (사용자 수기 변경은 untracked로 들어와도
# `--untracked-files=no`를 통과하므로 사전 검사가 catch하지 못함. 사용자가 워크트리
# 안에 임시 파일을 둔 경우 --force는 그것까지 삭제 — 본 phase는 PR merged 후 호출되므로
# 정상 흐름에선 사용자가 워크트리에 별도 작업을 두지 않는다는 가정.)
echo "[cleanup-phase] git worktree remove --force $WT"
if ! ( cd "$PROJECT_ROOT" && git worktree remove --force "$WT" 2>&1 ); then
  emit_escalation "git worktree remove 실패 — 수동: git worktree remove --force $WT"
  exit 1
fi

# ----- 3. 로컬 feat 브랜치 삭제 -----
echo "[cleanup-phase] git branch -D $BRANCH"
if ! ( cd "$PROJECT_ROOT" && git branch -D "$BRANCH" 2>&1 ); then
  emit_escalation "로컬 브랜치 삭제 실패: $BRANCH"
  exit 1
fi

# ----- 4. origin feat 브랜치 삭제 -----
echo "[cleanup-phase] git push --delete origin $BRANCH"
if ! ( cd "$PROJECT_ROOT" && git push --delete origin "$BRANCH" 2>&1 ); then
  # 원격 삭제 실패는 보통 이미 삭제됐거나 네트워크 일시 — escalation 아닌 WARN.
  echo "WARN: origin/$BRANCH 삭제 실패 (이미 삭제됐거나 네트워크 오류). 수동 확인 필요." >&2
fi

# ----- 5. 추상 상태 'Done' 전이 (gh project item-edit) -----
# 구체 값·매핑은 rules/context.md 단일 출처에 의존. 환경 변수로 주입.
#   LOOP_PROJECT_ID         GitHub Project node ID (예: PVT_xxx)
#   LOOP_STATUS_FIELD_ID    Status single-select field node ID
#   LOOP_STATUS_DONE_OPTION_ID  "Done" option ID
#   LOOP_PROJECT_ITEM_ID    이 task가 추가된 project item ID (issue → item)
# 위 4 변수가 모두 set일 때만 호출. 하나라도 부재면 무음 skip.
if command -v gh >/dev/null 2>&1 \
   && [[ -n "${LOOP_PROJECT_ID:-}" && -n "${LOOP_STATUS_FIELD_ID:-}" \
         && -n "${LOOP_STATUS_DONE_OPTION_ID:-}" && -n "${LOOP_PROJECT_ITEM_ID:-}" ]]; then
  echo "[cleanup-phase] 상태 전이: Done (gh project item-edit)"
  if ! gh project item-edit \
       --project-id "$LOOP_PROJECT_ID" \
       --id "$LOOP_PROJECT_ITEM_ID" \
       --field-id "$LOOP_STATUS_FIELD_ID" \
       --single-select-option-id "$LOOP_STATUS_DONE_OPTION_ID" >/dev/null 2>&1; then
    echo "WARN: 상태 전이(Done) 실패 — 수동 처리 필요" >&2
  fi
else
  echo "[cleanup-phase] 상태 전이 환경변수 부재 — Done 전이 skip (rules/context.md 백엔드 비활성)"
fi

echo "[cleanup-phase] 정리 완료: task=$TASK_ID branch=$BRANCH"
exit 0
