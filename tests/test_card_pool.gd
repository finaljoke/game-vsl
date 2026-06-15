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

func _stub_owns(id: String, lvl: int) -> void:
	# 测试 seam：直接注入持有状态而不实例化武器场景（避免副作用如 OrbShield 子节点）
	_player.owned_weapons[id] = {"node": null, "level": lvl}

func test_pick_excludes_weapon_already_owned() -> void:
	_stub_owns("knife", 1)
	var cards := CardPool.pick(_player, 10)
	for card in cards:
		assert_str(card["id"]).is_not_equal("knife")

func test_pick_includes_upgrade_when_weapon_at_level1() -> void:
	_stub_owns("knife", 1)
	var cards := CardPool.pick(_player, 10)
	var found := false
	for card in cards:
		if card["id"] == "knife_2":
			found = true
	assert_bool(found).is_true()

func test_pick_excludes_upgrade_when_weapon_at_level2() -> void:
	_stub_owns("knife", 2)
	var cards := CardPool.pick(_player, 10)
	for card in cards:
		assert_str(card["id"]).is_not_equal("knife_2")

func test_pick_returns_all_available_when_pool_smaller_than_count() -> void:
	# 三种武器都升到 Lv.3（满级）→ 只剩 6 张属性牌（5 种有上限 perk + perk_heal 无上限）
	_stub_owns("knife", 3)
	_stub_owns("orb", 3)
	_stub_owns("explosion", 3)
	var cards := CardPool.pick(_player, 20)
	assert_int(cards.size()).is_equal(6)

func test_pick_includes_lv3_upgrade_when_weapon_at_level2() -> void:
	_stub_owns("knife", 2)
	var cards := CardPool.pick(_player, 20)
	var found := false
	for card in cards:
		if card["id"] == "knife_3":
			found = true
	assert_bool(found).is_true()

func test_pick_excludes_lv3_upgrade_when_weapon_at_level3() -> void:
	_stub_owns("knife", 3)
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
	# 所有有上限 perk 全满 + 所有武器升满 → 池里仍至少有 perk_heal（无上限兜底）+ 3 张进化卡
	# 取 pool 全量（pick > pool size 直接返回所有可选），断言 perk_heal 一定在其中。
	_stub_owns("knife", 3)
	_stub_owns("orb", 3)
	_stub_owns("explosion", 3)
	_player.perk_stacks["perk_speed"] = 8
	_player.perk_stacks["perk_hp"] = 10
	_player.perk_stacks["perk_attack"] = 8
	_player.perk_stacks["perk_xp"] = 6
	_player.perk_stacks["perk_damage"] = 8
	var cards := CardPool.pick(_player, 20)
	assert_int(cards.size()).is_greater_equal(1)
	var has_heal := false
	for c in cards:
		if c["id"] == "perk_heal":
			has_heal = true
	assert_bool(has_heal).is_true()

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
	assert_int(_player.get_weapon_level("knife")).is_equal(1)

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
	CardPool.apply({"id": "knife_2"}, _player)
	CardPool.apply({"id": "knife_3"}, _player)
	assert_int(_player.get_weapon_level("knife")).is_equal(3)
	for child in _player.get_children():
		if child is KnifeWeapon:
			assert_float(child.cooldown).is_equal_approx(0.3, 0.001)
			assert_int(child.pierce).is_equal(4)

func test_apply_explosion_3_sets_level_and_cooldown() -> void:
	CardPool.apply({"id": "explosion"}, _player)
	CardPool.apply({"id": "explosion_2"}, _player)
	CardPool.apply({"id": "explosion_3"}, _player)
	assert_int(_player.get_weapon_level("explosion")).is_equal(3)
	for child in _player.get_children():
		if child is ExplosionWeapon:
			assert_float(child.cooldown).is_equal_approx(1.0, 0.001)

func test_apply_orb_3_sets_level_and_orb_count() -> void:
	CardPool.apply({"id": "orb"}, _player)
	CardPool.apply({"id": "orb_2"}, _player)
	CardPool.apply({"id": "orb_3"}, _player)
	assert_int(_player.get_weapon_level("orb")).is_equal(3)
	for child in _player.get_children():
		if child is OrbShield:
			assert_int(child.total_orbs).is_equal(4)

# ── apply() 进化：3 张进化卡命中真实 evolved .tres，不再走 source 数据兜底 ──────

func test_apply_evolve_knife_grants_thousand_edge() -> void:
	# 拉满源武器 + 进化（走真实 thousand_edge.tres，不再 fallback 到 knife）
	CardPool.apply({"id": "knife"}, _player)
	CardPool.apply({"id": "knife_2"}, _player)
	CardPool.apply({"id": "knife_3"}, _player)
	CardPool.apply({"id": "evolve_knife", "type": "evolution"}, _player)
	assert_bool(_player.has_weapon("thousand_edge")).is_true()
	assert_bool(_player.has_weapon("knife")).is_false()
	# 新挂上的 KnifeWeapon 实例的 data.id 必须是 thousand_edge 且 cooldown=0.15、pierce=8
	for child in _player.get_children():
		if child is KnifeWeapon and child.data != null and child.data.id == "thousand_edge":
			assert_float(child.cooldown).is_equal_approx(0.15, 0.001)
			assert_int(child.pierce).is_equal(8)

func test_apply_evolve_orb_grants_mega_orb() -> void:
	CardPool.apply({"id": "orb"}, _player)
	CardPool.apply({"id": "orb_2"}, _player)
	CardPool.apply({"id": "orb_3"}, _player)
	CardPool.apply({"id": "evolve_orb", "type": "evolution"}, _player)
	assert_bool(_player.has_weapon("mega_orb")).is_true()
	assert_bool(_player.has_weapon("orb")).is_false()
	for child in _player.get_children():
		if child is OrbWeapon and child.data != null and child.data.id == "mega_orb":
			assert_int(child.total_orbs).is_equal(8)

func test_apply_evolve_explosion_grants_nuke() -> void:
	CardPool.apply({"id": "explosion"}, _player)
	CardPool.apply({"id": "explosion_2"}, _player)
	CardPool.apply({"id": "explosion_3"}, _player)
	CardPool.apply({"id": "evolve_explosion", "type": "evolution"}, _player)
	assert_bool(_player.has_weapon("nuke")).is_true()
	assert_bool(_player.has_weapon("explosion")).is_false()
	for child in _player.get_children():
		if child is ExplosionWeapon and child.data != null and child.data.id == "nuke":
			assert_float(child.cooldown).is_equal_approx(0.5, 0.001)

# ── 进化解锁阈值：读 evolution.requires_perk_stacks（半值），不再要求 perk 满层 ──

func test_evolve_unlocks_at_half_perk_stacks() -> void:
	# knife Lv.3 + perk_attack 4 层（perk cap 是 8，半值 4）→ evolve_knife 应被 pick 选中
	_stub_owns("knife", 3)
	_player.perk_stacks["perk_attack"] = 4
	var cards := CardPool.pick(_player, 20)
	var found := false
	for c in cards:
		if c["id"] == "evolve_knife":
			found = true
	assert_bool(found).is_true()

func test_evolve_locked_below_half_perk_stacks() -> void:
	# knife Lv.3 + perk_attack 3 层 → 还差 1 层，进化卡不应出现
	_stub_owns("knife", 3)
	_player.perk_stacks["perk_attack"] = 3
	var cards := CardPool.pick(_player, 20)
	for c in cards:
		assert_str(c["id"]).is_not_equal("evolve_knife")

func test_pick_excludes_base_weapon_after_evolution() -> void:
	# 回归：进化后 replace_weapon 抹掉源武器 id，no:<id> 条件曾让基础武器卡重新可选。
	# 进化成 nuke 后，"explosion" 基础卡不应再出现。
	CardPool.apply({"id": "explosion"}, _player)
	CardPool.apply({"id": "explosion_2"}, _player)
	CardPool.apply({"id": "explosion_3"}, _player)
	CardPool.apply({"id": "evolve_explosion", "type": "evolution"}, _player)
	var cards := CardPool.pick(_player, 20)
	for card in cards:
		assert_str(card["id"]).is_not_equal("explosion")
		assert_str(card["id"]).is_not_equal("explosion_2")
		assert_str(card["id"]).is_not_equal("explosion_3")

func test_evolve_explosion_sets_distinct_blast_visuals() -> void:
	# 进化形态应有区别于基础的视觉(更大/变色)，由 nuke.tres 的 levels 数据驱动注入。
	CardPool.apply({"id": "explosion"}, _player)
	CardPool.apply({"id": "explosion_2"}, _player)
	CardPool.apply({"id": "explosion_3"}, _player)
	CardPool.apply({"id": "evolve_explosion", "type": "evolution"}, _player)
	var found := false
	for child in _player.get_children():
		if child is ExplosionWeapon and child.data != null and child.data.id == "nuke":
			found = true
			assert_float(child.blast_scale).is_greater(1.0)
	assert_bool(found).is_true()

func test_evolve_knife_sets_distinct_projectile_visuals() -> void:
	CardPool.apply({"id": "knife"}, _player)
	CardPool.apply({"id": "knife_2"}, _player)
	CardPool.apply({"id": "knife_3"}, _player)
	CardPool.apply({"id": "evolve_knife", "type": "evolution"}, _player)
	var found := false
	for child in _player.get_children():
		if child is KnifeWeapon and child.data != null and child.data.id == "thousand_edge":
			found = true
			assert_float(child.proj_scale).is_greater(1.0)
	assert_bool(found).is_true()

func test_base_weapons_have_neutral_visuals() -> void:
	# 基础武器不指定视觉键 → 保持默认(scale=1.0)，不被进化视觉影响
	CardPool.apply({"id": "explosion"}, _player)
	CardPool.apply({"id": "knife"}, _player)
	for child in _player.get_children():
		if child is ExplosionWeapon and child.data != null and child.data.id == "explosion":
			assert_float(child.blast_scale).is_equal_approx(1.0, 0.001)
		if child is KnifeWeapon and child.data != null and child.data.id == "knife":
			assert_float(child.proj_scale).is_equal_approx(1.0, 0.001)

func test_evolve_orb_uses_its_own_threshold() -> void:
	# orb 的 requires_perk_stacks=5（perk_hp cap 是 10）；5 层够、4 层不够
	_stub_owns("orb", 3)
	_player.perk_stacks["perk_hp"] = 5
	var cards5 := CardPool.pick(_player, 20)
	var found5 := false
	for c in cards5:
		if c["id"] == "evolve_orb":
			found5 = true
	assert_bool(found5).is_true()

	_player.perk_stacks["perk_hp"] = 4
	var cards4 := CardPool.pick(_player, 20)
	for c in cards4:
		assert_str(c["id"]).is_not_equal("evolve_orb")
