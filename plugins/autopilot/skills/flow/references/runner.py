#!/usr/bin/env python3
"""flow runner — execute a workflow definition with the Workflow Replica engine
and emit a machine-readable JSON result on stdout.

A *workflow definition* is a plain Python file that, when imported with
``workflow_replica`` importable, exposes exactly one entry point:

* ``NODES``    — a list of :class:`workflow_replica.Node` (declarative DAG), or
* ``WORKFLOW`` — an ``async def WORKFLOW(wf)`` script (imperative authoring).

Optional module-level knobs: ``CONCURRENCY`` (int, default 4) and, for the
declarative form, ``JOURNAL`` (path to a resume journal).

Output (stdout) is a single JSON object; ``ok`` is true when the run completed
without an internal error. The result is JSON for programmatic consumption by a
caller (e.g. another skill) — no free-text parsing required.
"""
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)  # make `import workflow_replica` work for the script

import workflow_replica as wr  # noqa: E402


def _emit(obj, code=0):
    sys.stdout.write(json.dumps(obj, default=str) + "\n")
    sys.exit(code)


def _load_module(path):
    spec = importlib.util.spec_from_file_location("flow_workflow", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run(path):
    if not os.path.isfile(path) or not os.access(path, os.R_OK):
        _emit({"ok": False, "error": f"workflow definition not found or unreadable: {path!r}"}, 2)
    try:
        mod = _load_module(path)
    except Exception as e:  # import/syntax error in the definition
        _emit({"ok": False, "error": f"failed to import workflow definition: {e}"}, 1)

    concurrency = int(getattr(mod, "CONCURRENCY", 4))

    if hasattr(mod, "WORKFLOW"):
        try:
            wrun = wr.workflow(mod.WORKFLOW, concurrency=concurrency)
        except Exception as e:
            _emit({"ok": False, "mode": "workflow", "error": str(e)}, 1)
        _emit({
            "ok": True,
            "mode": "workflow",
            "result": wrun.result,
            "events": wrun.orchestrator.events,
            "max_concurrency": wrun.orchestrator.max_live,
        })

    if hasattr(mod, "NODES"):
        journal = None
        jpath = getattr(mod, "JOURNAL", None)
        if jpath:
            journal = wr.JsonlJournal(jpath)
        try:
            res = wr.run(mod.NODES, concurrency=concurrency, journal=journal)
        except Exception as e:
            _emit({"ok": False, "mode": "nodes", "error": str(e)}, 1)
        _emit({
            "ok": True,
            "mode": "nodes",
            "succeeded": sorted(res.succeeded),
            "failed": sorted(res.failed),
            "skipped": sorted(res.skipped),
            "cached": sorted(res.cached),
            "results": res.results,
        })

    _emit({"ok": False, "error": "workflow definition exposes neither NODES nor WORKFLOW"}, 1)


def main(argv):
    if len(argv) < 2 or argv[1] != "run" or len(argv) < 3:
        _emit({"ok": False, "error": "usage: runner.py run <workflow-definition.py>"}, 2)
    run(argv[2])


if __name__ == "__main__":
    main(sys.argv)
