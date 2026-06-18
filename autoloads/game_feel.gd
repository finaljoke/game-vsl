extends Node

# ── Signals ───────────────────────────────────────────────────────────────
signal enemy_hit(amount: float, position: Vector2, enemy: Node2D)
signal enemy_died(position: Vector2, enemy: Node2D)
signal player_hit(amount: float)
# 纯指标信号(DebugMetrics 订阅)：玩家实际回血增量，封顶后为 0。GameFeel 自身不处理。
signal player_healed(amount: float)
signal player_leveled_up(level: int)
signal xp_collected(position: Vector2)
signal player_died
signal item_selected
# Boss 登场前 BOSS_WARNING_LEAD 秒由 spawner 发一次；HUD 监听并弹中央顶部红色 Label
signal boss_incoming

# ── Audio resources ───────────────────────────────────────────────────────
const SFX_HIT          = preload("res://assets/audio/sfx/hit.wav")
const SFX_DEATH        = preload("res://assets/audio/sfx/enemy_death.wav")
const SFX_XP           = preload("res://assets/audio/sfx/xp_collect.wav")
const SFX_LEVELUP      = preload("res://assets/audio/sfx/level_up.wav")
const SFX_PLAYER_HURT  = preload("res://assets/audio/sfx/player_hurt.wav")
const SFX_PLAYER_DEATH = preload("res://assets/audio/sfx/player_death.wav")
const SFX_ITEM_SELECT  = preload("res://assets/audio/sfx/item_select.wav")

# ── 混音 dB（逐音效，差异化压平反馈层次；config 级，靠实跑听感校准）──────────
# 高频杂兵命中/击杀压低，避免盖过 BGM 与重要反馈；受击降幅小（重要提示）；选卡音抬高。
const SFX_HIT_DB: float    = -7.0
const SFX_DEATH_DB: float  = -9.0
const SFX_HURT_DB: float   = -5.0
const SFX_SELECT_DB: float = 4.0

# ── Shake emitters ────────────────────────────────────────────────────────
var _emitter_hit: PhantomCameraNoiseEmitter2D
var _emitter_player: PhantomCameraNoiseEmitter2D
var _emitter_levelup: PhantomCameraNoiseEmitter2D

# 武器手感专用震屏分级(与 player/levelup 解耦,调武器手感不影响受击/升级反馈)。
# 各档:[amplitude, frequency, duration, decay]。
const SHAKE_PRESETS := {
	&"light":  [6.0,  9.0, 0.10, 0.06],
	&"medium": [12.0, 7.0, 0.16, 0.10],
	&"heavy":  [22.0, 5.0, 0.24, 0.14],
}
var _weapon_emitters := {}  # StringName -> PhantomCameraNoiseEmitter2D

# ── Cached references ─────────────────────────────────────────────────────
var _player_node: Node2D = null
var _flash_rect: ColorRect = null

# ── Setup ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_setup_flash_rect()
	_setup_shake_emitters()
	enemy_hit.connect(_on_enemy_hit)
	enemy_died.connect(_on_enemy_died)
	player_hit.connect(_on_player_hit)
	player_leveled_up.connect(_on_player_leveled_up)
	xp_collected.connect(_on_xp_collected)
	player_died.connect(_on_player_died)
	item_selected.connect(_on_item_selected)

func _setup_flash_rect() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_flash_rect)

# ── Lazy lookups ──────────────────────────────────────────────────────────
func _get_player() -> Node2D:
	if _player_node == null or not is_instance_valid(_player_node):
		_player_node = get_tree().get_first_node_in_group("player") as Node2D
	return _player_node

# ── Effect helpers ────────────────────────────────────────────────────────
func _setup_shake_emitters() -> void:
	_emitter_hit     = _make_emitter(4.0,  8.0, 0.08, 0.05, false)
	_emitter_player  = _make_emitter(24.0, 5.0, 0.25, 0.15, false)
	_emitter_levelup = _make_emitter(10.0, 6.0, 0.15, 0.10, false)
	for key in SHAKE_PRESETS:
		var p: Array = SHAKE_PRESETS[key]
		_weapon_emitters[key] = _make_emitter(p[0], p[1], p[2], p[3], false)

func _make_emitter(amplitude: float, frequency: float, duration: float, decay: float, rotational: bool) -> PhantomCameraNoiseEmitter2D:
	var noise := PhantomCameraNoise2D.new()
	noise.amplitude = amplitude
	noise.frequency = frequency
	noise.positional_noise = true
	noise.rotational_noise = rotational
	noise.randomize_noise_seed = true
	var emitter := PhantomCameraNoiseEmitter2D.new()
	emitter.noise = noise
	emitter.duration = duration
	emitter.decay_time = decay
	emitter.continuous = false
	add_child(emitter)
	return emitter

# 武器/系统按手感分级请求震屏。未知预设安全 no-op。
func shake(preset: StringName) -> void:
	var e: PhantomCameraNoiseEmitter2D = _weapon_emitters.get(preset)
	if e != null:
		e.emit()

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

# ── Signal handlers ───────────────────────────────────────────────────────
func _on_enemy_hit(amount: float, position: Vector2, enemy: Node2D) -> void:
	# 用 >1.0 的 modulate 真正"过曝"贴图；纯 Color.WHITE 是 identity 看不出来。
	_flash_node(enemy, Color(2.5, 2.5, 2.5), 0.15)
	if enemy.has_method("_apply_knockback"):
		enemy._apply_knockback(position)
	_spawn_damage_number(amount, position)
	var p := SoundManager.play_sound(SFX_HIT)
	if p: p.volume_db = SFX_HIT_DB

func _on_enemy_died(position: Vector2, enemy: Node2D) -> void:
	_spawn_particles(position)
	_emitter_hit.emit()
	# 顿帧只留给 Boss：割草游戏里杂兵击杀高频，全局 time_scale 会叠成永久慢放。
	if enemy != null and is_instance_valid(enemy) and enemy.get("behavior") == "boss":
		hitstop(0.05)
	var p := SoundManager.play_sound(SFX_DEATH)
	if p: p.volume_db = SFX_DEATH_DB

# Engine.time_scale 全局拖慢制造击杀冲击感；恢复 timer 必须 ignore_time_scale，
# 否则它自己也会被拖慢导致永远不归位。
func hitstop(duration: float) -> void:
	# bot/headless 模式跳过:顿帧用实时计时器,其窗口内物理帧数依赖真机 wall-clock,会破坏确定性。
	# 且 headless 下顿帧无视觉意义。详见 RunHarness。
	if RunHarness.active:
		return
	Engine.time_scale = 0.05
	var t := get_tree().create_timer(duration, false, true, true)
	# 恢复到快进基线(惰性时=1.0)而非写死 1.0,避免冲掉 --fast。
	t.timeout.connect(func() -> void: Engine.time_scale = RunHarness.base_time_scale)

func _on_player_hit(_amount: float) -> void:
	_emitter_player.emit()
	_screen_flash(Color(1.0, 0.0, 0.0, 0.25), 0.18)
	var p := _get_player()
	if p != null:
		_flash_node(p, Color(1.0, 0.2, 0.2), 0.2)
	var snd := SoundManager.play_sound(SFX_PLAYER_HURT)
	if snd: snd.volume_db = SFX_HURT_DB

func _on_player_leveled_up(_level: int) -> void:
	_screen_flash(Color(1, 1, 1, 0.6), 0.15)
	_emitter_levelup.emit()
	SoundManager.play_sound(SFX_LEVELUP)

func _on_xp_collected(_position: Vector2) -> void:
	SoundManager.play_sound(SFX_XP)

func _on_player_died() -> void:
	_screen_flash(Color(1, 0, 0, 0.4), 0.5)
	_emitter_player.emit()
	SoundManager.play_sound(SFX_PLAYER_DEATH)

func _on_item_selected() -> void:
	var p := SoundManager.play_ui_sound(SFX_ITEM_SELECT)
	if p: p.volume_db = SFX_SELECT_DB
