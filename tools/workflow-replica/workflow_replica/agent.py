"""LLM agent node (acceptance condition C8).

An agent node spawns an LLM subagent to process a prompt and, when a structured
schema is supplied, returns a schema-validated object — re-prompting the
subagent with the validation errors until it conforms or retries are exhausted.

The actual model invocation is delegated to a *caller*: any callable
``caller(prompt: str) -> str`` (sync or async). This keeps the harness
LLM-agnostic and standalone — wire it to whatever local subagent path exists.
:class:`SubprocessAgentCaller` is a ready-made caller that literally spawns a
subagent process and feeds the prompt on stdin (no external library needed).

Tests inject a deterministic caller; the model's own output is non-deterministic
and out of the SPEC's scheduler-determinism scope.
"""
import asyncio
import inspect
import json

from .errors import SchemaValidationError
from .graph import Node
from .schema import validate


def agent_node(id, prompt, caller, schema=None, deps=(), max_retries=2,
               fingerprint=None):
    """Build an agent :class:`~workflow_replica.graph.Node`.

    Args:
        prompt: a prompt string, or a callable ``prompt(inputs) -> str`` that
            builds the prompt from dependency results (enables composition).
        caller: ``caller(prompt) -> str`` (sync or async); the subagent adapter.
        schema: optional JSON-schema (subset) the result must satisfy.
        max_retries: extra attempts after the first on a schema mismatch.
        fingerprint: resume-journal key; defaults to the prompt when it is a str.
    """
    if fingerprint is None and isinstance(prompt, str):
        fingerprint = prompt

    async def runner(inputs):
        base = prompt(inputs) if callable(prompt) else prompt
        return await run_agent(caller, base, schema=schema, max_retries=max_retries)

    return Node(
        id,
        deps=deps,
        runner=runner,
        meta={"type": "agent", "fingerprint": fingerprint},
    )


async def run_agent(caller, prompt, schema=None, max_retries=2):
    """Invoke the caller, validating/retrying against ``schema`` if given."""
    attempt = 0
    current_prompt = prompt
    while True:
        raw = caller(current_prompt)
        if inspect.isawaitable(raw):
            raw = await raw

        if schema is None:
            return raw

        try:
            obj = extract_json(raw)
        except ValueError as exc:
            errors = [f"response was not valid JSON: {exc}"]
        else:
            errors = validate(obj, schema)
            if not errors:
                return obj

        attempt += 1
        if attempt > max_retries:
            raise SchemaValidationError(errors, raw)
        current_prompt = prompt + "\n\n" + _correction(errors, schema)


def _correction(errors, schema):
    return (
        "Your previous response did not conform to the required schema.\n"
        "Validation errors:\n- " + "\n- ".join(errors) + "\n\n"
        "Return ONLY a JSON value matching this schema, with no prose:\n"
        + json.dumps(schema)
    )


def extract_json(text):
    """Parse a JSON value from model text, tolerating prose and code fences.

    Tries the whole string first, then a ```...``` fenced block, then the first
    balanced ``{...}`` or ``[...]`` region. Raises ``ValueError`` if none parse.
    """
    if not isinstance(text, str):
        raise ValueError("response is not text")
    candidates = [text.strip()]

    fenced = _fenced_block(text)
    if fenced is not None:
        candidates.append(fenced)

    span = _balanced_span(text)
    if span is not None:
        candidates.append(span)

    for cand in candidates:
        try:
            return json.loads(cand)
        except (json.JSONDecodeError, ValueError):
            continue
    raise ValueError("no JSON value found in response")


def _fenced_block(text):
    start = text.find("```")
    if start == -1:
        return None
    rest = text[start + 3:]
    newline = rest.find("\n")
    if newline != -1 and rest[:newline].strip().lower() in ("json", ""):
        rest = rest[newline + 1:]
    end = rest.find("```")
    return rest[:end].strip() if end != -1 else None


def _balanced_span(text):
    for opener, closer in (("{", "}"), ("[", "]")):
        start = text.find(opener)
        if start == -1:
            continue
        depth = 0
        in_str = False
        esc = False
        for i in range(start, len(text)):
            c = text[i]
            if in_str:
                # Inside a JSON string: only an unescaped quote ends it, and
                # braces here are data, not structure.
                if esc:
                    esc = False
                elif c == "\\":
                    esc = True
                elif c == '"':
                    in_str = False
                continue
            if c == '"':
                in_str = True
            elif c == opener:
                depth += 1
            elif c == closer:
                depth -= 1
                if depth == 0:
                    return text[start:i + 1]
    return None


class SubprocessAgentCaller:
    """Caller that spawns a subagent process and feeds the prompt on stdin.

    ``argv`` is the subagent command (e.g. a local LLM CLI). The prompt is
    written to stdin; stdout is returned as the response. A non-zero exit raises
    ``RuntimeError`` so the scheduler treats the agent node as failed.
    """

    def __init__(self, argv, cwd=None, env=None):
        self.argv = list(argv)
        self.cwd = cwd
        self.env = env

    async def __call__(self, prompt):
        proc = await asyncio.create_subprocess_exec(
            *self.argv,
            cwd=self.cwd,
            env=self.env,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        out, err = await proc.communicate(prompt.encode("utf-8"))
        if proc.returncode != 0:
            raise RuntimeError(
                f"subagent {self.argv!r} exited {proc.returncode}: "
                + err.decode("utf-8", "replace")
            )
        return out.decode("utf-8", "replace")
