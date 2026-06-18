extends GdUnitTestSuite

func test_weapon_burst_presets_registered() -> void:
	for k in [&"blood_burst", &"crit_spark", &"ice_shard", &"shock_spark"]:
		assert_bool(Vfx.BURST_PRESETS.has(k)).is_true()

func test_make_trail_returns_emitting_particles() -> void:
	var t: CPUParticles2D = Vfx.make_trail(Color(1, 0, 0))
	assert_bool(t is CPUParticles2D).is_true()
	assert_bool(t.emitting).is_true()
	assert_bool(t.one_shot).is_false()
	t.free()

func test_make_trail_additive_uses_add_material() -> void:
	var t: CPUParticles2D = Vfx.make_trail(Color(1, 1, 1), true)
	assert_int((t.material as CanvasItemMaterial).blend_mode).is_equal(CanvasItemMaterial.BLEND_MODE_ADD)
	t.free()
