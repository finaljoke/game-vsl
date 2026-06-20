# tests/test_run_harness.gd
extends GdUnitTestSuite

const Harness := preload("res://autoloads/run_harness.gd")
const LevelUpUI := preload("res://scenes/ui/level_up_ui.gd")

# 全局状态安全网:任一用例若在 inline 还原前断言失败,这里兜底复位,避免泄漏到后续用例。
func after_each() -> void:
	RunHarness.active = false
	RunHarness.base_time_scale = 1.0
	Engine.time_scale = 1.0

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
	GameFeel.hitstop(0.05)
	# bot 模式应直接跳过,不把 time_scale 砸到 0.05
	assert_float(Engine.time_scale).is_equal_approx(3.0, 0.001)
	# 还原,避免污染其他用例(对称保存/还原,不写死)
	RunHarness.active = prev_active
	RunHarness.base_time_scale = prev_base_scale
	Engine.time_scale = prev_scale

# ── level_up_ui 在 bot 模式早退(不二次 pick) ───────────────────────────────────
func test_level_up_ui_early_returns_when_harness_active() -> void:
	var prev_active := RunHarness.active
	RunHarness.active = true
	var scene := load("res://scenes/ui/level_up_ui.tscn") as PackedScene
	var ui: LevelUpUI = auto_free(scene.instantiate())
	add_child(ui)
	await get_tree().process_frame
	assert_bool(ui.visible).is_false()  # 前置:_ready() 已把它设为 false
	ui._on_level_up()
	# 早退:不显示、不出卡
	assert_bool(ui.visible).is_false()
	assert_int(ui._current_cards.size()).is_equal(0)
	RunHarness.active = prev_active

# ── 命令行解析 ───────────────────────────────────────────────────────────────
func test_parse_args_defaults_when_no_bot() -> void:
	var cfg: Dictionary = RunHarness.parse_args([])
	assert_bool(cfg["active"]).is_false()

func test_parse_args_reads_bot_and_seed() -> void:
	var cfg: Dictionary = RunHarness.parse_args(["--bot=kite", "--seed=42"])
	assert_bool(cfg["active"]).is_true()
	assert_str(cfg["bot"]).is_equal("kite")
	assert_int(cfg["seed"]).is_equal(42)

func test_parse_args_defaults_fast_and_cards() -> void:
	var cfg: Dictionary = RunHarness.parse_args(["--bot=still"])
	assert_float(cfg["fast"]).is_equal_approx(3.0, 0.001)
	assert_str(cfg["cards"]).is_equal("default")

func test_parse_args_reads_fast_out_maxtime() -> void:
	var cfg: Dictionary = RunHarness.parse_args(["--bot=kite", "--fast=5", "--out=telemetry/run_x", "--maxtime=30"])
	assert_float(cfg["fast"]).is_equal_approx(5.0, 0.001)
	assert_str(cfg["out"]).is_equal("telemetry/run_x")
	assert_float(cfg["maxtime"]).is_equal_approx(30.0, 0.001)

# ── 躲弹方向(compute_dodge_dir) ──────────────────────────────────────────
func test_dodge_no_projectiles_is_zero() -> void:
	assert_vector(Harness.compute_dodge_dir(Vector2(640, 360), [], 200.0)).is_equal(Vector2.ZERO)

func test_dodge_sidesteps_perpendicular_to_incoming() -> void:
	# 弹在玩家左下、向右飞,玩家在弹道线上方 → 垂直侧移(向上=负 y),且垂直于弹速
	var dir := Harness.compute_dodge_dir(Vector2(640, 360), [{"pos": Vector2(540, 380), "vel": Vector2(220, 0)}], 200.0)
	assert_float(dir.y).is_less(0.0)
	assert_float(dir.dot(Vector2(1, 0))).is_equal_approx(0.0, 0.001)
	assert_float(dir.length()).is_equal_approx(1.0, 0.001)

func test_dodge_ignores_receding_projectile() -> void:
	# 弹向左飞(远离右侧玩家)→ vel·to_player<0 → 不躲
	var dir := Harness.compute_dodge_dir(Vector2(640, 360), [{"pos": Vector2(540, 360), "vel": Vector2(-220, 0)}], 200.0)
	assert_vector(dir).is_equal(Vector2.ZERO)

func test_dodge_ignores_projectile_beyond_radius() -> void:
	# 弹距离 340 > 半径 200 → 忽略
	var dir := Harness.compute_dodge_dir(Vector2(640, 360), [{"pos": Vector2(300, 360), "vel": Vector2(220, 0)}], 200.0)
	assert_vector(dir).is_equal(Vector2.ZERO)

func test_dodge_head_on_uses_deterministic_perpendicular() -> void:
	# 玩家恰在弹道延长线上 → lateral≈0 → 兜底 (-vdir.y, vdir.x) = (0,1)
	var dir := Harness.compute_dodge_dir(Vector2(640, 360), [{"pos": Vector2(540, 360), "vel": Vector2(220, 0)}], 200.0)
	assert_vector(dir).is_equal(Vector2(0, 1))

func test_dodge_order_independent() -> void:
	# 内部排序 → 同一组弹乱序输入两次结果逐位一致(C5 单元锁)
	var p := Vector2(640, 360)
	var a := {"pos": Vector2(540, 340), "vel": Vector2(220, 0)}
	var b := {"pos": Vector2(560, 380), "vel": Vector2(0, -220)}
	var r1 := Harness.compute_dodge_dir(p, [a, b], 200.0)
	var r2 := Harness.compute_dodge_dir(p, [b, a], 200.0)
	assert_vector(r1).is_equal(r2)

func test_kite_order_independent() -> void:
	# 排序后:同一组敌人乱序输入两次结果逐位一致(C5 单元锁;后期大输入下顺序真会变)
	var p := Vector2(640, 360)
	var e1 := Vector2(600, 340)
	var e2 := Vector2(680, 380)
	var e3 := Vector2(620, 400)
	var r1 := Harness.compute_kite_dir(p, [e1, e2, e3], Vector2(640, 360), 220.0)
	var r2 := Harness.compute_kite_dir(p, [e3, e1, e2], Vector2(640, 360), 220.0)
	assert_vector(r1).is_equal(r2)
