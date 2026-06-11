"""Journal-based resume (acceptance condition C4).

A journal records the result of every node that succeeds. On a later run with
the same journal file, the scheduler asks the journal which nodes are already
done (``load``) and reuses their results instead of re-executing them; only
incomplete and failed nodes run again.

Identity key & stale-cache safety
---------------------------------
A cache entry is keyed by ``(node id, fingerprint)``. The fingerprint is a
stable derivation of the node's *definition* (e.g. a command node's argv, or a
caller-supplied string). If a node's definition changes, its fingerprint
changes, the key no longer matches, and the entry is treated as a miss — the
node re-runs. This makes the SPEC's "stale journal" risk observable: changing a
node invalidates its cached result rather than silently reusing it.

Persisted values must be JSON-serializable. Nodes whose results are not
JSON-friendly should not opt into journalling (or should return a serializable
representation).
"""
import hashlib
import json
import os


def fingerprint_key(node):
    """Stable identity key for a node, as ``(id, fingerprint)`` hashed to hex."""
    fp = node.meta.get("fingerprint")
    payload = json.dumps(
        {"id": node.id, "fp": fp}, sort_keys=True, default=str
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


class JsonlJournal:
    """Append-only JSON-lines journal backed by a file on disk.

    Each successful node appends one line:
    ``{"id": <id>, "key": <hex>, "value": <json>}``. The latest line for a
    given key wins, so a re-recorded node naturally supersedes its old entry.
    """

    def __init__(self, path):
        self.path = path

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

    def load(self, graph):
        """Return ``{node_id: cached_value}`` for nodes whose current key
        matches a recorded success in this journal.
        """
        entries = self._read_entries()
        cached = {}
        for node in graph.values():
            key = fingerprint_key(node)
            if key in entries:
                cached[node.id] = entries[key]
        return cached

    def record(self, node, value):
        """Append a successful node's result to the journal."""
        rec = {"id": node.id, "key": fingerprint_key(node), "value": value}
        line = json.dumps(rec, default=str)
        directory = os.path.dirname(self.path)
        if directory:
            os.makedirs(directory, exist_ok=True)
        with open(self.path, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
            fh.flush()
            os.fsync(fh.fileno())
