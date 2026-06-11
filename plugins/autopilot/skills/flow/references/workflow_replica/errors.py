"""Error types for the workflow replica harness."""


class WorkflowError(Exception):
    """Base class for all harness errors."""


class CyclicGraphError(WorkflowError):
    """Raised before any node runs when the dependency graph has a cycle.

    `cycle` holds the node ids forming the cycle, as reported by the
    topological sort (the last element repeats the first).
    """

    def __init__(self, cycle):
        self.cycle = list(cycle)
        super().__init__(
            "dependency cycle detected: " + " -> ".join(str(c) for c in self.cycle)
        )


class DuplicateNodeError(WorkflowError):
    """Two nodes share the same id."""


class UnknownDependencyError(WorkflowError):
    """A node declares a dependency on an id that is not in the graph."""


class SchemaValidationError(WorkflowError):
    """An agent node's output failed schema validation after all retries."""

    def __init__(self, errors, last_response):
        self.errors = list(errors)
        self.last_response = last_response
        super().__init__(
            "agent output failed schema validation after retries: "
            + "; ".join(self.errors)
        )


class CommandFailed(WorkflowError):
    """A command node exited with a non-zero status."""

    def __init__(self, node_id, result):
        self.node_id = node_id
        self.result = result
        super().__init__(
            f"command node {node_id!r} exited with {result.returncode}"
        )
