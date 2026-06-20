# tools/analyze_evolutions.gd —— headless: -s res://tools/analyze_evolutions.gd -- --dir=telemetry/p2a [--report=...]
# 读每个 solo_* run 的 summary+tick+events,按 solo 武器分组,切进化窗口,多轴判据,出报告。
extends SceneTree

const RA := preload("res://tools/run_analysis.gd")

func _initialize() -> void:
	var cfg := _parse(OS.get_cmdline_user_args())
	var dir_rel: String = cfg.get("dir", "telemetry/p2a")
	var report_rel: String = cfg.get("report", dir_rel + "/report.json")
	var abs_dir := ProjectSettings.globalize_path(_res(dir_rel))
	var d := DirAccess.open(abs_dir)
	if d == null:
		push_error("analyze_evolutions: 打不开 %s" % abs_dir)
		quit(1)
		return
	var by_evo := {}   # weapon_id -> Array[metrics]
	for fn in d.get_files():
		if not fn.ends_with(".summary.json"):
			continue
		var base := fn.replace(".summary.json", "")
		var su = JSON.parse_string(FileAccess.get_file_as_string(abs_dir.path_join(fn)))
		if typeof(su) != TYPE_DICTIONARY:
			continue
		var cards := String(su.get("config", {}).get("cards", ""))
		var spec := RA.solo_spec(cards)
		if not spec["is_solo"]:
			continue
		var wid: String = spec["weapon_id"]
		var events := RA.events_from_jsonl(FileAccess.get_file_as_string(abs_dir.path_join(base + ".events.jsonl")))
		var ticks := RA.tick_rows_from_csv(FileAccess.get_file_as_string(abs_dir.path_join(base + ".tick.csv")))
		var t_evo := RA.evolution_unlock_time(events, wid)
		var win := RA.window_rows(ticks, t_evo)
		var m := RA.window_metrics(win, t_evo, float(su.get("survived_s", 0.0)), String(su.get("outcome", "")))
		if not by_evo.has(wid):
			by_evo[wid] = []
		by_evo[wid].append(m)
	var summary := {}
	for wid in by_evo:
		summary["evolve_" + wid] = RA.summarize_evolution(by_evo[wid])
	var flags := RA.flag_multi_axis(summary)
	print("evolution,n,reached,kpm_post,kpm_eff,surv_post,hp_min,verdict")
	for k in flags:
		var s = summary[k]
		var fl = flags[k]
		print("%s,%d,%.2f,%.1f,%+.2f,%.0f,%.2f,%s" % [
			k, int(s["n"]), float(s["reached_ratio"]), float(s["kpm_post_med"]),
			float(fl["kpm_eff"]), float(s["survived_post_med"]), float(s["hp_min_post_med"]), String(fl["verdict"])])
	var f := FileAccess.open(_res(report_rel), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"summary": summary, "flags": flags}, "\t"))
		f.close()
	quit()

func _parse(args: Array) -> Dictionary:
	var cfg := {}
	for raw in args:
		var a := String(raw)
		if a.begins_with("--dir="):
			cfg["dir"] = a.split("=")[1]
		elif a.begins_with("--report="):
			cfg["report"] = a.split("=")[1]
	return cfg

func _res(p: String) -> String:
	return p if (p.begins_with("res://") or p.begins_with("user://")) else "res://" + p
