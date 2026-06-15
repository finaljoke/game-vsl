extends GdUnitTestSuite

# 验证行为树工厂 EnemyBT.build、远程风筝 kite_move 纯函数、Boss 阶段 selector。
# 依赖 LimboAI GDExtension（BehaviorTree/BTAction/BTSelector/BTSequence）——headless 测试进程会加载。

const EnemyBT := preload("res://scenes/enemies/ai/enemy_bt.gd")
const KiteTask := preload("res://scenes/enemies/ai/atoms/bt_kite_target.gd")
const HpBelow := preload("res://scenes/enemies/ai/atoms/bt_hp_below.gd")
const ProjectileScene := preload("res://scenes/enemies/enemy_projectile.tscn")

const CHASE_PATH    := "res://scenes/enemies/ai/atoms/bt_chase_target.gd"
const RANGED_PATH   := "res://scenes/enemies/ai/atoms/bt_kite_target.gd"
const BOMBER_PATH   := "res://scenes/enemies/ai/atoms/bt_bomber_attack.gd"
const CHARGER_PATH  := "res://scenes/enemies/ai/atoms/bt_charger.gd"
const MOVE_PATH     := "res://scenes/enemies/ai/atoms/bt_move_to_target.gd"
const SUMMON_PATH   := "res://scenes/enemies/ai/atoms/bt_spawn_minions.gd"
const FIRE_PATH     := "res://scenes/enemies/ai/atoms/bt_fire_projectile.gd"
const COOLDOWN_PATH := "res://scenes/enemies/ai/atoms/bt_cooldown_ready.gd"
const WAIT_PATH     := "res://scenes/enemies/ai/atoms/bt_wait.gd"

# ── EnemyBT.build：每种 behavior 返回非空树且 root_task 类型正确 ──────────────

func test_build_chase_returns_chase_root() -> void:
	var bt := EnemyBT.build("chase")
	assert_object(bt).is_not_null()
	assert_str(bt.root_task.get_script().resource_path).is_equal(CHASE_PATH)

func test_build_ranged_returns_ranged_root() -> void:
	var bt := EnemyBT.build("ranged")
	assert_str(bt.root_task.get_script().resource_path).is_equal(RANGED_PATH)

func test_build_bomber_returns_bomber_root() -> void:
	var bt := EnemyBT.build("bomber")
	assert_str(bt.root_task.get_script().resource_path).is_equal(BOMBER_PATH)

func test_build_charger_returns_charger_root() -> void:
	var bt := EnemyBT.build("charger")
	assert_str(bt.root_task.get_script().resource_path).is_equal(CHARGER_PATH)

func test_build_unknown_falls_back_to_chase() -> void:
	var bt := EnemyBT.build("nonsense")
	assert_str(bt.root_task.get_script().resource_path).is_equal(CHASE_PATH)

# ── Boss 阶段 selector：root 是 BTSelector，外层有 3 个分支 ─────────────────────

func test_build_boss_returns_selector_with_three_branches() -> void:
	var bt := EnemyBT.build("boss")
	assert_object(bt.root_task).is_instanceof(BTSelector)
	# Phase3 sequence + Phase2 sequence + Phase1 fallback = 3 个子任务
	assert_int(bt.root_task.get_child_count()).is_equal(3)
	# 前两个分支应是 BTSequence（带 HpBelow 守卫），第三个 fallback 是 BTAction
	assert_object(bt.root_task.get_child(0)).is_instanceof(BTSequence)
	assert_object(bt.root_task.get_child(1)).is_instanceof(BTSequence)

func test_boss_phase_guards_have_correct_thresholds() -> void:
	var bt := EnemyBT.build("boss")
	# 顺序：先 0.3，再 0.7（越严格的阈值越靠前）
	var phase3_guard := bt.root_task.get_child(0).get_child(0) as BTCondition
	var phase2_guard := bt.root_task.get_child(1).get_child(0) as BTCondition
	assert_float(phase3_guard.threshold).is_equal_approx(0.3, 0.001)
	assert_float(phase2_guard.threshold).is_equal_approx(0.7, 0.001)

func test_boss_phase1_fallback_is_move_to_target() -> void:
	# 第 3 个分支是 phase1 fallback：MoveToTarget(desired_dist=0)
	var bt := EnemyBT.build("boss")
	var phase1 := bt.root_task.get_child(2)
	assert_str(phase1.get_script().resource_path).is_equal(MOVE_PATH)
	assert_float(phase1.desired_dist).is_equal_approx(0.0, 0.001)

func test_boss_phase2_subtree_has_cooldown_then_summon() -> void:
	# phase2_tree = Selector[Sequence[CooldownReady, SpawnMinions], MoveToTarget]
	var bt := EnemyBT.build("boss")
	var phase2 := bt.root_task.get_child(1).get_child(1)
	assert_object(phase2).is_instanceof(BTSelector)
	var summon_seq := phase2.get_child(0)
	assert_object(summon_seq).is_instanceof(BTSequence)
	assert_str(summon_seq.get_child(0).get_script().resource_path).is_equal(COOLDOWN_PATH)
	assert_str(summon_seq.get_child(1).get_script().resource_path).is_equal(SUMMON_PATH)
	assert_int(summon_seq.get_child(1).count).is_equal(3)
	# fallback 应是 MoveToTarget
	assert_str(phase2.get_child(1).get_script().resource_path).is_equal(MOVE_PATH)

func test_boss_phase3_subtree_has_cooldown_fire_wait() -> void:
	# phase3_tree = Selector[Sequence[CooldownReady, FireProjectile, Wait], MoveToTarget]
	var bt := EnemyBT.build("boss")
	var phase3 := bt.root_task.get_child(0).get_child(1)
	assert_object(phase3).is_instanceof(BTSelector)
	var fire_seq := phase3.get_child(0)
	assert_object(fire_seq).is_instanceof(BTSequence)
	assert_str(fire_seq.get_child(0).get_script().resource_path).is_equal(COOLDOWN_PATH)
	assert_str(fire_seq.get_child(1).get_script().resource_path).is_equal(FIRE_PATH)
	assert_str(fire_seq.get_child(2).get_script().resource_path).is_equal(WAIT_PATH)
	# 5 连发扇形
	assert_int(fire_seq.get_child(1).count).is_equal(5)
	assert_str(phase3.get_child(1).get_script().resource_path).is_equal(MOVE_PATH)

# ── kite_move：三段距离决策（1=靠近 / 0=驻守开火 / -1=后退）─────────────────

func test_kite_move_approaches_when_too_far() -> void:
	# dist 350 > preferred 260 + band 40 = 300 → 靠近
	assert_int(KiteTask.kite_move(350.0, 260.0, 40.0)).is_equal(1)

func test_kite_move_holds_within_band() -> void:
	# dist 260 在 [220, 300] 区间内 → 驻守
	assert_int(KiteTask.kite_move(260.0, 260.0, 40.0)).is_equal(0)

func test_kite_move_retreats_when_too_close() -> void:
	# dist 150 < preferred 260 - band 40 = 220 → 后退
	assert_int(KiteTask.kite_move(150.0, 260.0, 40.0)).is_equal(-1)

func test_kite_move_band_edges_hold() -> void:
	# 恰在环带边界（含端点）应驻守，不抖动
	assert_int(KiteTask.kite_move(300.0, 260.0, 40.0)).is_equal(0)
	assert_int(KiteTask.kite_move(220.0, 260.0, 40.0)).is_equal(0)

# ── 子弹场景：根节点必须挂着脚本（防回归：曾漏 script= 导致发射时崩）────────────

func test_projectile_scene_has_script_attached() -> void:
	# 若 .tscn 忘了给根节点赋 script，instantiate 得到裸 Area2D，_shoot 注入 direction 会崩。
	var p = auto_free(ProjectileScene.instantiate())
	assert_object(p.get_script()).is_not_null()
	assert_bool("direction" in p).is_true()
	assert_bool("damage" in p).is_true()
