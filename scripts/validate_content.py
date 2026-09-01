#!/usr/bin/env python3
"""Offline jsonschema validation for Starsoil gameplay content (WP01).

Validates the WP12 content pack against the frozen schemas in schemas/:

    data/content/items.json          -> schemas/content-item.schema.json
    data/content/buildings.json      -> schemas/building-recipe.schema.json
    data/content/combat_units.json   -> schemas/combat-unit.schema.json
    data/content/combat_actions.json -> schemas/combat-action.schema.json
    data/events/*.json               -> schemas/event.schema.json
    data/encounters/encounters.json  -> schemas/encounter.schema.json
    data/world/world_config.json     -> schemas/world-config.schema.json (DLX-5)

Each target file must contain either a single definition object or an array of
definition objects (the same shapes ContentDB.bootstrap accepts). Duplicate ids
inside one file are rejected, matching ContentDB's `duplicate_id` semantics.

Exit codes:
    0 = data missing/empty (nothing to validate yet) or every file is valid
    1 = validation failures; every error is listed
    2 = environment problem (jsonschema not importable)

Usage:
    python scripts/validate_content.py [--data-root PATH] [--schemas-dir PATH]

`--data-root`/`--schemas-dir` default to <repo>/data and <repo>/schemas, where
<repo> is the parent of this script's directory. The optional overrides exist
so CI and local self-tests can point at scratch directories.
"""

import argparse
import json
import sys
from pathlib import Path

SCHEMA_TARGETS = {
    "content/items.json": "content-item",
    "content/buildings.json": "building-recipe",
    "content/combat_units.json": "combat-unit",
    "content/combat_actions.json": "combat-action",
    "encounters/encounters.json": "encounter",
    "world/world_config.json": "world-config",
}
GLOB_TARGETS = {
    "events/*.json": "event",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Starsoil content data against frozen schemas.")
    default_root = Path(__file__).resolve().parent.parent
    parser.add_argument(
        "--data-root",
        type=Path,
        default=default_root / "data",
        help="Content data directory (default: <repo>/data).",
    )
    parser.add_argument(
        "--schemas-dir",
        type=Path,
        default=default_root / "schemas",
        help="Schema directory (default: <repo>/schemas).",
    )
    return parser.parse_args()


def rel(path: Path) -> str:
    try:
        return path.resolve().as_posix()
    except OSError:
        return str(path)


def entry_label(path: Path, index: int, entry: object) -> str:
    label = f"{rel(path)}[{index}]"
    if isinstance(entry, dict) and isinstance(entry.get("id"), str):
        label += f" (id={entry['id']})"
    return label


def load_json_file(path: Path, errors: list[str]) -> object | None:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:
        errors.append(f"{rel(path)}: invalid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}")
    except OSError as exc:
        errors.append(f"{rel(path)}: cannot read file: {exc.strerror}")
    return None


def definition_entries(path: Path, parsed: object, errors: list[str]) -> list[object]:
    if isinstance(parsed, list):
        return parsed
    if isinstance(parsed, dict):
        return [parsed]
    errors.append(f"{rel(path)}: content must be a definition object or an array of definition objects.")
    return []


def validate_file(path: Path, schema: dict, validator_type: object, errors: list[str]) -> int:
    parsed = load_json_file(path, errors)
    if parsed is None:
        return 0
    validator = validator_type(schema)
    entries = definition_entries(path, parsed, errors)
    checked = 0
    seen_ids: dict[str, int] = {}
    for index, entry in enumerate(entries):
        valid = True
        for error in validator.iter_errors(entry):
            json_path = error.json_path
            location = "(root)" if json_path == "$" else "$" + json_path[1:]
            errors.append(f"{entry_label(path, index, entry)}: {location}: {error.message}")
            valid = False
        if isinstance(entry, dict):
            entry_id = entry.get("id")
            if isinstance(entry_id, str):
                if entry_id in seen_ids:
                    errors.append(
                        f"{rel(path)}[{index}] (id={entry_id}): duplicate id"
                        f" (first seen at index {seen_ids[entry_id]})."
                    )
                    valid = False
                else:
                    seen_ids[entry_id] = index
        if valid:
            checked += 1
    return checked


def main() -> int:
    args = parse_args()
    data_root: Path = args.data_root
    schemas_dir: Path = args.schemas_dir

    if not data_root.is_dir():
        print(f"data root {rel(data_root)} does not exist yet.")
        print("The gameplay content pack is delivered by WP12; skipping offline schema validation.")
        print("RESULT: SKIPPED (no data)")
        return 0

    fixed_files = [(data_root / target_rel, target_rel, schema_name) for target_rel, schema_name in SCHEMA_TARGETS.items()]
    glob_files: list[tuple[Path, str, str]] = []
    for pattern, schema_name in GLOB_TARGETS.items():
        for match in sorted(data_root.glob(pattern)):
            glob_files.append((match, match.relative_to(data_root).as_posix(), schema_name))

    existing = [(path, target_rel, schema_name) for path, target_rel, schema_name in fixed_files + glob_files if path.is_file()]
    if not existing:
        print(f"data root {rel(data_root)} exists but contains no content files.")
        print("The gameplay content pack is delivered by WP12; skipping offline schema validation.")
        print("RESULT: SKIPPED (no data)")
        return 0

    try:
        import jsonschema
    except ImportError as exc:
        print(f"ERROR: jsonschema is required to validate content ({exc}).")
        print("Install dependencies with: pip install -r requirements-dev.txt")
        return 2

    schemas: dict[str, dict] = {}
    for _, _, schema_name in existing:
        if schema_name in schemas:
            continue
        schema_errors: list[str] = []
        schema_path = schemas_dir / f"{schema_name}.schema.json"
        schema = load_json_file(schema_path, schema_errors)
        if not isinstance(schema, dict):
            schema_errors.append(f"{rel(schema_path)}: schema must be a JSON object.")
            for message in schema_errors:
                print(f"ERROR: {message}")
            return 1
        schemas[schema_name] = schema
    validator_type = jsonschema.validators.validator_for(schemas[next(iter(schemas))])

    errors: list[str] = []
    checked_definitions = 0
    for path, target_rel, schema_name in existing:
        checked_definitions += validate_file(path, schemas[schema_name], validator_type, errors)

    missing = [f"{rel(path)}: missing required content file '{target_rel}'." for path, target_rel, _ in fixed_files if not path.is_file()]
    if not glob_files:
        missing.append(f"{rel(data_root / 'events')}: no event files matching 'events/*.json'.")
    errors.extend(missing)

    print(f"Checked {len(existing)} content file(s), {checked_definitions} definition(s) against {len(schemas)} schema(s).")
    if errors:
        print(f"RESULT: FAILED with {len(errors)} error(s):")
        for message in errors:
            print(f"  - {message}")
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
