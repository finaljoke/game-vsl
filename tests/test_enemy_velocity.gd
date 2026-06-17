extends GdUnitTestSuite
# Enemy.compose_velocity 纯静态合成单测(无需实例化场景)。
const EnemyScript := preload("res://scenes/enemies/enemy.gd")

func test_compose_full_speed_no_status_no_external() -> void:
	var v: Vector2 = EnemyScript.compose_velocity(Vector2(80, 0), 1.0, false, Vector2.ZERO)
	assert_vector(v).is_equal(Vector2(80, 0))

func test_compose_slow_scales_desired() -> void:
	var v: Vector2 = EnemyScript.compose_velocity(Vector2(80, 0), 0.5, false, Vector2.ZERO)
	assert_vector(v).is_equal(Vector2(40, 0))

func test_compose_adds_external_velocity() -> void:
	var v: Vector2 = EnemyScript.compose_velocity(Vector2(80, 0), 1.0, false, Vector2(0, 100))
	assert_vector(v).is_equal(Vector2(80, 100))

func test_compose_stunned_drops_self_motion_keeps_external() -> void:
	# 硬直：自身期望速度归零，但仍受外力(击退/拉拽)推动
	var v: Vector2 = EnemyScript.compose_velocity(Vector2(80, 0), 1.0, true, Vector2(0, 100))
	assert_vector(v).is_equal(Vector2(0, 100))

func test_compose_frozen_zero_mult_still_takes_external() -> void:
	# 冻结时调用方传 speed_mult=0 且 stunned=true → 只剩外力
	var v: Vector2 = EnemyScript.compose_velocity(Vector2(80, 0), 0.0, true, Vector2(50, 0))
	assert_vector(v).is_equal(Vector2(50, 0))
