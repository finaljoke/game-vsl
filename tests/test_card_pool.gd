# tests/test_card_pool.gd
extends GdUnitTestSuite

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

# ── pick() 条件过滤 ────────────────────────────────────────────────────────

func test_pick_returns_at_most_3_cards() -> void:
	var cards := CardPool.pick(_player, 3)
	assert_int(cards.size()).is_less_equal(3)

func test_pick_excludes_weapon_already_owned() -> void:
	_player.owned_weapons["knife"] = 1
	var cards := CardPool.pick(_player, 10)
	for card in cards:
		assert_str(card["id"]).is_not_equal("knife")

func test_pick_includes_upgrade_when_weapon_at_level1() -> void:
	_player.owned_weapons["knife"] = 1
	var cards := CardPool.pick(_player, 10)
	var found := false
	for card in cards:
		if card["id"] == "knife_2":
			found = true
	assert_bool(found).is_true()

func test_pick_excludes_upgrade_when_weapon_at_level2() -> void:
	_player.owned_weapons["knife"] = 2
	var cards := CardPool.pick(_player, 10)
	for card in cards:
		assert_str(card["id"]).is_not_equal("knife_2")

func test_pick_returns_all_available_when_pool_smaller_than_count() -> void:
	# 三种武器都升到 Lv.3（满级）→ 只剩 6 张属性牌（5 种有上限 perk + perk_heal 无上限）
	_player.owned_weapons["knife"] = 3
	_player.owned_weapons["orb"] = 3
	_player.owned_weapons["explosion"] = 3
	var cards := CardPool.pick(_player, 20)
	assert_int(cards.size()).is_equal(6)

func test_pick_includes_lv3_upgrade_when_weapon_at_level2() -> void:
	_player.owned_weapons["knife"] = 2
	var cards := CardPool.pick(_player, 20)
	var found := false
	for card in cards:
		if card["id"] == "knife_3":
			found = true
	assert_bool(found).is_true()

func test_pick_excludes_lv3_upgrade_when_weapon_at_level3() -> void:
	_player.owned_weapons["knife"] = 3
	var cards := CardPool.pick(_player, 20)
	for card in cards:
		assert_str(card["id"]).is_not_equal("knife_3")

func test_pick_always_includes_perks() -> void:
	var cards := CardPool.pick(_player, 20)
	var perk_ids := ["perk_speed", "perk_hp", "perk_attack", "perk_xp", "perk_damage", "perk_heal"]
	for perk_id in perk_ids:
		var found := false
		for card in cards:
			if card["id"] == perk_id:
				found = true
		assert_bool(found).is_true()

func test_pick_excludes_perk_at_max_stacks() -> void:
	# perk_speed 封顶 8 次
	_player.perk_stacks["perk_speed"] = 8
	var cards := CardPool.pick(_player, 20)
	for card in cards:
		assert_str(card["id"]).is_not_equal("perk_speed")

func test_pick_still_has_cards_when_all_capped() -> void:
	# 所有有上限 perk 全满 + 所有武器升满（Lv.3）→ 只剩 perk_heal
	_player.owned_weapons["knife"] = 3
	_player.owned_weapons["orb"] = 3
	_player.owned_weapons["explosion"] = 3
	_player.perk_stacks["perk_speed"] = 8
	_player.perk_stacks["perk_hp"] = 10
	_player.perk_stacks["perk_attack"] = 8
	_player.perk_stacks["perk_xp"] = 6
	_player.perk_stacks["perk_damage"] = 8
	var cards := CardPool.pick(_player, 3)
	# 兜底卡 perk_heal 保证卡池不为空
	assert_int(cards.size()).is_greater_equal(1)
	assert_str(cards[0]["id"]).is_equal("perk_heal")

# ── apply() 属性效果 ──────────────────────────────────────────────────────

func test_apply_perk_speed_multiplies_speed_mult() -> void:
	CardPool.apply({"id": "perk_speed"}, _player)
	assert_float(_player.speed_mult).is_equal_approx(1.15, 0.001)

func test_apply_perk_hp_increases_max_hp() -> void:
	CardPool.apply({"id": "perk_hp"}, _player)
	assert_float(_player.max_hp).is_equal(120.0)

func test_apply_perk_hp_heals_current_hp() -> void:
	_player.hp = 80.0
	CardPool.apply({"id": "perk_hp"}, _player)
	# min(80 + 20, 120) = 100
	assert_float(_player.hp).is_equal(100.0)

func test_apply_perk_attack_multiplies_attack_speed_mult() -> void:
	CardPool.apply({"id": "perk_attack"}, _player)
	assert_float(_player.attack_speed_mult).is_equal_approx(1.15, 0.001)

func test_apply_perk_xp_multiplies_xp_mult() -> void:
	CardPool.apply({"id": "perk_xp"}, _player)
	assert_float(_player.xp_mult).is_equal_approx(1.25, 0.001)

func test_apply_perk_speed_stacks_multiplicatively() -> void:
	CardPool.apply({"id": "perk_speed"}, _player)
	CardPool.apply({"id": "perk_speed"}, _player)
	assert_float(_player.speed_mult).is_equal_approx(1.15 * 1.15, 0.001)

func test_apply_weapon_registers_in_owned_weapons() -> void:
	CardPool.apply({"id": "knife"}, _player)
	assert_int(_player.owned_weapons.get("knife", 0)).is_equal(1)

func test_apply_perk_damage_multiplies_damage_mult() -> void:
	CardPool.apply({"id": "perk_damage", "type": "perk"}, _player)
	assert_float(_player.damage_mult).is_equal_approx(1.15, 0.001)

func test_apply_perk_damage_stacks_multiplicatively() -> void:
	CardPool.apply({"id": "perk_damage", "type": "perk"}, _player)
	CardPool.apply({"id": "perk_damage", "type": "perk"}, _player)
	assert_float(_player.damage_mult).is_equal_approx(1.15 * 1.15, 0.001)

func test_apply_perk_heal_restores_hp() -> void:
	_player.hp = 50.0
	CardPool.apply({"id": "perk_heal", "type": "perk"}, _player)
	# min(50 + 30, 100) = 80
	assert_float(_player.hp).is_equal_approx(80.0, 0.001)

func test_apply_perk_heal_does_not_overheal() -> void:
	_player.hp = 90.0
	CardPool.apply({"id": "perk_heal", "type": "perk"}, _player)
	assert_float(_player.hp).is_equal_approx(100.0, 0.001)

func test_apply_perk_tracks_stacks() -> void:
	CardPool.apply({"id": "perk_speed", "type": "perk"}, _player)
	CardPool.apply({"id": "perk_speed", "type": "perk"}, _player)
	assert_int(_player.perk_stacks.get("perk_speed", 0)).is_equal(2)

# ── apply() 武器 Lv.3 升级 ────────────────────────────────────────────────

func test_apply_knife_sets_default_pierce() -> void:
	CardPool.apply({"id": "knife"}, _player)
	for child in _player.get_children():
		if child is KnifeWeapon:
			assert_int(child.pierce).is_equal(2)

func test_apply_knife_3_sets_level_cooldown_and_pierce() -> void:
	CardPool.apply({"id": "knife"}, _player)
	CardPool.apply({"id": "knife_3"}, _player)
	assert_int(_player.owned_weapons.get("knife", 0)).is_equal(3)
	for child in _player.get_children():
		if child is KnifeWeapon:
			assert_float(child.cooldown).is_equal_approx(0.3, 0.001)
			assert_int(child.pierce).is_equal(4)

func test_apply_explosion_3_sets_level_and_cooldown() -> void:
	CardPool.apply({"id": "explosion"}, _player)
	CardPool.apply({"id": "explosion_3"}, _player)
	assert_int(_player.owned_weapons.get("explosion", 0)).is_equal(3)
	for child in _player.get_children():
		if child is ExplosionWeapon:
			assert_float(child.cooldown).is_equal_approx(1.0, 0.001)

func test_apply_orb_3_sets_level_and_orb_count() -> void:
	CardPool.apply({"id": "orb"}, _player)
	CardPool.apply({"id": "orb_3"}, _player)
	assert_int(_player.owned_weapons.get("orb", 0)).is_equal(3)
	for child in _player.get_children():
		if child is OrbShield:
			assert_int(child.total_orbs).is_equal(4)
