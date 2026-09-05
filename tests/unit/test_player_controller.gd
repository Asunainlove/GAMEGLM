extends GutTest

const PLAYER_SCENE_PATH: String = "res://scenes/player.tscn"
const PLAYER_SCRIPT_PATH: String = "res://src/player/player_controller.gd"
const REQUIRED_ACTIONS: Array[String] = [
	"move_left",
	"move_right",
	"move_up",
	"move_down",
	"interact",
	"mine",
	"place",
	"toggle_inventory",
	"toggle_overlay",
	"menu",
]

## Injected callable targets must be stored on test instance fields: a Callable
## only holds an ObjectID, so a temporary RefCounted target would be freed
## before the controller ever calls it (lesson learned in WP03).
var _resolver_host: CellResolverHost = null


class CellResolverHost:
	var call_count: int = 0

	func resolve() -> Vector2i:
		call_count += 1
		return Vector2i(3, 4)


func _player_scene() -> PackedScene:
	var scene: PackedScene = load(PLAYER_SCENE_PATH)
	assert_not_null(scene, "Missing player scene: %s" % PLAYER_SCENE_PATH)
	return scene


func _player_script() -> Script:
	var script: Script = load(PLAYER_SCRIPT_PATH)
	assert_not_null(script, "Missing player controller script: %s" % PLAYER_SCRIPT_PATH)
	return script


func _spawn_player() -> Node:
	var player: Node = _player_scene().instantiate()
	add_child_autofree(player)
	return player


func _action_event(action: String, pressed: bool) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func test_input_map_registers_all_ten_contract_actions() -> void:
	for action: String in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action), "Missing input action: %s" % action)


func test_player_scene_matches_contract_layout() -> void:
	var player: Node = _spawn_player()
	assert_eq(player.name, "Player")
	assert_true(player is CharacterBody2D, "Player root must be a CharacterBody2D.")
	assert_true(player.is_in_group("player"), "Player root must join group 'player'.")
	var attached_script: Script = player.get_script()
	assert_not_null(attached_script)
	assert_eq(attached_script.resource_path, PLAYER_SCRIPT_PATH)

	var sprite: Node = player.get_node_or_null("Sprite")
	assert_true(sprite is AnimatedSprite2D, "Sprite must be AnimatedSprite2D (Luoxian idle/walk).")
	if sprite is AnimatedSprite2D:
		var anim: AnimatedSprite2D = sprite as AnimatedSprite2D
		assert_not_null(anim.sprite_frames, "Sprite must have SpriteFrames.")
		if anim.sprite_frames != null:
			assert_true(anim.sprite_frames.has_animation(&"idle"), "SpriteFrames must include idle.")
			assert_true(anim.sprite_frames.has_animation(&"walk"), "SpriteFrames must include walk.")
			assert_eq(anim.sprite_frames.get_frame_count(&"idle"), 1)
			assert_eq(anim.sprite_frames.get_frame_count(&"walk"), 2)
			var idle_tex: Texture2D = anim.sprite_frames.get_frame_texture(&"idle", 0)
			assert_not_null(idle_tex)
			if idle_tex != null:
				assert_eq(
					idle_tex.resource_path,
					"res://assets/art/characters/luoxian/actions/luoxian_action_idle_00.png"
				)

	var collision: Node = player.get_node_or_null("Collision")
	assert_true(collision is CollisionShape2D, "Collision must be a CollisionShape2D.")
	if collision is CollisionShape2D:
		var body_shape: Shape2D = (collision as CollisionShape2D).shape
		assert_true(body_shape is RectangleShape2D, "Collision must use a RectangleShape2D.")
		if body_shape is RectangleShape2D:
			assert_eq((body_shape as RectangleShape2D).size, Vector2(20, 20))

	var probe: Node = player.get_node_or_null("InteractionProbe")
	assert_true(probe is Area2D, "InteractionProbe must be an Area2D.")
	if probe is Area2D:
		var probe_shape_node: Node = (probe as Area2D).get_node_or_null("Collision")
		assert_true(probe_shape_node is CollisionShape2D, "InteractionProbe needs a CollisionShape2D.")
		if probe_shape_node is CollisionShape2D:
			var probe_shape: Shape2D = (probe_shape_node as CollisionShape2D).shape
			assert_true(probe_shape is CircleShape2D, "InteractionProbe must use a CircleShape2D.")
			if probe_shape is CircleShape2D:
				assert_almost_eq((probe_shape as CircleShape2D).radius, 40.0, 0.001)


func test_compute_velocity_scales_axis_input_by_speed() -> void:
	var right_velocity: Vector2 = _player_script().compute_velocity(Vector2(1, 0), 160)
	assert_eq(right_velocity, Vector2(160, 0))
	var up_velocity: Vector2 = _player_script().compute_velocity(Vector2(0, -1), 160)
	assert_eq(up_velocity, Vector2(0, -160))


func test_compute_velocity_normalizes_magnitude_before_scaling() -> void:
	var velocity: Vector2 = _player_script().compute_velocity(Vector2(2, 0), 160)
	assert_eq(velocity, Vector2(160, 0), "Input magnitude must not change output speed.")


func test_compute_velocity_normalizes_diagonal_input_to_full_speed() -> void:
	var velocity: Vector2 = _player_script().compute_velocity(Vector2(1, 1), 160)
	assert_almost_eq(velocity.length(), 160.0, 0.001, "Diagonal input must keep full speed.")
	assert_almost_eq(velocity.x, 113.137, 0.01)
	assert_almost_eq(velocity.y, 113.137, 0.01)


func test_compute_velocity_returns_zero_for_neutral_input() -> void:
	assert_eq(_player_script().compute_velocity(Vector2.ZERO, 160), Vector2.ZERO)


func test_facing_defaults_down_and_follows_velocity_direction() -> void:
	var player: Node = _spawn_player()
	assert_eq(player.facing, Vector2.DOWN, "Facing must default to Vector2.DOWN.")
	player.set_facing_from_velocity(Vector2(160, 0))
	assert_eq(player.facing, Vector2.RIGHT)
	player.set_facing_from_velocity(Vector2(0, -160))
	assert_eq(player.facing, Vector2.UP)
	player.set_facing_from_velocity(Vector2.ZERO)
	assert_eq(player.facing, Vector2.UP, "Idle velocity must not change facing.")


func test_interact_action_emits_interact_requested() -> void:
	var player: Node = _spawn_player()
	watch_signals(player)
	player._unhandled_input(_action_event("interact", true))
	assert_signal_emitted(player, "interact_requested")


func test_released_interact_action_does_not_emit() -> void:
	var player: Node = _spawn_player()
	watch_signals(player)
	player._unhandled_input(_action_event("interact", false))
	assert_signal_not_emitted(player, "interact_requested")


func test_unrelated_action_does_not_emit_player_signals() -> void:
	var player: Node = _spawn_player()
	watch_signals(player)
	player._unhandled_input(_action_event("menu", true))
	assert_signal_not_emitted(player, "interact_requested")
	assert_signal_not_emitted(player, "mine_requested")
	assert_signal_not_emitted(player, "place_requested")


func test_mine_action_emits_mine_requested_with_injected_resolver_cell() -> void:
	var player: Node = _spawn_player()
	_resolver_host = CellResolverHost.new()
	player.cell_resolver = Callable(_resolver_host, "resolve")
	watch_signals(player)
	player._unhandled_input(_action_event("mine", true))
	assert_signal_emitted_with_parameters(player, "mine_requested", [Vector2i(3, 4)])
	assert_eq(_resolver_host.call_count, 1, "Injected resolver must be the cell source.")


func test_place_action_emits_place_requested_with_injected_resolver_cell() -> void:
	var player: Node = _spawn_player()
	_resolver_host = CellResolverHost.new()
	player.cell_resolver = Callable(_resolver_host, "resolve")
	watch_signals(player)
	player._unhandled_input(_action_event("place", true))
	assert_signal_emitted_with_parameters(player, "place_requested", [Vector2i(3, 4)])
	assert_eq(_resolver_host.call_count, 1)


func test_mine_action_without_injection_still_emits_a_target_cell() -> void:
	var player: Node = _spawn_player()
	var captured: Array[Vector2i] = []
	player.mine_requested.connect(func(cell: Vector2i) -> void: captured.append(cell))
	player._unhandled_input(_action_event("mine", true))
	assert_eq(captured.size(), 1, "Default mouse resolver must emit exactly one target cell.")
