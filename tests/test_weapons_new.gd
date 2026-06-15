# tests/test_weapons_new.gd
# 新武器的纯算法单测(闪电链选择 / 横扫鞭扇形命中) + 数据/注册集成验证。
# 用 preload 引用脚本(而非 class_name 全局标识)，避免依赖类缓存重建。
extends GdUnitTestSuite

const LightningScript := preload("res://scenes/weapons/lightning/lightning_weapon.gd")
const WhipScript := preload("res://scenes/weapons/whip/whip_weapon.gd")
const WeaponBaseScript := preload("res://scenes/weapons/weapon_base.gd")

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

# ── 闪电链：chain_targets 连锁选择(纯函数)─────────────────────────────────

func test_chain_targets_picks_nearest_then_chains_in_order() -> void:
	# origin(0,0)；沿 x 递增、相邻间距均 < link_range，最远那个超出最后一跳的范围
	var positions := [Vector2(10, 0), Vector2(60, 0), Vector2(120, 0), Vector2(900, 0)]
	var idx: Array = LightningScript.chain_targets(Vector2.ZERO, positions, 3, 80.0)
	assert_int(idx.size()).is_equal(3)
	assert_int(idx[0]).is_equal(0)   # 最近 origin
	assert_int(idx[1]).is_equal(1)   # 距 (10,0) 最近且在 80 内
	assert_int(idx[2]).is_equal(2)   # 距 (60,0) 最近且在 80 内

func test_chain_targets_stops_when_out_of_range() -> void:
	var positions := [Vector2(10, 0), Vector2(900, 0)]
	var idx: Array = LightningScript.chain_targets(Vector2.ZERO, positions, 5, 80.0)
	assert_int(idx.size()).is_equal(1)  # 第二个超距，链断

func test_chain_targets_no_duplicates() -> void:
	var positions := [Vector2(10, 0), Vector2(20, 0)]
	var idx: Array = LightningScript.chain_targets(Vector2.ZERO, positions, 5, 80.0)
	assert_int(idx.size()).is_equal(2)
	assert_bool(idx[0] != idx[1]).is_true()

func test_chain_targets_caps_at_max_links() -> void:
	var positions := [Vector2(10, 0), Vector2(20, 0), Vector2(30, 0), Vector2(40, 0)]
	var idx: Array = LightningScript.chain_targets(Vector2.ZERO, positions, 2, 80.0)
	assert_int(idx.size()).is_equal(2)

func test_chain_targets_empty_when_none() -> void:
	var idx: Array = LightningScript.chain_targets(Vector2.ZERO, [], 3, 80.0)
	assert_int(idx.size()).is_equal(0)

# ── 横扫鞭：in_cone 扇形命中(纯函数)────────────────────────────────────────

func test_in_cone_hits_enemy_in_front() -> void:
	assert_bool(WhipScript.in_cone(Vector2(50, 0), Vector2.ZERO, Vector2.RIGHT, 120.0, 130.0)).is_true()

func test_in_cone_misses_enemy_behind() -> void:
	assert_bool(WhipScript.in_cone(Vector2(-50, 0), Vector2.ZERO, Vector2.RIGHT, 120.0, 130.0)).is_false()

func test_in_cone_misses_out_of_range() -> void:
	assert_bool(WhipScript.in_cone(Vector2(200, 0), Vector2.ZERO, Vector2.RIGHT, 120.0, 130.0)).is_false()

func test_in_cone_within_arc_edge() -> void:
	# 120度扇形(半角60度)；偏离朝向 55 度仍命中
	var p := Vector2(cos(deg_to_rad(-55)), sin(deg_to_rad(-55))) * 50.0
	assert_bool(WhipScript.in_cone(p, Vector2.ZERO, Vector2.RIGHT, 120.0, 130.0)).is_true()

func test_in_cone_outside_arc() -> void:
	# 偏离朝向 80 度，超出半角 60 度 → 未命中
	var p := Vector2(cos(deg_to_rad(80)), sin(deg_to_rad(80))) * 50.0
	assert_bool(WhipScript.in_cone(p, Vector2.ZERO, Vector2.RIGHT, 120.0, 130.0)).is_false()

# ── 数据/注册集成验证 ─────────────────────────────────────────────────────

func test_weapondb_has_new_base_weapons() -> void:
	for id in ["lightning", "whip", "boomerang", "aura"]:
		assert_object(WeaponDB.get_data(id)).is_not_null()

func test_weapondb_has_new_evolved_weapons() -> void:
	for id in ["thunderstorm", "bloody_whip", "cyclone", "inferno_aura"]:
		assert_object(WeaponDB.get_data(id)).is_not_null()

func test_all_evolvable_count_is_seven() -> void:
	# 7 把可进化 base：knife/orb/explosion + lightning/whip/boomerang/aura
	assert_int(WeaponDB.all_evolvable().size()).is_equal(7)

func test_new_weapons_registered_in_effect_registry() -> void:
	for id in ["lightning", "whip", "boomerang", "aura"]:
		assert_bool(CardPool.effect_registry.has(id)).is_true()
		assert_bool(CardPool.effect_registry.has("evolve_%s" % id)).is_true()

func test_grant_lightning_reflects_level1_chains() -> void:
	CardPool.apply({"id": "lightning"}, _player)
	var node := _player.get_weapon_node("lightning")
	assert_object(node).is_not_null()
	assert_int(node.get("chains")).is_equal(3)

func test_grant_whip_reflects_level1_arc() -> void:
	CardPool.apply({"id": "whip"}, _player)
	var node := _player.get_weapon_node("whip")
	assert_float(node.get("arc_deg")).is_equal_approx(120.0, 0.001)

func test_grant_boomerang_reflects_level1_pierce() -> void:
	CardPool.apply({"id": "boomerang"}, _player)
	var node := _player.get_weapon_node("boomerang")
	assert_int(node.get("pierce")).is_equal(3)

func test_grant_aura_reflects_level1_radius() -> void:
	CardPool.apply({"id": "aura"}, _player)
	var node := _player.get_weapon_node("aura")
	assert_float(node.get("radius")).is_equal_approx(90.0, 0.001)

func test_evolve_lightning_grants_thunderstorm() -> void:
	CardPool.apply({"id": "lightning"}, _player)
	CardPool.apply({"id": "lightning_2"}, _player)
	CardPool.apply({"id": "lightning_3"}, _player)
	CardPool.apply({"id": "evolve_lightning", "type": "evolution"}, _player)
	assert_bool(_player.has_weapon("thunderstorm")).is_true()
	assert_bool(_player.has_weapon("lightning")).is_false()
	assert_int(_player.get_weapon_node("thunderstorm").get("chains")).is_equal(8)

func test_evolve_aura_grants_inferno() -> void:
	CardPool.apply({"id": "aura"}, _player)
	CardPool.apply({"id": "aura_2"}, _player)
	CardPool.apply({"id": "aura_3"}, _player)
	CardPool.apply({"id": "evolve_aura", "type": "evolution"}, _player)
	assert_bool(_player.has_weapon("inferno_aura")).is_true()
	assert_float(_player.get_weapon_node("inferno_aura").get("radius")).is_equal_approx(170.0, 0.001)

# ── 进化辨识度：4 把新进化武器有(各自不同的)图标，且 thunderstorm 在世特效染白紫 ──

func test_new_evolved_weapons_have_icons() -> void:
	for id in ["thunderstorm", "bloody_whip", "cyclone", "inferno_aura"]:
		var data := WeaponDB.get_data(id)
		assert_object(data).is_not_null()
		assert_object(data.icon).is_not_null()

func test_thunderstorm_bolt_tint_differs_from_base() -> void:
	CardPool.apply({"id": "lightning"}, _player)
	CardPool.apply({"id": "lightning_2"}, _player)
	CardPool.apply({"id": "lightning_3"}, _player)
	CardPool.apply({"id": "evolve_lightning", "type": "evolution"}, _player)
	var tint: Color = _player.get_weapon_node("thunderstorm").get("bolt_tint")
	# 进化雷暴注入白紫(R≈0.85)，明显区别于基础闪电的青(R≈0.62)
	assert_float(tint.r).is_equal_approx(0.85, 0.001)
	assert_float(tint.b).is_equal_approx(1.0, 0.001)

# ── WeaponBase：反射注入字段校验(纯函数，防 .tres 拼错键静默失效)──────────────

func test_filter_unknown_lists_keys_not_in_known() -> void:
	var unknown: Array = WeaponBaseScript.filter_unknown(["cooldown", "pierce"], {"cooldown": 1, "bogus": 2})
	assert_int(unknown.size()).is_equal(1)
	assert_bool(unknown.has("bogus")).is_true()

func test_filter_unknown_empty_when_all_known() -> void:
	var unknown: Array = WeaponBaseScript.filter_unknown(["cooldown", "pierce"], {"cooldown": 1, "pierce": 4})
	assert_int(unknown.size()).is_equal(0)

# ── WeaponBase：mod_int 统一全局 modifier 读取(取代 knife._mod_int / boomerang._global_pierce)──

func test_mod_int_reads_player_field() -> void:
	var w = auto_free(WeaponBaseScript.new())
	_player.add_child(w)
	await get_tree().process_frame
	_player.global_pierce = 3
	assert_int(w.mod_int("global_pierce")).is_equal(3)

func test_mod_int_zero_when_field_absent() -> void:
	var w = auto_free(WeaponBaseScript.new())
	_player.add_child(w)
	await get_tree().process_frame
	assert_int(w.mod_int("totally_not_a_field")).is_equal(0)
