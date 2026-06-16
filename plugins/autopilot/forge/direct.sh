#!/usr/bin/env bash
# direct.sh — forge 어댑터 direct 구현 (origin 없음: 로컬 review + ff-only 직접 머지).
# dispatch 워커 헬퍼의 -direct 경로를 감싸 재사용. forge.sh 가 source. FG_REF = dispatch references.

fg_integrate() {  # <spec> <run_dir> <key>
  bash "$FG_REF/integration.sh" integrate-direct "$@"
}
fg_review() {     # <run_dir> <key> <spec> [pr] [branch]  (pr 는 direct 에서 무시)
  local run_dir="$1" key="$2" spec="$3" branch="${5:-}"
  bash "$FG_REF/review-loop.sh" run-direct "$run_dir" "$key" "$spec" "$branch"
}
fg_merge() {      # <spec> <run_dir> <key> [pr]  → direct ff-only (pr 없이 direct=1)
  local spec="$1" run_dir="$2" key="$3"
  bash "$FG_REF/merge.sh" finish "$spec" "$run_dir" "$key" "" 1
}
