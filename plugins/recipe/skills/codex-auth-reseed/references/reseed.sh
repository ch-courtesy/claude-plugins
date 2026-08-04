#!/usr/bin/env bash
# reseed.sh — Codex CI 인증 시크릿(기본 CODEX_AUTH_JSON) 격리 재시드 도구.
#
# 임시 CODEX_HOME 디렉터리에서 `codex login --device-auth` 로 새 auth.json 을 발급받아
# GitHub Actions 리포 시크릿을 갱신한다. codex 는 인증 상태를 $CODEX_HOME 아래에만 쓰므로
# host 의 ~/.codex/auth.json(다른 소비자가 쓰는 시드)은 무접촉이다. 컨테이너 불필요 —
# host 네트워크·CA 스토어를 그대로 쓰므로 bridge IPv6 egress 단절이나 slim 이미지
# ca-certificates 부재 같은 컨테이너 유발 문제가 애초에 없다.
#
# 서브커맨드:
#   setup     격리 CODEX_HOME 생성 + device-auth 시작. 인증 URL·코드를 stdout 에 출력.
#   complete  auth.json 이 나올 때까지 폴링 → 구조 검증 → gh secret set → 격리 디렉터리 파기.
#   status    현재 login 출력/auth.json 존재 여부 표시.
#   abort     로그인 프로세스·격리 디렉터리 파기(취소·정리).
#
# 환경변수(선택):
#   RESEED_REPO       대상 repo "owner/name" (기본: gh 현재 repo)
#   RESEED_SECRET     시크릿 이름 (기본: CODEX_AUTH_JSON)
#   RESEED_HOME       격리 CODEX_HOME 겸 상태 디렉터리 (기본: ${TMPDIR:-/tmp}/codex-reseed)
#   RESEED_TIMEOUT    complete 폴링 최대 초 (기본: 840 = 14분, device code 만료 대비)
set -euo pipefail

REPO="${RESEED_REPO:-}"
SECRET="${RESEED_SECRET:-CODEX_AUTH_JSON}"
if [[ -n "${RESEED_HOME:-}" ]]; then
  STATE="$RESEED_HOME"
else
  _tmp="${TMPDIR:-/tmp}"
  STATE="${_tmp%/}/codex-reseed"
fi
TIMEOUT="${RESEED_TIMEOUT:-840}"

die() { echo "reseed: $*" >&2; exit 1; }

resolve_repo() {
  [[ -n "$REPO" ]] && { echo "$REPO"; return; }
  gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null \
    || die "대상 repo 를 알 수 없음 — RESEED_REPO=owner/name 로 지정"
}

# codex CLI: host 설치본 우선, 없으면 npx 일회 실행(글로벌 npm 무접촉).
codex_cmd() {
  if command -v codex >/dev/null 2>&1; then echo "codex"
  elif command -v npx >/dev/null 2>&1; then echo "npx -y @openai/codex"
  else die "codex 또는 npx(node) 필요(둘 다 미설치)"
  fi
}

require() {
  command -v gh >/dev/null 2>&1 || die "gh 필요(미설치)"
  command -v jq >/dev/null 2>&1 || die "jq 필요(미설치)"
  gh auth status >/dev/null 2>&1 || die "gh 미인증 — gh auth login 필요"
}

# 토큰 파일을 복구 불가능하게 지운다(shred 없으면 rm 폴백).
scrub() { shred -u "$1" 2>/dev/null || rm -f "$1"; }

teardown() {
  if [[ -f "$STATE/login.pid" ]]; then
    kill "$(cat "$STATE/login.pid")" 2>/dev/null || true
  fi
  [[ -f "$STATE/auth.json" ]] && scrub "$STATE/auth.json"
  rm -rf "$STATE"
}

cmd_setup() {
  require
  local codex; codex="$(codex_cmd)"
  local repo; repo="$(resolve_repo)"
  echo "reseed setup: repo=$repo secret=$SECRET home=$STATE"

  # 잔여 상태 정리(멱등) 후 소유자 전용 권한으로 격리 CODEX_HOME 생성.
  teardown
  (umask 077 && mkdir -p "$STATE")

  # device-auth 를 백그라운드로 시작 → login.out 에 URL·코드가 쓰인다.
  # CODEX_HOME 격리로 host ~/.codex 무접촉. nohup: 스크립트 종료 후에도 토큰 교환 폴링 유지.
  # $codex 는 의도적 미인용 — npx 폴백 시 다중 단어("npx -y @openai/codex").
  # shellcheck disable=SC2086
  CODEX_HOME="$STATE" nohup $codex login --device-auth > "$STATE/login.out" 2>&1 &
  echo $! > "$STATE/login.pid"

  # URL·코드가 나올 때까지 짧게 대기(최대 ~40초)
  for _ in $(seq 1 20); do
    if grep -q 'auth.openai.com' "$STATE/login.out" 2>/dev/null; then
      echo "----- device-auth (사용자 인증 필요) -----"
      cat "$STATE/login.out"
      echo "------------------------------------------"
      echo "위 URL 을 브라우저에서 열고 코드를 입력해 인증한 뒤, complete 서브커맨드를 실행하세요."
      return 0
    fi
    if grep -qiE 'error|failed' "$STATE/login.out" 2>/dev/null; then
      cat "$STATE/login.out" >&2
      die "device-auth 시작 실패(위 출력 참조)"
    fi
    sleep 2
  done
  die "device-auth URL·코드를 얻지 못함(타임아웃) — status 로 확인"
}

cmd_complete() {
  require
  local repo; repo="$(resolve_repo)"
  [[ -d "$STATE" ]] || die "격리 디렉터리 '$STATE' 가 없음 — 먼저 setup 실행"
  # EXIT 트랩: die(exit) 로 빠지는 실패 경로에서도 토큰 파일이 반드시 shred·파기되게 한다.
  trap teardown EXIT

  echo "인증 완료 대기(폴링, 최대 ${TIMEOUT}s)..."
  local waited=0
  while (( waited < TIMEOUT )); do
    [[ -s "$STATE/auth.json" ]] && break
    if grep -qiE 'error|expired|failed' "$STATE/login.out" 2>/dev/null; then
      tail -3 "$STATE/login.out" >&2
      die "로그인 실패/만료(위 출력 참조) — setup 부터 재시도"
    fi
    sleep 10; waited=$((waited+10))
  done
  [[ -s "$STATE/auth.json" ]] || die "auth.json 미생성(타임아웃) — setup 부터 재시도"

  # 토큰 값은 출력하지 않는다. auth.json 은 umask 077 격리 디렉터리 안에만 존재한다.
  jq -e '(.tokens.access_token // .access_token) and (.tokens.refresh_token // .refresh_token)' \
      "$STATE/auth.json" >/dev/null \
    || die "auth.json 구조 이상(access/refresh token 누락) — setup 부터 재시도"
  echo "auth.json 검증 OK (account_id=$(jq -r '.tokens.account_id // .account_id // "n/a"' "$STATE/auth.json"))"

  echo "시크릿 갱신: $SECRET @ $repo"
  gh secret set "$SECRET" -R "$repo" < "$STATE/auth.json" \
    || die "gh secret set 실패 — 토큰의 secrets 쓰기 권한 확인"
  echo "SECRET_UPDATED_OK"

  teardown
  echo "격리 디렉터리 파기 완료. host ~/.codex 무접촉."
}

cmd_status() {
  if [[ -d "$STATE" ]]; then
    echo "state: 존재 ($STATE)"
    [[ -s "$STATE/auth.json" ]] && echo "auth.json: 준비됨" || echo "auth.json: 대기중"
    echo "--- login.out ---"; cat "$STATE/login.out" 2>/dev/null || echo "(없음)"
  else
    echo "state: 없음(setup 전 또는 정리됨)"
  fi
}

cmd_abort() {
  if [[ -d "$STATE" ]]; then teardown; echo "격리 디렉터리 파기 완료"
  else echo "파기할 상태 없음"
  fi
}

case "${1:-}" in
  setup)    cmd_setup ;;
  complete) cmd_complete ;;
  status)   cmd_status ;;
  abort)    cmd_abort ;;
  *) die "usage: reseed.sh {setup|complete|status|abort}" ;;
esac
