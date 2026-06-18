extends GdUnitTestSuite

func test_shake_presets_defined() -> void:
	assert_bool(GameFeel.SHAKE_PRESETS.has(&"light")).is_true()
	assert_bool(GameFeel.SHAKE_PRESETS.has(&"medium")).is_true()
	assert_bool(GameFeel.SHAKE_PRESETS.has(&"heavy")).is_true()

func test_weapon_emitters_built() -> void:
	assert_object(GameFeel._weapon_emitters.get(&"light")).is_not_null()
	assert_object(GameFeel._weapon_emitters.get(&"medium")).is_not_null()
	assert_object(GameFeel._weapon_emitters.get(&"heavy")).is_not_null()

func test_shake_known_and_unknown_no_crash() -> void:
	# 已知预设触发、未知预设安全 no-op(headless 无法断言相机位移,只验不崩)。
	GameFeel.shake(&"light")
	GameFeel.shake(&"heavy")
	GameFeel.shake(&"does_not_exist")
	assert_bool(true).is_true()

func test_hitstop_guarded_when_harness_active() -> void:
	var prev_active: bool = RunHarness.active
	var prev_scale := Engine.time_scale
	RunHarness.active = true
	GameFeel.hitstop(0.05)
	assert_float(Engine.time_scale).is_equal(prev_scale)  # 护栏:harness 下不动 time_scale
	RunHarness.active = prev_active
