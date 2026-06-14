extends GdUnitTestSuite

# 验证行为树工厂 EnemyBT.build 与远程风筝的纯函数 kite_move。
# 依赖 LimboAI GDExtension（BehaviorTree/BTAction）——headless 测试进程会加载。

const EnemyBT := preload("res://scenes/enemies/ai/enemy_bt.gd")
const RangedTask := preload("res://scenes/enemies/ai/bt_ranged_kite.gd")
const ProjectileScene := preload("res://scenes/enemies/enemy_projectile.tscn")

const CHASE_PATH := "res://scenes/enemies/ai/bt_chase.gd"
const RANGED_PATH := "res://scenes/enemies/ai/bt_ranged_kite.gd"
const BOMBER_PATH := "res://scenes/enemies/ai/bt_bomber.gd"

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

func test_build_unknown_falls_back_to_chase() -> void:
	var bt := EnemyBT.build("nonsense")
	assert_str(bt.root_task.get_script().resource_path).is_equal(CHASE_PATH)

# ── kite_move：三段距离决策（1=靠近 / 0=驻守开火 / -1=后退）─────────────────

func test_kite_move_approaches_when_too_far() -> void:
	# dist 350 > preferred 260 + band 40 = 300 → 靠近
	assert_int(RangedTask.kite_move(350.0, 260.0, 40.0)).is_equal(1)

func test_kite_move_holds_within_band() -> void:
	# dist 260 在 [220, 300] 区间内 → 驻守
	assert_int(RangedTask.kite_move(260.0, 260.0, 40.0)).is_equal(0)

func test_kite_move_retreats_when_too_close() -> void:
	# dist 150 < preferred 260 - band 40 = 220 → 后退
	assert_int(RangedTask.kite_move(150.0, 260.0, 40.0)).is_equal(-1)

func test_kite_move_band_edges_hold() -> void:
	# 恰在环带边界（含端点）应驻守，不抖动
	assert_int(RangedTask.kite_move(300.0, 260.0, 40.0)).is_equal(0)
	assert_int(RangedTask.kite_move(220.0, 260.0, 40.0)).is_equal(0)

# ── 子弹场景：根节点必须挂着脚本（防回归：曾漏 script= 导致发射时崩）────────────

func test_projectile_scene_has_script_attached() -> void:
	# 若 .tscn 忘了给根节点赋 script，instantiate 得到裸 Area2D，_shoot 注入 direction 会崩。
	var p = auto_free(ProjectileScene.instantiate())
	assert_object(p.get_script()).is_not_null()
	assert_bool("direction" in p).is_true()
	assert_bool("damage" in p).is_true()
