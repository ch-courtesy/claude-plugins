#!/bin/sh
# Every stage of the lantern from the plan, with its gate. From the project root.
M="py -3 .claude/skills/mesh-session/scripts/mesh.py"
D=work/lantern
C=fidelity/concept_lantern
sh "$D/build.sh" "full pipeline run" | grep -E "gate\] modeling|FAIL|ERROR|stopped"
$M "$D" uv | grep -E "Traceback|Error"
$M "$D" gate uv --note "full pipeline run" | grep -E "gate\] uv|FAIL"
$M "$D" texture "$C" --keep Glass --see-through Glass --emit Flame --turn --ink-facing 0.54 | grep -E "Traceback|Error"
$M "$D" gate texture_prop --note "full pipeline run" | grep -E "gate\] texture|FAIL"
$M "$D" glb --height 0.32 --concept "$C" --see-through Glass | grep -E "Traceback|Error|check_glb"
$M "$D" gate export_prop --note "full pipeline run" | grep -E "gate\] export|FAIL"
