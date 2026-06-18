# tools/run_analysis.gd
# 平衡分析纯函数核。无 IO、无场景。analyze_runs.gd 与单测共用。
extends RefCounted

static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	var n := v.size()
	if n % 2 == 1:
		return float(v[n / 2])
	return (float(v[n / 2 - 1]) + float(v[n / 2])) * 0.5

static func kills_per_min(summary: Dictionary) -> float:
	var s := float(summary.get("survived_s", 0.0))
	if s <= 0.0:
		return 0.0
	return float(summary.get("kills", 0)) / (s / 60.0)

static func summarize_profile(summaries: Array) -> Dictionary:
	var surv: Array = []
	var kpm: Array = []
	var hpmin: Array = []
	var danger: Array = []
	for su in summaries:
		surv.append(float(su.get("survived_s", 0.0)))
		kpm.append(kills_per_min(su))
		hpmin.append(float(su.get("hp_pct_min", 0.0)))
		danger.append(float(su.get("danger_total_s", 0.0)))
	return {
		"n": summaries.size(),
		"survived_med": median(surv),
		"kills_per_min_med": median(kpm),
		"hp_pct_min_med": median(hpmin),
		"danger_med": median(danger),
	}

# 以全档 kills_per_min_med 的中位数为基准,±band 外判 OP/weak。
static func flag_off_band(by_profile: Dictionary, band: float = 0.35) -> Dictionary:
	var meds: Array = []
	for k in by_profile:
		meds.append(float(by_profile[k]["kills_per_min_med"]))
	var m := median(meds)
	var flags := {}
	for k in by_profile:
		var v := float(by_profile[k]["kills_per_min_med"])
		var verdict := "ok"
		if m > 0.0:
			if v > m * (1.0 + band):
				verdict = "OP"
			elif v < m * (1.0 - band):
				verdict = "weak"
		flags[k] = {"kills_per_min_med": v, "cross_median": m, "verdict": verdict}
	return flags
