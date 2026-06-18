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
