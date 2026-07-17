#!/usr/bin/env bash
# gitlab.sh — forge 어댑터 gitlab 구현 (MR, glab). **v1 미구현 확장점.**
# origin 이 gitlab 이면 forge.sh 가 이 파일을 source 해 fg_<verb> 를 호출하지만,
# v1 에서는 glab 기반 MR 생성·리뷰·머지가 미구현이라 명확히 안내 후 비-0 exit 한다(조용한 실패 금지).
#
# 기여 지점(구현 시 forge 추상화를 glab 으로 확장):
#   fg_integrate → glab mr create / push
#   fg_review    → glab mr 리뷰 fetch + 승인 게이트
#   fg_merge     → glab mr merge (ff-only)

_gl_unimplemented() {
  echo "forge(gitlab): GitLab MR 경로는 v1 미구현 확장점입니다 (forge/gitlab.sh)." >&2
  echo "  - 임시 회피: origin 을 제거/변경해 direct(로컬 review) 경로를 쓰거나, github 원격을 사용하세요." >&2
  echo "  - 구현 기여: glab 기반 mr create/review/merge 를 fg_integrate/fg_review/fg_merge 에 추가." >&2
  exit 3
}

fg_integrate() { _gl_unimplemented; }
fg_review()    { _gl_unimplemented; }
fg_merge()     { _gl_unimplemented; }
