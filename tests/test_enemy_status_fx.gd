extends GdUnitTestSuite

const EnemyScript := preload("res://scenes/enemies/enemy.gd")

# ── 纯差分(无场景) ──────────────────────────────────────────────
func test_diff_adds_new_statuses() -> void:
	var d: Dictionary = EnemyScript.diff_status_fx([&"burn", &"slow"], [])
	assert_array(d["add"]).contains([&"burn", &"slow"])
	assert_array(d["remove"]).is_empty()

func test_diff_removes_gone_statuses() -> void:
	var d: Dictionary = EnemyScript.diff_status_fx([], [&"burn"])
	assert_array(d["remove"]).contains([&"burn"])
	assert_array(d["add"]).is_empty()

func test_diff_stable_when_unchanged() -> void:
	var d: Dictionary = EnemyScript.diff_status_fx([&"burn"], [&"burn"])
	assert_array(d["add"]).is_empty()
	assert_array(d["remove"]).is_empty()

# ── 场景集成(实例化 enemy.tscn,依赖 W0 状态系统) ─────────────────
func test_burn_status_spawns_indicator_child() -> void:
	var e: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child(e)
	await get_tree().process_frame
	e.apply_status(&"burn", 5.0, 2.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(e._status_fx.has(&"burn")).is_true()
	assert_object(e._status_fx[&"burn"]).is_not_null()
	assert_object(e._status_fx[&"burn"].get_parent()).is_same(e)
	e.queue_free()
