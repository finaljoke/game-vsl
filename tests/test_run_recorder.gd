# tests/test_run_recorder.gd
extends GdUnitTestSuite

const Recorder := preload("res://autoloads/run_recorder.gd")

# ── CSV 表头/行:字段顺序与数量一致 ─────────────────────────────────────────
func test_tick_header_field_count() -> void:
	var fields := Recorder.tick_header().split(",")
	assert_int(fields.size()).is_equal(13)

func test_tick_header_order() -> void:
	var expected := "t,level,kills_total,kills_ps,dmg_dealt_ps,dmg_taken_ps,hp,hp_pct,danger_ps,enemies_alive,enemies_near,healed_ps,time_scale"
	assert_str(Recorder.tick_header()).is_equal(expected)

func test_format_row_joins_values_in_order() -> void:
	var row := Recorder.format_row([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])
	assert_str(row).is_equal("1,2,3,4,5,6,7,8,9,10,11,12,13")

func test_format_row_field_count_matches_header() -> void:
	var row := Recorder.format_row([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
	assert_int(row.split(",").size()).is_equal(Recorder.tick_header().split(",").size())

# ── 输出路径解析:相对名补 res:// 前缀,已带前缀的保持 ─────────────────────────
func test_resolve_path_adds_res_prefix() -> void:
	assert_str(Recorder.resolve_base_path("telemetry/run_42")).is_equal("res://telemetry/run_42")

func test_resolve_path_keeps_existing_res_prefix() -> void:
	assert_str(Recorder.resolve_base_path("res://telemetry/run_42")).is_equal("res://telemetry/run_42")

func test_resolve_path_keeps_user_prefix() -> void:
	assert_str(Recorder.resolve_base_path("user://run_42")).is_equal("user://run_42")
