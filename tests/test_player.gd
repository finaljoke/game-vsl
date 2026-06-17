extends GdUnitTestSuite

# 测试 Player 的 HP / XP / 升级逻辑（实例化真实场景）

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

# ── HP / 伤害 ────────────────────────────────────────────────────────────

func test_initial_hp_is_100() -> void:
	assert_float(_player.hp).is_equal(100.0)

func test_take_damage_reduces_hp() -> void:
	_player.take_damage(30.0)
	assert_float(_player.hp).is_equal(70.0)

func test_take_damage_clamps_to_zero() -> void:
	_player.take_damage(999.0)
	assert_float(_player.hp).is_equal(0.0)

func test_take_damage_does_not_go_negative() -> void:
	_player.take_damage(999.0)
	assert_float(_player.hp).is_greater_equal(0.0)

func test_death_sets_dead_flag() -> void:
	_player.take_damage(100.0)
	assert_bool(_player._dead).is_true()

func test_dead_flag_blocks_further_damage() -> void:
	_player.take_damage(100.0)       # 致死
	_player.hp = 50.0                # 强制重置 hp 验证 _dead 是否真正阻断
	_player.take_damage(50.0)
	assert_float(_player.hp).is_equal(50.0)  # _dead = true 时不扣血

func test_partial_damage_survives() -> void:
	_player.take_damage(99.9)
	assert_bool(_player._dead).is_false()
	assert_float(_player.hp).is_greater(0.0)

# ── XP / 升级 ────────────────────────────────────────────────────────────

func test_initial_level_is_1() -> void:
	assert_int(_player.level).is_equal(1)

func test_initial_xp_threshold_is_100() -> void:
	assert_float(_player.xp_threshold).is_equal(100.0)

func test_add_xp_accumulates_without_level_up() -> void:
	_player.add_xp(50.0)
	assert_float(_player.xp).is_equal(50.0)
	assert_int(_player.level).is_equal(1)

func test_add_xp_triggers_level_up_at_threshold() -> void:
	_player.add_xp(100.0)
	assert_int(_player.level).is_equal(2)

func test_add_xp_subtracts_threshold_on_level_up() -> void:
	_player.add_xp(130.0)  # 超出 100 阈值 30 点
	assert_int(_player.level).is_equal(2)
	assert_float(_player.xp).is_equal_approx(30.0, 0.001)

func test_xp_threshold_scales_after_level_up() -> void:
	_player.add_xp(100.0)
	assert_float(_player.xp_threshold).is_equal_approx(115.0, 0.001)

func test_two_level_ups_scale_threshold_twice() -> void:
	_player.add_xp(100.0)  # level 2, threshold → 115
	_player.add_xp(115.0)  # level 3, threshold → 132.25
	assert_int(_player.level).is_equal(3)
	assert_float(_player.xp_threshold).is_equal_approx(132.25, 0.001)

# ── XP 百分比 ─────────────────────────────────────────────────────────────

func test_get_xp_percent_at_half() -> void:
	_player.add_xp(50.0)
	assert_float(_player.get_xp_percent()).is_equal_approx(0.5, 0.001)

func test_get_xp_percent_at_zero() -> void:
	assert_float(_player.get_xp_percent()).is_equal(0.0)

func test_get_xp_percent_just_before_level_up() -> void:
	_player.add_xp(99.0)
	assert_float(_player.get_xp_percent()).is_equal_approx(0.99, 0.001)
	assert_int(_player.level).is_equal(1)  # 还没升级

# ── while 修复验证：单次 add_xp 触发多次升级 ──────────────────────────────

func test_single_add_xp_can_level_up_twice() -> void:
	# 100 升到 level 2，再 115 升到 level 3，共需 215 XP
	_player.add_xp(220.0)
	assert_int(_player.level).is_equal(3)

func test_single_add_xp_double_levelup_xp_remainder() -> void:
	# 250 XP：消耗 100 + 115 = 215，剩余 35
	_player.add_xp(250.0)
	assert_int(_player.level).is_equal(3)
	assert_float(_player.xp).is_equal_approx(35.0, 0.001)

func test_single_add_xp_triple_levelup() -> void:
	# 100 + 115 + 132.25 = 347.25 XP 升到 level 4
	_player.add_xp(364.0)
	assert_int(_player.level).is_equal(4)

# ── 乘数初始值 ────────────────────────────────────────────────────────────

func test_initial_speed_mult_is_1() -> void:
	assert_float(_player.speed_mult).is_equal(1.0)

func test_initial_attack_speed_mult_is_1() -> void:
	assert_float(_player.attack_speed_mult).is_equal(1.0)

func test_initial_xp_mult_is_1() -> void:
	assert_float(_player.xp_mult).is_equal(1.0)

func test_owned_weapons_starts_empty() -> void:
	assert_int(_player.owned_weapons.size()).is_equal(0)

func test_xp_mult_scales_xp_gain() -> void:
	_player.xp_mult = 1.25
	_player.add_xp(100.0)
	# 100 * 1.25 = 125 XP → 升级（消耗 100）→ xp 剩余 25
	assert_int(_player.level).is_equal(2)
	assert_float(_player.xp).is_equal_approx(25.0, 0.001)

# ── 武器槽上限 ────────────────────────────────────────────────────────────

func test_max_weapon_slots_is_positive() -> void:
	assert_int(_player.MAX_WEAPON_SLOTS).is_greater(0)

func test_grant_weapon_succeeds_below_slot_cap() -> void:
	var w = _player.grant_weapon(WeaponDB.get_data("knife"))
	assert_object(w).is_not_null()
	assert_int(_player.owned_weapons.size()).is_equal(1)

func test_grant_weapon_returns_null_when_slots_full() -> void:
	# 占满槽位(stub)后 grant 真实武器应被拒，且不改变持有数
	for i in range(_player.MAX_WEAPON_SLOTS):
		_player.owned_weapons["slot_%d" % i] = {"node": null, "level": 1}
	var w = _player.grant_weapon(WeaponDB.get_data("knife"))
	assert_object(w).is_null()
	assert_int(_player.owned_weapons.size()).is_equal(_player.MAX_WEAPON_SLOTS)

# ── 重抽券(E2)────────────────────────────────────────────────────────────

func test_reroll_tokens_default_zero() -> void:
	assert_int(_player.reroll_tokens).is_equal(0)

# ── 质变 modifier(E3)──────────────────────────────────────────────────────

func test_global_pierce_default_zero() -> void:
	assert_int(_player.global_pierce).is_equal(0)

func test_extra_projectiles_default_zero() -> void:
	assert_int(_player.extra_projectiles).is_equal(0)

func test_pickup_range_mult_default_one() -> void:
	assert_float(_player.pickup_range_mult).is_equal(1.0)

func test_lifesteal_default_zero() -> void:
	assert_float(_player.lifesteal).is_equal(0.0)

func test_lifesteal_connected_to_enemy_died() -> void:
	assert_bool(GameFeel.enemy_died.is_connected(_player._lifesteal_on_death)).is_true()

func test_lifesteal_heals_on_death() -> void:
	_player.hp = 50.0
	_player.lifesteal = 2.0
	_player._lifesteal_on_death(Vector2.ZERO, null)
	assert_float(_player.hp).is_equal_approx(52.0, 0.001)

func test_lifesteal_does_not_overheal() -> void:
	_player.hp = 99.5
	_player.lifesteal = 2.0
	_player._lifesteal_on_death(Vector2.ZERO, null)
	assert_float(_player.hp).is_equal_approx(100.0, 0.001)

func test_no_lifesteal_when_zero() -> void:
	_player.hp = 50.0
	_player._lifesteal_on_death(Vector2.ZERO, null)
	assert_float(_player.hp).is_equal(50.0)

# ── Bot 注入钩子 ───────────────────────────────────────────────────────────
func test_bot_input_overrides_movement() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	var p: Player = auto_free(scene.instantiate() as Player)
	add_child(p)
	await get_tree().process_frame
	p.bot_input = Vector2(1, 0)
	p._physics_process(0.016)
	assert_float(p.velocity.x).is_greater(0.0)
	assert_float(p.velocity.y).is_equal_approx(0.0, 0.001)

func test_default_bot_input_is_inf_sentinel() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	var p: Player = auto_free(scene.instantiate() as Player)
	add_child(p)
	await get_tree().process_frame
	# 默认 INF = 真人路径;无按键时 Input.get_vector 返回 ZERO → 速度 ZERO
	assert_bool(p.bot_input == Vector2.INF).is_true()
	p._physics_process(0.016)
	assert_float(p.velocity.length()).is_equal_approx(0.0, 0.001)

# ── 接触伤害结算(W0)：硬直敌人不结算、最多累计 CONTACT_MAX_SOURCES 个来源 ──────
func test_sum_contact_damage_skips_stunned() -> void:
	var entries := [
		{"damage": 8.0, "stunned": false},
		{"damage": 8.0, "stunned": true},   # 硬直 → 跳过
		{"damage": 8.0, "stunned": false},
	]
	# 0.5s：两个非硬直 × 8 × 0.5 = 8.0
	assert_float(Player.sum_contact_damage(entries, 0.5, 6)).is_equal_approx(8.0, 0.001)

func test_sum_contact_damage_caps_at_max_sources() -> void:
	var entries: Array = []
	for i in range(10):
		entries.append({"damage": 10.0, "stunned": false})
	# 上限 6 个来源 × 10 × 1.0s = 60
	assert_float(Player.sum_contact_damage(entries, 1.0, 6)).is_equal_approx(60.0, 0.001)

func test_sum_contact_damage_all_stunned_is_zero() -> void:
	var entries := [{"damage": 8.0, "stunned": true}, {"damage": 8.0, "stunned": true}]
	assert_float(Player.sum_contact_damage(entries, 1.0, 6)).is_equal(0.0)
