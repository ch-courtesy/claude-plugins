"""Slice 4 — imperative authoring API + runtime-determined graph (condition C7).

An author expresses a workflow as an imperative async script using the
orchestrator primitives (call/agent/command/parallel/pipeline/phase/log). The
script may branch on a stage's result to decide which nodes run next
(runtime-determined graph). Concurrency stays bounded across all primitives.
"""
import threading
import time
import unittest

from workflow_replica.api import Orchestrator, workflow


class TestImperativeBasics(unittest.TestCase):
    def test_sequential_result_threading(self):
        async def script(wf):
            a = await wf.call(lambda i: 10)
            b = await wf.call(lambda i: a + 5)
            return b

        run = workflow(script, concurrency=2)
        self.assertEqual(run.result, 15)

    def test_parallel_returns_all_and_caps_concurrency(self):
        lock = threading.Lock()
        live = {"n": 0, "max": 0}

        def make(v):
            def fn(inputs):
                with lock:
                    live["n"] += 1
                    live["max"] = max(live["max"], live["n"])
                time.sleep(0.05)
                with lock:
                    live["n"] -= 1
                return v
            return fn

        async def script(wf):
            return await wf.parallel([(lambda f=make(i): wf.call(f)) for i in range(8)])

        run = workflow(script, concurrency=3)
        self.assertEqual(sorted(run.result), list(range(8)))
        self.assertLessEqual(live["max"], 3)
        self.assertGreater(live["max"], 1)


class TestRuntimeDeterminedGraph(unittest.TestCase):
    def test_next_nodes_depend_on_prior_result(self):
        ran = []

        async def script(wf):
            seed = await wf.call(lambda i: 7)  # produce a value at runtime
            if seed % 2 == 1:
                ran.append("odd")
                return await wf.call(lambda i: "odd-branch")
            ran.append("even")
            return await wf.call(lambda i: "even-branch")

        run = workflow(script, concurrency=2)
        self.assertEqual(run.result, "odd-branch")
        self.assertEqual(ran, ["odd"])  # only the chosen branch executed

    def test_fan_count_decided_at_runtime(self):
        async def script(wf):
            n = await wf.call(lambda i: 4)  # how many workers is decided here
            results = await wf.parallel([(lambda k=k: wf.call(lambda i: k * k))
                                         for k in range(n)])
            return sum(results)

        run = workflow(script, concurrency=4)
        self.assertEqual(run.result, 0 + 1 + 4 + 9)


class TestPipelineNoBarrier(unittest.TestCase):
    def test_items_flow_independently_through_stages(self):
        events = []

        async def stage1(item, original, idx):
            events.append(("s1-start", idx, time.monotonic()))
            # item 0 is slow in stage1, item 1 is fast
            await _sleep(0.20 if idx == 0 else 0.01)
            events.append(("s1-end", idx, time.monotonic()))
            return item

        async def stage2(prev, original, idx):
            events.append(("s2-start", idx, time.monotonic()))
            return prev * 10

        async def script(wf):
            return await wf.pipeline([1, 2], stage1, stage2)

        run = workflow(script, concurrency=4)
        self.assertEqual(run.result, [10, 20])
        s2_start_1 = next(t for (tag, idx, t) in events if tag == "s2-start" and idx == 1)
        s1_end_0 = next(t for (tag, idx, t) in events if tag == "s1-end" and idx == 0)
        # Fast item 1 must reach stage2 before slow item 0 finishes stage1.
        self.assertLess(s2_start_1, s1_end_0)


async def _sleep(s):
    import asyncio
    await asyncio.sleep(s)


class TestPhaseAndLog(unittest.TestCase):
    def test_events_recorded(self):
        async def script(wf):
            wf.phase("build")
            wf.log("starting")
            await wf.call(lambda i: 1)
            return "ok"

        run = workflow(script, concurrency=1)
        kinds = [e[0] for e in run.orchestrator.events]
        self.assertIn("phase", kinds)
        self.assertIn("log", kinds)


if __name__ == "__main__":
    unittest.main()
