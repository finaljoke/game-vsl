extends GdUnitTestSuite

# SpawnDirector：节拍调度策略(纯逻辑，无场景依赖)。决定"何时、哪种节拍事件"，
# 由 enemy_spawner 执行实际刷怪。把平直 trickle 改成锯齿强度曲线(铺垫→爆发→喘息)。

const DirectorScript := preload("res://scenes/enemies/spawn_director.gd")

var _d

func before_test() -> void:
	_d = auto_free(DirectorScript.new())

# ── 节拍时机：首拍 45s，之后每 50s 一拍 ──────────────────────────────────────

func test_first_event_time() -> void:
	assert_float(_d.next_event_time()).is_equal(45.0)

func test_not_due_before_first_event() -> void:
	assert_bool(_d.is_due(44.0)).is_false()

func test_due_at_first_event() -> void:
	assert_bool(_d.is_due(45.0)).is_true()

func test_advance_increments_and_pushes_next_time() -> void:
	_d.advance(45.0)
	assert_int(_d.events_fired).is_equal(1)
	assert_float(_d.next_event_time()).is_equal(95.0)

func test_not_due_again_immediately_after_advance() -> void:
	_d.advance(45.0)
	assert_bool(_d.is_due(50.0)).is_false()
	assert_bool(_d.is_due(95.0)).is_true()

# ── 事件类型按固定序列循环，含周期性 breather(张弛) ──────────────────────────

func test_event_sequence_cycles() -> void:
	assert_str(_d.event_type_at(0)).is_equal("swarm_rush")
	assert_str(_d.event_type_at(1)).is_equal("pincer")
	assert_str(_d.event_type_at(2)).is_equal("breather")
	assert_str(_d.event_type_at(3)).is_equal("elite_pack")
	assert_str(_d.event_type_at(4)).is_equal("swarm_rush")  # 循环回头

func test_breather_appears_every_fourth() -> void:
	assert_str(_d.event_type_at(2)).is_equal("breather")
	assert_str(_d.event_type_at(6)).is_equal("breather")
	assert_str(_d.event_type_at(10)).is_equal("breather")

func test_advance_returns_typed_event() -> void:
	var ev: Dictionary = _d.advance(45.0)
	assert_str(ev["type"]).is_equal("swarm_rush")
	var ev2: Dictionary = _d.advance(95.0)
	assert_str(ev2["type"]).is_equal("pincer")

# ── 一局 600s 内应有足够多的节拍，保证全程"总有下一拍" ─────────────────────

func test_roughly_ten_plus_beats_over_run() -> void:
	var count := 0
	var t := 0.0
	while t <= 600.0:
		if _d.is_due(t):
			_d.advance(t)
			count += 1
		t += 1.0
	assert_int(count).is_greater_equal(10)
