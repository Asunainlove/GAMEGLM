# Starsoil Vertical Slice Implementation Plan

> **Required workflow:** execute test-first in isolated worktrees, with spec and code-quality review for every work package.

**Goal:** Build the approved 45–60 minute Godot vertical slice described in `docs/PROJECT_CHARTER.md`.

**Architecture:** `ContentDB` owns immutable definitions, `GameState` owns all mutable runtime state, and `SaveService` owns versioned persistence. Scene-owned world, narrative, and battle sessions propose typed patches rather than mutating global state.

**Tech Stack:** Godot 4.7.2, strongly typed GDScript, GUT 9.7.1, Python/jsonschema, Git LFS.

---

## Milestones

1. **G0 — Toolchain and governance:** reproducible engine/test setup, repository rules, state and handoff records.
2. **G1 — Walking Skeleton:** move, mine, collect, place an anchor block, save, quit, and reload.
3. **G2 — State/content foundation:** ContentDB, schemas, references, StatePatch, Save v1 recovery and migrations.
4. **G3 — Sandbox Alpha:** authored 4×2 Chunk topology, seeded overlays, inventory, six recipes, guided workshop, room and power rules.
5. **G4 — Narrative and Battle Alpha:** typed events/dialogue/effects, relationships, three choices, deterministic three-slot battle and three encounters.
6. **G5 — Complete graybox:** all three endings playable in 45–60 minutes; core-system freeze.
7. **G6 — Art and presentation:** approved asset manifest, canonical references, portraits, tile art, UI and sound.
8. **G7 — Beta and Windows RC:** external playtest, performance, recovery, originality and clean export gates.

## W000 tasks

### Task 1: Bootstrap

- Pin and smoke-test Godot/GUT/Python.
- Create the minimum Godot project and a test that proves the runner reports failure correctly.
- Acceptance: engine version matches, headless import exits zero, passing and intentional failing fixtures produce the expected exit codes.

### Task 2: State and save

- Test-first implementation of `AppResult`, `StatePatch`, `GameState`, `SaveCodec`, and `SaveService`.
- Acceptance: a patch is atomic; invalid inventory changes leave state unchanged; save round-trip retains revision/inventory/world deltas/buildings; invalid primary recovers a valid candidate.

### Task 3: Walking Skeleton world

- Test-first single-Chunk player movement, deterministic mineable cells, inventory pickup, anchor placement, and UI.
- Acceptance: mine once yields one item; repeated/invalid mining is a no-op; valid placement consumes inventory and records the building; save/reload preserves all outcomes.

### Task 4: Integration and handoff

- Wire App, input, HUD, world and persistence.
- Run focused tests, the complete suite, headless app smoke, and a manual save/relaunch check.
- Record evidence, last verified commit, limitations, and the unique next work package.

