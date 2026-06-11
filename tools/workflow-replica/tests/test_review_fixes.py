"""Regression tests for the code-review findings on PR #373.

Each test pins a specific reported defect so it cannot silently return:
  #1 transitive cache key (stale dependent reuse)
  #2 CommandResult journal round-trip (type preserved on resume)
  #4 one-shot iterable (generator) dependency validation
  #5 JSON brace inside a string must not end extraction early
  #3 pipeline stages built from leaf primitives stay within the concurrency cap
"""
import os
import tempfile
import threading
import time
import unittest

from workflow_replica import (
    CommandResult,
    Node,
    callable_node,
    command_node,
    run,
)
from workflow_replica.agent import extract_json
from workflow_replica.api import workflow
from workflow_replica.errors import UnknownDependencyError
from workflow_replica.journal import JsonlJournal


class TestTransitiveCacheKey(unittest.TestCase):
    # Finding #1
    def _journal(self):
        return JsonlJournal(os.path.join(tempfile.mkdtemp(), "j.jsonl"))

    def _node(self, counter, nid, deps=(), fp=None):
        def fn(inputs):
            counter[nid] = counter.get(nid, 0) + 1
            return nid
        return callable_node(nid, fn, deps=deps, fingerprint=fp)

    def test_changed_dependency_invalidates_dependent(self):
        j = self._journal()
        c = {}
        run([self._node(c, "A", fp="v1"), self._node(c, "B", deps=("A",))],
            journal=JsonlJournal(j.path))
        self.assertEqual(c, {"A": 1, "B": 1})

        # A's definition changes (v1 -> v2). A re-runs; B MUST also re-run,
        # because its transitive key folds in A's (now different) key.
        c.clear()
        r2 = run([self._node(c, "A", fp="v2"), self._node(c, "B", deps=("A",))],
                 journal=JsonlJournal(j.path))
        self.assertEqual(c, {"A": 1, "B": 1})  # both re-ran
        self.assertEqual(r2.cached, set())

    def test_unchanged_graph_still_caches(self):
        # Guard against over-invalidation: an identical graph must still cache.
        j = self._journal()
        c = {}
        run([self._node(c, "A"), self._node(c, "B", deps=("A",))],
            journal=JsonlJournal(j.path))
        c.clear()
        r2 = run([self._node(c, "A"), self._node(c, "B", deps=("A",))],
                 journal=JsonlJournal(j.path))
        self.assertEqual(c, {})
        self.assertEqual(r2.cached, {"A", "B"})


class TestCommandResultJournalling(unittest.TestCase):
    # Finding #2
    def test_command_result_roundtrips_with_type(self):
        path = os.path.join(tempfile.mkdtemp(), "j.jsonl")
        r1 = run([command_node("echo", ["printf", "hi"])], journal=JsonlJournal(path))
        self.assertIsInstance(r1.results["echo"], CommandResult)
        self.assertEqual(r1.results["echo"].stdout, "hi")

        # Resume: loaded from the journal, must STILL be a CommandResult, not a str.
        r2 = run([command_node("echo", ["printf", "hi"])], journal=JsonlJournal(path))
        self.assertEqual(r2.cached, {"echo"})
        self.assertIsInstance(r2.results["echo"], CommandResult)
        self.assertEqual(r2.results["echo"].stdout, "hi")

    def test_unserializable_result_raises_not_silently_corrupts(self):
        path = os.path.join(tempfile.mkdtemp(), "j.jsonl")
        n = callable_node("X", lambda i: object())  # not JSON-serializable
        with self.assertRaises(TypeError):
            run([n], journal=JsonlJournal(path))


class TestGeneratorNodes(unittest.TestCase):
    # Finding #4
    def test_generator_unknown_dependency_detected(self):
        def gen():
            yield Node("A", deps=("missing",), runner=lambda i: 1)
        with self.assertRaises(UnknownDependencyError):
            run(gen())

    def test_generator_valid_graph_runs(self):
        def gen():
            yield Node("A", deps=(), runner=lambda i: 1)
            yield Node("B", deps=("A",), runner=lambda i: i["A"] + 1)
        r = run(gen())
        self.assertEqual(r.results["B"], 2)


class TestJsonBraceInString(unittest.TestCase):
    # Finding #5
    def test_brace_inside_string_value(self):
        text = 'Sure: {"text": "a } brace", "n": 1} done'
        self.assertEqual(extract_json(text), {"text": "a } brace", "n": 1})

    def test_escaped_quote_then_brace(self):
        text = 'prefix {"q": "he said \\"}\\""} suffix'
        self.assertEqual(extract_json(text), {"q": 'he said "}"'})


class TestPipelineConcurrencyCap(unittest.TestCase):
    # Finding #3: stages built from leaf primitives stay within the cap.
    def test_leaf_stages_respect_cap(self):
        lock = threading.Lock()
        live = {"n": 0, "max": 0}

        def work(v):
            def fn(inputs):
                with lock:
                    live["n"] += 1
                    live["max"] = max(live["max"], live["n"])
                time.sleep(0.03)
                with lock:
                    live["n"] -= 1
                return v
            return fn

        async def script(wf):
            return await wf.pipeline(
                [1, 2, 3, 4],
                lambda item, o, i: wf.call(work(item)),  # leaf -> bounded
            )

        wr = workflow(script, concurrency=2)
        self.assertEqual(sorted(wr.result), [1, 2, 3, 4])
        self.assertLessEqual(wr.orchestrator.max_live, 2)
        self.assertGreater(wr.orchestrator.max_live, 1)


class TestEnvelopeNoTypeTagCollision(unittest.TestCase):
    # Finding #6 (re-review): a user result must not be misdecoded just because
    # it resembles the harness's internal CommandResult encoding.
    def test_user_dict_resembling_command_result_stays_a_dict(self):
        path = os.path.join(tempfile.mkdtemp(), "j.jsonl")
        payload = {"__wfr_type__": "CommandResult", "returncode": 0,
                   "stdout": "x", "stderr": ""}
        run([callable_node("U", lambda i: dict(payload))], journal=JsonlJournal(path))

        r2 = run([callable_node("U", lambda i: dict(payload))],
                 journal=JsonlJournal(path))
        self.assertEqual(r2.cached, {"U"})
        self.assertNotIsInstance(r2.results["U"], CommandResult)
        self.assertEqual(r2.results["U"], payload)  # round-trips as the raw dict


class TestDeepChainKeyComputation(unittest.TestCase):
    # Finding #7 (re-review): a long serial DAG must not RecursionError while
    # computing transitive cache keys.
    def test_long_chain_load_no_recursion_error(self):
        n = 1500  # well past Python's default recursion limit
        graph = {}
        for i in range(n):
            deps = (f"n{i - 1}",) if i else ()
            graph[f"n{i}"] = Node(f"n{i}", deps=deps, runner=lambda inp: 1)
        cached = JsonlJournal(os.path.join(tempfile.mkdtemp(), "j.jsonl")).load(graph)
        self.assertEqual(cached, {})  # empty journal, but computed without error


if __name__ == "__main__":
    unittest.main()
