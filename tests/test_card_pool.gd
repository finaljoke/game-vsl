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
	# 三种武器都升到 Lv.2 → 只剩 4 张属性牌
	_player.owned_weapons["knife"] = 2
	_player.owned_weapons["orb"] = 2
	_player.owned_weapons["explosion"] = 2
	var cards := CardPool.pick(_player, 10)
	assert_int(cards.size()).is_equal(4)

func test_pick_always_includes_perks() -> void:
	var cards := CardPool.pick(_player, 10)
	var perk_ids := ["perk_speed", "perk_hp", "perk_attack", "perk_xp"]
	for perk_id in perk_ids:
		var found := false
		for card in cards:
			if card["id"] == perk_id:
				found = true
		assert_bool(found).is_true()

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
