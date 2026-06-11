#!/usr/bin/env bash
# flow — CLI runner for the Workflow Replica engine (autopilot:flow skill).
#
# Subcommands (only these are executed; unknown ones error out):
#   run <workflow-definition.py>   Execute a workflow definition; emit a single
#                                  JSON result on stdout (machine-readable).
#   selftest                       Run the engine's own test suite; emit a JSON
#                                  summary {tests, ok} on stdout.
#   deps                           Report the runtime dependency (python3) and
#                                  whether it is available.
#
# Standard-library only: needs python3 (3.9+). No external packages, no network,
# no built-in Workflow tool — this is the replacement for when that tool is
# unavailable.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${FLOW_PYTHON:-python3}"

die() { printf '%s\n' "$*" >&2; exit 2; }

cmd="${1:-}"
case "$cmd" in
  run)
    shift
    [ "$#" -ge 1 ] || die "usage: flow.sh run <workflow-definition.py>"
    exec "$PY" "$HERE/runner.py" run "$1"
    ;;
  selftest)
    # Run the engine test suite from the references dir so `workflow_replica`
    # is importable, and summarize the result as JSON.
    out="$(cd "$HERE" && "$PY" -m unittest discover -s tests -p 'test_*.py' 2>&1)" && rc=0 || rc=$?
    ran="$(printf '%s\n' "$out" | sed -n 's/^Ran \([0-9]*\) test.*/\1/p' | tail -1)"
    if [ "$rc" -eq 0 ]; then
      printf '{"ok": true, "tests": %s}\n' "${ran:-0}"
    else
      printf '{"ok": false, "tests": %s}\n' "${ran:-0}"
      printf '%s\n' "$out" >&2
      exit 1
    fi
    ;;
  deps)
    if command -v "$PY" >/dev/null 2>&1; then
      printf '{"python3": "%s", "available": true}\n' "$("$PY" --version 2>&1)"
    else
      printf '{"python3": null, "available": false}\n'; exit 1
    fi
    ;;
  ""|-h|--help)
    die "usage: flow.sh <run|selftest|deps> [args]"
    ;;
  *)
    die "unknown subcommand: $cmd (use: run|selftest|deps)"
    ;;
esac
