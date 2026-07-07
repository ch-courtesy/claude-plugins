#!/usr/bin/env bash
# forge.sh — autopilot forge 어댑터 라우터 (origin 호스트 → github/gitlab/direct)
#
# 책임:
#   - `git remote get-url origin` 으로 호스트를 판정해 review→머지 단계를 라우팅.
#   - 동사(integrate/review/merge) 를 호스트 구현(fg_<verb>)으로 위임. 계약: contract.md.
#
# 하지 않는 일:
#   - rules/ 지침·다른 스킬 doc 참조. (런타임 헬퍼는 형제 lib/ 를 감싸 재사용.)
set -euo pipefail

FG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fg_die() { echo "forge: $*" >&2; exit 1; }

# 감지: cwd 의 git origin 으로 호스트 분류
fg_host() {
  local url; url="$(git remote get-url origin 2>/dev/null || true)"
  case "$url" in
    "")                              echo direct;;
    *github.com*)                    echo github;;
    # gitlab.com 또는 gitlab.* 호스트만 — `my-gitlab-backup.example.com` 같은 오탐 회피
    *gitlab.com*|*://gitlab.*|*@gitlab.*) echo gitlab;;
    *)                               echo direct;;
  esac
}

fg_load() {
  local host; host="$(fg_host)"
  local impl="$FG_DIR/$host.sh"
  [[ -f "$impl" ]] || fg_die "forge 구현 없음: $impl"
  FG_HOST="$host"
  # 통합/리뷰/머지 엔진 헬퍼 경로 — **스크립트 위치 기준**으로 계산(설치형 플러그인 호환).
  # 소비 프로젝트 git 루트 아래를 가정하지 않는다(forge/ 의 하위 lib/).
  FG_REF="$FG_DIR/lib"
  # shellcheck disable=SC1090
  source "$impl"
}

main() {
  local verb="${1:-}"; shift || true
  case "$verb" in
    host)     fg_host;;
    selftest) fg_selftest;;
    integrate|review|merge) fg_load; "fg_$verb" "$@";;
    ""|-h|--help|help)
      echo "usage: forge.sh <integrate|review|merge|host|selftest> [args]" >&2; exit 2;;
    *) fg_die "알 수 없는 동사: $verb";;
  esac
}

# ----- selftest: origin url 별 호스트 판정 검증 (임시 repo) -----
fg_selftest() {
  local TMP; TMP="$(mktemp -d)"; local fail=0
  ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
  chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }
  mk(){ rm -rf "$TMP/r"; mkdir -p "$TMP/r"; ( cd "$TMP/r" && git init -q && [[ -n "$1" ]] && git remote add origin "$1" || true ); }
  mk "";                                   chk "origin 없음→direct"  "$(cd "$TMP/r" && bash "$FG_DIR/forge.sh" host)" "direct"
  mk "https://github.com/o/r.git";         chk "github https→github" "$(cd "$TMP/r" && bash "$FG_DIR/forge.sh" host)" "github"
  mk "git@github.com:o/r.git";             chk "github ssh→github"   "$(cd "$TMP/r" && bash "$FG_DIR/forge.sh" host)" "github"
  mk "https://gitlab.com/o/r.git";         chk "gitlab→gitlab"       "$(cd "$TMP/r" && bash "$FG_DIR/forge.sh" host)" "gitlab"
  mk "https://gitlab.example.org/o/r.git"; chk "self-hosted gitlab"  "$(cd "$TMP/r" && bash "$FG_DIR/forge.sh" host)" "gitlab"
  mk "https://bitbucket.org/o/r.git";      chk "미상→direct 폴백"     "$(cd "$TMP/r" && bash "$FG_DIR/forge.sh" host)" "direct"
  # gitlab 구현은 확장점: 호출 시 비-0
  if ( cd "$TMP" && bash "$FG_DIR/gitlab.sh" >/dev/null 2>&1 ); then :; fi
  rm -rf "$TMP"
  echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; return $fail
}

main "$@"
