# ADR-0001: Engine and vertical-slice boundary

## Decision

Use Godot 4.7.2 Standard Win64 with strongly typed GDScript. The current target is the bounded 45–60 minute vertical slice in `docs/PROJECT_CHARTER.md`, not the complete long-term game.

## Alternatives

- Unity/C#: rejected because the approved report and local plan select Godot/GDScript.
- Godot development snapshots: rejected because repeatability is more important than unreleased features.
- Full report scope: deferred because it prevents early validation of the causal construction thesis.

## Consequences

The project pins exact engine/test versions, avoids .NET, and treats all out-of-scope systems as future candidates requiring new ADRs.

