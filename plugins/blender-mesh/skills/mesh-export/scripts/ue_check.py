"""Runs inside Unreal Editor (see unreal_session.py). Config comes from MESH_UE_CONFIG.

Brings the GLB in, lists what arrived and reads each action's joints from the asset. With a weapon
(config "prop"), its own GLB comes in as a static mesh: its axes in the engine are found by matching
its bounding box to the file's, and on every sampled pose its point, carried by the socket joint, is
measured against the marker joint. Then puts the character in the level with the weapon attached to
the socket, renders its albedo, starts a Play session, and plays each action on the running component,
reading bones back from it and taking a picture. The editor world does not tick
without a viewport, so a component there never leaves its rest pose: only a game world proves it.
"""
import json
import math
import os
import time
import traceback

import unreal


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


C = read_json(os.environ["MESH_UE_CONFIG"], encoding="utf-8")
OUT, DEST = C["out"], C["dest"]
eal = unreal.EditorAssetLibrary


def ue_name(bone):
    return bone.replace(".", "_")


def assets():
    return {p: eal.load_asset(p) for p in eal.list_assets(DEST, recursive=True)}


def find_action(found, name):
    for a in found.values():
        if isinstance(a, unreal.AnimSequence) and a.get_name().endswith(name):
            return a
    return None


def quat_of(m):
    """A rotation matrix (column vectors, v' = m v) as quaternion x, y, z, w."""
    tr = m[0][0] + m[1][1] + m[2][2]
    if tr > 0:
        s = (tr + 1) ** 0.5 * 2
        return [(m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s, s / 4]
    i = max(range(3), key=lambda k: m[k][k])
    j, k = (i + 1) % 3, (i + 2) % 3
    s = (1 + m[i][i] - m[j][j] - m[k][k]) ** 0.5 * 2
    q = [0.0, 0.0, 0.0, (m[k][j] - m[j][k]) / s]
    q[i], q[j], q[k] = s / 4, (m[j][i] + m[i][j]) / s, (m[k][i] + m[i][k]) / s
    return q


def import_phase():
    if eal.does_directory_exist(DEST):
        eal.delete_directory(DEST)
    task = unreal.AssetImportTask()
    for key, value in (("filename", C["glb"]), ("destination_path", DEST), ("automated", True), ("save", True),
                       ("replace_existing", True)):
        task.set_editor_property(key, value)
    unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
    found = assets()
    meshes = [a for a in found.values() if isinstance(a, unreal.SkeletalMesh)]
    instances = [a for a in found.values() if isinstance(a, unreal.MaterialInstanceConstant)]
    R = {"engine": unreal.SystemLibrary.get_engine_version(), "skeletal_meshes": len(meshes),
         "textures": sum(isinstance(a, unreal.Texture2D) for a in found.values()), "materials": len(instances),
         "materials_untextured": sum(1 for m in instances if not [
             v for v in m.get_editor_property("texture_parameter_values") if v.get_editor_property("parameter_value")]),
         "actions": {}}
    if meshes:
        R["mesh_path"] = meshes[0].get_path_name()
        R["height_m"] = meshes[0].get_bounds().box_extent.z * 2 / 100
        skeleton = meshes[0].get_editor_property("skeleton")
        R["skeleton"] = skeleton.get_name()
    parents = C["parents"]
    P, tip, worst = C.get("prop"), None, 0.0
    if P:
        task = unreal.AssetImportTask()
        for key, value in (("filename", P["glb"]), ("destination_path", DEST + "/Prop"), ("automated", True),
                           ("save", True), ("replace_existing", True)):
            task.set_editor_property(key, value)
        unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
        props = [a for a in assets().values() if isinstance(a, unreal.StaticMesh)]
        R["weapon"] = {"static_meshes": len(props)}
        if props:
            R["weapon_mesh"] = props[0].get_path_name()
            box = props[0].get_bounding_box()
            lo, hi = [box.min.x, box.min.y, box.min.z], [box.max.x, box.max.y, box.max.z]
            glo, ghi = [100 * v for v in P["box_gltf"][0]], [100 * v for v in P["box_gltf"][1]]
            axes, fit = [], 0.0
            for i in range(3):                         # which file axis, and which way, each engine axis is
                best = min(((abs(lo[i] - s * (glo[j] if s > 0 else ghi[j])) + abs(hi[i] - s * (ghi[j] if s > 0 else glo[j])), j, s)
                            for j in range(3) for s in (1, -1)))
                axes.append((best[1], best[2]))
                fit = max(fit, best[0])
            R["weapon"].update({"axes": axes, "box_fit_cm": fit})
            if len({j for j, _ in axes}) == 3:
                tip = unreal.Vector(*[s * 100 * P["point_gltf"][j] for j, s in axes])
                # joints keep the file's axes, the mesh was turned to Z-up: attach it turned back
                back = [[0.0] * 3 for _ in range(3)]
                for i, (j, s) in enumerate(axes):
                    back[j][i] = float(s)
                want = unreal.Vector(*[100 * v for v in P["point_gltf"]])
                turn = None
                for q in (quat_of(back), [-v for v in quat_of(back)[:3]] + [quat_of(back)[3]]):
                    got = unreal.Quat(*q).rotate_vector(tip)
                    if ((got.x - want.x) ** 2 + (got.y - want.y) ** 2 + (got.z - want.z) ** 2) ** 0.5 < 0.01:
                        turn = q
                        break
                R["weapon"]["attach_quat"] = turn
                if turn is not None:
                    r = unreal.Quat(*turn).rotator()
                    R["weapon"]["attach_rotator"] = [r.roll, r.pitch, r.yaw]
                    tip = unreal.Quat(*turn).rotate_vector(tip)
                else:
                    tip = None
    for name, times in C["times"].items():
        anim = find_action(found, name)
        if anim is None:
            continue
        poses = []
        for t in times:
            local = {b: unreal.AnimationLibrary.get_bone_pose_for_time(anim, ue_name(b), t, False) for b in parents}
            world = {}

            def get(b):
                if b not in world:
                    world[b] = local[b] if parents[b] is None else local[b] * get(parents[b])
                return world[b]

            poses.append({b: [get(b).translation.x, get(b).translation.y, get(b).translation.z] for b in parents})
            if tip is not None:                        # the weapon's point, carried by the socket, at the marker?
                at = get(P["socket"]).transform_location(tip)
                mark = get(P["marker"]).translation
                worst = max(worst, ((at.x - mark.x) ** 2 + (at.y - mark.y) ** 2 + (at.z - mark.z) ** 2) ** 0.5 * 10)
        R["actions"][name] = {"asset": anim.get_path_name(), "length": anim.get_play_length(),
                              "frames": unreal.AnimationLibrary.get_num_frames(anim), "poses": poses}
    if tip is not None:
        R["weapon"]["point_error_mm"] = worst
    with open(os.path.join(OUT, "import.json"), "w", encoding="utf-8") as fh:
        json.dump(R, fh, indent=1)
    print("UEC import done", R["skeletal_meshes"], "mesh,", len(R["actions"]), "actions,", R["textures"], "textures")


# ---------------------------------------------------------------- live component
VIEW_YAW = 62                                          # three-quarter front, on the lit side
S = {"stage": "import", "start": time.time(), "wait": 0.0, "queue": [], "played": {}}


def world():
    return S.get("world") or unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()


def setup():
    info = read_json(os.path.join(OUT, "import.json"), encoding="utf-8")
    actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    actor = actors.spawn_actor_from_class(unreal.SkeletalMeshActor, unreal.Vector(0, 0, 0))
    comp = actor.skeletal_mesh_component
    comp.set_skeletal_mesh_asset(eal.load_asset(info["mesh_path"]))
    # nothing is on a screen here, and by default bones are only refreshed for a mesh that was rendered
    comp.set_editor_property("visibility_based_anim_tick_option",
                             unreal.VisibilityBasedAnimTickOption.ALWAYS_TICK_POSE_AND_REFRESH_BONES)
    if info.get("weapon_mesh") and C.get("prop"):      # the weapon rides the socket, turned back to the file's axes
        held = actors.spawn_actor_from_class(unreal.StaticMeshActor, unreal.Vector(0, 0, 0))
        held.static_mesh_component.set_mobility(unreal.ComponentMobility.MOVABLE)
        held.static_mesh_component.set_static_mesh(eal.load_asset(info["weapon_mesh"]))
        rule = unreal.AttachmentRule.SNAP_TO_TARGET
        held.attach_to_actor(actor, ue_name(C["prop"]["socket"]), rule, rule, unreal.AttachmentRule.KEEP_WORLD, False)
        if info.get("weapon", {}).get("attach_quat"):
            held.root_component.set_relative_rotation(unreal.Quat(*info["weapon"]["attach_quat"]).rotator(), False, False)
    target = unreal.RenderingLibrary.create_render_target2d(world(), 1024, 1024, unreal.TextureRenderTargetFormat.RTF_RGBA8,
                                                            unreal.LinearColor(0, 0, 0, 1), False)
    camera = actors.spawn_actor_from_class(unreal.SceneCapture2D, unreal.Vector(0, 300, 65))
    capture = camera.capture_component2d
    capture.set_editor_property("texture_target", target)
    capture.set_editor_property("capture_every_frame", False)
    capture.set_editor_property("capture_on_movement", False)
    S.update(actor=actor, comp=comp, target=target, camera=camera, capture=capture, info=info)
    S["queue"] = [(name, t) for name, times in C["play"].items() for t in times]
    # the editor asset library refuses to load anything once the Play session runs
    S["anims"] = {name: eal.load_asset(info["actions"][name]["asset"]) for name in C["play"]}
    fill = actors.spawn_actor_from_class(unreal.DirectionalLight, unreal.Vector(0, 0, 300), unreal.Rotator(0, -25, VIEW_YAW + 180))
    fill.get_component_by_class(unreal.DirectionalLightComponent).set_cast_shadows(False)
    under = actors.spawn_actor_from_class(unreal.DirectionalLight, unreal.Vector(0, 0, -300), unreal.Rotator(0, 55, VIEW_YAW + 180))
    light = under.get_component_by_class(unreal.DirectionalLightComponent)
    light.set_editor_property("intensity", 2.0)        # a capture has no bounce light
    light.set_cast_shadows(False)                      # the floor would block it
    unreal.SystemLibrary.execute_console_command(world(), "r.TextureStreaming 0")


def aim(yaw, distance, height):
    x, y = distance * math.cos(math.radians(yaw)), distance * math.sin(math.radians(yaw))
    S["camera"].set_actor_location(unreal.Vector(x, y, height), False, False)
    S["camera"].set_actor_rotation(unreal.Rotator(0, 0, yaw + 180), False)


def shoot(name, flat):
    c = S["capture"]
    k = max(1.0, S["info"].get("height_m", 1.2) / 1.2)   # framed for a 1.2 m character, wider for a taller one
    if flat:
        aim(90, 300 * k, 65 * k)
        c.set_editor_property("projection_type", unreal.CameraProjectionMode.ORTHOGRAPHIC)
        c.set_editor_property("ortho_width", 200.0 * k)
        c.set_editor_property("capture_source", unreal.SceneCaptureSource.SCS_BASE_COLOR)
        c.set_editor_property("primitive_render_mode", unreal.SceneCapturePrimitiveRenderMode.PRM_USE_SHOW_ONLY_LIST)
        c.clear_show_only_components()
        c.show_only_actor_components(S["actor"])
    else:
        aim(VIEW_YAW, 300 * k, 75 * k)
        c.set_editor_property("projection_type", unreal.CameraProjectionMode.PERSPECTIVE)
        c.set_editor_property("fov_angle", 32.0)
        c.set_editor_property("capture_source", unreal.SceneCaptureSource.SCS_FINAL_COLOR_LDR)
        c.set_editor_property("primitive_render_mode", unreal.SceneCapturePrimitiveRenderMode.PRM_LEGACY_SCENE_CAPTURE)
    c.capture_scene()
    unreal.RenderingLibrary.export_render_target(world(), S["target"], OUT, name)


def enter_game_world():
    """Point at the running copies of the actors once the Play session is up."""
    level = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    game = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_game_world()
    if not level.is_in_play_in_editor() or game is None:
        return False
    S["world"] = game
    S["actor"] = unreal.GameplayStatics.get_all_actors_of_class(game, unreal.SkeletalMeshActor)[0]
    S["camera"] = unreal.GameplayStatics.get_all_actors_of_class(game, unreal.SceneCapture2D)[0]
    S["comp"], S["capture"] = S["actor"].skeletal_mesh_component, S["camera"].capture_component2d
    S["target"] = S["capture"].get_editor_property("texture_target")   # the session has its own copy
    return True


def pose_on_component(name, t):
    comp = S["comp"]
    comp.play_animation(S["anims"][name], True)
    comp.set_position(t, False)
    comp.set_play_rate(0.0)


def read_bones():
    return {b: list(S["comp"].get_socket_location(ue_name(b)).to_tuple()) for b in C["track"]}


def finish():
    with open(os.path.join(OUT, "played.json"), "w", encoding="utf-8") as fh:
        json.dump(S["played"], fh, indent=1)
    print("UEC play done")
    unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).editor_request_end_play()
    unreal.unregister_slate_post_tick_callback(S["handle"])
    unreal.SystemLibrary.quit_editor()


def tick(_):
    try:
        now = time.time()
        if now < S["wait"] or S["stage"] == "busy":
            return
        stage, S["stage"] = S["stage"], "busy"
        if stage == "import":
            import_phase()
            S["stage"] = "setup"
        elif stage == "setup":
            setup()
            S["wait"], S["stage"] = now + C["warm_seconds"], "albedo"
        elif stage == "albedo":
            shoot("albedo_front.png", True)
            unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).editor_request_begin_play()
            S["wait"], S["stage"], S["play_by"] = now + 1.0, "enter", now + 120
        elif stage == "enter":
            if enter_game_world():
                print("UEC in the game world")
                S["wait"], S["stage"] = now + 3.0, "next"
            elif now > S["play_by"]:
                raise RuntimeError("the Play session did not start")
            else:
                S["wait"], S["stage"] = now + 1.0, "enter"
        elif stage == "next":
            if not S["queue"]:
                finish()
                return
            S["current"] = S["queue"].pop(0)
            pose_on_component(*S["current"])
            S["wait"], S["stage"] = now + 0.6, "shot"
        elif stage == "shot":
            name, t = S["current"]
            S["played"].setdefault(name, []).append({"t": t, "bones": read_bones()})
            shoot(f"{name}_{int(round(t * 1000)):05d}.png", False)
            S["stage"] = "next"
    except Exception:  # noqa: BLE001 - a failure must close the editor and leave a trace
        print("UEC EXCEPTION", traceback.format_exc())
        with open(os.path.join(OUT, "played.json"), "w", encoding="utf-8") as fh:
            json.dump({"error": traceback.format_exc()}, fh)
        unreal.unregister_slate_post_tick_callback(S["handle"])
        unreal.SystemLibrary.quit_editor()


S["handle"] = unreal.register_slate_post_tick_callback(tick)
