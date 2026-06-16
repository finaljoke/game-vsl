# tests/test_run_harness.gd
extends GdUnitTestSuite

const Harness := preload("res://autoloads/run_harness.gd")

# ── kite 向量:远离敌群 + 避墙拉回中心 ─────────────────────────────────────
func test_kite_flees_single_enemy_on_left() -> void:
	# 玩家在中心,敌人在左侧 → 应朝右(正 x)逃
	var dir := Harness.compute_kite_dir(Vector2(640, 360), [Vector2(540, 360)], Vector2(640, 360), 220.0)
	assert_float(dir.x).is_greater(0.0)

func test_kite_flees_single_enemy_on_right() -> void:
	var dir := Harness.compute_kite_dir(Vector2(640, 360), [Vector2(740, 360)], Vector2(640, 360), 220.0)
	assert_float(dir.x).is_less(0.0)

func test_kite_ignores_enemy_beyond_perception() -> void:
	# 敌人在感知半径外 + 玩家在中心 → 无斥力,无偏心 → 零向量
	var dir := Harness.compute_kite_dir(Vector2(640, 360), [Vector2(640, 50)], Vector2(640, 360), 220.0)
	assert_vector(dir).is_equal(Vector2.ZERO)

func test_kite_pulls_back_to_center_near_wall() -> void:
	# 无敌人但玩家贴右墙 → 应朝左(负 x)被拉回中心
	var dir := Harness.compute_kite_dir(Vector2(1200, 360), [], Vector2(640, 360), 220.0)
	assert_float(dir.x).is_less(0.0)

func test_kite_returns_unit_vector_when_nonzero() -> void:
	var dir := Harness.compute_kite_dir(Vector2(640, 360), [Vector2(540, 360)], Vector2(640, 360), 220.0)
	assert_float(dir.length()).is_equal_approx(1.0, 0.001)

# ── 选卡优先级表 ─────────────────────────────────────────────────────────
func test_choose_card_prefers_exact_id_higher_in_profile() -> void:
	var offered := [
		{"id": "perk_speed", "type": "perk"},
		{"id": "perk_hp", "type": "perk"},
	]
	var profile := ["perk_hp", "type:perk"]
	var picked := Harness.choose_card(offered, profile)
	assert_str(picked["id"]).is_equal("perk_hp")

func test_choose_card_matches_by_type_when_no_exact_id() -> void:
	var offered := [
		{"id": "knife_2", "type": "upgrade"},
		{"id": "perk_speed", "type": "perk"},
	]
	var profile := ["perk_hp", "type:upgrade"]
	var picked := Harness.choose_card(offered, profile)
	assert_str(picked["id"]).is_equal("knife_2")

func test_choose_card_falls_back_to_first_when_no_match() -> void:
	var offered := [
		{"id": "perk_xp", "type": "perk"},
		{"id": "perk_damage", "type": "perk"},
	]
	var profile := ["type:evolution"]
	var picked := Harness.choose_card(offered, profile)
	assert_str(picked["id"]).is_equal("perk_xp")

func test_default_profile_is_nonempty() -> void:
	assert_int(Harness.DEFAULT_PROFILE.size()).is_greater(0)

# ── hitstop 在 bot 模式跳过(确定性) ───────────────────────────────────────
func test_hitstop_skipped_when_harness_active() -> void:
	var prev_active := RunHarness.active
	var prev_base_scale := RunHarness.base_time_scale
	var prev_scale := Engine.time_scale
	RunHarness.active = true
	RunHarness.base_time_scale = 3.0
	Engine.time_scale = 3.0
	GameFeel._trigger_hitstop(0.05)
	# bot 模式应直接跳过,不把 time_scale 砸到 0.05
	assert_float(Engine.time_scale).is_equal_approx(3.0, 0.001)
	# 还原,避免污染其他用例(对称保存/还原,不写死)
	RunHarness.active = prev_active
	RunHarness.base_time_scale = prev_base_scale
	Engine.time_scale = prev_scale
