"""Imperative authoring API (acceptance condition C7).

Mirrors the built-in dynamic Workflow's imperative surface. An author writes an
async *script* ``async def script(wf): ...`` and drives work with the
:class:`Orchestrator` primitives:

* ``await wf.call(fn)``        — run a Python callable (sync or async) as a node.
* ``await wf.command(argv)``   — run an external command node.
* ``await wf.agent(prompt, caller, schema=...)`` — run an LLM agent node.
* ``await wf.parallel([thunk, ...])`` — run thunks concurrently (barrier).
* ``await wf.pipeline(items, *stages)`` — flow each item through stages with no
  barrier between stages (a fast item reaches a later stage while a slow item is
  still early).
* ``wf.phase(title)`` / ``wf.log(msg)`` — progress events.

Because the script is ordinary imperative async code, it can ``await`` a result
and then decide which nodes to run next — a runtime-determined graph.

Concurrency cap: the **leaf primitives** (call/command/agent) are the bounded
units of work — each acquires the shared semaphore, so no more than
``concurrency`` of them run at once, however parallel()/pipeline() fan them out.
The composites (parallel/pipeline) only orchestrate; they must NOT themselves
take the semaphore (a stage that holds it and then calls a leaf would deadlock
at ``concurrency=1``). Build stage and thunk bodies out of the leaf primitives
so their work stays bounded; raw blocking work placed directly in a stage —
rather than via ``call`` — runs outside the cap and on the event loop, exactly
as a thunk's body does, and is the author's responsibility.

The scheduler's determinism contract still holds: scheduling/branch decisions
depend only on recorded results, never on wall-clock or randomness.
"""
import asyncio
import inspect

from .agent import run_agent
from .nodes import run_command


class Orchestrator:
    """Holds the shared concurrency limiter and progress events for one run."""

    def __init__(self, concurrency=4):
        self._sem = asyncio.Semaphore(max(1, int(concurrency)))
        self.events = []      # list of (kind, payload)
        self.phase_name = None
        self._live = 0
        self.max_live = 0     # observed peak concurrency of bounded primitives

    # -- progress -------------------------------------------------------
    def phase(self, title):
        self.phase_name = title
        self.events.append(("phase", title))

    def log(self, message):
        self.events.append(("log", message))

    # -- bounded execution ---------------------------------------------
    async def _bounded(self, make_coro):
        async with self._sem:
            self._live += 1
            self.max_live = max(self.max_live, self._live)
            try:
                return await make_coro()
            finally:
                self._live -= 1

    # -- leaf primitives ------------------------------------------------
    async def call(self, fn, inputs=None):
        inputs = {} if inputs is None else inputs

        async def go():
            if inspect.iscoroutinefunction(fn):
                return await fn(inputs)
            loop = asyncio.get_running_loop()
            return await loop.run_in_executor(None, fn, inputs)

        return await self._bounded(go)

    async def command(self, argv, cwd=None, env=None):
        return await self._bounded(
            lambda: run_command(argv, cwd=cwd, env=env)
        )

    async def agent(self, prompt, caller, schema=None, max_retries=2):
        return await self._bounded(
            lambda: run_agent(caller, prompt, schema=schema, max_retries=max_retries)
        )

    # -- composite primitives ------------------------------------------
    async def parallel(self, thunks):
        """Run each zero-arg thunk concurrently; await all (barrier)."""
        return await asyncio.gather(*[t() for t in thunks])

    async def pipeline(self, items, *stages):
        """Flow each item through ``stages`` independently — no barrier between
        stages. Each stage callback receives ``(prev_result, original_item,
        index)``."""
        async def chain(original, idx):
            prev = original
            for stage in stages:
                prev = stage(prev, original, idx)
                if inspect.isawaitable(prev):
                    prev = await prev
            return prev

        return await asyncio.gather(
            *[chain(item, i) for i, item in enumerate(items)]
        )


class WorkflowRun:
    """Result of :func:`workflow`: the script's return value plus orchestrator."""

    def __init__(self, orchestrator, result):
        self.orchestrator = orchestrator
        self.result = result


def workflow(script, concurrency=4):
    """Run an imperative async ``script(wf)`` to completion.

    Returns a :class:`WorkflowRun` exposing ``.result`` (the script's return
    value) and ``.orchestrator`` (events, observed peak concurrency).
    """
    async def main():
        wf = Orchestrator(concurrency=concurrency)
        result = await script(wf)
        return WorkflowRun(wf, result)

    return asyncio.run(main())
