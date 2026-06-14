extends Node

# ── Signals ───────────────────────────────────────────────────────────────
signal enemy_hit(amount: float, position: Vector2, enemy: Node2D)
signal enemy_died(position: Vector2)
signal player_hit(amount: float)
signal player_leveled_up(level: int)
signal xp_collected(position: Vector2)

# ── Shake state ───────────────────────────────────────────────────────────
var _shake_magnitude: float = 0.0
var _shake_decay: float = 0.0

# ── Cached references ─────────────────────────────────────────────────────
var _camera: Camera2D = null
var _player_node: Node2D = null
var _flash_rect: ColorRect = null

# ── Audio players ─────────────────────────────────────────────────────────
var _sfx_hit: AudioStreamPlayer
var _sfx_death: AudioStreamPlayer
var _sfx_xp: AudioStreamPlayer
var _sfx_levelup: AudioStreamPlayer
var _sfx_player_hurt: AudioStreamPlayer

# ── Setup ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_setup_flash_rect()
	_setup_audio()
	enemy_hit.connect(_on_enemy_hit)
	enemy_died.connect(_on_enemy_died)
	player_hit.connect(_on_player_hit)
	player_leveled_up.connect(_on_player_leveled_up)
	xp_collected.connect(_on_xp_collected)

func _setup_flash_rect() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_flash_rect)

func _setup_audio() -> void:
	_sfx_hit         = _make_sfx_player("res://assets/audio/sfx/hit.wav")
	_sfx_death       = _make_sfx_player("res://assets/audio/sfx/enemy_death.wav")
	_sfx_xp          = _make_sfx_player("res://assets/audio/sfx/xp_collect.wav")
	_sfx_levelup     = _make_sfx_player("res://assets/audio/sfx/level_up.wav")
	_sfx_player_hurt = _make_sfx_player("res://assets/audio/sfx/player_hurt.wav")

func _make_sfx_player(path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	if ResourceLoader.exists(path):
		player.stream = load(path)
	return player

# ── Process: screen shake ─────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _shake_magnitude <= 0.0:
		return
	_shake_magnitude = max(0.0, _shake_magnitude - _shake_decay * delta)
	var cam := _get_camera()
	if cam == null:
		return
	if _shake_magnitude < 0.1:
		cam.offset = Vector2.ZERO
		_shake_magnitude = 0.0
	else:
		cam.offset = Vector2(
			randf_range(-_shake_magnitude, _shake_magnitude),
			randf_range(-_shake_magnitude, _shake_magnitude)
		)

# ── Lazy lookups ──────────────────────────────────────────────────────────
func _get_camera() -> Camera2D:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_2d()
	return _camera

func _get_player() -> Node2D:
	if _player_node == null or not is_instance_valid(_player_node):
		_player_node = get_tree().get_first_node_in_group("player") as Node2D
	return _player_node

# ── Effect helpers ────────────────────────────────────────────────────────
func _shake(magnitude: float, duration: float) -> void:
	if magnitude > _shake_magnitude:
		_shake_magnitude = magnitude
		_shake_decay = magnitude / duration

func _flash_node(node: Node2D, color: Color, duration: float) -> void:
	if not is_instance_valid(node):
		return
	node.modulate = color
	var tween := create_tween().bind_node(node)
	tween.tween_property(node, "modulate", Color.WHITE, duration)

func _screen_flash(color: Color, duration: float) -> void:
	if _flash_rect == null:
		return
	_flash_rect.color = color
	var tween := create_tween()
	tween.tween_property(_flash_rect, "color:a", 0.0, duration)

func _spawn_particles(pos: Vector2) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := CPUParticles2D.new()
	scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 8
	p.lifetime = 0.4
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 150.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color = Color(1.0, 0.6, 0.1)
	get_tree().create_timer(p.lifetime + 0.1).timeout.connect(
		func(): if is_instance_valid(p): p.queue_free()
	)

func _spawn_damage_number(amount: float, pos: Vector2) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var label := Label.new()
	label.text = str(int(amount))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	scene.add_child(label)
	label.global_position = pos
	var target_y := label.global_position.y - 40.0
	var tween := create_tween().bind_node(label)
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", target_y, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.finished.connect(func(): if is_instance_valid(label): label.queue_free())

func _play_sfx(player: AudioStreamPlayer) -> void:
	if is_instance_valid(player) and player.stream != null:
		player.play()

# ── Signal handlers ───────────────────────────────────────────────────────
func _on_enemy_hit(amount: float, position: Vector2, enemy: Node2D) -> void:
	_flash_node(enemy, Color.WHITE, 0.08)
	_spawn_damage_number(amount, position)
	_play_sfx(_sfx_hit)

func _on_enemy_died(position: Vector2) -> void:
	_spawn_particles(position)
	_shake(3.0, 0.1)
	_play_sfx(_sfx_death)

func _on_player_hit(_amount: float) -> void:
	_shake(8.0, 0.3)
	var p := _get_player()
	if p != null:
		_flash_node(p, Color(1.0, 0.3, 0.3), 0.12)
	_play_sfx(_sfx_player_hurt)

func _on_player_leveled_up(_level: int) -> void:
	_screen_flash(Color(1, 1, 1, 0.6), 0.15)
	_shake(5.0, 0.2)
	_play_sfx(_sfx_levelup)

func _on_xp_collected(_position: Vector2) -> void:
	_play_sfx(_sfx_xp)
