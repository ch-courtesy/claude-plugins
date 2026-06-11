"""Worker node factories.

Two worker tiers, mirroring the built-in dynamic Workflow's node kinds:

* :func:`command_node` — a generic external-command worker. LLM-independent;
  success/failure is decided by process exit status. (Acceptance C9.)
* :func:`callable_node` — wraps an arbitrary Python callable (sync or async)
  as a node. Sync callables run in a thread so they don't block the event loop.

The LLM agent-node tier lives in :mod:`workflow_replica.agent` (later slice).
"""
import asyncio
import inspect

from .errors import CommandFailed
from .graph import Node


class CommandResult:
    """Result of a command node: exit status plus captured output."""

    __slots__ = ("returncode", "stdout", "stderr")

    def __init__(self, returncode, stdout, stderr):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr

    def __repr__(self):
        return f"CommandResult(returncode={self.returncode})"


def command_node(id, argv, deps=(), cwd=None, env=None, fingerprint=None):
    """A node that runs ``argv`` as a subprocess.

    Exit status 0 -> success (returns a :class:`CommandResult`); non-zero ->
    failure (raises :class:`CommandFailed`, which the scheduler isolates). No
    LLM is involved.

    ``fingerprint`` (default: the argv) keys the resume journal; changing the
    command changes the fingerprint and invalidates any cached result.
    """
    argv = list(argv)
    if fingerprint is None:
        fingerprint = argv

    async def runner(inputs):
        proc = await asyncio.create_subprocess_exec(
            *argv,
            cwd=cwd,
            env=env,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        out, err = await proc.communicate()
        res = CommandResult(
            proc.returncode,
            out.decode("utf-8", "replace"),
            err.decode("utf-8", "replace"),
        )
        if proc.returncode != 0:
            raise CommandFailed(id, res)
        return res

    return Node(
        id,
        deps=deps,
        runner=runner,
        meta={"type": "command", "argv": argv, "fingerprint": fingerprint},
    )


def callable_node(id, fn, deps=(), fingerprint=None):
    """Wrap a Python callable ``fn(inputs) -> result`` as a node.

    ``fn`` may be async (awaited) or sync (run in a worker thread so blocking
    calls do not stall the scheduler's event loop).

    ``fingerprint`` keys the resume journal. A Python callable's identity cannot
    be derived reliably, so callers that journal callable nodes should pass an
    explicit fingerprint that changes when the node's behaviour changes.
    """

    async def runner(inputs):
        if inspect.iscoroutinefunction(fn):
            return await fn(inputs)
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, fn, inputs)

    return Node(
        id,
        deps=deps,
        runner=runner,
        meta={"type": "callable", "fingerprint": fingerprint},
    )
