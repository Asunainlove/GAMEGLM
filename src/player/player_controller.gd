extends CharacterBody2D
## Player controller (WP02). Presentation-only node: it converts input into
## movement and emits intent signals. It never mutates persistent state; the
## world/interaction layer subscribes to the signals and goes through
## GameState + StatePatch (contract module-contracts.md section 0/4).
##
## Visual: Player/Sprite is AnimatedSprite2D (ART-019 explore frames: idle,
## walk, mine, place, talk). Action anims sync from existing intent signals
## only — no new gameplay systems. Controller API and flat node paths stay
## unchanged for tests.

signal interact_requested
signal mine_requested(cell: Vector2i)
signal place_requested(cell: Vector2i)

const CELL_SIZE: int = 32
const DEFAULT_FACING: Vector2 = Vector2.DOWN
const ANIM_IDLE: StringName = &"idle"
const ANIM_WALK: StringName = &"walk"
const ANIM_MINE: StringName = &"mine"
const ANIM_PLACE: StringName = &"place"
const ANIM_TALK: StringName = &"talk"

@export var move_speed: int = 160

var facing: Vector2 = DEFAULT_FACING
## Injectable cell resolver; when unset, the target cell falls back to the
## mouse position snapped to the world grid.
var cell_resolver: Callable = Callable()

## True while a one-shot action animation (mine/place/talk) is playing so
## idle/walk sync does not interrupt it.
var _action_playing: bool = false

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	if _sprite != null and not _sprite.animation_finished.is_connected(_on_sprite_animation_finished):
		_sprite.animation_finished.connect(_on_sprite_animation_finished)


static func compute_velocity(input_vec: Vector2, speed: int) -> Vector2:
	if input_vec == Vector2.ZERO:
		return Vector2.ZERO
	return input_vec.normalized() * float(speed)


func _physics_process(_delta: float) -> void:
	var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = compute_velocity(input_vec, move_speed)
	set_facing_from_velocity(velocity)
	_sync_sprite()
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		interact_requested.emit()
		_play_action(ANIM_TALK)
	elif event.is_action_pressed("mine"):
		mine_requested.emit(resolve_target_cell())
		_play_action(ANIM_MINE)
	elif event.is_action_pressed("place"):
		place_requested.emit(resolve_target_cell())
		_play_action(ANIM_PLACE)


func set_facing_from_velocity(new_velocity: Vector2) -> void:
	if new_velocity != Vector2.ZERO:
		facing = new_velocity.normalized()


func resolve_target_cell() -> Vector2i:
	if cell_resolver.is_valid():
		var resolved: Variant = cell_resolver.call()
		if resolved is Vector2i:
			return resolved
		if resolved is Vector2:
			return Vector2i((resolved as Vector2).floor())
		push_warning(
			"player_controller.cell_resolver returned %s, expected Vector2i." % type_string(typeof(resolved))
		)
		return Vector2i.ZERO
	return default_target_cell()


func default_target_cell() -> Vector2i:
	return Vector2i((get_global_mouse_position() / CELL_SIZE).floor())


## Idle when stopped; walk when moving. Horizontal facing flips the sprite
## (ART-019: right-facing frames + flip_h for left). One-shot action anims
## (mine/place/talk) lock until animation_finished.
func _sync_sprite() -> void:
	if _sprite == null:
		return
	if facing.x != 0.0:
		_sprite.flip_h = facing.x < 0.0
	if _action_playing:
		return
	var wanted: StringName = ANIM_WALK if velocity != Vector2.ZERO else ANIM_IDLE
	if _sprite.animation != wanted:
		_sprite.play(wanted)


func _play_action(anim: StringName) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	if not _sprite.sprite_frames.has_animation(anim):
		return
	_action_playing = true
	_sprite.play(anim)


func _on_sprite_animation_finished() -> void:
	if not _action_playing:
		return
	_action_playing = false
	_sync_sprite()
