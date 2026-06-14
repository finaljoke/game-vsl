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
	assert_float(_player.xp_threshold).is_equal_approx(120.0, 0.001)

func test_two_level_ups_scale_threshold_twice() -> void:
	_player.add_xp(100.0)  # level 2, threshold → 120
	_player.add_xp(120.0)  # level 3, threshold → 144
	assert_int(_player.level).is_equal(3)
	assert_float(_player.xp_threshold).is_equal_approx(144.0, 0.001)

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
	# 100 升到 level 2，再 120 升到 level 3，共需 220 XP
	_player.add_xp(220.0)
	assert_int(_player.level).is_equal(3)

func test_single_add_xp_double_levelup_xp_remainder() -> void:
	# 250 XP：消耗 100 + 120 = 220，剩余 30
	_player.add_xp(250.0)
	assert_int(_player.level).is_equal(3)
	assert_float(_player.xp).is_equal_approx(30.0, 0.001)

func test_single_add_xp_triple_levelup() -> void:
	# 100 + 120 + 144 = 364 XP 升到 level 4
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
