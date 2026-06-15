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

func test_bomber_locked_before_120s() -> void:
	assert_bool(_ids(_spawner._eligible_archetypes(119.0)).has("bomber")).is_false()

func test_bomber_unlocks_at_120s() -> void:
	assert_bool(_ids(_spawner._eligible_archetypes(120.0)).has("bomber")).is_true()

func test_charger_locked_before_180s() -> void:
	assert_bool(_ids(_spawner._eligible_archetypes(179.0)).has("charger")).is_false()

func test_charger_unlocks_at_180s() -> void:
	assert_bool(_ids(_spawner._eligible_archetypes(180.0)).has("charger")).is_true()

func test_brute_locked_before_240s() -> void:
	var ids := _ids(_spawner._eligible_archetypes(239.0))
	assert_bool(ids.has("brute")).is_false()

func test_brute_unlocks_at_240s() -> void:
	var ids := _ids(_spawner._eligible_archetypes(240.0))
	assert_bool(ids.has("brute")).is_true()

func test_splitter_locked_before_330s() -> void:
	assert_bool(_ids(_spawner._eligible_archetypes(329.0)).has("splitter")).is_false()

func test_splitter_unlocks_at_330s() -> void:
	assert_bool(_ids(_spawner._eligible_archetypes(330.0)).has("splitter")).is_true()

func test_boss_never_in_trickle_eligibility() -> void:
	# Boss 改为脚本化登场(BOSS_EVENTS)，after 设哨兵值 → 永不进随机出怪池
	assert_bool(_ids(_spawner._eligible_archetypes(600.0)).has("boss")).is_false()

func test_boss_events_schedule_times_and_kinds() -> void:
	# 脚本化 Boss：3:00/6:30 幕间小 Boss，9:00 终局 Boss
	var ev = _spawner.BOSS_EVENTS
	assert_int(ev.size()).is_equal(3)
	assert_float(ev[0]["time"]).is_equal(180.0)
	assert_str(ev[0]["kind"]).is_equal("mini")
	assert_float(ev[1]["time"]).is_equal(390.0)
	assert_str(ev[1]["kind"]).is_equal("mini")
	assert_float(ev[2]["time"]).is_equal(540.0)
	assert_str(ev[2]["kind"]).is_equal("final")

func test_final_boss_is_last_and_before_win_time() -> void:
	var ev = _spawner.BOSS_EVENTS
	var last: Dictionary = ev[ev.size() - 1]
	assert_str(last["kind"]).is_equal("final")
	assert_float(last["time"]).is_less(600.0)  # 终局 Boss 在胜利时间前登场，留出决战窗口

func test_eligible_count_grows_by_threshold() -> void:
	# 解锁铺满全程：每 60~90s 进一个新类型，让"新东西"贯穿整局而非前 2 分钟塞满。
	# Boss 不在随机池(脚本化)，所以最多 7 种：
	# 0s=2(normal,swarm)、60s=3(+ranged)、120s=4(+bomber)、180s=5(+charger)、
	# 240s=6(+brute)、330s=7(+splitter)
	assert_int(_spawner._eligible_archetypes(0.0).size()).is_equal(2)
	assert_int(_spawner._eligible_archetypes(60.0).size()).is_equal(3)
	assert_int(_spawner._eligible_archetypes(120.0).size()).is_equal(4)
	assert_int(_spawner._eligible_archetypes(180.0).size()).is_equal(5)
	assert_int(_spawner._eligible_archetypes(240.0).size()).is_equal(6)
	assert_int(_spawner._eligible_archetypes(330.0).size()).is_equal(7)
	assert_int(_spawner._eligible_archetypes(420.0).size()).is_equal(7)
	assert_int(_spawner._eligible_archetypes(600.0).size()).is_equal(7)

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
	# 4min=240s 属 Act2(×1.4)：scaled_base_hp = 20*(1+4*0.25)*1.4 = 40*1.4 = 56；swarm ×0.45 ≈ 25.2
	var base_hp: float = _spawner._scaled_base_hp(240.0)
	var swarm := _by_id("swarm")
	assert_float(base_hp * swarm["hp"]).is_equal_approx(25.2, 0.001)

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
	assert_str(_by_id("boss")["behavior"]).is_equal("boss")
	# 冲锋者走专属 charger 行为树；分裂者移动同 chase，分裂靠死亡钩子
	assert_str(_by_id("charger")["behavior"]).is_equal("charger")
	assert_str(_by_id("splitter")["behavior"]).is_equal("chase")

func test_charger_hits_harder_on_contact() -> void:
	# 冲锋撞击应比普通怪更疼，制造"被它顶到很亏"的爆发威胁
	assert_float(_by_id("charger")["con"]).is_greater(_by_id("normal")["con"])

func test_splitter_spawns_offspring_on_death() -> void:
	# split 字段 > 0 表示死亡时分裂出的小怪数量
	assert_int(int(_by_id("splitter").get("split", 0))).is_greater(0)

func test_boss_is_tankier_and_larger_than_brute() -> void:
	# Boss 是稀有大体型阶段杀手：HP/体型显著高于 brute
	var brute := _by_id("brute")
	var boss := _by_id("boss")
	assert_float(boss["hp"]).is_greater(brute["hp"])
	assert_float(boss["scale"]).is_greater(brute["scale"])

# ── 幕结构与难度乘区 ──────────────────────────────────────────────────────
# 三幕：Act1 [0,180) ×1.0、Act2 [180,390) ×1.4、Act3 [390,∞) ×2.0
# 切换点对齐幕间小 Boss(3:00 / 6:30)，让后半程难度真正递增而非纯线性拉长。
# 乘区只作用于 HP 与 XP 掉落（与 HP 同步防升级断档），不动速度。

func test_act_is_1_at_start() -> void:
	assert_int(_spawner._current_act(0.0)).is_equal(1)

func test_act_is_1_just_before_180s() -> void:
	assert_int(_spawner._current_act(179.0)).is_equal(1)

func test_act_is_2_at_180s() -> void:
	assert_int(_spawner._current_act(180.0)).is_equal(2)

func test_act_is_2_just_before_390s() -> void:
	assert_int(_spawner._current_act(389.0)).is_equal(2)

func test_act_is_3_at_390s() -> void:
	assert_int(_spawner._current_act(390.0)).is_equal(3)

func test_difficulty_mult_per_act() -> void:
	assert_float(_spawner._difficulty_mult(0.0)).is_equal(1.0)
	assert_float(_spawner._difficulty_mult(180.0)).is_equal(1.4)
	assert_float(_spawner._difficulty_mult(390.0)).is_equal(2.0)

func test_difficulty_mult_is_nondecreasing() -> void:
	var prev := 0.0
	for t in [0.0, 100.0, 180.0, 300.0, 390.0, 500.0, 600.0]:
		var m: float = _spawner._difficulty_mult(t)
		assert_float(m).is_greater_equal(prev)
		prev = m

func test_scaled_base_hp_at_start_is_unmultiplied() -> void:
	# 0s Act1(×1.0)：20*(1+0)*1.0 = 20
	assert_float(_spawner._scaled_base_hp(0.0)).is_equal(20.0)

func test_scaled_base_hp_includes_act_mult() -> void:
	# 240s Act2(×1.4)：20*(1+4*0.25)*1.4 = 40*1.4 = 56
	assert_float(_spawner._scaled_base_hp(240.0)).is_equal_approx(56.0, 0.001)

func test_scaled_base_hp_late_game_escalates() -> void:
	# 480s Act3(×2.0)：20*(1+8*0.25)*2.0 = 60*2 = 120，远高于旧线性的 60
	assert_float(_spawner._scaled_base_hp(480.0)).is_equal_approx(120.0, 0.001)

func test_scaled_xp_value_tracks_difficulty() -> void:
	# XP 掉落与 HP 同步乘区：240s Act2 → 10*(1+1)*1.4 = 28
	assert_float(_spawner._scaled_xp_value(240.0)).is_equal_approx(28.0, 0.001)

func test_scaled_xp_value_at_start() -> void:
	assert_float(_spawner._scaled_xp_value(0.0)).is_equal(10.0)

# 同屏敌人上限按幕递增：后期真的更密，而非在 ~3:20 封顶后一直"一样多"。
func test_max_enemies_scales_per_act() -> void:
	assert_int(_spawner._max_enemies(0.0)).is_equal(120)
	assert_int(_spawner._max_enemies(180.0)).is_equal(200)
	assert_int(_spawner._max_enemies(390.0)).is_equal(300)

func test_max_enemies_nondecreasing() -> void:
	assert_int(_spawner._max_enemies(179.0)).is_less_equal(_spawner._max_enemies(180.0))
	assert_int(_spawner._max_enemies(389.0)).is_less_equal(_spawner._max_enemies(390.0))

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
