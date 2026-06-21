extends GdUnitTestSuite
# W1 新机制单测：纯函数 + 数据驱动反射 + 状态附着。preload 引用脚本。

const KnifeScript := preload("res://scenes/weapons/knife/knife_weapon.gd")
const EnemyScene := preload("res://scenes/enemies/enemy.tscn")

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

# 在玩家附近 dist 处生成一只敌人(入 "enemies" 组)，返回之。
func _spawn_enemy_near(dist: float) -> Enemy:
	var e: Enemy = EnemyScene.instantiate()
	e.behavior = "chase"
	add_child(e)
	e.add_to_group("enemies")
	e.global_position = _player.global_position + Vector2(dist, 0)
	return auto_free(e)

# ── 回旋斧(boomerang) Lv1 冷却数据 ──
func test_throwing_axe_lv1_cooldown() -> void:
	CardPool.apply({"id": "boomerang"}, _player)
	assert_float(_player.get_weapon_node("boomerang").cooldown).is_equal_approx(1.5, 0.001)

func test_throwing_axe_lv1_damage() -> void:
	CardPool.apply({"id": "boomerang"}, _player)
	assert_float(_player.get_weapon_node("boomerang").get("damage")).is_equal_approx(20.0, 0.001)

# ── 缚灵(spectral wisps) orbit_radius 数据驱动 ──
func test_spectral_wisps_data_drives_orbit_radius() -> void:
	CardPool.apply({"id": "orb"}, _player)
	for c in _player.get_children():
		if c is OrbShield:
			assert_float(c.orbit_radius).is_equal_approx(60.0, 0.001)  # 缚灵 Lv1=60

# ── 烈焰护体(flame cloak) burn 附着 ──
func test_flame_cloak_applies_burn_to_enemy_in_radius() -> void:
	CardPool.apply({"id": "aura"}, _player)
	var aura := _player.get_weapon_node("aura")
	var e := _spawn_enemy_near(30.0)   # 在 Lv1 radius=90 内
	await get_tree().process_frame
	aura.attack()
	assert_bool(e.has_status(&"burn")).is_true()

func test_flame_cloak_no_burn_when_dps_zero() -> void:
	# 进化 inferno_aura 不注入 burn_dps → 默认 0 → 不附 burn（W1 不改进化行为）
	CardPool.apply({"id": "aura"}, _player)
	var aura := _player.get_weapon_node("aura")
	aura.burn_dps = 0.0
	var e := _spawn_enemy_near(30.0)
	await get_tree().process_frame
	aura.attack()
	assert_bool(e.has_status(&"burn")).is_false()

# ── 连锁闪电(lightning) 链尾附 stun ──
func test_chain_lightning_stuns_tail_enemy() -> void:
	CardPool.apply({"id": "lightning"}, _player)
	var lw := _player.get_weapon_node("lightning")
	var e := _spawn_enemy_near(50.0)   # 唯一敌 → 既是链首也是链尾
	await get_tree().process_frame
	lw.attack()
	assert_bool(e.is_stunned()).is_true()

func test_chain_lightning_no_stun_when_dur_zero() -> void:
	CardPool.apply({"id": "lightning"}, _player)
	var lw := _player.get_weapon_node("lightning")
	lw.shock_dur = 0.0   # 进化 thunderstorm 不注入 → 不附 stun
	var e := _spawn_enemy_near(50.0)
	await get_tree().process_frame
	lw.attack()
	assert_bool(e.is_stunned()).is_false()

# ── 长弓距离/满血暴击口径(纯函数)──
func test_longbow_crit_bonus_far_target() -> void:
	# dist 300 > crit_range 260 → 给 bonus
	assert_float(KnifeScript.longbow_crit_bonus(300.0, 260.0, false, 0.25)).is_equal_approx(0.25, 0.001)

func test_longbow_crit_bonus_full_hp_target() -> void:
	# 近距但满血 → 给 bonus
	assert_float(KnifeScript.longbow_crit_bonus(100.0, 260.0, true, 0.25)).is_equal_approx(0.25, 0.001)

func test_longbow_crit_bonus_near_and_hurt_no_bonus() -> void:
	# 近距且非满血 → 不给
	assert_float(KnifeScript.longbow_crit_bonus(100.0, 260.0, false, 0.25)).is_equal(0.0)

func test_longbow_zero_bonus_field_never_crits() -> void:
	# 进化 thousand_edge crit_bonus 默认 0 → 任何情况返回 0
	assert_float(KnifeScript.longbow_crit_bonus(999.0, 260.0, true, 0.0)).is_equal(0.0)

func test_longbow_reflects_crit_fields() -> void:
	CardPool.apply({"id": "knife"}, _player)
	var node := _player.get_weapon_node("knife")
	assert_float(node.get("crit_range")).is_equal_approx(260.0, 0.001)
	assert_float(node.get("crit_bonus")).is_equal_approx(0.25, 0.001)
	assert_float(node.get("proj_speed")).is_greater(400.0)

func test_longbow_lv1_damage_is_data_driven() -> void:
	CardPool.apply({"id": "knife"}, _player)
	assert_float(_player.get_weapon_node("knife").get("damage")).is_equal_approx(18.0, 0.001)

func test_fireball_reflects_burn_field_data() -> void:
	CardPool.apply({"id": "explosion"}, _player)
	var node := _player.get_weapon_node("explosion")
	assert_float(node.get("blast_radius")).is_equal_approx(80.0, 0.001)
	assert_float(node.get("burn_dps")).is_equal_approx(4.0, 0.001)    # 报告 §5① 复衡:L1 地火 6→4(周期化爆发,削持续地火)
	assert_float(node.get("field_dur")).is_equal_approx(1.5, 0.001)   # L1 field_dur 2.0→1.5
