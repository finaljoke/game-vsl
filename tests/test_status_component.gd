extends GdUnitTestSuite
# 状态底座纯逻辑单测(RefCounted，无需场景)。preload 引用脚本，避免类缓存重建依赖。

const StatusComponentScript := preload("res://scenes/enemies/status_component.gd")

func _sc():
	return StatusComponentScript.new()

func test_no_status_speed_mult_is_one() -> void:
	assert_float(_sc().move_speed_mult()).is_equal(1.0)

func test_no_status_not_stunned() -> void:
	assert_bool(_sc().is_stunned()).is_false()

func test_slow_sets_speed_mult() -> void:
	var s = _sc()
	s.apply(&"slow", 0.5, 1.0)
	assert_float(s.move_speed_mult()).is_equal_approx(0.5, 0.001)

func test_slow_takes_strongest_lower_mult() -> void:
	var s = _sc()
	s.apply(&"slow", 0.5, 1.0)
	s.apply(&"slow", 0.7, 1.0)   # 较弱(更快) → 不取代
	assert_float(s.move_speed_mult()).is_equal_approx(0.5, 0.001)
	s.apply(&"slow", 0.3, 1.0)   # 更强(更慢) → 取代
	assert_float(s.move_speed_mult()).is_equal_approx(0.3, 0.001)

func test_freeze_zeroes_speed_and_stuns() -> void:
	var s = _sc()
	s.apply(&"freeze", 0.0, 1.0)
	assert_float(s.move_speed_mult()).is_equal(0.0)
	assert_bool(s.is_stunned()).is_true()

func test_stun_sets_stunned_without_slowing() -> void:
	var s = _sc()
	s.apply(&"stun", 0.0, 1.0)
	assert_bool(s.is_stunned()).is_true()
	assert_float(s.move_speed_mult()).is_equal(1.0)

func test_burn_returns_damage_in_quarter_second_chunks() -> void:
	var s = _sc()
	s.apply(&"burn", 8.0, 2.0)   # 8 dps
	assert_float(s.tick(0.25)).is_equal_approx(2.0, 0.001)   # 一拍 = 8×0.25
	assert_float(s.tick(0.25)).is_equal_approx(2.0, 0.001)

func test_burn_accumulates_partial_deltas() -> void:
	var s = _sc()
	s.apply(&"burn", 8.0, 2.0)
	assert_float(s.tick(0.1)).is_equal(0.0)                  # 0.1 < 0.25 未满一拍
	assert_float(s.tick(0.1)).is_equal(0.0)                  # 累计 0.2，仍未满
	assert_float(s.tick(0.1)).is_equal_approx(2.0, 0.001)    # 累计 0.3 → 结算一拍

func test_burn_refresh_takes_strongest_dps() -> void:
	var s = _sc()
	s.apply(&"burn", 4.0, 2.0)
	s.apply(&"burn", 8.0, 2.0)   # 更高 dps → 取代
	assert_float(s.tick(0.25)).is_equal_approx(2.0, 0.001)   # 8×0.25

func test_burn_damage_on_expiry_tick() -> void:
	var s = _sc()
	s.apply(&"burn", 8.0, 0.25)   # 时长恰好等于一拍 → 到期同帧仍应结算这一拍
	assert_float(s.tick(0.25)).is_equal_approx(2.0, 0.001)   # 不能为 0

func test_no_burn_tick_returns_zero() -> void:
	assert_float(_sc().tick(1.0)).is_equal(0.0)

func test_status_expires_after_duration() -> void:
	var s = _sc()
	s.apply(&"slow", 0.5, 0.5)
	s.tick(0.6)   # 超过时长 → 过期
	assert_float(s.move_speed_mult()).is_equal(1.0)
	assert_bool(s.has(&"slow")).is_false()

func test_has_reports_active_status() -> void:
	var s = _sc()
	s.apply(&"slow", 0.5, 1.0)
	assert_bool(s.has(&"slow")).is_true()
	assert_bool(s.has(&"freeze")).is_false()

func test_apply_zero_duration_is_noop() -> void:
	var s = _sc()
	s.apply(&"slow", 0.5, 0.0)
	assert_bool(s.has(&"slow")).is_false()

func test_freeze_overrides_slow_for_speed() -> void:
	var s = _sc()
	s.apply(&"slow", 0.5, 1.0)
	s.apply(&"freeze", 0.0, 1.0)
	assert_float(s.move_speed_mult()).is_equal(0.0)
