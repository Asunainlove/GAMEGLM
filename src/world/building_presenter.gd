class_name BuildingPresenter
extends RefCounted

## P0-B presentation: sync snapshot `placed_buildings` into `$Buildings` sprites.
## Probe ENV-21..26 contract ids first: `env_bld_<id>_{powered,unpowered}.png`
## under `world/buildings/` (AssetAdapter env_ → world). Legacy `<id>_powered`
## kept as last fallback. Missing art → visible 48×48 graybox. Powered skin
## follows PowerGrid allocation within World poll (~0.5–1s). No Autoload / SFX.

const CELL_SIZE: int = 32
const SPRITE_SIZE: int = 48
const DEFAULT_ASSET_BASE_DIR: String = "res://assets/art"
const BUILDING_ASSET_ID_FORMAT: String = "env_bld_%s_%s"
const BUILDING_LEGACY_PROBE_REL: String = "world/buildings/%s_%s.png"

## Cool dusk graybox (永暮余辉). Powered = slightly warmer/brighter; unpowered =
## dimmer. No decorative teal (teal = power/energy chrome only elsewhere).
const GRAYBOX_POWERED := Color(0.42, 0.40, 0.38, 0.95)
const GRAYBOX_UNPOWERED := Color(0.22, 0.22, 0.24, 0.90)

## asset_base_dir injectable for tests (user://).
var asset_base_dir: String = DEFAULT_ASSET_BASE_DIR

## building_id → {power_draw, power_supply, requires_room}. Injected by World.
var building_defs: Dictionary = {}


## Stable instance key matching GameSession power counting (chunk + cell).
static func instance_key(entry: Dictionary) -> String:
	return "%s|%d|%d" % [
		str(entry.get("chunk_id", "")),
		int(entry.get("cell_x", 0)),
		int(entry.get("cell_y", 0)),
	]


## World-pixel center of a placed building cell (1×1 footprint).
static func cell_center_pixels(entry: Dictionary) -> Vector2:
	var cell := Vector2(float(int(entry.get("cell_x", 0))), float(int(entry.get("cell_y", 0))))
	return (cell + Vector2(0.5, 0.5)) * float(CELL_SIZE)


## Per-instance powered map: keys from instance_key → bool.
## power_draw <= 0 (supply / passive) always powered skin; draw > 0 follows
## PowerGrid allocation order (first N instances of each id in input order).
static func powered_by_instance(buildings: Array, defs: Dictionary) -> Dictionary:
	var evaluation := PowerGrid.evaluate(buildings, defs)
	var remaining: Dictionary = {}
	for powered_value: Variant in evaluation.get("powered_ids", []):
		var powered_id := str(powered_value)
		remaining[powered_id] = int(remaining.get(powered_id, 0)) + 1
	var result: Dictionary = {}
	for building_value: Variant in buildings:
		var entry := building_value as Dictionary
		if entry == null:
			continue
		var key := instance_key(entry)
		var building_id := str(entry.get("building_id", ""))
		var building_def: Dictionary = defs.get(building_id, {}) as Dictionary
		var power_draw := int(building_def.get("power_draw", 0))
		if power_draw <= 0:
			result[key] = true
			continue
		if int(remaining.get(building_id, 0)) > 0:
			result[key] = true
			remaining[building_id] = int(remaining[building_id]) - 1
		else:
			result[key] = false
	return result


## Probe powered/unpowered texture; null when missing (caller grayboxes).
## Order: contract env_bld_<id>_<suffix> → explicit buildings path → legacy short name.
func probe_texture(building_id: String, powered: bool) -> Texture2D:
	if building_id.is_empty():
		return null
	var suffix := "powered" if powered else "unpowered"
	var asset_id := BUILDING_ASSET_ID_FORMAT % [building_id, suffix]
	var texture := AssetAdapter.texture(asset_id, asset_base_dir)
	if texture != null:
		return texture
	texture = AssetAdapter.texture_at("%s/world/buildings/%s.png" % [asset_base_dir, asset_id])
	if texture != null:
		return texture
	return AssetAdapter.texture_at(
		"%s/%s" % [asset_base_dir, BUILDING_LEGACY_PROBE_REL % [building_id, suffix]]
	)


## Spawn / despawn / update Sprite2D children under `parent` from placed list.
func sync(parent: Node2D, buildings: Array) -> void:
	if parent == null:
		return
	var powered_map := powered_by_instance(buildings, building_defs)
	var desired: Dictionary = {}
	for building_value: Variant in buildings:
		var entry := building_value as Dictionary
		if entry == null:
			continue
		var building_id := str(entry.get("building_id", ""))
		if building_id.is_empty():
			continue
		var key := instance_key(entry)
		desired[key] = entry
		var powered := bool(powered_map.get(key, true))
		var node := parent.get_node_or_null(key) as Node2D
		if node == null:
			node = _make_node(key)
			parent.add_child(node)
		_apply_visual(node, building_id, powered)
		node.position = cell_center_pixels(entry)
	var stale: Array[Node] = []
	for child: Node in parent.get_children():
		if not desired.has(str(child.name)):
			stale.append(child)
	for child: Node in stale:
		parent.remove_child(child)
		child.free()


func _make_node(key: String) -> Node2D:
	var root := Node2D.new()
	root.name = key
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = true
	root.add_child(sprite)
	var graybox := ColorRect.new()
	graybox.name = "Graybox"
	graybox.size = Vector2(SPRITE_SIZE, SPRITE_SIZE)
	graybox.position = Vector2(-SPRITE_SIZE * 0.5, -SPRITE_SIZE * 0.5)
	graybox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(graybox)
	return root


func _apply_visual(node: Node2D, building_id: String, powered: bool) -> void:
	var sprite := node.get_node_or_null("Sprite") as Sprite2D
	var graybox := node.get_node_or_null("Graybox") as ColorRect
	var texture := probe_texture(building_id, powered)
	if texture != null and sprite != null:
		sprite.texture = texture
		sprite.visible = true
		if graybox != null:
			graybox.visible = false
		node.set_meta("powered", powered)
		node.set_meta("building_id", building_id)
		node.set_meta("graybox", false)
		return
	if sprite != null:
		sprite.texture = null
		sprite.visible = false
	if graybox != null:
		graybox.visible = true
		graybox.color = GRAYBOX_POWERED if powered else GRAYBOX_UNPOWERED
	node.set_meta("powered", powered)
	node.set_meta("building_id", building_id)
	node.set_meta("graybox", true)


## ENV-27: one-shot build dust over a cell (presentation-only). Plays f0→f1 then frees.
## Spec: 64×64, ~120 ms/frame, above building sprites under `$Buildings`. Missing art → null.
const DUST_ASSET_IDS: Array[String] = [
	"env_fx_build_dust_seq_f0",
	"env_fx_build_dust_seq_f1",
]
const DUST_FRAME_DURATION_SEC: float = 0.12
const DUST_ANIM_NAME: String = "build_dust"
const DUST_Z_INDEX: int = 10


func play_build_dust(parent: Node2D, world_position: Vector2) -> AnimatedSprite2D:
	if parent == null:
		return null
	var frames := SpriteFrames.new()
	frames.add_animation(DUST_ANIM_NAME)
	frames.set_animation_loop(DUST_ANIM_NAME, false)
	var fps := 1.0 / DUST_FRAME_DURATION_SEC
	frames.set_animation_speed(DUST_ANIM_NAME, fps)
	var loaded := 0
	for asset_id: String in DUST_ASSET_IDS:
		var texture := AssetAdapter.texture(asset_id, asset_base_dir)
		if texture == null:
			continue
		frames.add_frame(DUST_ANIM_NAME, texture)
		loaded += 1
	if loaded == 0:
		return null
	var sprite := AnimatedSprite2D.new()
	sprite.name = "BuildDust"
	sprite.centered = true
	sprite.z_index = DUST_Z_INDEX
	sprite.sprite_frames = frames
	sprite.position = world_position
	sprite.animation = DUST_ANIM_NAME
	parent.add_child(sprite)
	sprite.animation_finished.connect(sprite.queue_free)
	sprite.play(DUST_ANIM_NAME)
	return sprite
