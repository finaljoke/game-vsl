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
	var cards := CardPool.pick(_player, 99)
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
	# 占满 6 武器槽全满级 → 武器/升级/进化全剔除。满血 → perk_heal 剔除。
	# 剩：5 属性 + 4 现有质变 + perk_crit + synergy_crit(物理武器在) = 11
	for id in ["knife", "orb", "explosion", "lightning", "whip", "boomerang"]:
		_stub_owns(id, 3)
	_player.hp = _player.max_hp
	var cards := CardPool.pick(_player, 99)
	assert_int(cards.size()).is_equal(11)

func test_pick_includes_lv3_upgrade_when_weapon_at_level2() -> void:
	_stub_owns("knife", 2)
	var cards := CardPool.pick(_player, 99)
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
	var cards := CardPool.pick(_player, 99)
	# 新(perk_heal 改为受伤条件卡，不再恒在池中):
	var perk_ids := ["perk_speed", "perk_hp", "perk_attack", "perk_xp", "perk_damage"]
	for perk_id in perk_ids:
		var found := false
		for card in cards:
			if card["id"] == perk_id:
				found = true
		assert_bool(found).is_true()

func test_pick_excludes_weapon_cards_when_slots_full() -> void:
	# 槽位占满 → weapon 类型卡不再进入选项(在 UI 层就消失，产生"装不下"的取舍)
	for i in range(_player.MAX_WEAPON_SLOTS):
		_player.owned_weapons["slot_%d" % i] = {"node": null, "level": 1}
	var cards := CardPool.pick(_player, 50)
	for card in cards:
		assert_str(card.get("type", "")).is_not_equal("weapon")

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
	var cards := CardPool.pick(_player, 99)
	assert_int(cards.size()).is_greater_equal(1)
	# (原 has_heal 断言已删：perk_heal 满血不再进池)

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
			assert_float(child.cooldown).is_equal_approx(0.5, 0.001)   # 长弓 Lv3=0.5(原 0.3)
			assert_int(child.pierce).is_equal(4)

func test_apply_explosion_3_sets_level_and_cooldown() -> void:
	CardPool.apply({"id": "explosion"}, _player)
	CardPool.apply({"id": "explosion_2"}, _player)
	CardPool.apply({"id": "explosion_3"}, _player)
	assert_int(_player.get_weapon_level("explosion")).is_equal(3)
	for child in _player.get_children():
		if child is ExplosionWeapon:
			assert_float(child.cooldown).is_equal_approx(1.3, 0.001)

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

# ── 进化解锁阈值：C1 统一降到 3(配合 XP 提速让进化落在 ~5 分钟)──────────────

func test_evolve_unlocks_at_perk_threshold() -> void:
	# knife Lv.3 + perk_attack 达阈值(3) → evolve_knife 应被 pick 选中
	_stub_owns("knife", 3)
	_player.perk_stacks["perk_attack"] = 3
	var cards := CardPool.pick(_player, 99)
	var found := false
	for c in cards:
		if c["id"] == "evolve_knife":
			found = true
	assert_bool(found).is_true()

func test_evolve_locked_below_perk_threshold() -> void:
	# knife Lv.3 + perk_attack 2 层 → 还差 1 层，进化卡不应出现
	_stub_owns("knife", 3)
	_player.perk_stacks["perk_attack"] = 2
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
	# orb 的 requires_perk_stacks=3：3 层够、2 层不够
	_stub_owns("orb", 3)
	_player.perk_stacks["perk_hp"] = 3
	var cards3 := CardPool.pick(_player, 99)
	var found3 := false
	for c in cards3:
		if c["id"] == "evolve_orb":
			found3 = true
	assert_bool(found3).is_true()

	_player.perk_stacks["perk_hp"] = 2
	var cards2 := CardPool.pick(_player, 99)
	for c in cards2:
		assert_str(c["id"]).is_not_equal("evolve_orb")

# ── E2: 稀有度加权 / banish / reset_run ────────────────────────────────────

func test_rarity_weight_orders_by_rarity() -> void:
	var w_common := CardPool.rarity_weight({"rarity": "common"})
	var w_uncommon := CardPool.rarity_weight({"rarity": "uncommon"})
	var w_rare := CardPool.rarity_weight({"rarity": "rare"})
	var w_legendary := CardPool.rarity_weight({"rarity": "legendary"})
	assert_int(w_common).is_greater(w_uncommon)
	assert_int(w_uncommon).is_greater(w_rare)
	assert_int(w_rare).is_greater(w_legendary)

func test_rarity_weight_defaults_to_common() -> void:
	assert_int(CardPool.rarity_weight({})).is_equal(CardPool.rarity_weight({"rarity": "common"}))

func test_all_runtime_cards_have_rarity() -> void:
	for card in CardPool._runtime_cards:
		assert_bool(card.has("rarity")).is_true()

func test_weapon_cards_are_uncommon() -> void:
	for card in CardPool._runtime_cards:
		if card.get("type", "") == "weapon":
			assert_str(card["rarity"]).is_equal("uncommon")

func test_evolution_cards_are_legendary() -> void:
	for card in CardPool._runtime_cards:
		if card.get("type", "") == "evolution":
			assert_str(card["rarity"]).is_equal("legendary")

func test_banish_removes_card_from_pool() -> void:
	CardPool.reset_run()
	CardPool.banish("perk_speed")
	var cards := CardPool.pick(_player, 99)
	for card in cards:
		assert_str(card["id"]).is_not_equal("perk_speed")
	CardPool.reset_run()  # 清理：别污染其他用例

func test_reset_run_restores_banished() -> void:
	CardPool.banish("perk_speed")
	CardPool.reset_run()
	var cards := CardPool.pick(_player, 99)
	var found := false
	for card in cards:
		if card["id"] == "perk_speed":
			found = true
	assert_bool(found).is_true()

func test_pick_has_no_duplicate_ids() -> void:
	var cards := CardPool.pick(_player, 99)
	var seen := {}
	for card in cards:
		assert_bool(seen.has(card["id"])).is_false()
		seen[card["id"]] = true

# ── E3: 质变卡条件 + 效果 ──────────────────────────────────────────────────

func test_has_condition_true_when_owned() -> void:
	_stub_owns("knife", 1)
	assert_bool(CardPool._check_condition("has:knife", _player)).is_true()

func test_has_condition_false_when_not_owned() -> void:
	assert_bool(CardPool._check_condition("has:knife", _player)).is_false()

func test_has_any_true_when_one_owned() -> void:
	_stub_owns("boomerang", 1)
	assert_bool(CardPool._check_condition("has_any:knife,boomerang", _player)).is_true()

func test_has_any_false_when_none_owned() -> void:
	assert_bool(CardPool._check_condition("has_any:knife,boomerang", _player)).is_false()

func test_synergy_pierce_increments_global_pierce() -> void:
	CardPool.apply({"id": "synergy_pierce", "type": "synergy"}, _player)
	assert_int(_player.global_pierce).is_equal(1)

func test_synergy_multishot_increments_extra_projectiles() -> void:
	CardPool.apply({"id": "synergy_multishot", "type": "synergy"}, _player)
	assert_int(_player.extra_projectiles).is_equal(1)

func test_synergy_magnet_scales_pickup_range() -> void:
	CardPool.apply({"id": "synergy_magnet", "type": "synergy"}, _player)
	assert_float(_player.pickup_range_mult).is_equal_approx(1.5, 0.001)

func test_synergy_lifesteal_increases_lifesteal() -> void:
	CardPool.apply({"id": "synergy_lifesteal", "type": "synergy"}, _player)
	assert_float(_player.lifesteal).is_equal_approx(0.5, 0.001)

func test_synergy_tracks_stacks() -> void:
	CardPool.apply({"id": "synergy_magnet", "type": "synergy"}, _player)
	CardPool.apply({"id": "synergy_magnet", "type": "synergy"}, _player)
	assert_int(_player.perk_stacks.get("synergy_magnet", 0)).is_equal(2)

func test_synergy_pierce_gated_by_weapon_ownership() -> void:
	# 不持有投射武器 → synergy_pierce 不入池；持有 knife → 入池
	for c in CardPool.pick(_player, 99):
		assert_str(c["id"]).is_not_equal("synergy_pierce")
	_stub_owns("knife", 1)
	var found := false
	for c in CardPool.pick(_player, 99):
		if c["id"] == "synergy_pierce":
			found = true
	assert_bool(found).is_true()

# ── Phase0 单元1：进化就绪扫描 ─────────────────────────────────────────────
func test_ready_evolutions_empty_when_none_ready() -> void:
	assert_int(CardPool.ready_evolutions(_player).size()).is_equal(0)

func test_ready_evolutions_returns_single_ready() -> void:
	_stub_owns("orb", 3)
	_player.perk_stacks["perk_hp"] = 3
	var ready := CardPool.ready_evolutions(_player)
	assert_int(ready.size()).is_equal(1)
	assert_str(ready[0]["id"]).is_equal("evolve_orb")

func test_ready_evolutions_sorted_by_weapon_id() -> void:
	# explosion(perk_damage) 与 orb(perk_hp) 同时就绪 → 字典序 explosion < orb
	_stub_owns("explosion", 3)
	_player.perk_stacks["perk_damage"] = 3
	_stub_owns("orb", 3)
	_player.perk_stacks["perk_hp"] = 3
	var ready := CardPool.ready_evolutions(_player)
	assert_int(ready.size()).is_equal(2)
	assert_str(ready[0]["id"]).is_equal("evolve_explosion")
	assert_str(ready[1]["id"]).is_equal("evolve_orb")

# ── Phase0 单元1：就绪进化确定性投放 ───────────────────────────────────────
func test_pick_offers_ready_evolution() -> void:
	_stub_owns("orb", 3)
	_player.perk_stacks["perk_hp"] = 3
	var cards := CardPool.pick(_player, 3)
	var found := false
	for c in cards:
		if c["id"] == "evolve_orb":
			found = true
	assert_bool(found).is_true()

func test_pick_no_evolution_when_none_ready() -> void:
	var cards := CardPool.pick(_player, 3)
	for c in cards:
		assert_str(c.get("type", "")).is_not_equal("evolution")

func test_pick_offers_exactly_one_evolution_when_multiple_ready() -> void:
	_stub_owns("explosion", 3)
	_player.perk_stacks["perk_damage"] = 3
	_stub_owns("orb", 3)
	_player.perk_stacks["perk_hp"] = 3
	var cards := CardPool.pick(_player, 3)
	var evo_count := 0
	var evo_id := ""
	for c in cards:
		if c.get("type", "") == "evolution":
			evo_count += 1
			evo_id = c["id"]
	assert_int(evo_count).is_equal(1)
	assert_str(evo_id).is_equal("evolve_explosion")  # 字典序第一

# ── Phase0 单元1：进化卡门控透明化 ─────────────────────────────────────────
func test_evolution_desc_states_requirement() -> void:
	var desc := ""
	for card in CardPool._runtime_cards:
		if card["id"] == "evolve_orb":
			desc = String(card["desc"])
	assert_str(desc).contains("生命上限")  # perk_hp 中文名
	assert_str(desc).contains("3")          # 阈值

# ── Phase0 单元2：perk_heal 去陷阱 ─────────────────────────────────────────
func test_perk_heal_excluded_at_full_hp() -> void:
	_player.hp = _player.max_hp
	var cards := CardPool.pick(_player, 99)
	for c in cards:
		assert_str(c["id"]).is_not_equal("perk_heal")

func test_perk_heal_offered_when_wounded() -> void:
	_player.hp = _player.max_hp * 0.5
	var cards := CardPool.pick(_player, 99)
	var found := false
	for c in cards:
		if c["id"] == "perk_heal":
			found = true
	assert_bool(found).is_true()

# ── Phase0 单元2：空池兜底 ─────────────────────────────────────────────────
func test_fallback_card_grants_reroll_token() -> void:
	var before := _player.reroll_tokens
	CardPool.apply(CardPool._fallback_card(), _player)
	assert_int(_player.reroll_tokens).is_equal(before + 1)

func test_pick_never_empty_via_fallback() -> void:
	CardPool.reset_run()
	# 把所有运行时卡 banish 掉 → 随机池与就绪进化全清空 → 触发兜底
	for card in CardPool._runtime_cards:
		CardPool.banish(String(card["id"]))
	_player.hp = _player.max_hp
	var cards := CardPool.pick(_player, 3)
	assert_int(cards.size()).is_equal(1)
	assert_str(cards[0]["id"]).is_equal("fallback_token")
	CardPool.reset_run()  # 清理：别污染其它用例

# ── P1 单元1：has_tag 条件 DSL ─────────────────────────────────────────────
func test_has_tag_false_when_no_tagged_weapon() -> void:
	assert_bool(CardPool._check_condition("has_tag:fire", _player)).is_false()

func test_has_tag_true_when_owns_fire_weapon() -> void:
	_stub_owns("explosion", 1)
	assert_bool(CardPool._check_condition("has_tag:fire", _player)).is_true()

func test_has_tag_physical_true_for_knife() -> void:
	_stub_owns("knife", 1)
	assert_bool(CardPool._check_condition("has_tag:physical", _player)).is_true()

# ── P1 单元3：暴击卡 ───────────────────────────────────────────────────────
func test_perk_crit_increases_crit_chance() -> void:
	CardPool.apply({"id": "perk_crit", "type": "perk"}, _player)
	assert_float(_player.crit_chance).is_equal_approx(0.08, 0.001)

func test_perk_crit_caps_at_60_percent() -> void:
	for i in range(20):
		CardPool.apply({"id": "perk_crit", "type": "perk"}, _player)
	assert_float(_player.crit_chance).is_equal_approx(0.60, 0.001)

func test_synergy_crit_increases_crit_mult() -> void:
	CardPool.apply({"id": "synergy_crit", "type": "synergy"}, _player)
	assert_float(_player.crit_mult).is_equal_approx(2.4, 0.001)

func test_crit_cards_gated_by_physical_weapon() -> void:
	for c in CardPool.pick(_player, 99):
		assert_str(c["id"]).is_not_equal("perk_crit")
	_stub_owns("knife", 1)
	var found := false
	for c in CardPool.pick(_player, 99):
		if c["id"] == "perk_crit":
			found = true
	assert_bool(found).is_true()
