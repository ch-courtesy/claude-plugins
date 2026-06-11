"""Journal-based resume (acceptance condition C4).

A journal records the result of every node that succeeds. On a later run with
the same journal file, the scheduler asks the journal which nodes are already
done (``load``) and reuses their results instead of re-executing them; only
incomplete and failed nodes run again.

Identity key & stale-cache safety
---------------------------------
A cache entry is keyed by a node's *transitive* identity: the node's own
``(id, fingerprint)`` **folded together with the keys of its dependencies**.
The fingerprint is a stable derivation of the node's definition (e.g. a command
node's argv, or a caller-supplied string). Because dependency keys are folded
in, changing *any* upstream node's definition changes the key of every
downstream node, so a stale dependent is never reused with an out-of-date
upstream result. Changing a node's own definition likewise invalidates it. This
makes the SPEC's "stale journal" risk observable: a changed node (or any of its
transitive dependencies) re-runs rather than silently reusing a cached result.

Persisted values must be JSON-serializable. :class:`CommandResult` is supported
explicitly (round-tripped with its type preserved); any other non-serializable
result raises on record rather than being silently coerced to a string.
"""
import hashlib
import json
import os

from .nodes import CommandResult


def fingerprint_key(node):
    """Leaf identity component for a node: ``(id, fingerprint)`` hashed to hex.

    This is only the node's *own* contribution. Cache identity is transitive —
    the journal folds each node's dependency keys into the stored key (see
    :meth:`JsonlJournal._compute_keys`).
    """
    fp = node.meta.get("fingerprint")
    payload = json.dumps(
        {"id": node.id, "fp": fp}, sort_keys=True, default=str
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _encode(value):
    """Convert a node result into a JSON-serializable form, preserving type
    information for the result kinds the harness produces itself."""
    if isinstance(value, CommandResult):
        return {
            "__wfr_type__": "CommandResult",
            "returncode": value.returncode,
            "stdout": value.stdout,
            "stderr": value.stderr,
        }
    return value


def _decode(value):
    """Inverse of :func:`_encode`."""
    if isinstance(value, dict) and value.get("__wfr_type__") == "CommandResult":
        return CommandResult(value["returncode"], value["stdout"], value["stderr"])
    return value


class JsonlJournal:
    """Append-only JSON-lines journal backed by a file on disk.

    Each successful node appends one line:
    ``{"id": <id>, "key": <hex>, "value": <json>}``. The latest line for a
    given key wins, so a re-recorded node naturally supersedes its old entry.

    :meth:`load` must be called (with the graph) before :meth:`record`; the
    transitive cache keys are computed from the graph and shared by both.
    """

    def __init__(self, path):
        self.path = path
        self._keys = None  # node_id -> transitive cache key (set by load)

    def _read_entries(self):
        if not os.path.exists(self.path):
            return {}
        entries = {}  # key -> value (last line wins)
        with open(self.path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue  # tolerate a torn final line
                if "key" in rec:
                    entries[rec["key"]] = rec.get("value")
        return entries

    def _compute_keys(self, graph):
        """Transitive cache key per node: its leaf key folded with the sorted
        keys of its dependencies. The graph is acyclic here (the scheduler
        rejects cycles before loading), so the recursion terminates."""
        keys = {}

        def keyof(nid):
            if nid in keys:
                return keys[nid]
            node = graph[nid]
            dep_keys = sorted(keyof(d) for d in node.deps)
            payload = json.dumps(
                {"leaf": fingerprint_key(node), "deps": dep_keys},
                sort_keys=True,
            ).encode("utf-8")
            k = hashlib.sha256(payload).hexdigest()
            keys[nid] = k
            return k

        for nid in graph:
            keyof(nid)
        return keys

    def load(self, graph):
        """Return ``{node_id: cached_value}`` for nodes whose current transitive
        key matches a recorded success in this journal."""
        self._keys = self._compute_keys(graph)
        entries = self._read_entries()
        cached = {}
        for nid, key in self._keys.items():
            if key in entries:
                cached[nid] = _decode(entries[key])
        return cached

    def record(self, node, value):
        """Append a successful node's result to the journal."""
        if self._keys is None or node.id not in self._keys:
            raise RuntimeError(
                "JsonlJournal.record requires load(graph) to be called first"
            )
        try:
            encoded = json.dumps(
                {"id": node.id, "key": self._keys[node.id], "value": _encode(value)}
            )
        except TypeError as exc:
            raise TypeError(
                f"node {node.id!r} result is not JSON-serializable and cannot be "
                f"journalled ({exc}); return a serializable value or omit the journal"
            ) from None
        directory = os.path.dirname(self.path)
        if directory:
            os.makedirs(directory, exist_ok=True)
        with open(self.path, "a", encoding="utf-8") as fh:
            fh.write(encoded + "\n")
            fh.flush()
            os.fsync(fh.fileno())
