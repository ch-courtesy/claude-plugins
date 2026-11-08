#!/bin/sh
# Every stage of the lamp-keeper from the plan, with its gate. From the project root.
# Needs work/lantern built first. D=<folder> rebuilds a copy instead. Rendered frames are not remade.
M="py -3 .claude/skills/mesh-session/scripts/mesh.py"
D=${D:-work/lampkeeper}
C=fidelity/concept_lampkeeper
MAP="--map Brass=buckle --map Sole=boots --map Cuff=boots"
rm -rf "$D/uv" "$D/texture" "$D/export" "$D/motions" "$D/anim"
sh "$D/build.sh" "full pipeline run" | grep -E "gate\] modeling|FAIL|ERROR|stopped"
$M "$D" rig "$D/rig.json" | grep -E "Traceback|Error"
$M "$D" gate rigging --note "full pipeline run" | grep -E "gate\] rigging|FAIL"
$M "$D" uv | grep -E "Traceback|Error"
$M "$D" gate uv --note "full pipeline run" | grep -E "gate\] uv|FAIL"
$M "$D" texture "$C" $MAP | grep -E "Traceback|Error"
$M "$D" gate texture --note "full pipeline run" | grep -E "gate\] texture|FAIL"
for x in walk:walk.json:motion_walk idle:motions_spec/idle.json:motion_idle wave:motions_spec/wave.json:motion_action \
         raise_lantern:motions_spec/raise_lantern.json:motion_action; do
  m=${x%%:*}; y=${x#*:}; spec=${y%%:*}; g=${y##*:}
  $M "$D" animate "$D/$spec" "$D/rig.json" | grep -E "Traceback|Error:"
  $M "$D" gate animation --anim "motions/$m" --note "full pipeline run" | grep -E "gate\] animation|FAIL"
  $M "$D" gate "$g" --anim "motions/$m" --note "full pipeline run" | grep -E "gate\] motion|FAIL"
  $M "$D" propcheck "motions/$m" "$D/carry.json" | grep -E "Traceback|\[prop\]"
  $M "$D" gate prop_contact --anim "motions/$m" --note "full pipeline run" | grep -E "gate\] prop|FAIL"
done
$M "$D" glb --spec "$D/rig.json" --concept "$C" $MAP | grep -E "Traceback|Error|check_glb"
$M "$D" gate export --note "full pipeline run" | grep -E "gate\] export|FAIL"
$M "$D" unreal | grep -E "Traceback|\[unreal\]"
$M "$D" gate engine_unreal --note "full pipeline run" | grep -E "gate\] engine|FAIL"
