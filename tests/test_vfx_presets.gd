extends GdUnitTestSuite

func test_burst_preset_has_expected_keys() -> void:
	var cfg := Vfx.get_preset(&"fire_burst")
	assert_bool(cfg.is_empty()).is_false()
	assert_bool(cfg.has("color")).is_true()
	assert_bool(cfg.has("amount")).is_true()
	assert_bool(cfg.has("lifetime")).is_true()

func test_anim_preset_has_expected_keys() -> void:
	var cfg := Vfx.get_preset(&"explosion_regular")
	assert_bool(cfg.is_empty()).is_false()
	assert_int(cfg["count"]).is_equal(9)
	assert_str(cfg["base"]).is_equal("regularExplosion")

func test_unknown_preset_is_empty() -> void:
	assert_bool(Vfx.get_preset(&"does_not_exist").is_empty()).is_true()

func test_core_presets_registered() -> void:
	# 底座必备最小集；逐武器扩充留 VFX Wave 2。
	for k in [&"fire_burst", &"frost_burst", &"hit_spark", &"magic_burst"]:
		assert_bool(Vfx.BURST_PRESETS.has(k)).is_true()
	for k in [&"explosion_regular", &"explosion_sonic", &"explosion_ground"]:
		assert_bool(Vfx.ANIM_PRESETS.has(k)).is_true()
