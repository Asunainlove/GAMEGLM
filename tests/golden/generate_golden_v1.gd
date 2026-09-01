extends SceneTree

## WP04 golden fixture generator (provenance tooling, not a test).
## Regenerates the exact envelope frozen in tests/golden/save_v1_golden.json:
##   godot --headless --path . --script res://tests/golden/generate_golden_v1.gd
## The printed line is the raw SaveCodec.encode_snapshot() output; it must be
## copied verbatim into tests/golden/save_v1_golden.json.
## DLX-6: content_hash semantics cover "ContentDB definitions + progression
## config files". G7P-2 (S1/S5/S10): the config set is now endings/characters/
## event_chain/ending_gate/objectives/hints/world_config (see
## ContentDB.HASH_CONFIG_FILES for the authoritative list). The fixture
## records the real bootstrap("res://data") total hash, making it a hash_match
## specimen under docs/save-content-policy.md. Maintenance contract: any change
## to data/** definitions or any HASH_CONFIG_FILES entry requires rerunning this
## generator and updating save_v1_golden.json.


func _initialize() -> void:
	var content_db: Node = load("res://src/content/content_db.gd").new()
	var boot: AppResult = content_db.bootstrap("res://data")
	if not boot.is_ok:
		push_error("Golden content bootstrap failed: %s %s" % [boot.code, boot.message])
		content_db.free()
		quit(1)
		return

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
	# DLX-6：content_hash = ContentDB 真实 bootstrap 的总哈希（六类定义 +
	# endings/event_chain/world_config 三进度配置文件的 canonical JSON 总哈希）。
	snapshot["content_hash"] = content_db.content_hash()
	content_db.free()

	var codec: SaveCodec = SaveCodec.new()
	var encoded: AppResult = codec.encode_snapshot(snapshot)
	if not encoded.is_ok:
		push_error("Golden encode failed: %s %s" % [encoded.code, encoded.message])
		quit(1)
		return
	print(encoded.value)
	state.free()
	quit(0)
