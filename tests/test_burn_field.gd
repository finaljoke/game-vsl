extends GdUnitTestSuite
# 燃烧地火实体集成验证(实例化 enemy.tscn → 依赖 LimboAI headless 加载)。

const BurnFieldScript := preload("res://scenes/weapons/explosion/burn_field.gd")
const EnemyScene := preload("res://scenes/enemies/enemy.tscn")

func _enemy_at(pos: Vector2) -> Enemy:
	var e: Enemy = EnemyScene.instantiate()
	e.behavior = "chase"
	add_child(e)
	e.add_to_group("enemies")
	e.global_position = pos
	return auto_free(e)

func _field(radius: float, dps: float, dur: float) -> Node2D:
	var f = BurnFieldScript.new()
	f.radius = radius
	f.burn_dps = dps
	f.field_dur = dur
	add_child(f)
	f.global_position = Vector2.ZERO
	return auto_free(f)

func test_burn_field_applies_burn_to_enemy_in_radius() -> void:
	var f := _field(80.0, 8.0, 2.0)
	var e := _enemy_at(Vector2(40, 0))   # 半径内
	for i in range(20):
		await get_tree().physics_frame
	assert_bool(e.has_status(&"burn")).is_true()

func test_burn_field_ignores_enemy_out_of_radius() -> void:
	var f := _field(80.0, 8.0, 2.0)
	var e := _enemy_at(Vector2(300, 0))  # 半径外
	for i in range(20):
		await get_tree().physics_frame
	assert_bool(e.has_status(&"burn")).is_false()

func test_burn_field_expires_after_field_dur() -> void:
	var f := _field(80.0, 8.0, 0.2)
	for i in range(30):                  # ~0.5s > 0.2s
		await get_tree().physics_frame
	assert_bool(is_instance_valid(f)).is_false()
