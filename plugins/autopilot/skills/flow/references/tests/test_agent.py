"""Slice 3 — LLM agent node with schema validation + retry (condition C8).

The agent node spawns an LLM subagent (here, an injected caller stand-in),
processes a prompt, and — when a structured schema is given — returns a
schema-validated object, re-prompting for a corrected result on a mismatch.

The LLM itself is non-deterministic and out of scheduler-determinism scope
(per SPEC), so tests inject a deterministic caller to exercise harness logic.
"""
import unittest

from workflow_replica import Node, run
from workflow_replica.agent import agent_node
from workflow_replica.errors import SchemaValidationError
from workflow_replica.schema import validate


PERSON_SCHEMA = {
    "type": "object",
    "properties": {
        "name": {"type": "string"},
        "age": {"type": "integer"},
    },
    "required": ["name", "age"],
    "additionalProperties": False,
}


class ScriptedCaller:
    """Returns canned responses in order; records prompts it was called with."""

    def __init__(self, responses):
        self.responses = list(responses)
        self.prompts = []

    def __call__(self, prompt):
        self.prompts.append(prompt)
        return self.responses.pop(0)


class TestSchemaValidator(unittest.TestCase):
    def test_valid_object_passes(self):
        self.assertEqual(validate({"name": "x", "age": 3}, PERSON_SCHEMA), [])

    def test_missing_required_and_wrong_type_reported(self):
        errs = validate({"name": 5}, PERSON_SCHEMA)
        self.assertTrue(any("age" in e for e in errs))
        self.assertTrue(any("name" in e for e in errs))

    def test_enum_and_array(self):
        sch = {"type": "array", "items": {"enum": ["a", "b"]}}
        self.assertEqual(validate(["a", "b"], sch), [])
        self.assertTrue(validate(["a", "c"], sch))


class TestAgentNode(unittest.TestCase):
    def test_schemaless_returns_raw_text(self):
        caller = ScriptedCaller(["hello world"])
        node = agent_node("a", "say hi", caller=caller)
        r = run([node], concurrency=1)
        self.assertEqual(r.results["a"], "hello world")

    def test_valid_structured_result_returned(self):
        caller = ScriptedCaller(['{"name": "Ada", "age": 36}'])
        node = agent_node("a", "make a person", caller=caller, schema=PERSON_SCHEMA)
        r = run([node], concurrency=1)
        self.assertEqual(r.results["a"], {"name": "Ada", "age": 36})
        self.assertEqual(len(caller.prompts), 1)

    def test_invalid_then_corrected_retry(self):
        # First response violates schema (age is a string), second is valid.
        caller = ScriptedCaller([
            '{"name": "Ada", "age": "old"}',
            'Sure: {"name": "Ada", "age": 36}',  # prose-wrapped JSON
        ])
        node = agent_node("a", "make a person", caller=caller,
                          schema=PERSON_SCHEMA, max_retries=2)
        r = run([node], concurrency=1)
        self.assertEqual(r.results["a"], {"name": "Ada", "age": 36})
        self.assertEqual(len(caller.prompts), 2)  # one retry happened
        self.assertIn("age", caller.prompts[1])   # correction mentions the error

    def test_exhausted_retries_fails_node(self):
        caller = ScriptedCaller(['nope', 'still bad', '{"name": 1}'])
        node = agent_node("a", "make a person", caller=caller,
                          schema=PERSON_SCHEMA, max_retries=2)
        r = run([node], concurrency=1)
        self.assertEqual(r.states["a"], "failed")
        self.assertIsInstance(r.errors["a"], SchemaValidationError)
        self.assertEqual(len(caller.prompts), 3)  # initial + 2 retries

    def test_prompt_can_use_dependency_results(self):
        async def upstream(inputs):
            return "Grace Hopper"

        caller = ScriptedCaller(['{"name": "Grace Hopper", "age": 85}'])
        node = agent_node(
            "a",
            prompt=lambda inputs: f'make a person named {inputs["u"]}',
            caller=caller, schema=PERSON_SCHEMA, deps=("u",),
        )
        graph = [Node("u", deps=(), runner=upstream), node]
        r = run(graph, concurrency=2)
        self.assertEqual(r.results["a"]["name"], "Grace Hopper")
        self.assertIn("Grace Hopper", caller.prompts[0])


if __name__ == "__main__":
    unittest.main()
