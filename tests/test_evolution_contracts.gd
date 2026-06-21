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

# ── P3b 复衡守恒契约(5 进化)──────────────────────────────────────────────────
# ── nuke ≥ explosion L3(全屏覆盖/地火/二连爆身份) ──
func test_nuke_clearing_ge_base_l3() -> void:
	var nuke := _evo("nuke")
	var l3 := _l3("explosion")
	assert_float(float(nuke["blast_radius"])).is_greater_equal(float(l3["blast_radius"]))  # 覆盖 ≥ base
	assert_float(float(nuke["burn_dps"])).is_greater_equal(float(l3["burn_dps"]))          # 地火 ≥ base
	assert_float(float(nuke["field_dur"])).is_greater_equal(float(l3["field_dur"]))        # 地火时长 ≥ base
	assert_float(float(nuke["cooldown"])).is_less_equal(float(l3["cooldown"]))             # 引爆不慢于 base
	assert_int(int(nuke.get("secondary_count", 0))).is_greater(0)                          # 二连爆=质变身份(base 无)

# ── thunderstorm ≥ lightning L3(连锁 + 天雷身份) ──
func test_thunderstorm_clearing_ge_base_l3() -> void:
	var ts := _evo("thunderstorm")
	var l3 := _l3("lightning")
	assert_int(int(ts["chains"])).is_greater_equal(int(l3["chains"]))          # 连锁 ≥ base
	assert_float(float(ts["cooldown"])).is_less_equal(float(l3["cooldown"]))   # 不慢于 base
	assert_int(int(ts.get("sky_strikes", 0))).is_greater(0)                    # 天雷=质变身份(base 无)

# ── earthshatter ≥ maul L3(命中身份)+ 冲击波质变 ──
func test_earthshatter_shockwave_ge_base_l3() -> void:
	var es := _evo("earthshatter")
	var l3 := _l3("maul")
	assert_float(float(es["damage"])).is_greater_equal(float(l3["damage"]))      # 命中伤 ≥ base
	assert_float(float(es["radius"])).is_greater_equal(float(l3["radius"]))       # 命中半径 ≥ base
	assert_float(float(es.get("shockwave_radius", 0.0))).is_greater(0.0)          # 冲击波=质变身份(base 无)
	assert_float(float(es["shockwave_radius"])).is_greater(float(es["radius"]))   # 环带须超出命中半径才有意义

# ── thousand_edge ≥ knife L3(多发/穿透/射速/暴击轴,不锁单发 damage) ──
func test_thousand_edge_ceiling_ge_base_l3() -> void:
	var te := _evo("thousand_edge")
	var l3 := _l3("knife")
	assert_int(int(te.get("volley", 0))).is_greater_equal(2)                        # 多发身份(base knife 无 volley)
	assert_int(int(te["pierce"])).is_greater_equal(int(l3["pierce"]))               # 穿透 ≥ base
	assert_float(float(te["cooldown"])).is_less_equal(float(l3["cooldown"]))        # 不慢于 base
	assert_float(float(te["crit_bonus"])).is_greater_equal(float(l3["crit_bonus"])) # 暴击加成 ≥ base(防过砍暴击轴退化)
