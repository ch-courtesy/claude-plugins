#!/usr/bin/env bash
# github.sh — forge 어댑터 github 구현 (PR, gh). dispatch 워커 헬퍼를 감싸 재사용.
# forge.sh 가 source 해 fg_<verb> 를 호출. FG_REF = dispatch references 경로.

fg_integrate() {  # <spec> <run_dir> <key>
  bash "$FG_REF/integration.sh" integrate "$@"
}
fg_review() {     # <run_dir> <key> <spec> [pr] [branch]
  bash "$FG_REF/review-loop.sh" run "$@"
}
fg_merge() {      # <spec> <run_dir> <key> [pr]
  bash "$FG_REF/merge.sh" finish "$@"
}
