#!/usr/bin/env bash
# test-lease-reclaim.sh — in_progress + stale lease 가 list_ready 로 회수되는지 검증(filesystem).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
A="$HERE/../adapter.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q; git config user.email t@t; git config user.name t
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }

# ttl 을 짧게 (2초) 둔 config
bash "$A" init --backend filesystem >/dev/null
jq '.lease_ttl_seconds=2' .autopilot/task-backend.json > c && mv c .autopilot/task-backend.json

id="$(bash "$A" create_task --title "Lease" --body "## 목표"$'\n'"x" | jq -r .task_id)"
bash "$A" set_status --task-id "$id" --status in_progress >/dev/null

# 신선한 lease → list_ready 에서 제외
r="$(bash "$A" list_ready | jq -r '.[].task_id' | tr '\n' ' ')"
[[ "$r" != *"$id"* ]] && ok "신선 lease 제외" || bad "신선 lease 제외 (got '$r')"

# heartbeat 갱신 후에도 제외
bash "$A" renew_lease --task-id "$id" >/dev/null
r="$(bash "$A" list_ready | jq -r '.[].task_id' | tr '\n' ' ')"
[[ "$r" != *"$id"* ]] && ok "renew 후 제외" || bad "renew 후 제외 (got '$r')"

# ttl 초과 → 회수(ready)
sleep 3
r="$(bash "$A" list_ready | jq -r '.[].task_id' | tr '\n' ' ')"
[[ "$r" == *"$id"* ]] && ok "stale lease 회수" || bad "stale lease 회수 (got '$r')"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
