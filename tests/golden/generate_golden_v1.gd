extends SceneTree

## WP04 golden fixture generator (provenance tooling, not a test).
## Regenerates the exact envelope frozen in tests/golden/save_v1_golden.json:
##   godot --headless --path . --script res://tests/golden/generate_golden_v1.gd
## The printed line is the raw SaveCodec.encode_snapshot() output; it must be
## copied verbatim into tests/golden/save_v1_golden.json.


func _initialize() -> void:
	var state: Node = load("res://src/state/game_state.gd").new()

	var seed_patch: StatePatch = state.begin_patch("wp04_golden_seed", 0)
	seed_patch.add_item("starsoil_dust", 12)
	seed_patch.add_item("salvage_metal", 5)
	seed_patch.set_destructible_cell("surface_0_0", 3, 5, true)
	seed_patch.place_building("anchor_block", "surface_0_0", 8, 9)
	seed_patch.set_flag("first_anchor_placed", true)
	seed_patch.complete_event("event_prologue_landing")
	seed_patch.complete_event("event_first_mining")
	seed_patch.set_relationship("luoxian", "affection", 35)
	seed_patch.set_relationship("luoxian", "trust", 20)
	seed_patch.set_relationship("misa", "affection", 30)
	seed_patch.set_relationship("misa", "trust", 25)
	seed_patch.adjust_ideology("stewardship", 20)
	seed_patch.adjust_ideology("continuity", -15)
	seed_patch.set_player_position(4, -2)
	var seed_result: AppResult = state.commit(seed_patch)
	if not seed_result.is_ok:
		push_error("Golden seed patch failed: %s %s" % [seed_result.code, seed_result.message])
		quit(1)
		return

	var outcome_patch: StatePatch = state.begin_patch("wp04_golden_outcome", 1)
	outcome_patch.add_item("resonant_glass", 2)
	outcome_patch.set_relationship("luoxian", "ideology", 10)
	outcome_patch.adjust_ideology("agency", 40)
	outcome_patch.record_battle_outcome("encounter_first_drift", "victory", 4)
	outcome_patch.set_flag("encounter_first_drift_won", true)
	outcome_patch.set_flag("event_prologue_landing_done", true)
	var outcome_result: AppResult = state.commit(outcome_patch)
	if not outcome_result.is_ok:
		push_error("Golden outcome patch failed: %s %s" % [outcome_result.code, outcome_result.message])
		quit(1)
		return

	var snapshot: Dictionary = state.snapshot()
	snapshot["world_seed"] = 1337
	snapshot["content_hash"] = "starsoil-content-v1-vertical-slice".sha256_text()

	var codec: SaveCodec = SaveCodec.new()
	var encoded: AppResult = codec.encode_snapshot(snapshot)
	if not encoded.is_ok:
		push_error("Golden encode failed: %s %s" % [encoded.code, encoded.message])
		quit(1)
		return
	print(encoded.value)
	state.free()
	quit(0)
