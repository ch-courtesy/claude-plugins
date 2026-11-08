#!/bin/sh
# Rebuild the lantern from plan_steps.py, review it and score the modeling stage.
# usage: sh work/lantern/build.sh "what changed"   (from the project root)
M="py -3 .claude/skills/mesh-session/scripts/mesh.py"
D=work/lantern
rm -rf "$D/steps" "$D/snaps" "$D/session.json" "$D/log.jsonl" "$D/fidelity" "$D/report" "$D/review" "$D/uv" "$D/texture" "$D/export"
py -3 "$D/plan_steps.py" > "$D/steps.jsonl"
$M "$D" run "$D/steps.jsonl" --strict | grep -vE "checks: ok|^\[meshop\] [0-9]"
$M "$D" finish --tier pc --res 900 --samples 64 --asymmetric | grep -E "ERROR|Traceback|warnings:|^\[inspect\]   "
$M "$D" fidelity fidelity/concept_lantern --see-through Glass | grep -E "materials"
$M "$D" gate modeling --note "$1"
sed -n '10,19p' "$D/fidelity/compare.md"
sed -n '/Largest gaps/,$p' "$D/fidelity/compare.md" | sed -n '4,12p'
