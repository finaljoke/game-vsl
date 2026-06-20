extends GdUnitTestSuite

const Harness := preload("res://autoloads/run_harness.gd")

func test_solo_profile_takes_weapon_first() -> void:
	var prof := Harness.solo_profile("knife", "perk_attack")
	var offered := [{"id": "perk_hp", "type": "perk"}, {"id": "knife", "type": "weapon"}]
	assert_str(String(Harness.choose_card(offered, prof)["id"])).is_equal("knife")

func test_solo_profile_prefers_evo_perk_over_survival() -> void:
	# 进化 perk 优先于通用生存 perk → 保证能堆到 evolve_ready 阈值。
	var prof := Harness.solo_profile("knife", "perk_attack")
	var offered := [{"id": "perk_hp", "type": "perk"}, {"id": "perk_attack", "type": "perk"}]
	assert_str(String(Harness.choose_card(offered, prof)["id"])).is_equal("perk_attack")

func test_solo_profile_takes_evolution_when_offered() -> void:
	var prof := Harness.solo_profile("knife", "perk_attack")
	var offered := [{"id": "perk_attack", "type": "perk"}, {"id": "evolve_knife", "type": "evolution"}]
	assert_str(String(Harness.choose_card(offered, prof)["id"])).is_equal("evolve_knife")

func test_profile_for_solo_dispatch() -> void:
	var prof: Array = Harness.profile_for("solo_whip")
	assert_bool(prof.is_empty()).is_false()
	assert_str(String(prof[0])).is_equal("whip")

func test_profile_for_default_fallback() -> void:
	assert_array(Harness.profile_for("default")).is_equal(Harness.DEFAULT_PROFILE)

# ── P3:混编优先表 ───────────────────────────────────────────────────────────
func test_mix_profile_target_first_then_chassis() -> void:
	var p := Harness.mix_profile("knife", "perk_attack")
	# 目标武器及其进化链排在底盘(frostbite)之前
	assert_int(p.find("knife")).is_less(p.find("frostbite"))
	assert_int(p.find("evolve_knife")).is_greater_equal(0)
	assert_int(p.find("perk_attack")).is_greater_equal(0)
	# 不含通用 type:weapon(否则拿外来武器污染混编)
	assert_bool(p.has("type:weapon")).is_false()

func test_mix_profile_base_has_no_target() -> void:
	var p := Harness.mix_profile("", "perk_hp")
	assert_bool(p.has("frostbite")).is_true()        # 底盘仍在
	assert_bool(p.has("evolve_")).is_false()

func test_profile_for_mix_dispatch() -> void:
	var prof: Array = Harness.profile_for("mix_knife")
	assert_int(prof.find("knife")).is_less(prof.find("frostbite"))
