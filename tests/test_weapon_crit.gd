extends GdUnitTestSuite
# 暴击口径：crit_multiplier 纯函数 + damage_for 实例(在玩家下)集成。
# 概率中段用纯函数显式 roll 覆盖；damage_for 用确定性极值(chance 0/1)避免依赖 randf。

const WeaponBaseScript := preload("res://scenes/weapons/weapon_base.gd")

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

# ── crit_multiplier 纯函数 ──
func test_crit_below_threshold_crits() -> void:
	assert_float(WeaponBaseScript.crit_multiplier(0.10, 0.25, 0.0, 2.0)).is_equal(2.0)

func test_crit_above_threshold_no_crit() -> void:
	assert_float(WeaponBaseScript.crit_multiplier(0.50, 0.25, 0.0, 2.0)).is_equal(1.0)

func test_crit_bonus_raises_threshold() -> void:
	# 0.40 < 0.25+0.30=0.55 → 暴击
	assert_float(WeaponBaseScript.crit_multiplier(0.40, 0.25, 0.30, 2.0)).is_equal(2.0)

func test_crit_threshold_clamped_to_one() -> void:
	# 0.8+0.5=1.3 clamp 1.0；roll 0.99 < 1.0 → 必暴
	assert_float(WeaponBaseScript.crit_multiplier(0.99, 0.8, 0.5, 2.0)).is_equal(2.0)

func test_crit_zero_chance_never_crits() -> void:
	assert_float(WeaponBaseScript.crit_multiplier(0.0, 0.0, 0.0, 2.0)).is_equal(1.0)

# ── damage_for 实例(确定性极值)──
func test_damage_for_no_crit_is_base_times_mult() -> void:
	var w = auto_free(WeaponBaseScript.new())
	_player.add_child(w)
	await get_tree().process_frame
	_player.damage_mult = 2.0
	assert_float(w.damage_for(10.0)).is_equal_approx(20.0, 0.001)

func test_damage_for_guaranteed_crit() -> void:
	var w = auto_free(WeaponBaseScript.new())
	_player.add_child(w)
	await get_tree().process_frame
	_player.damage_mult = 1.0
	_player.crit_chance = 1.0   # 必暴
	_player.crit_mult = 2.0
	assert_float(w.damage_for(10.0, true)).is_equal_approx(20.0, 0.001)

func test_damage_for_can_crit_false_ignores_crit() -> void:
	var w = auto_free(WeaponBaseScript.new())
	_player.add_child(w)
	await get_tree().process_frame
	_player.damage_mult = 1.0
	_player.crit_chance = 1.0
	assert_float(w.damage_for(10.0, false)).is_equal_approx(10.0, 0.001)
