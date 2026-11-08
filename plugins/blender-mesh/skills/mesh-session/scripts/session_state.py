"""Session bookkeeping shared by mesh.py and meshop.py, so both undo the same way (no Blender needed)."""
import os


def state_from(steps):
    """The mirror axis and the triangle-budget tier in force after these steps, read from the history."""
    mirror = tier = None
    for s in steps:
        args = s.get("args") or {}
        if "tier" in args:
            tier = args["tier"]
        if s.get("op") == "mirror":
            mirror = args.get("axis", "x") if args.get("mode", "setup") == "setup" else None
    return {"mirror": mirror, "tier": tier}


def undo(S, sdir):
    """Drop the last step and its files, and put the session back as it was before it. Returns that step."""
    gone = S["steps"].pop()
    stale = [os.path.join(sdir, gone["file"]), os.path.join(sdir, gone["file"]) + "1"]
    stale += [os.path.join(sdir, "snaps", f"{gone['n']:03d}.{e}") for e in ("png", "json")]
    for fp in stale:
        if os.path.exists(fp):
            os.remove(fp)
    S["current"] = S["steps"][-1]["file"]
    S["active"] = S["steps"][-1].get("active")
    S.update(state_from(S["steps"]))
    return gone
