"""workflow_replica — a standalone replica of Claude Code's dynamic Workflow
multi-agent orchestration, built on the Python standard library only.

Public surface (slice 1):

* :class:`Node` — a unit of work with dependencies and a runner.
* :func:`run` / :func:`run_graph` — execute a DAG with streaming fan-out,
  a concurrency cap, transitive failure isolation, result passing and cycle
  detection.
* :class:`RunResult` — run outcome (per-node states, results, errors).
* :func:`command_node` / :func:`callable_node` — worker node factories.
"""
from .agent import SubprocessAgentCaller, agent_node, run_agent
from .errors import (
    CommandFailed,
    CyclicGraphError,
    DuplicateNodeError,
    SchemaValidationError,
    UnknownDependencyError,
    WorkflowError,
)
from .graph import Node
from .journal import JsonlJournal, fingerprint_key
from .nodes import CommandResult, callable_node, command_node
from .scheduler import RunResult, run, run_graph
from .schema import validate as validate_schema

__all__ = [
    "Node",
    "run",
    "run_graph",
    "RunResult",
    "command_node",
    "callable_node",
    "CommandResult",
    "JsonlJournal",
    "fingerprint_key",
    "agent_node",
    "run_agent",
    "SubprocessAgentCaller",
    "validate_schema",
    "SchemaValidationError",
    "WorkflowError",
    "CyclicGraphError",
    "DuplicateNodeError",
    "UnknownDependencyError",
    "CommandFailed",
]
