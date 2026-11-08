"""Session bookkeeping shared by mesh.py and meshop.py, so both undo the same way (no Blender needed).

The contract: besides the current .blend, a session carries a mode state (MODE: the mirror axis in
force and the triangle-budget tier) that later steps obey. Every step's log entry stores that state as
it stood after the step (`state_of`), and undo drops the last step and takes the state stored with the
step that becomes current, so the state always belongs to the .blend that is opened next. Sessions
written before entries stored it are read from their history instead (`replayed`).
"""
import os

MODE = ("mirror", "tier")


def state_of(S):
    """The mode state to store in a step's entry: the session's, as it stands after the step."""
    return {k: S.get(k) for k in MODE}


def replayed(steps):
    """The mode state after these steps, rebuilt from their ops and arguments (old sessions only):
    mirror setup sets the axis (default x), mirror apply clears it, any step with a tier sets it."""
    mirror = tier = None
    for s in steps:
        args = s.get("args") or {}
        if "tier" in args:
            tier = args["tier"]
        if s.get("op") == "mirror":
            mirror = args.get("axis", "x") if args.get("mode", "setup") == "setup" else None
    return {"mirror": mirror, "tier": tier}


def state_after(steps):
    """The mode state after the last of these steps."""
    stored = steps[-1].get("state")
    return {k: stored.get(k) for k in MODE} if isinstance(stored, dict) else replayed(steps)


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
    S.update(state_after(S["steps"]))
    return gone
