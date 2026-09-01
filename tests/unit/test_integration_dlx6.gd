extends GutTest

## DLX-6 读档内容政策集成测试：boot 读档点（GameSession._ready →
## _try_load_autosave）的三档政策落地——divergent 孤儿降级清理 + 当前
## content_hash 回写（set_content_hash 专用 op）、superset（纯新增内容包）
## 旧档无损载入、hash_match 收敛后零额外写入。除被测链路外全部经注入的
## 独立 GameState 实例（真实 patch 管线）驱动，不污染全局 autoload。

const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"

## 每个 before_each 生成互不重用的存档根，杜绝自动读档串场。
static var _save_root_seq: int = 0

var store: Node
var world: Node2D
var _save_root: String = ""


func before_each() -> void:
	if not ContentDB.is_bootstrapped():
		var boot: AppResult = ContentDB.bootstrap()
		assert_true(boot.is_ok, "ContentDB bootstrap must succeed: %s" % boot.message)
	_save_root_seq += 1
	_save_root = "user://saves_dlx6_%d_%d" % [Time.get_ticks_msec(), _save_root_seq]
	assert_true(SaveService.configure_root_for_tests(_save_root).is_ok)
	store = GAME_STATE_SCRIPT.new()
	world = _make_world()


func after_each() -> void:
	if is_instance_valid(world):
		world.free()
	if is_instance_valid(store):
		store.free()
	world = null
	store = null


# ---------------------------------------------------------------- 场景构造


func _make_world() -> Node2D:
	var packed := load(WORLD_SCENE_PATH) as PackedScene
	var world_node := packed.instantiate() as Node2D
	world_node.set("snapshot_provider", Callable(store, "snapshot"))
	add_child_autofree(world_node)
	return world_node


func _base_snapshot() -> Dictionary:
	## 一个引用真实内容定义的合法进度快照（物品/事件 done/网格内 chunk/
	## 真实遭遇战果/建筑），content_hash 指向一个"旧内容包"哈希。
	var state: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(state)
	var patch: StatePatch = state.begin_patch("dlx6_seed", 0)
	patch.add_item("starsoil_dust", 6)
	patch.set_flag("first_mining_done", true)
	patch.set_destructible_cell("chunk_0_0", 3, 4, true)
	patch.place_building("anchor_block", "chunk_0_0", 8, 9)
	patch.record_battle_outcome("encounter_first_drift", "victory", 4)
	assert_true(state.commit(patch).is_ok)
	var snapshot: Dictionary = state.snapshot()
	snapshot["content_hash"] = "f".repeat(64)
	snapshot["world_seed"] = 7
	return snapshot


func _superset_snapshot() -> Dictionary:
	## 相对当前内容为"纯新增"的旧档：只引用真实定义，无任何孤儿。
	var snapshot: Dictionary = _base_snapshot()
	return snapshot


func _divergent_snapshot() -> Dictionary:
	## 旧档引用了当前内容中不存在的物品/事件/遭遇，以及世界网格外的 chunk。
	var snapshot: Dictionary = _base_snapshot()
	(snapshot["inventory"] as Dictionary)["ghost_material"] = 2
	snapshot["flags"]["event_event_ghost_done"] = true
	(snapshot["chunk_deltas"] as Dictionary)["chunk_9_9"] = [
		{"cell_x": 1, "cell_y": 1, "destroyed": true},
	]
	(snapshot["battle_outcomes"] as Dictionary)["encounter_ghost"] = {
		"result": "defeat", "turns": 2,
	}
	return snapshot


## 把 snapshot 预置进 auto 槽，再经全新 GameSession._ready 的 boot 读档链
## 载入全新 store，返回最终持久快照（与生产读档路径完全同构）。
func _load_snapshot_through_boot(snapshot: Dictionary) -> Dictionary:
	assert_true(SaveService.save_slot("auto", snapshot).is_ok, "预置 auto 槽存档必须成功。")
	var fresh_store: Node = GAME_STATE_SCRIPT.new()
	var fresh_session := GameSession.new()
	fresh_session.store = fresh_store
	fresh_session.world = world
	add_child_autofree(fresh_session)
	var payload: Dictionary = fresh_store.snapshot()
	fresh_session.free()
	fresh_store.free()
	return payload


# ---------------------------------------------------------------- divergent


func test_divergent_save_sanitizes_orphans_and_writes_back_current_hash() -> void:
	var payload: Dictionary = _load_snapshot_through_boot(_divergent_snapshot())

	# 孤儿降级清理：引用不存在定义/网格外的条目被移除。
	assert_eq(
		payload["inventory"], {"starsoil_dust": 6},
		"ghost_material 必须被清理，真实物品必须原样保留。"
	)
	var flags: Dictionary = payload["flags"] as Dictionary
	assert_false(flags.get("event_event_ghost_done", false), "孤儿事件 done flag 必须被清理。")
	assert_true(bool(flags.get("first_mining_done", false)), "真实进度 flag 必须保留。")
	var deltas: Dictionary = payload["chunk_deltas"] as Dictionary
	assert_false(deltas.has("chunk_9_9"), "世界网格外的 chunk 条目必须被清理。")
	assert_true(deltas.has("chunk_0_0"), "网格内 chunk 条目必须保留。")
	var outcomes: Dictionary = payload["battle_outcomes"] as Dictionary
	assert_false(outcomes.has("encounter_ghost"), "不存在遭遇的战果必须被清理。")
	assert_true(outcomes.has("encounter_first_drift"), "真实遭遇战果必须保留。")
	assert_eq((payload["placed_buildings"] as Array).size(), 1, "建筑不属于清理规则，必须保留。")

	# 当前 content_hash 回写（set_content_hash 专用 op）。
	assert_eq(
		str(payload["content_hash"]), ContentDB.content_hash(),
		"读档政策落地后持久状态必须携带当前内容总哈希。"
	)


# ---------------------------------------------------------------- superset


func test_superset_save_loads_losslessly_and_updates_content_hash() -> void:
	var saved: Dictionary = _superset_snapshot()
	var revision_before: int = int(saved["revision"])

	var payload: Dictionary = _load_snapshot_through_boot(saved)

	assert_eq(int((payload["inventory"] as Dictionary).get("starsoil_dust", 0)), 6)
	assert_eq((payload["placed_buildings"] as Array).size(), 1)
	assert_true(bool((payload["flags"] as Dictionary).get("first_mining_done", false)))
	assert_eq(
		str(payload["content_hash"]), ContentDB.content_hash(),
		"superset 接受后同样必须把当前内容总哈希回写。"
	)
	assert_eq(
		int(payload["revision"]), revision_before + 1,
		"唯一允许的持久变化是 content_hash 回写 patch（revision 恰 +1）。"
	)


# ---------------------------------------------------------------- hash_match


func test_hash_match_save_loads_without_extra_writes() -> void:
	## 已收敛存档（content_hash = 当前内容总哈希）：hash_match 原样载入，
	## 不产生任何额外 patch（revision 不变）。
	var saved: Dictionary = _superset_snapshot()
	saved["content_hash"] = ContentDB.content_hash()
	var revision_before: int = int(saved["revision"])

	var payload: Dictionary = _load_snapshot_through_boot(saved)

	assert_eq(int(payload["revision"]), revision_before, "hash_match 不得产生任何回写 patch。")
	assert_eq(str(payload["content_hash"]), ContentDB.content_hash())
	assert_eq(int((payload["inventory"] as Dictionary).get("starsoil_dust", 0)), 6)
