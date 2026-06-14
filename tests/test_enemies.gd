extends GdUnitTestSuite

# 验证 enemy_spawner.gd 的敌人原型选型与三围倍率
# _eligible_archetypes 是纯函数，可在脱离场景树的脚本实例上直接调用

const SpawnerScript := preload("res://scenes/enemies/enemy_spawner.gd")

var _spawner

func before_test() -> void:
	_spawner = auto_free(SpawnerScript.new())

# ── 解锁门槛：after <= elapsed ────────────────────────────────────────────

func test_normal_and_swarm_available_from_start() -> void:
	var ids := _ids(_spawner._eligible_archetypes(0.0))
	assert_bool(ids.has("normal")).is_true()
	assert_bool(ids.has("swarm")).is_true()

func test_ranged_locked_before_60s() -> void:
	assert_bool(_ids(_spawner._eligible_archetypes(59.0)).has("ranged")).is_false()

func test_ranged_unlocks_at_60s() -> void:
	assert_bool(_ids(_spawner._eligible_archetypes(60.0)).has("ranged")).is_true()

func test_bomber_locked_before_90s() -> void:
	assert_bool(_ids(_spawner._eligible_archetypes(89.0)).has("bomber")).is_false()

func test_bomber_unlocks_at_90s() -> void:
	assert_bool(_ids(_spawner._eligible_archetypes(90.0)).has("bomber")).is_true()

func test_brute_locked_before_120s() -> void:
	var ids := _ids(_spawner._eligible_archetypes(119.0))
	assert_bool(ids.has("brute")).is_false()

func test_brute_unlocks_at_120s() -> void:
	var ids := _ids(_spawner._eligible_archetypes(120.0))
	assert_bool(ids.has("brute")).is_true()

func test_eligible_count_grows_by_threshold() -> void:
	# 0s=2(normal,swarm)、60s=3(+ranged)、90s=4(+bomber)、120s=5(+brute)
	assert_int(_spawner._eligible_archetypes(0.0).size()).is_equal(2)
	assert_int(_spawner._eligible_archetypes(60.0).size()).is_equal(3)
	assert_int(_spawner._eligible_archetypes(90.0).size()).is_equal(4)
	assert_int(_spawner._eligible_archetypes(120.0).size()).is_equal(5)

# ── 原型三围倍率数学 ──────────────────────────────────────────────────────

func test_swarm_is_faster_and_frailer_than_normal() -> void:
	var normal := _by_id("normal")
	var swarm := _by_id("swarm")
	assert_float(swarm["spd"]).is_greater(normal["spd"])
	assert_float(swarm["hp"]).is_less(normal["hp"])

func test_brute_is_tanky_and_slow() -> void:
	var brute := _by_id("brute")
	assert_float(brute["hp"]).is_greater(1.0)
	assert_float(brute["spd"]).is_less(1.0)
	assert_float(brute["con"]).is_greater(1.0)

func test_swarm_hp_at_4min() -> void:
	# base_hp = 20 * (1 + 4 * 0.25) = 40；swarm ×0.45 = 18
	var base_hp := 20.0 * (1.0 + 4.0 * 0.25)
	var swarm := _by_id("swarm")
	assert_float(base_hp * swarm["hp"]).is_equal_approx(18.0, 0.001)

func test_bomber_has_no_contact_damage() -> void:
	# 自爆敌人伤害来自爆炸而非接触，con 必须为 0
	assert_float(_by_id("bomber")["con"]).is_equal(0.0)

func test_ranged_is_slower_and_frailer_than_normal() -> void:
	var ranged := _by_id("ranged")
	assert_float(ranged["spd"]).is_less(1.0)
	assert_float(ranged["hp"]).is_less(1.0)

# ── 行为字段：原型与行为树类型一一对应 ────────────────────────────────────

func test_archetype_behaviors_are_correct() -> void:
	assert_str(_by_id("normal")["behavior"]).is_equal("chase")
	assert_str(_by_id("swarm")["behavior"]).is_equal("chase")
	assert_str(_by_id("brute")["behavior"]).is_equal("chase")
	assert_str(_by_id("ranged")["behavior"]).is_equal("ranged")
	assert_str(_by_id("bomber")["behavior"]).is_equal("bomber")

# ── helpers ───────────────────────────────────────────────────────────────

func _ids(arr: Array) -> Array:
	var out: Array = []
	for a in arr:
		out.append(a["id"])
	return out

func _by_id(id: String) -> Dictionary:
	for a in _spawner.ARCHETYPES:
		if a["id"] == id:
			return a
	return {}
