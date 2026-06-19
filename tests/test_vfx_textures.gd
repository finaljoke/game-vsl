extends GdUnitTestSuite
## VFX 视觉重做：粒子纹理化 + 新序列帧预设 + 带纹理拖尾的契约。

func test_all_burst_presets_have_texture() -> void:
	# 8 个爆发预设全部接上 pack/ 粒子贴图(不再是纯色方块)。
	for k: StringName in Vfx.BURST_PRESETS.keys():
		assert_str(Vfx.BURST_PRESETS[k].get("tex", "")).is_not_empty()

func test_spawn_burst_applies_texture() -> void:
	var host: Node2D = auto_free(Node2D.new())
	add_child(host)
	var p: CPUParticles2D = Vfx.spawn_burst(Vector2.ZERO, &"fire_burst", host)
	assert_object(p).is_not_null()
	assert_object(p.texture).is_not_null()

func test_spawn_burst_scale_normalized_to_texture() -> void:
	# 512px 贴图按宽度归一化后 scale_amount 应远小于 1(否则会铺满屏)。
	var host: Node2D = auto_free(Node2D.new())
	add_child(host)
	var p: CPUParticles2D = Vfx.spawn_burst(Vector2.ZERO, &"fire_burst", host)
	assert_float(p.scale_amount_max).is_less(0.5)
	assert_float(p.scale_amount_max).is_greater(0.0)

func test_new_anim_presets_registered() -> void:
	for k in [&"smoke_puff", &"muzzle_flash", &"gas_cloud"]:
		assert_bool(Vfx.ANIM_PRESETS.has(k)).is_true()

func test_build_frames_smoke_puff_count() -> void:
	var sf: SpriteFrames = Vfx.build_frames(&"smoke_puff")
	assert_object(sf).is_not_null()
	assert_int(sf.get_frame_count(&"default")).is_equal(25)

func test_make_textured_trail_is_emitting_textured() -> void:
	var t: CPUParticles2D = Vfx.make_textured_trail("trace_03.png", Color(1, 1, 1), true)
	assert_bool(t is CPUParticles2D).is_true()
	assert_bool(t.emitting).is_true()
	assert_bool(t.one_shot).is_false()
	assert_object(t.texture).is_not_null()
	assert_int((t.material as CanvasItemMaterial).blend_mode).is_equal(CanvasItemMaterial.BLEND_MODE_ADD)
	t.free()
