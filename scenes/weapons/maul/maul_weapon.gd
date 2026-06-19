# scenes/weapons/maul/maul_weapon.gd
# 碎 Maul（双手近战）：慢速大范围砸击，命中半径内全体 → 伤害 + 径向击退 + 硬直。低频高冲击控场。
class_name MaulWeapon
extends WeaponBase

# 由 WeaponData.levels 反射注入
var damage: float = 60.0
var radius: float = 130.0
var knockback: float = 220.0     # apply_impulse 强度(径向远离玩家)
var stun_dur: float = 0.4

# 进化专属：延迟扩张冲击波（默认 0 = 不触发，base maul 不变）
var shockwave_radius: float = 0.0
var shockwave_damage: float = 0.0
var shockwave_slow: float = 0.0       # 地裂减速乘子(0=不减速)
var shockwave_slow_dur: float = 0.0
const SHOCKWAVE_DELAY: float = 0.25
const HAMMER_TEX := preload("res://assets/sprites/kenney/weapons/hammer.png")  # 砸地锤头(Tiny Dungeon)

func attack() -> void:
	var origin: Vector2 = _player.global_position
	var dmg: float = damage_for(damage)
	for e in enemies():
		if not is_instance_valid(e):
			continue
		var epos: Vector2 = (e as Node2D).global_position
		if origin.distance_to(epos) > radius:
			continue
		e.take_damage(dmg)
		if not is_instance_valid(e):
			continue   # 可能被打死
		if e.has_method("apply_impulse"):
			var dir := (epos - origin).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			e.apply_impulse(dir, knockback)
		if e.has_method("apply_status"):
			e.apply_status(&"stun", 0.0, stun_dur)
	if shockwave_radius > 0.0:
		var c: Vector2 = origin
		get_tree().create_timer(SHOCKWAVE_DELAY).timeout.connect(func() -> void: _apply_shockwave(c))
	var fx := Vfx.spawn_anim(origin, &"explosion_ground", get_ysort())
	if fx != null:
		fx.scale = Vector2(0.7, 0.7)
	_spawn_slam_visual(origin)
	GameFeel.shake(&"heavy")
	GameFeel.hitstop(0.06)

# 砸地视觉：锤头在落点放大冲击后缩小淡出 + 土黄烟尘(给"碎"武器辨识度)。
func _spawn_slam_visual(origin: Vector2) -> void:
	var ys := get_ysort()
	if ys == null:
		return
	var h := Sprite2D.new()
	h.texture = HAMMER_TEX
	h.global_position = origin + Vector2(0, -10)
	h.scale = Vector2(4.2, 4.2)
	h.rotation = -0.35
	ys.add_child(h)
	var tw := h.create_tween()
	tw.set_parallel(true)
	tw.tween_property(h, "scale", Vector2(3.0, 3.0), 0.12)
	tw.tween_property(h, "modulate:a", 0.0, 0.18)
	tw.finished.connect(func() -> void: if is_instance_valid(h): h.queue_free())
	var dust := Vfx.spawn_anim(origin, &"smoke_puff", ys)
	if dust != null:
		dust.scale = Vector2(0.5, 0.5)
		dust.modulate = Color(0.82, 0.72, 0.55, 0.9)   # 土黄烟尘

# 冲击波：命中初始 radius 之外、shockwave_radius 之内的一圈敌人 + 地裂减速。
func _apply_shockwave(origin: Vector2) -> void:
	var dmg: float = damage_for(shockwave_damage)
	for e in enemies():
		if not is_instance_valid(e):
			continue
		var d: float = origin.distance_to((e as Node2D).global_position)
		if d > radius and d <= shockwave_radius:
			e.take_damage(dmg)
			if shockwave_slow > 0.0 and e.has_method("apply_status"):
				e.apply_status(&"slow", shockwave_slow, shockwave_slow_dur)
