# tools/analyze_dominance.gd —— headless: -s res://tools/analyze_dominance.gd -- --dir=telemetry/p2a [--report=...]
# P3 单元2:对现存 solo_* 遥测零重跑重算新支配指标(clear_eff/backlog),打印 新(clear_eff)vs 旧(kpm)verdict 对照,验证闸用。
extends SceneTree

const RA := preload("res://tools/run_analysis.gd")

func _initialize() -> void:
	var cfg := _parse(OS.get_cmdline_user_args())
	var dir_rel: String = cfg.get("dir", "telemetry/p2a")
	var report_rel: String = cfg.get("report", dir_rel + "/dominance_report.json")
	var abs_dir := ProjectSettings.globalize_path(_res(dir_rel))
	var d := DirAccess.open(abs_dir)
	if d == null:
		push_error("analyze_dominance: 打不开 %s" % abs_dir)
		quit(1)
		return
	var by_evo := {}
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
		if bool(spec.get("is_base", false)):
			continue   # base 档(solobase_)无进化 → 走 analyze_base_clear(max_level 锚),此处跳过防误判未达
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
	var new_flags := RA.flag_dominance(summary, 0.35, RA.roles_for(summary))  # P3c:角色感知清场组+未达过滤
	var old_flags := RA.flag_multi_axis(summary)
	# 主轴=backlog(反向:低=强清场);clear_eff/kpm 降级为 context 列。role=清场角色组(P3c)。
	print("evolution,role,n,reached,backlog,backlog_dev,clear_eff(ctx),kpm(ctx),hp_min,verdict_new,verdict_old")
	for k in new_flags:
		var s = summary[k]
		var nf = new_flags[k]
		var of = old_flags[k]
		print("%s,%s,%d,%.2f,%.0f,%+.2f,%.2f,%.0f,%.2f,%s,%s" % [
			k, String(nf["role"]), int(s["n"]), float(s["reached_ratio"]), float(s["backlog_mean_med"]),
			float(nf["backlog_dev"]), float(s["clear_eff_med"]), float(s["kpm_post_med"]),
			float(s["hp_min_post_med"]), String(nf["verdict"]), String(of["verdict"])])
	var f := FileAccess.open(_res(report_rel), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"summary": summary, "new_flags": new_flags, "old_flags": old_flags}, "\t"))
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
