#!/usr/bin/env bash
# github.sh — forge 어댑터 github 구현 (PR, gh). dispatch 워커 헬퍼를 감싸 재사용.
# forge.sh 가 source 해 fg_<verb> 를 호출. FG_REF = dispatch references 경로.

fg_integrate() {  # <spec> <run_dir> <key>
  bash "$FG_REF/integration.sh" integrate "$@"
}
fg_review() {     # <run_dir> <key> <spec> <pr> [branch] → rl_round 반환코드 그대로(0/10/20/30)
  # `round`(rl_round 직접)를 호출해 반환코드를 표면화한다. `run`(rl_review_loop)은 0/10/20/30 을
  # 전부 return 0 으로 collapse 하므로 단일 동기 드라이버(execute-task)가 분기할 수 없다(#426).
  # execute-task PR 경로가 30=approve / 0=재작업 재푸시 / 10=에스컬레이션·상한·핑퐁 / 20=대기 로 분기.
  # branch 영속화는 integrate(integration.sh int_set_branch)가 이미 수행 → merge 의 int_get_branch 불변.
  bash "$FG_REF/review-loop.sh" round "$@"
}
fg_merge() {      # <spec> <run_dir> <key> [pr]
  bash "$FG_REF/merge.sh" finish "$@"
}
