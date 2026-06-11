"""Slice 2 — journal-based resume (acceptance condition C4).

A resumed run must reuse the recorded results of previously-succeeded nodes
(no re-execution) and only re-run incomplete/failed nodes. Changing a node's
definition (its fingerprint) must invalidate its cache entry so it re-runs.
"""
import os
import tempfile
import unittest

from workflow_replica import Node, run
from workflow_replica.journal import JsonlJournal
from workflow_replica.nodes import callable_node


class TestResume(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.path = os.path.join(self.dir, "journal.jsonl")

    def _counter_node(self, nid, counter, deps=(), fingerprint=None, value=None,
                      fail=False):
        def fn(inputs):
            counter[nid] = counter.get(nid, 0) + 1
            if fail:
                raise RuntimeError("boom")
            return value if value is not None else nid
        return callable_node(nid, fn, deps=deps, fingerprint=fingerprint)

    def test_succeeded_nodes_not_reexecuted_on_resume(self):
        counter = {}
        graph = [
            self._counter_node("A", counter),
            self._counter_node("B", counter, deps=("A",)),
        ]
        j1 = JsonlJournal(self.path)
        r1 = run(graph, concurrency=2, journal=j1)
        self.assertEqual(r1.states["A"], "success")
        self.assertEqual(r1.states["B"], "success")
        self.assertEqual(counter, {"A": 1, "B": 1})

        # Resume with a fresh journal object over the same file + same graph.
        counter2 = {}
        graph2 = [
            self._counter_node("A", counter2),
            self._counter_node("B", counter2, deps=("A",)),
        ]
        j2 = JsonlJournal(self.path)
        r2 = run(graph2, concurrency=2, journal=j2)
        # Nothing re-executed; both came from the journal.
        self.assertEqual(counter2, {})
        self.assertEqual(r2.cached, {"A", "B"})
        self.assertEqual(r2.results["B"], "B")

    def test_only_incomplete_and_failed_nodes_rerun(self):
        counter = {}
        graph = [
            self._counter_node("A", counter),
            self._counter_node("B", counter, deps=("A",), fail=True),
            self._counter_node("C", counter, deps=("B",)),
        ]
        r1 = run(graph, concurrency=2, journal=JsonlJournal(self.path))
        self.assertEqual(r1.states["A"], "success")
        self.assertEqual(r1.states["B"], "failed")
        self.assertEqual(r1.states["C"], "skipped")
        self.assertEqual(counter, {"A": 1, "B": 1})

        # Resume: B now succeeds. A must be cached; B (failed) + C (incomplete) rerun.
        counter2 = {}
        graph2 = [
            self._counter_node("A", counter2),
            self._counter_node("B", counter2, deps=("A",)),  # no longer fails
            self._counter_node("C", counter2, deps=("B",)),
        ]
        r2 = run(graph2, concurrency=2, journal=JsonlJournal(self.path))
        self.assertEqual(r2.cached, {"A"})
        self.assertEqual(counter2, {"B": 1, "C": 1})  # A not rerun
        self.assertEqual(r2.states["C"], "success")

    def test_changed_fingerprint_invalidates_cache(self):
        counter = {}
        run([self._counter_node("A", counter, fingerprint="v1")],
            concurrency=1, journal=JsonlJournal(self.path))
        self.assertEqual(counter, {"A": 1})

        # Same id, different fingerprint -> cache miss -> re-run.
        counter2 = {}
        r2 = run([self._counter_node("A", counter2, fingerprint="v2")],
                 concurrency=1, journal=JsonlJournal(self.path))
        self.assertEqual(counter2, {"A": 1})  # re-executed
        self.assertEqual(r2.cached, set())

    def test_no_journal_means_no_cache(self):
        counter = {}
        n = self._counter_node("A", counter)
        r = run([n], concurrency=1)  # journal=None
        self.assertEqual(r.cached, set())
        self.assertEqual(counter, {"A": 1})


if __name__ == "__main__":
    unittest.main()
