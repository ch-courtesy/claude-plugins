"""Streaming, concurrency-bounded DAG scheduler.

The scheduler drives a dependency graph to completion with these guarantees:

* **Streaming fan-out (no wave barrier)** — each node starts the moment *its
  own* dependencies are done, never waiting on unrelated slower nodes. This is
  achieved by driving ``graphlib.TopologicalSorter`` incrementally
  (``get_ready`` / ``done``) rather than in layered waves.
* **Concurrency cap** — at most ``concurrency`` node runners execute at once,
  bounded by an ``asyncio.Semaphore``.
* **Transitive failure isolation** — a failed node's direct and indirect
  dependents are skipped (not run); unrelated branches finish. Failed and
  skipped nodes are still marked ``done`` in the topo sort so the graph keeps
  draining and skip status propagates to *their* dependents.
* **Result passing** — a node's return value is handed to its dependents.
* **Cycle detection** — a cyclic graph raises :class:`CyclicGraphError` before
  any node runs.

Scheduling decisions are deterministic given the same graph, journal and node
results: readiness comes from the topo sort and skip/run/cache choices are pure
functions of recorded states. Wall-clock time and randomness never feed
scheduling decisions.
"""
import asyncio
import inspect
from graphlib import CycleError, TopologicalSorter

from .errors import CyclicGraphError, DuplicateNodeError, UnknownDependencyError

SUCCESS = "success"
FAILED = "failed"
SKIPPED = "skipped"


class RunResult:
    """Outcome of a scheduler run."""

    def __init__(self):
        self.results = {}   # node_id -> return value (success only)
        self.states = {}    # node_id -> SUCCESS | FAILED | SKIPPED
        self.errors = {}    # node_id -> exception (failed only)
        self.cached = set() # node_ids whose result was reused from the journal

    def _ids(self, state):
        return {k for k, v in self.states.items() if v == state}

    @property
    def succeeded(self):
        return self._ids(SUCCESS)

    @property
    def failed(self):
        return self._ids(FAILED)

    @property
    def skipped(self):
        return self._ids(SKIPPED)

    def __repr__(self):
        return (
            f"RunResult(success={len(self.succeeded)}, "
            f"failed={len(self.failed)}, skipped={len(self.skipped)})"
        )


def _build_graph(nodes):
    nodes = list(nodes)  # materialize: the input may be a one-shot iterable
    graph = {}
    for n in nodes:
        if n.id in graph:
            raise DuplicateNodeError(f"duplicate node id: {n.id!r}")
        graph[n.id] = n
    for n in nodes:
        for d in n.deps:
            if d not in graph:
                raise UnknownDependencyError(
                    f"node {n.id!r} depends on unknown node {d!r}"
                )
    return graph


async def run_graph(nodes, concurrency=1, journal=None):
    """Execute ``nodes`` (an iterable of :class:`~workflow_replica.graph.Node`).

    Returns a :class:`RunResult`. Raises :class:`CyclicGraphError` (before any
    node runs) if the graph is cyclic.
    """
    graph = _build_graph(nodes)

    ts = TopologicalSorter()
    for n in graph.values():
        ts.add(n.id, *n.deps)
    try:
        ts.prepare()
    except CycleError as e:
        # e.args[1] is the list of nodes forming the cycle.
        raise CyclicGraphError(e.args[1]) from None

    result = RunResult()
    sem = asyncio.Semaphore(max(1, int(concurrency)))
    running = {}  # asyncio.Future -> node_id

    cached = journal.load(graph) if journal is not None else {}

    async def execute(node):
        async with sem:
            inputs = {d: result.results[d] for d in node.deps if d in result.results}
            r = node.runner(inputs)
            if inspect.isawaitable(r):
                r = await r
            return r

    def settle(nid, state, value=None, error=None):
        result.states[nid] = state
        if state == SUCCESS:
            result.results[nid] = value
        if error is not None:
            result.errors[nid] = error
        ts.done(nid)

    while ts.is_active():
        for nid in ts.get_ready():
            node = graph[nid]
            if nid in cached:
                result.cached.add(nid)
                settle(nid, SUCCESS, value=cached[nid])
                continue
            if any(result.states.get(d) in (FAILED, SKIPPED) for d in node.deps):
                settle(nid, SKIPPED)
                continue
            running[asyncio.ensure_future(execute(node))] = nid

        if not running:
            # No work in flight; remaining readiness (if any) comes from the
            # nodes just settled above on the next loop turn.
            continue

        done, _ = await asyncio.wait(running, return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            nid = running.pop(task)
            exc = task.exception()
            if exc is None:
                value = task.result()
                settle(nid, SUCCESS, value=value)
                if journal is not None:
                    journal.record(graph[nid], value)
            else:
                settle(nid, FAILED, error=exc)

    return result


def run(nodes, concurrency=1, journal=None):
    """Synchronous wrapper around :func:`run_graph` (uses ``asyncio.run``)."""
    return asyncio.run(run_graph(nodes, concurrency=concurrency, journal=journal))
