extends GdUnitTestSuite
# W3b 进化质变：反射 + 机制。preload 引用脚本；敌人实例化 enemy.tscn(headless 加载 LimboAI)。

const EnemyScene := preload("res://scenes/enemies/enemy.tscn")

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

func _tough_enemy_at(pos: Vector2) -> Enemy:
	var e: Enemy = EnemyScene.instantiate()
	e.behavior = "chase"
	add_child(e)
	e.add_to_group("enemies")
	e.MAX_HP = 500.0
	e.hp = 500.0
	e.global_position = pos
	return auto_free(e)

func _ysort_stub() -> void:
	var ys: Node2D = auto_free(Node2D.new()) as Node2D
	add_child(ys)
	ys.add_to_group("ysort")

# 拉满基础武器并进化(apply 跳过条件，直接走效果)
func _evolve(base_id: String, evolved_id: String) -> WeaponBase:
	_ysort_stub()
	CardPool.apply({"id": base_id}, _player)
	CardPool.apply({"id": "evolve_%s" % base_id, "type": "evolution"}, _player)
	return _player.get_weapon_node(evolved_id)

# ── 回旋斩 Whirlwind ──
func test_whirlwind_reflects_quale_fields() -> void:
	var w := _evolve("whip", "bloody_whip")
	assert_object(w).is_not_null()
	assert_bool(w.get("full_circle")).is_true()
	assert_float(w.get("bleed_dps")).is_greater(0.0)
	assert_float(w.get("lifesteal_on_hit")).is_greater(0.0)

func test_whirlwind_hits_enemy_behind_player() -> void:
	var w := _evolve("whip", "bloody_whip")
	_player.global_position = Vector2.ZERO
	w._facing = Vector2.RIGHT
	var e := _tough_enemy_at(Vector2(-60, 0))   # 在身后(锥形外)，但 360° 内
	await get_tree().process_frame
	w.attack()
	assert_float(e.hp).is_less(500.0)            # 全向命中
	assert_bool(e.has_status(&"burn")).is_true() # 流血(复用 burn)

# ── 箭雨 Arrow Storm ──
func test_arrow_storm_reflects_volley() -> void:
	var w := _evolve("knife", "thousand_edge")
	assert_int(w.get("volley")).is_greater(1)
	assert_float(w.get("crit_bonus")).is_equal_approx(1.0, 0.001)

func test_arrow_storm_fires_volley_projectiles() -> void:
	var ys: Node2D = auto_free(Node2D.new()); add_child(ys); ys.add_to_group("ysort")
	CardPool.apply({"id": "knife"}, _player)
	CardPool.apply({"id": "evolve_knife", "type": "evolution"}, _player)
	var w := _player.get_weapon_node("thousand_edge")
	_tough_enemy_at(_player.global_position + Vector2(100, 0))
	await get_tree().process_frame
	w.attack()
	# 齐射 5 发 → ysort 下至少 5 个投射体
	assert_int(ys.get_child_count()).is_greater_equal(5)

# ── 旋风斧 Cyclone ──
const BoomerangProjScript := preload("res://scenes/weapons/boomerang/boomerang_projectile.gd")

func test_cyclone_reflects_orbit_return() -> void:
	var w := _evolve("boomerang", "cyclone")
	assert_bool(w.get("orbit_return")).is_true()
	assert_int(w.get("count")).is_equal(3)

func test_cyclone_projectile_orbits_not_homes() -> void:
	var p = auto_free(BoomerangProjScript.new())
	p.max_range = 200.0
	p.orbit_return = true
	add_child(p)
	await get_tree().process_frame   # _ready 抓 player(=本测试的 _player)
	p.global_position = _player.global_position + Vector2(80, 0)
	p._returning = true              # 进入折返(环绕)阶段
	for i in range(15):
		await get_tree().physics_frame
	# 环绕态不应归位到玩家(距离仍 > 折返阈值)
	assert_float(p.global_position.distance_to(_player.global_position)).is_greater(20.0)

# ── 核爆 Cataclysm ──
func test_cataclysm_reflects_quale_fields() -> void:
	var w := _evolve("explosion", "nuke")
	assert_float(w.get("blast_radius")).is_greater(80.0)   # ×1.6
	assert_float(w.get("burn_dps")).is_greater(0.0)        # 炼狱地火
	assert_int(w.get("secondary_count")).is_greater(0)     # 二次引爆

# ── 炼狱 Inferno ──
func test_inferno_reflects_burn_and_lifesteal() -> void:
	var w := _evolve("aura", "inferno_aura")
	assert_float(w.get("burn_dps")).is_greater(0.0)
	assert_float(w.get("lifesteal_on_hit")).is_greater(0.0)
	assert_float(w.get("radius")).is_equal_approx(170.0, 0.001)

# ── 雷暴 Tempest ──
func test_tempest_reflects_sky_strikes() -> void:
	var w := _evolve("lightning", "thunderstorm")
	assert_int(w.get("sky_strikes")).is_greater(0)
	assert_int(w.get("chains")).is_equal(8)

func test_tempest_sky_strike_damages_enemies() -> void:
	var w := _evolve("lightning", "thunderstorm")
	var e := _tough_enemy_at(Vector2(300, 300))
	await get_tree().process_frame
	w._sky_strike([e])   # 直接打这一目标头顶落雷
	assert_float(e.hp).is_less(500.0)

# ── 缚刃 Bound Blades ──
const OrbShieldScript := preload("res://scenes/weapons/orb/orb_shield.gd")

func test_bound_blades_orbs_have_dash_enabled() -> void:
	_evolve("orb", "mega_orb")
	var found := false
	for c in _player.get_children():
		if c is OrbShield:
			found = true
			assert_bool(c.dash_enabled).is_true()
	assert_bool(found).is_true()

func test_orb_dashes_toward_enemy_when_due() -> void:
	var orb = auto_free(OrbShieldScript.new())
	orb.total_orbs = 1
	orb.dash_enabled = true
	orb.dash_interval = 0.0    # 立即可冲
	_player.add_child(orb)
	await get_tree().process_frame
	var e := _tough_enemy_at(_player.global_position + Vector2(200, 0))
	var d0: float = (orb as Node2D).global_position.distance_to(e.global_position)
	for i in range(10):
		await get_tree().process_frame
	assert_float((orb as Node2D).global_position.distance_to(e.global_position)).is_less(d0)

# ── 震地 Earthshatter ──
func test_evolve_maul_grants_earthshatter() -> void:
	var w := _evolve("maul", "earthshatter")
	assert_bool(_player.has_weapon("earthshatter")).is_true()
	assert_float(w.get("shockwave_radius")).is_greater(0.0)

func test_earthshatter_shockwave_hits_far_ring_and_slows() -> void:
	var w := _evolve("maul", "earthshatter")
	_player.global_position = Vector2.ZERO
	# 落在初始 radius(170) 外、shockwave_radius(280) 内
	var e := _tough_enemy_at(Vector2(240, 0))
	await get_tree().process_frame
	w._apply_shockwave(Vector2.ZERO)
	assert_float(e.hp).is_less(500.0)
	assert_bool(e.has_status(&"slow")).is_true()

# ── 暴雪 Blizzard ──
const SnowFieldScript := preload("res://scenes/weapons/frostbite/snow_field.gd")

func test_evolve_frostbite_grants_blizzard() -> void:
	var w := _evolve("frostbite", "blizzard")
	assert_bool(_player.has_weapon("blizzard")).is_true()
	assert_float(w.get("field_dur")).is_greater(0.0)

func test_snow_field_slows_enemy_in_radius() -> void:
	var f = auto_free(SnowFieldScript.new())
	f.radius = 110.0
	f.slow_factor = 0.5
	f.field_dur = 5.0
	f.freeze_dur = 0.6
	add_child(f)
	f.global_position = Vector2.ZERO
	var e := _tough_enemy_at(Vector2(40, 0))
	for i in range(20):
		await get_tree().physics_frame
	assert_bool(e.has_status(&"slow") or e.has_status(&"freeze")).is_true()
