"""Slice 1 — core streaming DAG scheduler + command/callable nodes.

Covers acceptance conditions C1 (streaming fan-out / no wave barrier),
C2 (concurrency cap), C3 (transitive failure isolation), C5 (result
passing), C6 (cycle detection), C9 (LLM-free command nodes).
"""
import asyncio
import threading
import time
import unittest

from workflow_replica import Node, run
from workflow_replica.errors import CyclicGraphError
from workflow_replica.nodes import callable_node, command_node


class TestStreamingFanout(unittest.TestCase):
    def test_node_starts_before_unrelated_slower_node_finishes(self):
        # C1: dependency-light branch must not wait on an unrelated slow node.
        events = []  # (event, node_id, monotonic_time)

        def rec(tag, nid):
            events.append((tag, nid, time.monotonic()))

        async def slow(inputs):
            rec("start", "slow")
            await asyncio.sleep(0.30)
            rec("end", "slow")
            return "slow"

        async def a(inputs):
            rec("start", "A")
            await asyncio.sleep(0.01)
            rec("end", "A")
            return "A"

        async def b(inputs):
            rec("start", "B")
            await asyncio.sleep(0.01)
            rec("end", "B")
            return "B"

        graph = [
            Node("slow", deps=(), runner=slow),
            Node("A", deps=(), runner=a),
            Node("B", deps=("A",), runner=b),  # B depends only on A, not on slow
        ]
        result = run(graph, concurrency=4)
        self.assertEqual(result.states["B"], "success")

        starts = {nid: t for (tag, nid, t) in events if tag == "start"}
        ends = {nid: t for (tag, nid, t) in events if tag == "end"}
        # B (downstream of fast A) must start before the unrelated slow node ends.
        self.assertLess(starts["B"], ends["slow"],
                        "B waited on unrelated slow node -> wave barrier present")


class TestConcurrencyCap(unittest.TestCase):
    def test_max_concurrency_not_exceeded(self):
        # C2: never run more than `concurrency` nodes at once.
        lock = threading.Lock()
        live = {"n": 0, "max": 0}

        def make(nid):
            def fn(inputs):
                with lock:
                    live["n"] += 1
                    live["max"] = max(live["max"], live["n"])
                time.sleep(0.05)
                with lock:
                    live["n"] -= 1
                return nid
            return callable_node(nid, fn)

        graph = [make(f"n{i}") for i in range(12)]
        result = run(graph, concurrency=3)
        self.assertEqual(len(result.succeeded), 12)
        self.assertLessEqual(live["max"], 3)
        self.assertGreater(live["max"], 1)  # actually ran in parallel


class TestFailureIsolation(unittest.TestCase):
    def test_transitive_dependents_skipped_unrelated_runs(self):
        # C3: failed node's transitive dependents are skipped; unrelated branch finishes.
        async def boom(inputs):
            raise RuntimeError("intentional failure")

        async def ok(inputs):
            return "ok"

        graph = [
            Node("X", deps=(), runner=boom),
            Node("Y", deps=("X",), runner=ok),       # direct dependent
            Node("Z", deps=("Y",), runner=ok),       # transitive dependent
            Node("U", deps=(), runner=ok),           # unrelated root
            Node("V", deps=("U",), runner=ok),       # unrelated branch
        ]
        result = run(graph, concurrency=4)
        self.assertEqual(result.states["X"], "failed")
        self.assertEqual(result.states["Y"], "skipped")
        self.assertEqual(result.states["Z"], "skipped")
        self.assertEqual(result.states["U"], "success")
        self.assertEqual(result.states["V"], "success")
        self.assertIn("X", result.failed)
        self.assertEqual(result.skipped, {"Y", "Z"})


class TestResultPassing(unittest.TestCase):
    def test_dependency_result_passed_to_dependent(self):
        # C5: a node's return value reaches dependents via inputs.
        async def produce(inputs):
            return 41

        async def consume(inputs):
            return inputs["p"] + 1

        graph = [
            Node("p", deps=(), runner=produce),
            Node("c", deps=("p",), runner=consume),
        ]
        result = run(graph, concurrency=2)
        self.assertEqual(result.results["c"], 42)


class TestCycleDetection(unittest.TestCase):
    def test_cycle_reported_no_node_runs(self):
        # C6: cyclic input -> no execution, cycle reported, error raised.
        ran = []

        async def mark(inputs):
            ran.append(1)
            return 1

        graph = [
            Node("A", deps=("B",), runner=mark),
            Node("B", deps=("A",), runner=mark),
        ]
        with self.assertRaises(CyclicGraphError) as ctx:
            run(graph, concurrency=2)
        self.assertEqual(ran, [])  # nothing executed
        self.assertTrue(set(ctx.exception.cycle) >= {"A", "B"})


class TestCommandNodes(unittest.TestCase):
    def test_pure_command_graph_no_llm(self):
        # C9: LLM-free command graph runs to completion via exit status.
        graph = [
            command_node("a", ["python3", "-c", "print('hi')"]),
            command_node("b", ["true"], deps=("a",)),
            command_node("c", ["python3", "-c", "import sys; sys.exit(0)"], deps=("b",)),
        ]
        result = run(graph, concurrency=2)
        self.assertEqual(result.states["a"], "success")
        self.assertEqual(result.states["b"], "success")
        self.assertEqual(result.states["c"], "success")
        self.assertIn("hi", result.results["a"].stdout)

    def test_command_nonzero_exit_fails_and_isolates(self):
        graph = [
            command_node("fail", ["false"]),
            command_node("down", ["true"], deps=("fail",)),
            command_node("indep", ["true"]),
        ]
        result = run(graph, concurrency=2)
        self.assertEqual(result.states["fail"], "failed")
        self.assertEqual(result.states["down"], "skipped")
        self.assertEqual(result.states["indep"], "success")


if __name__ == "__main__":
    unittest.main()
