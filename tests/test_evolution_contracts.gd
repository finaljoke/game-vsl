# tests/test_evolution_contracts.gd
# 质变守恒契约(C4 / 柱 P4):复衡后每个进化仍须在设计意图轴上严格 ≥ 基础武器满级 L3。
# 守卫测试——改 .tres 时仍须绿,防过砍把进化变退化。
extends GdUnitTestSuite

func _evo(id: String) -> Dictionary:
	return WeaponDB.get_data(id).levels[0]   # 进化武器单级

func _l3(id: String) -> Dictionary:
	var lv: Array = WeaponDB.get_data(id).levels
	return lv[lv.size() - 1]                 # 基础武器满级(末元素)

# ── inferno_aura ≥ aura L3(覆盖密度仍占优) ────────────────────────────────
func test_inferno_aura_radius_ge_base_l3() -> void:
	assert_float(float(_evo("inferno_aura")["radius"])).is_greater_equal(float(_l3("aura")["radius"]))

func test_inferno_aura_burn_ge_base_l3() -> void:
	assert_float(float(_evo("inferno_aura")["burn_dps"])).is_greater_equal(float(_l3("aura")["burn_dps"]))

# ── cyclone:多发 + 不慢于 boomerang L3 ───────────────────────────────────
func test_cyclone_is_multishot() -> void:
	assert_int(int(_evo("cyclone")["count"])).is_greater_equal(2)

func test_cyclone_cooldown_le_base_l3() -> void:
	assert_float(float(_evo("cyclone")["cooldown"])).is_less_equal(float(_l3("boomerang")["cooldown"]))

# ── horde 严格强于 reanimate L3 ───────────────────────────────────────────
func test_horde_max_minions_gt_base_l3() -> void:
	assert_int(int(_evo("horde")["max_minions"])).is_greater(int(_l3("reanimate")["max_minions"]))

func test_horde_damage_ge_base_l3() -> void:
	assert_float(float(_evo("horde")["damage"])).is_greater_equal(float(_l3("reanimate")["damage"]))

func test_horde_lifetime_ge_base_l3() -> void:
	assert_float(float(_evo("horde")["lifetime"])).is_greater_equal(float(_l3("reanimate")["lifetime"]))

# §3c 防御杠杆:群尸须带本体回血(基础 reanimate 无此键 → 进化独有的生存机制)
func test_horde_has_heal_on_hit() -> void:
	assert_float(float(_evo("horde").get("heal_on_hit", 0.0))).is_greater(0.0)
