"""Node model for the workflow replica harness.

A node is a unit of work with an id, a set of upstream dependencies, and a
`runner` callable. The runner receives a dict mapping each *resolved*
dependency id to that dependency's return value, and returns this node's
result (or raises to signal failure). The runner may be a plain callable
returning a value, or one returning an awaitable — the scheduler handles both.
"""


class Node:
    """A single work item in the dependency graph.

    Args:
        id: unique, hashable identifier.
        deps: iterable of upstream node ids this node depends on.
        runner: callable ``runner(inputs: dict) -> result``; the return value
            may be an awaitable. Receives ``{dep_id: dep_result}``.
        meta: optional metadata dict (e.g. node type, command argv). Used by
            the journal to derive a stable identity key.
    """

    __slots__ = ("id", "deps", "runner", "meta")

    def __init__(self, id, deps=(), runner=None, meta=None):
        self.id = id
        self.deps = tuple(deps)
        self.runner = runner
        self.meta = dict(meta) if meta else {}

    def __repr__(self):
        return f"Node(id={self.id!r}, deps={self.deps!r})"
