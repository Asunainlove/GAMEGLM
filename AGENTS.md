# Starsoil Project Rules

This repository contains the Godot 4 vertical slice for **《星壤：余辉纪元》**.

## Locked baseline

- Godot `4.7.2-stable` Standard Win64, strongly typed GDScript, GL Compatibility.
- Windows PC, offline single-player, Simplified Chinese, keyboard/mouse first.
- Gameplay content is data-driven and uses stable `snake_case` IDs.
- The approved product and implementation scope lives in `docs/PROJECT_CHARTER.md` and `docs/plans/`.

## Architecture

- Only `ContentDB`, `GameState`, and `SaveService` may be Autoloads.
- `GameState` is the sole mutable authority. Persistent changes go through `StatePatch`.
- Presentation nodes never mutate persistent dictionaries directly.
- Content is immutable after `ContentDB.bootstrap()`.
- Save schema changes require a version bump, migration, and golden fixture.
- Do not add global event buses, arbitrary expression evaluation, networking, stores, mods, or unrelated framework layers.

## Development discipline

- Use test-driven development: add and observe a failing test before production behavior.
- Keep work packages small, independently verifiable, and limited to their allowed paths.
- A subagent may report `SUBMITTED` or `BLOCKED`; only the coordinator may mark work `VERIFIED`.
- Every checkpoint records the exact command, exit code, commit, limitations, and next action.
- Never claim a test or build passes without fresh command output.
- Preserve user changes and never discard dirty work without explicit authorization.

## Content and originality

- All characters are original adults. Do not copy existing game characters, silhouettes, UI, icons, terminology, logos, or branded assets.
- Prompts must not request a living artist's style or imitation of a named commercial game.
- Generated assets require provenance and human approval before `approved` status.

