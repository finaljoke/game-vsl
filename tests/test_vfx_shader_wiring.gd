extends GdUnitTestSuite

const LightningScript := preload("res://scenes/weapons/lightning/lightning_weapon.gd")

func _make_player() -> Node2D:
	var p: Node2D = load("res://scenes/player/player.tscn").instantiate()
	add_child(p)
	return p

func _make_enemy_at(pos: Vector2) -> Node2D:
	var e: Node2D = load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child(e); e.global_position = pos; e.add_to_group("enemies")
	return e

func _ysort() -> Node:
	var ys: Node = get_tree().get_first_node_in_group("ysort")
	return ys if ys != null else get_tree().current_scene

func test_lightning_bolt_uses_electric_shader() -> void:
	var ys: Node2D = auto_free(Node2D.new()) as Node2D
	add_child(ys)
	ys.add_to_group("ysort")
	var player := _make_player()
	var lit := LightningScript.new()
	lit.data = null
	player.add_child(lit)
	await get_tree().process_frame
	var enemy := _make_enemy_at(player.global_position + Vector2(60, 0))
	await get_tree().process_frame
	lit.attack()
	await get_tree().process_frame
	var found := false
	for c in _ysort().get_children():
		if c is Sprite2D and (c as Sprite2D).material is ShaderMaterial:
			found = true
	assert_bool(found).is_true()
	player.queue_free()
	if is_instance_valid(enemy): enemy.queue_free()

func test_orb_shield_sprite_has_summon_shader() -> void:
	var player := _make_player()
	await get_tree().process_frame
	var orb: Node2D = (load("res://scenes/weapons/orb/orb_shield.tscn") as PackedScene).instantiate() as Node2D
	player.add_child(orb)
	await get_tree().process_frame
	var spr: Node = orb.get_node_or_null("Sprite2D")
	assert_object(spr).is_not_null()
	assert_bool((spr as Sprite2D).material is ShaderMaterial).is_true()
	player.queue_free()
