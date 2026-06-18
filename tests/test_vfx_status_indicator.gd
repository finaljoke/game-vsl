extends GdUnitTestSuite

func test_burn_indicator_is_emitting_particles() -> void:
	var n: Node2D = Vfx.make_status_indicator(&"burn")
	assert_object(n).is_not_null()
	assert_bool(n is CPUParticles2D).is_true()
	assert_bool((n as CPUParticles2D).emitting).is_true()
	n.free()

func test_slow_indicator_is_particles() -> void:
	var n: Node2D = Vfx.make_status_indicator(&"slow")
	assert_bool(n is CPUParticles2D).is_true()
	n.free()

func test_freeze_indicator_is_sprite_overlay() -> void:
	var n: Node2D = Vfx.make_status_indicator(&"freeze")
	assert_bool(n is Sprite2D).is_true()
	assert_object((n as Sprite2D).texture).is_not_null()
	n.free()

func test_stun_indicator_is_sprite_overlay() -> void:
	var n: Node2D = Vfx.make_status_indicator(&"stun")
	assert_bool(n is Sprite2D).is_true()
	n.free()

func test_unknown_kind_returns_null() -> void:
	assert_object(Vfx.make_status_indicator(&"nope")).is_null()
