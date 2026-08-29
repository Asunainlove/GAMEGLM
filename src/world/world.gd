extends Node2D

## world.tscn root script (module contract section 4).
##
## Owns the 4x2 slice-world chunk grid (chunk_0_0 .. chunk_3_1), renders only the
## initial chunk_0_0 through WorldRenderer, and keeps the presentation in sync
## with GameState by polling snapshot revisions. This script never mutates
## persistent state: it reads snapshots (injectable provider) and mirrors
## chunk_deltas onto the TileMapLayers.

const CHUNK_GRID_SIZE := Vector2i(4, 2)
const RENDERED_CHUNK_ID: String = "chunk_0_0"
const SNAPSHOT_POLL_SECONDS: float = 0.5
const SNAPSHOT_POLL_TIMER_NAME: String = "SnapshotPollTimer"

@export var player_scene_path: String = "res://scenes/player.tscn"

## Injectable snapshot source (parallel-development seam). When unset, the
## GameState autoload is used. Presentation only ever reads.
var snapshot_provider: Callable = Callable()

var _chunks: Dictionary = {}
var _renderer: WorldRenderer
var _last_revision: int = -1

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
	_renderer.render(_chunks[RENDERED_CHUNK_ID])
	refresh_from_snapshot()
	_spawn_player()
	_start_snapshot_polling()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_overlay") and _ore_overlay != null:
		_ore_overlay.visible = not _ore_overlay.visible


## Gathering contract seam: resolves a cell to its frozen gathering definition.
## Unknown chunks degrade to the soil def instead of erroring.
func cell_def_at(chunk_id: String, cell: Vector2i) -> Dictionary:
	var cells: Dictionary = {}
	if _chunks.has(chunk_id):
		cells = (_chunks[chunk_id] as Dictionary).get("cells", {})
	return ChunkData.cell_def(cells, cell)


## Generated chunk ids, sorted (the full 4x2 grid: chunk_0_0 .. chunk_3_1).
func chunk_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in _chunks:
		ids.append(str(id))
	ids.sort()
	return ids


## Re-reads the snapshot and mirrors destroyed cells of the rendered chunk onto
## both TileMapLayers. Public so tests (and future load flows) can force a sync.
func refresh_from_snapshot() -> void:
	var snapshot := _read_snapshot()
	_last_revision = int(snapshot.get("revision", 0))
	if _renderer != null:
		_renderer.apply_deltas(_destroyed_cells(snapshot, RENDERED_CHUNK_ID))


func _generate_chunks() -> void:
	var world_seed := int(_read_snapshot().get("world_seed", 0))
	for grid_y: int in CHUNK_GRID_SIZE.y:
		for grid_x: int in CHUNK_GRID_SIZE.x:
			var chunk_id := "chunk_%d_%d" % [grid_x, grid_y]
			_chunks[chunk_id] = ChunkData.generate(chunk_id, world_seed)


func _read_snapshot() -> Dictionary:
	if snapshot_provider.is_valid():
		var provided: Variant = snapshot_provider.call()
		if provided is Dictionary:
			return provided
		push_warning("World: snapshot provider must return a Dictionary; falling back to GameState.")
	return GameState.snapshot()


func _destroyed_cells(snapshot: Dictionary, chunk_id: String) -> Array[Vector2i]:
	var destroyed: Array[Vector2i] = []
	var deltas: Array = (snapshot.get("chunk_deltas", {}) as Dictionary).get(chunk_id, [])
	for delta_value: Variant in deltas:
		var delta := delta_value as Dictionary
		if delta == null or not bool(delta.get("destroyed", false)):
			continue
		destroyed.append(Vector2i(int(delta.get("cell_x", 0)), int(delta.get("cell_y", 0))))
	return destroyed


## Parallel-scene reference pattern (contract section 0): player.tscn belongs to
## WP02 and may not exist yet. Missing scenes are skipped with a warning, never
## crash; the path is injectable so tests and app wiring can point elsewhere.
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
	if player_node2d != null and _player_spawn != null:
		player_node2d.position = _player_spawn.position
	add_child(player)


func _start_snapshot_polling() -> void:
	var poll_timer := Timer.new()
	poll_timer.name = SNAPSHOT_POLL_TIMER_NAME
	poll_timer.wait_time = SNAPSHOT_POLL_SECONDS
	poll_timer.autostart = true
	poll_timer.timeout.connect(_on_snapshot_poll_timeout)
	add_child(poll_timer)


func _on_snapshot_poll_timeout() -> void:
	if int(_read_snapshot().get("revision", 0)) != _last_revision:
		refresh_from_snapshot()
