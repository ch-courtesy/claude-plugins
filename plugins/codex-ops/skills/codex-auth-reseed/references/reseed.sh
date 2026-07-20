#!/usr/bin/env bash
# reseed.sh — Codex CI 인증 시크릿(기본 CODEX_AUTH_JSON) 격리 재시드 도구.
#
# 격리된 일회용 docker 컨테이너에서 `codex login --device-auth` 로 새 auth.json 을 발급받아
# GitHub Actions 리포 시크릿을 갱신한다. host 의 ~/.codex/auth.json(다른 소비자가 쓰는 시드)은
# 마운트하지 않아 무접촉이다. 컨테이너는 host 네트워크로 띄운다 — bridge 네트워크에서 IPv6
# egress 가 끊긴 환경이면 codex(자체 DNS 리졸버)가 IPv6 를 골라 실패하는데, gai.conf 나
# /etc/hosts 로는 우회가 안 된다(둘 다 무시함).
#
# 서브커맨드:
#   setup     컨테이너 기동 + codex 설치 + device-auth 시작. 인증 URL·코드를 stdout 에 출력.
#   complete  auth.json 이 나올 때까지 폴링 → 구조 검증 → gh secret set → 컨테이너 파기.
#   status    현재 login 출력/auth.json 존재 여부 표시.
#   abort     컨테이너·잔여물 파기(취소·정리).
#
# 환경변수(선택):
#   RESEED_REPO       대상 repo "owner/name" (기본: gh 현재 repo)
#   RESEED_SECRET     시크릿 이름 (기본: CODEX_AUTH_JSON)
#   RESEED_IMAGE      컨테이너 이미지 (기본: node:22-slim)
#   RESEED_CONTAINER  컨테이너 이름 (기본: codex-reseed)
#   RESEED_TIMEOUT    complete 폴링 최대 초 (기본: 840 = 14분, device code 만료 대비)
set -euo pipefail

REPO="${RESEED_REPO:-}"
SECRET="${RESEED_SECRET:-CODEX_AUTH_JSON}"
IMAGE="${RESEED_IMAGE:-node:22-slim}"
C="${RESEED_CONTAINER:-codex-reseed}"
TIMEOUT="${RESEED_TIMEOUT:-840}"
CODEX_HOME_IN=/reseed   # 컨테이너 내부 격리 CODEX_HOME

die() { echo "reseed: $*" >&2; exit 1; }

resolve_repo() {
  [[ -n "$REPO" ]] && { echo "$REPO"; return; }
  gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null \
    || die "대상 repo 를 알 수 없음 — RESEED_REPO=owner/name 로 지정"
}

require() {
  command -v docker >/dev/null 2>&1 || die "docker 필요(미설치)"
  command -v gh     >/dev/null 2>&1 || die "gh 필요(미설치)"
  command -v jq     >/dev/null 2>&1 || die "jq 필요(미설치)"
  gh auth status >/dev/null 2>&1 || die "gh 미인증 — gh auth login 필요"
}

cmd_setup() {
  require
  local repo; repo="$(resolve_repo)"
  echo "reseed setup: repo=$repo secret=$SECRET image=$IMAGE container=$C"

  # 잔여 컨테이너 정리(멱등)
  docker rm -f "$C" >/dev/null 2>&1 || true
  # host ~/.codex 는 마운트하지 않음 → 무접촉. 격리 CODEX_HOME 은 컨테이너 내부.
  # --network host: bridge 에서 IPv6 egress 단절 시 codex 가 실패하는 문제 회피(헤더 주석 참조).
  docker run -d --name "$C" --network host -e CODEX_HOME="$CODEX_HOME_IN" "$IMAGE" sleep 3600 >/dev/null \
    || die "컨테이너 기동 실패"

  echo "codex CLI 설치 중(npm + ca-certificates)..."
  docker exec "$C" sh -c "mkdir -p $CODEX_HOME_IN && npm i -g @openai/codex >/tmp/npm.log 2>&1" \
    || { docker exec "$C" sh -c 'tail -20 /tmp/npm.log' >&2 || true; die "codex 설치 실패"; }

  # codex 는 rustls 로 TLS 를 검증하는데 node:*-slim 은 시스템 CA 스토어(/etc/ssl/certs)가
  # 비어 있어 'error sending request' 로 실패한다(node 자체는 내장 CA 라 멀쩡해 보임).
  docker exec "$C" sh -c 'test -e /etc/ssl/certs/ca-certificates.crt \
      || { apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq ca-certificates >/dev/null 2>&1; }' \
    || die "ca-certificates 설치 실패"

  # device-auth 를 백그라운드로 시작 → login.out 에 URL·코드가 쓰인다.
  docker exec "$C" sh -c "rm -f $CODEX_HOME_IN/login.out; codex login --device-auth > $CODEX_HOME_IN/login.out 2>&1 &"

  # URL·코드가 나올 때까지 짧게 대기(최대 ~40초)
  local i
  for i in $(seq 1 20); do
    if docker exec "$C" sh -c "grep -q 'auth.openai.com' $CODEX_HOME_IN/login.out 2>/dev/null"; then
      echo "----- device-auth (사용자 인증 필요) -----"
      docker exec "$C" sh -c "cat $CODEX_HOME_IN/login.out"
      echo "------------------------------------------"
      echo "위 URL 을 브라우저에서 열고 코드를 입력해 인증한 뒤, complete 서브커맨드를 실행하세요."
      return 0
    fi
    if docker exec "$C" sh -c "grep -qiE 'error|failed' $CODEX_HOME_IN/login.out 2>/dev/null"; then
      docker exec "$C" sh -c "cat $CODEX_HOME_IN/login.out" >&2
      die "device-auth 시작 실패(위 출력 참조)"
    fi
    sleep 2
  done
  die "device-auth URL·코드를 얻지 못함(타임아웃) — status 로 확인"
}

cmd_complete() {
  require
  local repo; repo="$(resolve_repo)"
  docker ps --filter "name=^${C}$" --format '{{.Names}}' | grep -q "$C" \
    || die "컨테이너 '$C' 가 없음 — 먼저 setup 실행"

  echo "인증 완료 대기(폴링, 최대 ${TIMEOUT}s)..."
  local waited=0
  while (( waited < TIMEOUT )); do
    if docker exec "$C" sh -c "test -s $CODEX_HOME_IN/auth.json"; then
      break
    fi
    if docker exec "$C" sh -c "grep -qiE 'error|expired|failed' $CODEX_HOME_IN/login.out 2>/dev/null"; then
      docker exec "$C" sh -c "tail -3 $CODEX_HOME_IN/login.out" >&2
      die "로그인 실패/만료(위 출력 참조) — abort 후 재시도"
    fi
    sleep 10; waited=$((waited+10))
  done
  docker exec "$C" sh -c "test -s $CODEX_HOME_IN/auth.json" || die "auth.json 미생성(타임아웃)"

  # 토큰 값은 출력하지 않는다. umask 077 임시 파일로 추출 후 검증.
  local tmp; tmp="$(mktemp)"; chmod 600 "$tmp"
  # shellcheck disable=SC2064
  trap "shred -u '$tmp' 2>/dev/null || rm -f '$tmp'" RETURN
  docker exec "$C" sh -c "cat $CODEX_HOME_IN/auth.json" > "$tmp"

  jq -e '(.tokens.access_token // .access_token) and (.tokens.refresh_token // .refresh_token)' "$tmp" >/dev/null \
    || die "auth.json 구조 이상(access/refresh token 누락) — abort 후 재시도"
  echo "auth.json 검증 OK (account_id=$(jq -r '.tokens.account_id // .account_id // "n/a"' "$tmp"))"

  echo "시크릿 갱신: $SECRET @ $repo"
  gh secret set "$SECRET" -R "$repo" < "$tmp" || die "gh secret set 실패 — 토큰의 secrets 쓰기 권한 확인"
  echo "SECRET_UPDATED_OK"

  docker rm -f "$C" >/dev/null 2>&1 || true
  echo "컨테이너 파기 완료. host ~/.codex 무접촉."
}

cmd_status() {
  if docker ps -a --filter "name=^${C}$" --format '{{.Names}}' | grep -q "$C"; then
    echo "container: 존재"
    docker exec "$C" sh -c "test -s $CODEX_HOME_IN/auth.json" && echo "auth.json: 준비됨" || echo "auth.json: 대기중"
    echo "--- login.out ---"; docker exec "$C" sh -c "cat $CODEX_HOME_IN/login.out 2>/dev/null || echo '(없음)'"
  else
    echo "container: 없음(setup 전 또는 정리됨)"
  fi
}

cmd_abort() {
  docker rm -f "$C" >/dev/null 2>&1 && echo "컨테이너 파기 완료" || echo "파기할 컨테이너 없음"
}

case "${1:-}" in
  setup)    cmd_setup ;;
  complete) cmd_complete ;;
  status)   cmd_status ;;
  abort)    cmd_abort ;;
  *) die "usage: reseed.sh {setup|complete|status|abort}" ;;
esac
