# tests/test_enemy_projectile.gd
# 弹体入组 enemy_projectiles,供 bot 躲弹感知(harness 读该组)。
extends GdUnitTestSuite

func test_enemy_projectile_joins_group_on_ready() -> void:
	var scene := load("res://scenes/enemies/enemy_projectile.tscn") as PackedScene
	var proj: Node = auto_free(scene.instantiate())
	add_child(proj)
	await get_tree().process_frame
	assert_bool(proj.is_in_group("enemy_projectiles")).is_true()
