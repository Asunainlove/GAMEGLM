extends GutTest

## DLX-6 存档内容政策单元测试（政策文本 docs/save-content-policy.md）：
## SaveCodec.sanitize_payload_against_content 的三档判定（hash_match /
## hash_superset / hash_divergent）、声明式孤儿清理规则、清理报告与输入
## 不可变性；"数据包即 DLC"的存档侧演练（内容包纯新增 = superset 旧档
## 无损载入）；以及 golden fixture content_hash 与当前内容总哈希的一致性。

const CONTENT_DB_PATH: String = "res://src/content/content_db.gd"
const GOLDEN_RESOURCE_PATH: String = "res://tests/golden/save_v1_golden.json"

const OLD_ITEM_ID: String = "starsoil_dust"
const OLD_EVENT_ID: String = "event_prologue_landing"
const OLD_ENCOUNTER_ID: String = "encounter_first_drift"
## 模拟 DLC 内容包新增的定义（仅存在于"当前内容"，旧档不知道它们）。
const DLC_ITEM_ID: String = "dlc_glow_charm"
const DLC_EVENT_ID: String = "event_dlc_greeting"
## 模拟被删改后残留的孤儿引用（旧档引用了"当前内容中不存在"的定义）。
const GHOST_ITEM_ID: String = "ghost_material"
const GHOST_EVENT_ID: String = "event_ghost"
const GHOST_ENCOUNTER_ID: String = "encounter_ghost"

## 哈希值只需彼此不同且形态合法（sanitize 比对的是字符串本身）。
const OLD_CONTENT_HASH: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const NEW_CONTENT_HASH: String = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

var _old_done_flag: String = "event_%s_done" % OLD_EVENT_ID


func _old_defs() -> Dictionary:
	## 旧内容包 defs：items/events/encounters 各一 + 世界网格两个 chunk。
	return {
		"items": {OLD_ITEM_ID: {"id": OLD_ITEM_ID}},
		"events": {OLD_EVENT_ID: {"id": OLD_EVENT_ID}},
		"encounters": {OLD_ENCOUNTER_ID: {"id": OLD_ENCOUNTER_ID}},
		"chunk_ids": ["chunk_0_0", "chunk_1_0"],
	}


func _superset_defs() -> Dictionary:
	## 当前内容 = 旧内容 + DLC 新增（物品 + 事件），encounters/chunk 不变。
	var defs: Dictionary = _old_defs()
	(defs["items"] as Dictionary)[DLC_ITEM_ID] = {"id": DLC_ITEM_ID}
	(defs["events"] as Dictionary)[DLC_EVENT_ID] = {"id": DLC_EVENT_ID}
	return defs


func _payload_for(hash_value: String) -> Dictionary:
	## 只引用旧内容包定义的合法存档 payload（字段集与 v1 schema 一致）。
	return {
		"save_version": 1,
		"content_hash": hash_value,
		"inventory": {OLD_ITEM_ID: 4},
		"flags": {
			_old_done_flag: true,
			"first_mining_done": true,
		},
		"chunk_deltas": {"chunk_0_0": [{"cell_x": 1, "cell_y": 2, "destroyed": true}]},
		"battle_outcomes": {OLD_ENCOUNTER_ID: {"result": "victory", "turns": 3}},
	}


func _divergent_payload() -> Dictionary:
	## 旧档额外引用了当前内容中已不存在的物品/事件/遭遇，以及网格外 chunk。
	var payload: Dictionary = _payload_for(OLD_CONTENT_HASH)
	(payload["inventory"] as Dictionary)[GHOST_ITEM_ID] = 7
	payload["flags"]["event_%s_done" % GHOST_EVENT_ID] = true
	payload["chunk_deltas"]["chunk_9_9"] = [{"cell_x": 0, "cell_y": 0, "destroyed": true}]
	payload["battle_outcomes"][GHOST_ENCOUNTER_ID] = {"result": "defeat", "turns": 1}
	return payload


# ---------------------------------------------------------------- hash_match


func test_hash_match_returns_payload_unchanged_with_match_report() -> void:
	var payload: Dictionary = _payload_for(OLD_CONTENT_HASH)
	var report: Dictionary = SaveCodec.sanitize_payload_against_content(
		payload, OLD_CONTENT_HASH, _old_defs()
	)

	assert_eq(str(report["policy"]), "hash_match")
	assert_true(bool(report["hash_matches"]))
	assert_false(bool(report["changed"]))
	for report_key: String in [
		"removed_inventory", "removed_flags", "removed_chunk_deltas", "removed_battle_outcomes",
	]:
		assert_true((report[report_key] as Array).is_empty(), "%s 必须为空。" % report_key)
	assert_eq(report["payload"], payload)


# ---------------------------------------------------------------- hash_superset（DLC 演练）


func test_dlc_content_pack_superset_loads_old_save_losslessly() -> void:
	## "数据包即 DLC"存档侧验收：当前内容在旧内容基础上纯新增（物品 + 事件），
	## 旧档引用全部仍存在 → hash_superset，零孤儿、零清理、payload 原样。
	var payload: Dictionary = _payload_for(OLD_CONTENT_HASH)
	var report: Dictionary = SaveCodec.sanitize_payload_against_content(
		payload, NEW_CONTENT_HASH, _superset_defs()
	)

	assert_eq(str(report["policy"]), "hash_superset")
	assert_false(bool(report["hash_matches"]))
	assert_false(bool(report["changed"]))
	for report_key: String in [
		"removed_inventory", "removed_flags", "removed_chunk_deltas", "removed_battle_outcomes",
	]:
		assert_true((report[report_key] as Array).is_empty(), "%s 必须为空。" % report_key)
	assert_eq(report["payload"], payload)
	var cleaned: Dictionary = report["payload"]
	assert_eq(cleaned["inventory"], {OLD_ITEM_ID: 4})
	assert_eq(cleaned["flags"], {_old_done_flag: true, "first_mining_done": true})


# ---------------------------------------------------------------- hash_divergent


func test_divergent_definitions_prune_orphans_and_keep_the_rest() -> void:
	var payload: Dictionary = _divergent_payload()
	var report: Dictionary = SaveCodec.sanitize_payload_against_content(
		payload, NEW_CONTENT_HASH, _superset_defs()
	)

	assert_eq(str(report["policy"]), "hash_divergent")
	assert_false(bool(report["hash_matches"]))
	assert_true(bool(report["changed"]))
	assert_eq(report["removed_inventory"], [GHOST_ITEM_ID])
	assert_eq(report["removed_flags"], ["event_%s_done" % GHOST_EVENT_ID])
	assert_eq(report["removed_chunk_deltas"], ["chunk_9_9"])
	assert_eq(report["removed_battle_outcomes"], [GHOST_ENCOUNTER_ID])

	var cleaned: Dictionary = report["payload"]
	assert_eq(cleaned["inventory"], {OLD_ITEM_ID: 4})
	assert_eq(cleaned["flags"], {_old_done_flag: true, "first_mining_done": true})
	assert_eq(
		cleaned["chunk_deltas"],
		{"chunk_0_0": [{"cell_x": 1, "cell_y": 2, "destroyed": true}]}
	)
	assert_eq(cleaned["battle_outcomes"], {OLD_ENCOUNTER_ID: {"result": "victory", "turns": 3}})


func test_divergent_cleanup_never_mutates_the_input_payload() -> void:
	var payload: Dictionary = _divergent_payload()
	var report: Dictionary = SaveCodec.sanitize_payload_against_content(
		payload, NEW_CONTENT_HASH, _superset_defs()
	)

	assert_true(bool(report["changed"]))
	assert_eq(int((payload["inventory"] as Dictionary).get(GHOST_ITEM_ID, 0)), 7)
	assert_true(bool((payload["flags"] as Dictionary).get("event_%s_done" % GHOST_EVENT_ID, false)))
	assert_true((payload["chunk_deltas"] as Dictionary).has("chunk_9_9"))
	assert_true((payload["battle_outcomes"] as Dictionary).has(GHOST_ENCOUNTER_ID))


func test_done_flag_of_existing_event_and_plain_flags_survive_divergent_cleanup() -> void:
	## 孤儿清理只针对"引用不存在事件的 event_*_done flag"：现存事件的 done
	## flag 与任意非 done 形态 flag（里程碑/政策/提示等）一律保留。
	var payload: Dictionary = _divergent_payload()
	payload["flags"]["policy_exploit"] = true
	payload["flags"]["hint_move_seen"] = true

	var report: Dictionary = SaveCodec.sanitize_payload_against_content(
		payload, NEW_CONTENT_HASH, _superset_defs()
	)

	assert_eq(str(report["policy"]), "hash_divergent")
	var flags: Dictionary = (report["payload"] as Dictionary)["flags"]
	assert_true(bool(flags.get(_old_done_flag, false)), "现存事件的 done flag 必须保留。")
	assert_true(bool(flags.get("first_mining_done", false)))
	assert_true(bool(flags.get("policy_exploit", false)), "非 done 形态 flag 不得误删。")
	assert_true(bool(flags.get("hint_move_seen", false)))
	assert_false(flags.has("event_%s_done" % GHOST_EVENT_ID))


func test_missing_chunk_ids_key_skips_chunk_rule_without_touching_other_rules() -> void:
	## defs 未携带 chunk_ids（调用方无世界网格目录）时跳过 chunk 规则，
	## 其余三条规则照常执行——声明式规则彼此独立。
	var defs: Dictionary = _superset_defs()
	defs.erase("chunk_ids")
	var payload: Dictionary = _divergent_payload()

	var report: Dictionary = SaveCodec.sanitize_payload_against_content(
		payload, NEW_CONTENT_HASH, defs
	)

	assert_eq(str(report["policy"]), "hash_divergent")
	assert_true((report["removed_chunk_deltas"] as Array).is_empty())
	assert_eq(report["removed_inventory"], [GHOST_ITEM_ID])
	assert_true((report["payload"] as Dictionary)["chunk_deltas"].has("chunk_9_9"))


# ---------------------------------------------------------------- golden 一致性


func test_golden_fixture_content_hash_equals_bootstrapped_content_hash() -> void:
	## golden fixture 的 content_hash 必须等于对 res://data 做一次真实 bootstrap
	## 的总哈希（六类定义 + HASH_CONFIG_FILES 进度配置文件——G7P-2 S1/S5/S10
	## 起为 endings/characters/event_chain/ending_gate/objectives/hints/
	## world_config 七文件）：锁定哈希语义扩展与 golden 重生成的连贯性——
	## 内容数据任何改动都必须伴随 golden 重生成（政策文档的维护契约）。
	var db: Node = (load(CONTENT_DB_PATH) as Script).new()
	add_child_autofree(db)
	var boot: AppResult = db.bootstrap("res://data")
	assert_true(boot.is_ok, boot.message)

	var golden_text: String = FileAccess.get_file_as_string(GOLDEN_RESOURCE_PATH)
	assert_true(golden_text.length() > 0, "Golden fixture must exist and be non-empty.")
	var golden: Dictionary = JSON.parse_string(golden_text) as Dictionary
	assert_eq(str(golden["payload"]["content_hash"]), db.content_hash())
