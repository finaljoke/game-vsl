extends GdUnitTestSuite

func test_spawn_burst_returns_configured_particles() -> void:
	var host: Node2D = auto_free(Node2D.new())
	add_child(host)
	var p: CPUParticles2D = Vfx.spawn_burst(Vector2(10, 20), &"fire_burst", host)
	assert_object(p).is_not_null()
	assert_bool(p is CPUParticles2D).is_true()
	assert_bool(p.emitting).is_true()
	assert_bool(p.one_shot).is_true()
	assert_int(p.amount).is_equal(10)
	assert_object(p.get_parent()).is_same(host)
	assert_vector(p.global_position).is_equal_approx(Vector2(10, 20), Vector2(0.5, 0.5))

func test_spawn_burst_additive_preset_uses_add_material() -> void:
	var host: Node2D = auto_free(Node2D.new())
	add_child(host)
	var p: CPUParticles2D = Vfx.spawn_burst(Vector2.ZERO, &"hit_spark", host)
	assert_object(p.material).is_not_null()
	assert_int((p.material as CanvasItemMaterial).blend_mode).is_equal(CanvasItemMaterial.BLEND_MODE_ADD)

func test_spawn_burst_unknown_preset_returns_null() -> void:
	var host: Node2D = auto_free(Node2D.new())
	add_child(host)
	assert_object(Vfx.spawn_burst(Vector2.ZERO, &"nope", host)).is_null()

func test_build_frames_count() -> void:
	var sf: SpriteFrames = Vfx.build_frames(&"explosion_regular")
	assert_object(sf).is_not_null()
	assert_int(sf.get_frame_count(&"default")).is_equal(9)

func test_build_frames_cached() -> void:
	var a: SpriteFrames = Vfx.build_frames(&"explosion_regular")
	var b: SpriteFrames = Vfx.build_frames(&"explosion_regular")
	assert_object(a).is_same(b)

func test_build_frames_unknown_null() -> void:
	assert_object(Vfx.build_frames(&"nope")).is_null()

func test_spawn_anim_plays_and_parents() -> void:
	var host: Node2D = auto_free(Node2D.new())
	add_child(host)
	var a: AnimatedSprite2D = Vfx.spawn_anim(Vector2(5, 5), &"explosion_sonic", host)
	assert_object(a).is_not_null()
	assert_bool(a is AnimatedSprite2D).is_true()
	assert_bool(a.is_playing()).is_true()
	assert_object(a.get_parent()).is_same(host)
