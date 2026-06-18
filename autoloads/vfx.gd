extends Node
## Vfx — 全局视效工厂 + 预设注册表。
## 一处定义 FX 配方,武器/敌人/状态系统只调用,不各写一套粒子代码。
## 分工:GameFeel 管屏幕级反馈(震屏/闪屏/顿帧/音效/伤害数字);
##       Vfx 管世界空间的粒子/序列帧/状态指示器实例化。

const PACK := "res://assets/sprites/kenney/particles/pack/"
const EXPL := "res://assets/sprites/kenney/explosions/"

# 一次性粒子爆发预设(CPUParticles2D 配方)。additive=true 走加色发光材质。
const BURST_PRESETS := {
	&"fire_burst":  {"color": Color(1.0, 0.6, 0.1),   "amount": 10, "lifetime": 0.40, "vmin": 50.0, "vmax": 150.0, "smin": 3.0, "smax": 6.0, "additive": false},
	&"frost_burst": {"color": Color(0.55, 0.85, 1.0), "amount": 10, "lifetime": 0.40, "vmin": 40.0, "vmax": 120.0, "smin": 3.0, "smax": 5.0, "additive": false},
	&"hit_spark":   {"color": Color(1.0, 1.0, 0.85),  "amount": 6,  "lifetime": 0.25, "vmin": 60.0, "vmax": 180.0, "smin": 2.0, "smax": 4.0, "additive": true},
	&"magic_burst": {"color": Color(0.7, 0.5, 1.0),   "amount": 12, "lifetime": 0.45, "vmin": 30.0, "vmax": 110.0, "smin": 3.0, "smax": 6.0, "additive": true},
}

# 序列帧预设:目录 + 帧名前缀 + 帧数(00..count-1) + 帧率。
const ANIM_PRESETS := {
	&"explosion_regular": {"dir": "res://assets/sprites/kenney/explosions/", "base": "regularExplosion", "count": 9, "fps": 24.0},
	&"explosion_sonic":   {"dir": "res://assets/sprites/kenney/explosions/", "base": "sonicExplosion",   "count": 9, "fps": 24.0},
	&"explosion_ground":  {"dir": "res://assets/sprites/kenney/explosions/", "base": "groundExplosion",  "count": 9, "fps": 24.0},
}

func get_preset(name: StringName) -> Dictionary:
	if BURST_PRESETS.has(name):
		return BURST_PRESETS[name]
	if ANIM_PRESETS.has(name):
		return ANIM_PRESETS[name]
	return {}

# ── 一次性粒子爆发工厂 ─────────────────────────────────────────────────────────

static var _add_mat: CanvasItemMaterial = null

static func additive_material() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat

static func _configure_burst(p: CPUParticles2D, cfg: Dictionary) -> void:
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = cfg["amount"]
	p.lifetime = cfg["lifetime"]
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.initial_velocity_min = cfg["vmin"]
	p.initial_velocity_max = cfg["vmax"]
	p.scale_amount_min = cfg["smin"]
	p.scale_amount_max = cfg["smax"]
	p.color = cfg["color"]
	if cfg.get("additive", false):
		p.material = additive_material()

func spawn_burst(pos: Vector2, preset: StringName, parent: Node = null) -> CPUParticles2D:
	var cfg: Dictionary = BURST_PRESETS.get(preset, {})
	if cfg.is_empty():
		return null
	var host: Node = parent if parent != null else get_tree().current_scene
	if host == null:
		return null
	var p := CPUParticles2D.new()
	_configure_burst(p, cfg)
	host.add_child(p)
	p.global_position = pos
	get_tree().create_timer(p.lifetime + 0.1).timeout.connect(
		func() -> void:
			if is_instance_valid(p): p.queue_free()
	)
	return p

# ── 序列帧工厂 ────────────────────────────────────────────────────────────────

var _frames_cache := {}  # StringName -> SpriteFrames

func build_frames(name: StringName) -> SpriteFrames:
	if _frames_cache.has(name):
		return _frames_cache[name]
	var cfg: Dictionary = ANIM_PRESETS.get(name, {})
	if cfg.is_empty():
		return null
	var sf := SpriteFrames.new()
	sf.set_animation_speed(&"default", cfg["fps"])
	sf.set_animation_loop(&"default", false)
	for i in range(cfg["count"]):
		var idx := str(i).pad_zeros(2)  # 0->"00", 8->"08"
		var tex := load(cfg["dir"] + cfg["base"] + idx + ".png") as Texture2D
		if tex != null:
			sf.add_frame(&"default", tex)
	_frames_cache[name] = sf
	return sf

func spawn_anim(pos: Vector2, name: StringName, parent: Node = null) -> AnimatedSprite2D:
	var sf := build_frames(name)
	if sf == null:
		return null
	var host: Node = parent if parent != null else get_tree().current_scene
	if host == null:
		return null
	var a := AnimatedSprite2D.new()
	a.sprite_frames = sf
	host.add_child(a)
	a.global_position = pos
	a.play(&"default")
	a.animation_finished.connect(
		func() -> void:
			if is_instance_valid(a): a.queue_free()
	)
	return a
