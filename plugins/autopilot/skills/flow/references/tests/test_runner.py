"""Regression tests for the flow runner/CLI contract (PR #376 review findings).

Pins:
  #1 a bad CONCURRENCY value yields the single error JSON, not a raw traceback.
  #2 exposing both / neither entry point is rejected (not silently one-sided).
  #3 `deps` reports availability based on the actual Python version, not mere
     presence of the executable.
"""
import json
import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REFS = os.path.dirname(HERE)  # .../references
FLOW = os.path.join(REFS, "flow.sh")


def _write(src):
    fd, path = tempfile.mkstemp(suffix=".py")
    with os.fdopen(fd, "w") as f:
        f.write(src)
    return path


def _run(path):
    p = subprocess.run(["bash", FLOW, "run", path], capture_output=True, text=True)
    out = json.loads(p.stdout) if p.stdout.strip() else None  # must be valid JSON
    return p.returncode, out


class TestRunnerContract(unittest.TestCase):
    def test_bad_concurrency_emits_json_not_traceback(self):  # finding #1
        path = _write(
            "from workflow_replica import Node\n"
            "NODES=[Node('a',deps=(),runner=lambda i:1)]\n"
            "CONCURRENCY='oops'\n"
        )
        rc, out = _run(path)
        self.assertIsNotNone(out)            # JSON emitted, not a bare traceback
        self.assertFalse(out["ok"])
        self.assertIn("CONCURRENCY", out["error"])
        self.assertNotEqual(rc, 0)

    def test_both_entry_points_rejected(self):  # finding #2
        path = _write(
            "from workflow_replica import Node\n"
            "NODES=[Node('a',deps=(),runner=lambda i:1)]\n"
            "async def WORKFLOW(wf):\n    return 1\n"
        )
        rc, out = _run(path)
        self.assertFalse(out["ok"])
        self.assertIn("exactly one", out["error"])

    def test_neither_entry_point_rejected(self):  # finding #2
        path = _write("X = 1\n")
        rc, out = _run(path)
        self.assertFalse(out["ok"])
        self.assertIn("exactly one", out["error"])

    def test_valid_nodes_definition_runs(self):
        path = _write(
            "from workflow_replica import Node\n"
            "async def f(i): return 5\n"
            "NODES=[Node('a',deps=(),runner=f)]\n"
        )
        rc, out = _run(path)
        self.assertTrue(out["ok"])
        self.assertEqual(out["mode"], "nodes")
        self.assertEqual(out["results"]["a"], 5)


class TestDepsVersionCheck(unittest.TestCase):
    def test_deps_invokes_python_version(self):  # finding #3
        # The engine requires 3.9+; this suite necessarily runs on 3.9+, so deps
        # must report available — and must have actually consulted the version
        # (a presence-only check could not distinguish 3.8 from 3.9).
        p = subprocess.run(["bash", FLOW, "deps"], capture_output=True, text=True)
        out = json.loads(p.stdout)
        self.assertTrue(out["available"])
        self.assertIn("3.", out["python3"])


if __name__ == "__main__":
    unittest.main()
