#!/bin/sh
# Rebuild the lamp-keeper from plan_steps.py, review it and score the modeling stage.
# usage: sh work/lampkeeper/build.sh "what changed"   (from the project root)
M="py -3 .claude/skills/mesh-session/scripts/mesh.py"
D=${D:-work/lampkeeper}
rm -rf "$D/steps" "$D/snaps" "$D/session.json" "$D/log.jsonl" "$D/fidelity" "$D/report" "$D/review" "$D/rig"
py -3 "$D/plan_steps.py" > "$D/steps.jsonl"
$M "$D" run "$D/steps.jsonl" --strict | grep -vE "checks: ok|^\[meshop\] [0-9]"
$M "$D" finish --tier pc --res 900 --samples 64 | grep -E "ERROR|Traceback|warnings:"
$M "$D" fidelity fidelity/concept_lampkeeper --map Brass=buckle --map Sole=boots --map Cuff=boots | grep -E "materials"
$M "$D" gate modeling --note "$1"
sed -n '10,22p' "$D/fidelity/compare.md"
