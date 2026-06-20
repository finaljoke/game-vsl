extends GdUnitTestSuite

const RA := preload("res://tools/run_analysis.gd")

func test_median_odd() -> void:
	assert_float(RA.median([3, 1, 2])).is_equal(2.0)

func test_median_even() -> void:
	assert_float(RA.median([1, 2, 3, 4])).is_equal(2.5)

func test_kills_per_min() -> void:
	assert_float(RA.kills_per_min({"kills": 120, "survived_s": 120.0})).is_equal(60.0)

func test_summarize_profile() -> void:
	var s: Dictionary = RA.summarize_profile([
		{"kills": 60, "survived_s": 60.0, "hp_pct_min": 0.4, "danger_total_s": 5.0},
		{"kills": 120, "survived_s": 60.0, "hp_pct_min": 0.2, "danger_total_s": 15.0},
	])
	assert_int(s["n"]).is_equal(2)
	assert_float(s["kills_per_min_med"]).is_equal(90.0)  # median(60,120)

func test_flag_off_band_detects_op_and_weak() -> void:
	var by := {
		"a": {"kills_per_min_med": 10.0},
		"b": {"kills_per_min_med": 10.0},
		"c": {"kills_per_min_med": 30.0},
		"d": {"kills_per_min_med": 3.0},
	}
	var f: Dictionary = RA.flag_off_band(by, 0.35)
	assert_str(String(f["c"]["verdict"])).is_equal("OP")
	assert_str(String(f["d"]["verdict"])).is_equal("weak")
	assert_str(String(f["a"]["verdict"])).is_equal("ok")

# ── P2a 单元:tick/events 解析 ──────────────────────────────────────────────
func test_tick_rows_from_csv_parses_header_and_rows() -> void:
	var csv := "t,level,kills_total,hp_pct,danger_ps\n10.0,5,100,0.8,2.0\n11.0,5,110,0.7,1.0"
	var rows := RA.tick_rows_from_csv(csv)
	assert_int(rows.size()).is_equal(2)
	assert_str(String(rows[0]["t"])).is_equal("10.0")
	assert_str(String(rows[1]["kills_total"])).is_equal("110")

func test_events_from_jsonl_parses_lines() -> void:
	var jsonl := '{"type":"level_up","picked":"evolve_orb","t":120.0}\n{"type":"death","t":200.0}'
	var events := RA.events_from_jsonl(jsonl)
	assert_int(events.size()).is_equal(2)
	assert_str(String(events[0]["picked"])).is_equal("evolve_orb")

# ── P2a 单元:进化解锁时刻 + 窗口切分 ──────────────────────────────────────
func test_evolution_unlock_time_found() -> void:
	var events := [
		{"type": "level_up", "picked": "explosion_2", "t": 50.0},
		{"type": "level_up", "picked": "evolve_explosion", "t": 191.9},
	]
	assert_float(RA.evolution_unlock_time(events, "explosion")).is_equal_approx(191.9, 0.01)

func test_evolution_unlock_time_absent_returns_negative() -> void:
	var events := [{"type": "level_up", "picked": "perk_xp", "t": 30.0}]
	assert_float(RA.evolution_unlock_time(events, "explosion")).is_equal(-1.0)

func test_window_rows_slices_at_t_evo() -> void:
	var rows := [
		{"t": "100.0", "kills_total": "50"},
		{"t": "191.9", "kills_total": "120"},
		{"t": "300.0", "kills_total": "400"},
	]
	assert_int(RA.window_rows(rows, 191.9).size()).is_equal(2)

func test_window_rows_empty_when_no_evolution() -> void:
	assert_int(RA.window_rows([{"t": "10.0"}], -1.0).size()).is_equal(0)

# ── P2a 单元:后期窗口三轴度量 ────────────────────────────────────────────
func test_window_metrics_computes_kpm_and_hpmin() -> void:
	# t_evo=200, t_end=260 → win_dur=60; kills 100→280=180 → kpm=180; danger (0+2)/2=1.0
	var win := [
		{"t": "200.0", "kills_total": "100", "hp_pct": "0.9", "danger_ps": "0.0"},
		{"t": "260.0", "kills_total": "280", "hp_pct": "0.7", "danger_ps": "2.0"},
	]
	var m := RA.window_metrics(win, 200.0, 260.0, "death")
	assert_bool(m["reached_evolution"]).is_true()
	assert_float(m["kpm_post"]).is_equal_approx(180.0, 0.1)
	assert_float(m["hp_min_post"]).is_equal_approx(0.7, 0.001)
	assert_float(m["danger_mean_post"]).is_equal_approx(1.0, 0.001)
	assert_float(m["survived_post"]).is_equal_approx(60.0, 0.001)

func test_window_metrics_empty_marks_unreached() -> void:
	var m := RA.window_metrics([], -1.0, 100.0, "death")
	assert_bool(m["reached_evolution"]).is_false()

# ── P2a 单元:跨种子聚合 + 多轴判据 ──────────────────────────────────────
func test_summarize_evolution_aggregates_medians_and_ratios() -> void:
	var ms := [
		{"reached_evolution": true, "kpm_post": 100.0, "hp_min_post": 0.9, "survived_post": 300.0, "outcome": "victory"},
		{"reached_evolution": true, "kpm_post": 140.0, "hp_min_post": 0.8, "survived_post": 360.0, "outcome": "victory"},
		{"reached_evolution": false, "kpm_post": 0.0, "hp_min_post": 0.0, "survived_post": 0.0, "outcome": "death"},
	]
	var s := RA.summarize_evolution(ms)
	assert_int(s["n"]).is_equal(3)
	assert_float(s["reached_ratio"]).is_equal_approx(0.6667, 0.001)
	assert_float(s["kpm_post_med"]).is_equal_approx(120.0, 0.1)  # median(100,140)

func test_flag_multi_axis_detects_op_and_weak() -> void:
	var by := {
		"evolve_a":    {"kpm_post_med": 100.0, "survived_post_med": 300.0, "hp_min_post_med": 0.8,  "reached_ratio": 1.0, "death_ratio": 0.2},
		"evolve_b":    {"kpm_post_med": 100.0, "survived_post_med": 300.0, "hp_min_post_med": 0.8,  "reached_ratio": 1.0, "death_ratio": 0.2},
		"evolve_op":   {"kpm_post_med": 200.0, "survived_post_med": 360.0, "hp_min_post_med": 0.95, "reached_ratio": 1.0, "death_ratio": 0.0},
		"evolve_weak": {"kpm_post_med": 30.0,  "survived_post_med": 100.0, "hp_min_post_med": 0.2,  "reached_ratio": 0.3, "death_ratio": 0.8},
	}
	var f := RA.flag_multi_axis(by, 0.35)
	assert_str(String(f["evolve_op"]["verdict"])).is_equal("OP")
	assert_str(String(f["evolve_weak"]["verdict"])).is_equal("weak")
	assert_str(String(f["evolve_a"]["verdict"])).is_equal("ok")
	assert_float(f["evolve_op"]["kpm_eff"]).is_equal_approx(1.0, 0.001)  # 200/100-1
