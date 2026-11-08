"""Runs inside Unreal Editor (see unreal_session.py). Config comes from MESH_UE_CONFIG.

Brings the GLB in, lists what arrived and reads each action's joints from the asset. Then puts the
character in the level, renders its albedo, starts a Play session, and plays each action on the
running component, reading bones back from it and taking a picture. The editor world does not tick
without a viewport, so a component there never leaves its rest pose: only a game world proves it.
"""
import json
import math
import os
import time
import traceback

import unreal

C = json.load(open(os.environ["MESH_UE_CONFIG"], encoding="utf-8"))
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
        R["actions"][name] = {"asset": anim.get_path_name(), "length": anim.get_play_length(),
                              "frames": unreal.AnimationLibrary.get_num_frames(anim), "poses": poses}
    json.dump(R, open(os.path.join(OUT, "import.json"), "w", encoding="utf-8"), indent=1)
    print("UEC import done", R["skeletal_meshes"], "mesh,", len(R["actions"]), "actions,", R["textures"], "textures")


# ---------------------------------------------------------------- live component
VIEW_YAW = 62                                          # three-quarter front, on the lit side
S = {"stage": "import", "start": time.time(), "wait": 0.0, "queue": [], "played": {}}


def world():
    return S.get("world") or unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()


def setup():
    info = json.load(open(os.path.join(OUT, "import.json"), encoding="utf-8"))
    actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    actor = actors.spawn_actor_from_class(unreal.SkeletalMeshActor, unreal.Vector(0, 0, 0))
    comp = actor.skeletal_mesh_component
    comp.set_skeletal_mesh_asset(eal.load_asset(info["mesh_path"]))
    # nothing is on a screen here, and by default bones are only refreshed for a mesh that was rendered
    comp.set_editor_property("visibility_based_anim_tick_option",
                             unreal.VisibilityBasedAnimTickOption.ALWAYS_TICK_POSE_AND_REFRESH_BONES)
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
    if flat:
        aim(90, 300, 65)
        c.set_editor_property("projection_type", unreal.CameraProjectionMode.ORTHOGRAPHIC)
        c.set_editor_property("ortho_width", 200.0)
        c.set_editor_property("capture_source", unreal.SceneCaptureSource.SCS_BASE_COLOR)
        c.set_editor_property("primitive_render_mode", unreal.SceneCapturePrimitiveRenderMode.PRM_USE_SHOW_ONLY_LIST)
        c.clear_show_only_components()
        c.show_only_actor_components(S["actor"])
    else:
        aim(VIEW_YAW, 300, 75)
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
    json.dump(S["played"], open(os.path.join(OUT, "played.json"), "w", encoding="utf-8"), indent=1)
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
        json.dump({"error": traceback.format_exc()}, open(os.path.join(OUT, "played.json"), "w", encoding="utf-8"))
        unreal.unregister_slate_post_tick_callback(S["handle"])
        unreal.SystemLibrary.quit_editor()


S["handle"] = unreal.register_slate_post_tick_callback(tick)
