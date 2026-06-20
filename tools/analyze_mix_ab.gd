# tools/analyze_mix_ab.gd —— headless: -s res://tools/analyze_mix_ab.gd -- --dir=telemetry/p3_mix
# P3 单元3:混编 A/B 边际归因(backlog 主轴,与 flag_dominance 定稿一致)。
# 对每 mix_<target>,取其进化窗 [t_evo, min(end_mix,end_base)] 共时重叠窗,比同种子 mixbase 同窗 backlog,
# marginal = backlog_base − backlog_mix(正 = 目标降低积压 = 清场贡献)。clear_eff/hp_min 作 context。
extends SceneTree

const RA := preload("res://tools/run_analysis.gd")

func _initialize() -> void:
	var cfg := _parse(OS.get_cmdline_user_args())
	var dir_rel: String = cfg.get("dir", "telemetry/p3_mix")
	var abs_dir := ProjectSettings.globalize_path(_res(dir_rel))
	var d := DirAccess.open(abs_dir)
	if d == null:
		push_error("analyze_mix_ab: 打不开 %s" % abs_dir)
		quit(1)
		return
	# 收集所有 run base 名。
	var bases: Array[String] = []
	for fn in d.get_files():
		if fn.ends_with(".summary.json"):
			bases.append(fn.replace(".summary.json", ""))
	# 收集目标集(mix_<target>，排除 mixbase)。
	var targets := {}
	for base in bases:
		var ms := RA.mix_spec(_cards_of(abs_dir, base))
		if ms["is_mix"] and not ms["is_base"]:
			targets[String(ms["target"])] = true
	print("target,n_reached,reached,backlog_mix,backlog_base,marginal,clear_eff_mix(ctx),hp_min_mix")
	var report := {}
	for t in targets:
		var mixv: Array = []
		var basev: Array = []
		var margv: Array = []
		var ceffv: Array = []
		var hpv: Array = []
		var reached := 0
		var total := 0
		for base in bases:
			if not base.begins_with("mix_%s_s" % t):
				continue
			total += 1
			var seed_tag := base.substr(base.rfind("_s"))   # "_s7"
			var base_run := "mixbase" + seed_tag
			if not bases.has(base_run):
				continue
			var ev := RA.events_from_jsonl(FileAccess.get_file_as_string(abs_dir.path_join(base + ".events.jsonl")))
			var t_evo := RA.evolution_unlock_time(ev, t)
			if t_evo < 0.0:
				continue   # 该种子目标没进化,不计入(reached 比例另算)
			var end_mix := _survived(abs_dir, base)
			var end_base := _survived(abs_dir, base_run)
			var t_end := minf(end_mix, end_base)   # 共时重叠窗右端
			if t_end <= t_evo:
				continue   # 无可比重叠窗(底盘比目标早死且早于进化)
			reached += 1
			var bl_mix := _backlog_in_range(abs_dir, base, t_evo, t_end)
			var bl_base := _backlog_in_range(abs_dir, base_run, t_evo, t_end)
			mixv.append(bl_mix)
			basev.append(bl_base)
			margv.append(bl_base - bl_mix)
			ceffv.append(_clear_eff_full(abs_dir, base, t_evo))
			hpv.append(_hp_min_in_range(abs_dir, base, t_evo, t_end))
		var row := {
			"n_reached": reached,
			"reached": float(reached) / float(maxi(total, 1)),
			"backlog_mix_med": RA.median(mixv),
			"backlog_base_med": RA.median(basev),
			"marginal_med": RA.median(margv),
			"clear_eff_mix_med": RA.median(ceffv),
			"hp_min_mix_med": RA.median(hpv),
		}
		report[t] = row
		print("%s,%d,%.2f,%.0f,%.0f,%+.0f,%.2f,%.2f" % [t, reached, row["reached"],
			row["backlog_mix_med"], row["backlog_base_med"], row["marginal_med"],
			row["clear_eff_mix_med"], row["hp_min_mix_med"]])
	var f := FileAccess.open(_res(dir_rel + "/mix_ab_report.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	quit()

func _cards_of(abs_dir: String, base: String) -> String:
	var su = JSON.parse_string(FileAccess.get_file_as_string(abs_dir.path_join(base + ".summary.json")))
	return String(su.get("config", {}).get("cards", "")) if typeof(su) == TYPE_DICTIONARY else ""

func _survived(abs_dir: String, base: String) -> float:
	var su = JSON.parse_string(FileAccess.get_file_as_string(abs_dir.path_join(base + ".summary.json")))
	return float(su.get("survived_s", 0.0)) if typeof(su) == TYPE_DICTIONARY else 0.0

# [t_start, t_end] 闭区间内 enemies_alive 均值。无行 → 0。
func _backlog_in_range(abs_dir: String, base: String, t_start: float, t_end: float) -> float:
	var ticks := RA.tick_rows_from_csv(FileAccess.get_file_as_string(abs_dir.path_join(base + ".tick.csv")))
	var sum := 0.0
	var n := 0
	for row in ticks:
		var rt := float(row.get("t", 0.0))
		if rt >= t_start and rt <= t_end:
			sum += float(row.get("enemies_alive", 0))
			n += 1
	return sum / maxi(n, 1)

func _hp_min_in_range(abs_dir: String, base: String, t_start: float, t_end: float) -> float:
	var ticks := RA.tick_rows_from_csv(FileAccess.get_file_as_string(abs_dir.path_join(base + ".tick.csv")))
	var hp_min := 1.0
	for row in ticks:
		var rt := float(row.get("t", 0.0))
		if rt >= t_start and rt <= t_end:
			hp_min = minf(hp_min, float(row.get("hp_pct", 1.0)))
	return hp_min

# clear_eff(context):目标进化后整窗(到 mix 自身终局),复用 window_metrics 定义。
func _clear_eff_full(abs_dir: String, base: String, t_evo: float) -> float:
	var end_mix := _survived(abs_dir, base)
	var ticks := RA.tick_rows_from_csv(FileAccess.get_file_as_string(abs_dir.path_join(base + ".tick.csv")))
	var win := RA.window_rows(ticks, t_evo)
	return float(RA.window_metrics(win, t_evo, end_mix, "").get("clear_eff", 0.0))

func _parse(args: Array) -> Dictionary:
	var cfg := {}
	for raw in args:
		var a := String(raw)
		if a.begins_with("--dir="):
			cfg["dir"] = a.split("=")[1]
	return cfg

func _res(p: String) -> String:
	return p if (p.begins_with("res://") or p.begins_with("user://")) else "res://" + p
