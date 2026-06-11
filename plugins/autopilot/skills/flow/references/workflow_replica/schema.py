"""A minimal, dependency-free JSON Schema validator.

Supports the common subset needed to validate structured agent output:
``type`` (object/array/string/integer/number/boolean/null, or a list of
types), ``properties``, ``required``, ``additionalProperties``, ``items``,
``enum``, ``minimum``/``maximum``, ``minItems``/``maxItems``. Unknown keywords
are ignored (treated as no constraint), so a schema using only this subset
validates exactly and a richer schema still validates the supported parts.

``validate(instance, schema)`` returns a list of human-readable error strings;
an empty list means the instance conforms.
"""

_TYPE_CHECKS = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    # bool is a subclass of int in Python; exclude it from number/integer.
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "boolean": lambda v: isinstance(v, bool),
    "null": lambda v: v is None,
}


def validate(instance, schema, path="$"):
    """Return a list of validation error strings (empty == valid)."""
    errors = []
    _validate(instance, schema, path, errors)
    return errors


def _validate(instance, schema, path, errors):
    if not isinstance(schema, dict):
        return

    if "enum" in schema:
        if instance not in schema["enum"]:
            errors.append(f"{path}: value {instance!r} not in enum {schema['enum']!r}")

    if "type" in schema:
        types = schema["type"]
        if isinstance(types, str):
            types = [types]
        if not any(_TYPE_CHECKS.get(t, lambda v: True)(instance) for t in types):
            errors.append(f"{path}: expected type {schema['type']!r}, got {_kind(instance)}")
            return  # further keyword checks assume the right type

    if isinstance(instance, dict):
        _validate_object(instance, schema, path, errors)
    elif isinstance(instance, list):
        _validate_array(instance, schema, path, errors)
    elif isinstance(instance, (int, float)) and not isinstance(instance, bool):
        _validate_number(instance, schema, path, errors)


def _validate_object(instance, schema, path, errors):
    props = schema.get("properties", {})
    for req in schema.get("required", []):
        if req not in instance:
            errors.append(f"{path}: missing required property {req!r}")
    for key, value in instance.items():
        if key in props:
            _validate(value, props[key], f"{path}.{key}", errors)
        elif schema.get("additionalProperties") is False:
            errors.append(f"{path}: additional property {key!r} not allowed")


def _validate_array(instance, schema, path, errors):
    if "minItems" in schema and len(instance) < schema["minItems"]:
        errors.append(f"{path}: array shorter than minItems {schema['minItems']}")
    if "maxItems" in schema and len(instance) > schema["maxItems"]:
        errors.append(f"{path}: array longer than maxItems {schema['maxItems']}")
    item_schema = schema.get("items")
    if item_schema is not None:
        for i, item in enumerate(instance):
            _validate(item, item_schema, f"{path}[{i}]", errors)


def _validate_number(instance, schema, path, errors):
    if "minimum" in schema and instance < schema["minimum"]:
        errors.append(f"{path}: {instance} < minimum {schema['minimum']}")
    if "maximum" in schema and instance > schema["maximum"]:
        errors.append(f"{path}: {instance} > maximum {schema['maximum']}")


def _kind(v):
    for name, check in _TYPE_CHECKS.items():
        if check(v):
            return name
    return type(v).__name__
