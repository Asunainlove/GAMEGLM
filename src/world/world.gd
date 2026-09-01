extends Node2D

## world.tscn root script (module contract section 4).
##
## Owns the 4x2 slice-world chunk grid (chunk_0_0 .. chunk_3_1), renders every
## chunk through WorldRenderer at its chunk origin (W002-GAP3), and keeps the
## presentation in sync with GameState by polling snapshot revisions. This
## script never mutates persistent state: it reads snapshots (injectable
## provider) and mirrors chunk_deltas of ALL chunks onto the TileMapLayers.
##
## Coordinate conventions (W002-GAP3):
## - Chunk data (ChunkData.generate) is chunk-local (0..31 per axis).
## - App-layer cells (player intents, chunk_deltas, placed_buildings) are
##   world-absolute. cell_def_at() therefore translates world cells into
##   chunk-local lookups via ChunkData.chunk_origin.

const CHUNK_GRID_SIZE := Vector2i(4, 2)
## 32 cells x 32 px = 1024 px per chunk edge.
const CHUNK_PIXELS: int = ChunkData.CHUNK_SIZE * ChunkData.CELL_SIZE
## Full world extent in pixels (4 x 1024, 2 x 1024).
const WORLD_PIXEL_SIZE := Vector2i(CHUNK_GRID_SIZE.x * CHUNK_PIXELS, CHUNK_GRID_SIZE.y * CHUNK_PIXELS)
const SNAPSHOT_POLL_SECONDS: float = 0.5
const SNAPSHOT_POLL_TIMER_NAME: String = "SnapshotPollTimer"
const DEFAULT_PLAYER_START_CELL: Vector2i = Vector2i(-1, -1)
## Player scene root sits in the "player" group (scenes/player.tscn).
const PLAYER_GROUP: String = "player"
## DLX-4 世界回应 flag：exploit 路线置位后，程序生成的 chunk 矿脉富集
##（ChunkData.generate enriched=true）。
const WORLD_RESPONSE_EXPLOITED_FLAG: String = "world_response_exploited"

@export var player_scene_path: String = "res://scenes/player.tscn"

## Injectable snapshot source (parallel-development seam). When unset, the
## GameState autoload is used. Presentation only ever reads.
var snapshot_provider: Callable = Callable()

## Injectable saved start cell (world grid coordinates). Vector2i(-1, -1) falls
## back to snapshot.player.position; the default cell (0, 0) keeps the
## PlayerSpawn marker so fresh runs never drop the player at the world corner.
var player_start_cell: Vector2i = DEFAULT_PLAYER_START_CELL

var _chunks: Dictionary = {}
var _renderer: WorldRenderer
var _last_revision: int = -1

## DLX-4 世界回应运行态：最近一次生成/重生成所用 exploited 值与其初始化标记
##（_ready 前的首次 _generate_chunks 记为已初始化，此后轮询只对跳变反应）。
var _world_response_exploited: bool = false
var _world_response_initialized: bool = false

@onready var _ground_layer: TileMapLayer = $Ground
@onready var _ore_overlay: TileMapLayer = $OreOverlay
@onready var _buildings: Node2D = $Buildings
@onready var _player_spawn: Marker2D = $PlayerSpawn


func _ready() -> void:
	_renderer = WorldRenderer.new()
	_renderer.name = "WorldRenderer"
	add_child(_renderer)
	_renderer.ground_layer = _ground_layer
	_renderer.ore_layer = _ore_overlay

	_generate_chunks()
	_render_all_chunks()
	refresh_from_snapshot()
	_spawn_player()
	_start_snapshot_polling()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_overlay") and _ore_overlay != null:
		_ore_overlay.visible = not _ore_overlay.visible


## Gathering contract seam: resolves a cell to its frozen gathering definition.
## `cell` is world-absolute; nonzero chunks are translated to chunk-local
## coordinates first. Unknown chunks degrade to the soil def instead of erroring.
func cell_def_at(chunk_id: String, cell: Vector2i) -> Dictionary:
	var cells: Dictionary = {}
	if _chunks.has(chunk_id):
		cells = (_chunks[chunk_id] as Dictionary).get("cells", {})
	return ChunkData.cell_def(cells, cell - ChunkData.chunk_origin(chunk_id))


## Generated chunk ids, sorted (the full 4x2 grid: chunk_0_0 .. chunk_3_1).
func chunk_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in _chunks:
		ids.append(str(id))
	ids.sort()
	return ids


## Re-reads the snapshot and mirrors destroyed cells of EVERY chunk onto both
## TileMapLayers (W002-GAP3 full sync). Public so tests (and future load flows)
## can force a sync.
func refresh_from_snapshot() -> void:
	var snapshot := _read_snapshot()
	_last_revision = int(snapshot.get("revision", 0))
	if _renderer == null:
		return
	var deltas: Dictionary = snapshot.get("chunk_deltas", {}) as Dictionary
	for chunk_id_value: Variant in deltas:
		var chunk_id := str(chunk_id_value)
		if not _chunks.has(chunk_id):
			continue
		var origin := ChunkData.chunk_origin(chunk_id)
		for delta_value: Variant in deltas[chunk_id_value]:
			var delta := delta_value as Dictionary
			if delta == null or not bool(delta.get("destroyed", false)):
				continue
			var world_cell := Vector2i(int(delta.get("cell_x", 0)), int(delta.get("cell_y", 0)))
			_renderer.apply_delta(chunk_id, world_cell - origin, true)


## Load-flow seam (W002-GAP3): moves an already-spawned player to a saved world
## grid cell. Returns false when no player node exists.
func place_player_at_cell(cell: Vector2i) -> bool:
	var player := _find_player_node()
	if player == null:
		return false
	player.position = Vector2(cell) * float(ChunkData.CELL_SIZE)
	return true


func _generate_chunks() -> void:
	var snapshot := _read_snapshot()
	var world_seed := int(snapshot.get("world_seed", 0))
	# DLX-4：启动生成（含读档）按快照 flags 决定富集；并记为跳变检测基线。
	_world_response_exploited = _exploited_flag_of(snapshot)
	_world_response_initialized = true
	for grid_y: int in CHUNK_GRID_SIZE.y:
		for grid_x: int in CHUNK_GRID_SIZE.x:
			var chunk_id := "chunk_%d_%d" % [grid_x, grid_y]
			if chunk_id == ChunkData.MINE_CHUNK_ID:
				# W002-GAP2：手工矿井/Boss 区（authored，无 RNG）覆盖程序生成结果；
				# 其余 7 chunk 保持种子确定性生成。
				_chunks[chunk_id] = ChunkData.generate_mine(chunk_id)
			else:
				_chunks[chunk_id] = ChunkData.generate(chunk_id, world_seed, _world_response_exploited)


## 只读提取 exploited flag；快照缺 flags 时按 false。
func _exploited_flag_of(snapshot: Dictionary) -> bool:
	return bool((snapshot.get("flags", {}) as Dictionary).get(WORLD_RESPONSE_EXPLOITED_FLAG, false))


## DLX-4 世界回应重生成（轮询 revision 变化后调用）：exploited flag 相对上次
## 生成发生跳变时，对无破坏记录（scar-free）的程序 chunk 以新参数重新
## generate 并全层重渲染，随后重放 chunk_deltas——已破坏格保持擦除；有破坏
## 记录的 chunk 保留原始生成数据（破坏格不得在富集数据中"复活"成为可采格；
## Gathering 亦有 destroyed delta 硬门）。矿井 chunk 恒为 authored，不参与。
## 实现选择：scar-free 判定按"该 chunk 存在 destroyed delta"二值划分，重生成
## 后走 _render_all_chunks + refresh_from_snapshot 全层重绘 + delta 重放，
## 不做逐格局部补丁——跳变是一次性事件，全量重绘成本可忽略且正确性显然。
func _reconcile_world_response(snapshot: Dictionary) -> void:
	var exploited := _exploited_flag_of(snapshot)
	if not _world_response_initialized:
		_world_response_exploited = exploited
		_world_response_initialized = true
		return
	if exploited == _world_response_exploited:
		return
	_world_response_exploited = exploited
	_regenerate_scar_free_chunks(snapshot)


func _regenerate_scar_free_chunks(snapshot: Dictionary) -> void:
	var world_seed := int(snapshot.get("world_seed", 0))
	var deltas: Dictionary = snapshot.get("chunk_deltas", {}) as Dictionary
	var scarred: Dictionary = {}
	for chunk_id_value: Variant in deltas:
		for delta_value: Variant in deltas[chunk_id_value]:
			var delta := delta_value as Dictionary
			if delta != null and bool(delta.get("destroyed", false)):
				scarred[str(chunk_id_value)] = true
				break
	for grid_y: int in CHUNK_GRID_SIZE.y:
		for grid_x: int in CHUNK_GRID_SIZE.x:
			var chunk_id := "chunk_%d_%d" % [grid_x, grid_y]
			if chunk_id == ChunkData.MINE_CHUNK_ID or scarred.has(chunk_id):
				continue
			_chunks[chunk_id] = ChunkData.generate(chunk_id, world_seed, _world_response_exploited)
	_render_all_chunks()
	refresh_from_snapshot()


## Renders the full 4x2 chunk grid onto the shared layers, each chunk at its
## grid origin (grid coordinates x CHUNK_SIZE cells).
func _render_all_chunks() -> void:
	_renderer.clear_layers()
	for grid_y: int in CHUNK_GRID_SIZE.y:
		for grid_x: int in CHUNK_GRID_SIZE.x:
			var chunk_id := "chunk_%d_%d" % [grid_x, grid_y]
			_renderer.render(_chunks[chunk_id], Vector2i(grid_x, grid_y) * ChunkData.CHUNK_SIZE)


func _read_snapshot() -> Dictionary:
	if snapshot_provider.is_valid():
		var provided: Variant = snapshot_provider.call()
		if provided is Dictionary:
			return provided
		push_warning("World: snapshot provider must return a Dictionary; falling back to GameState.")
	return GameState.snapshot()


## Parallel-scene reference pattern (contract section 0): player.tscn belongs to
## WP02 and may not exist yet. Missing scenes are skipped with a warning, never
## crash; the path is injectable so tests and app wiring can point elsewhere.
## W002-GAP3: the spawn position honors snapshot.player.position (or the
## injectable player_start_cell) and the scene Camera2D becomes a child of the
## player so it follows movement with its world limits intact.
func _spawn_player() -> void:
	if not ResourceLoader.exists(player_scene_path):
		push_warning("World: player scene '%s' not found; skipping player spawn." % player_scene_path)
		return
	var player_scene := load(player_scene_path) as PackedScene
	if player_scene == null:
		push_warning("World: player scene '%s' failed to load; skipping player spawn." % player_scene_path)
		return
	var player: Node = player_scene.instantiate()
	if player == null:
		push_warning("World: player scene '%s' instantiated null; skipping player spawn." % player_scene_path)
		return
	var player_node2d := player as Node2D
	if player_node2d != null:
		var start_cell := _resolve_player_start_cell()
		if start_cell != DEFAULT_PLAYER_START_CELL and start_cell != Vector2i.ZERO:
			player_node2d.position = Vector2(start_cell) * float(ChunkData.CELL_SIZE)
		elif _player_spawn != null:
			player_node2d.position = _player_spawn.position
	add_child(player)
	_attach_camera(player_node2d)


## Start cell resolution: injected player_start_cell wins, then the snapshot's
## player.position. A missing/default position yields the sentinel that keeps
## the PlayerSpawn marker.
func _resolve_player_start_cell() -> Vector2i:
	if player_start_cell != DEFAULT_PLAYER_START_CELL:
		return player_start_cell
	var player_state := _read_snapshot().get("player", {}) as Dictionary
	var position := player_state.get("position", {}) as Dictionary
	if position.is_empty():
		return DEFAULT_PLAYER_START_CELL
	return Vector2i(int(position.get("x", 0)), int(position.get("y", 0)))


## Reparents the scene Camera2D under the spawned player (world.gd keeps it in
## world.tscn so the scene stays viewable without a player). The camera snaps
## to the player origin so a loaded run starts centered, not panning.
func _attach_camera(player: Node2D) -> void:
	if player == null:
		return
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	if camera.is_inside_tree() and player.is_inside_tree():
		camera.reparent(player)
	else:
		var previous_parent := camera.get_parent()
		if previous_parent != null:
			previous_parent.remove_child(camera)
		player.add_child(camera)
	camera.position = Vector2.ZERO


func _find_player_node() -> Node2D:
	for candidate: Node in find_children("*", "", true, false):
		if candidate.is_in_group(PLAYER_GROUP):
			return candidate as Node2D
	return null


func _start_snapshot_polling() -> void:
	var poll_timer := Timer.new()
	poll_timer.name = SNAPSHOT_POLL_TIMER_NAME
	poll_timer.wait_time = SNAPSHOT_POLL_SECONDS
	poll_timer.autostart = true
	poll_timer.timeout.connect(_on_snapshot_poll_timeout)
	add_child(poll_timer)


func _on_snapshot_poll_timeout() -> void:
	var snapshot := _read_snapshot()
	if int(snapshot.get("revision", 0)) == _last_revision:
		return
	# DLX-4：revision 推进后先检查世界回应 flag 跳变（可能重生成 + 重渲染 +
	# 重放 delta），再走常规 delta 同步。
	_reconcile_world_response(snapshot)
	refresh_from_snapshot()
