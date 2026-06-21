# tools/analyze_base_clear.gd —— headless: -s res://tools/analyze_base_clear.gd -- --dir=telemetry/base_clear [--report=...]
# 报告 §5① 内容广度:对 solobase_* 遥测(永不进化的纯 base L3 跑)算 base 武器自身清场支配。
# 复用 P3c 角色感知清场组判据(flag_dominance + EVOLUTION_ROLE),但窗口锚用 max_level_time(满级)
# 而非 evolution_unlock_time(进化)——base 档无进化。键为 base_<wid>,与 analyze_dominance 的 evolve_<wid> 区分。
extends SceneTree

const RA := preload("res://tools/run_analysis.gd")

func _initialize() -> void:
	var cfg := _parse(OS.get_cmdline_user_args())
	var dir_rel: String = cfg.get("dir", "telemetry/base_clear")
	var report_rel: String = cfg.get("report", dir_rel + "/base_clear_report.json")
	var abs_dir := ProjectSettings.globalize_path(_res(dir_rel))
	var d := DirAccess.open(abs_dir)
	if d == null:
		push_error("analyze_base_clear: 打不开 %s" % abs_dir)
		quit(1)
		return
	var by_wid := {}
	for fn in d.get_files():
		if not fn.ends_with(".summary.json"):
			continue
		var base := fn.replace(".summary.json", "")
		var su = JSON.parse_string(FileAccess.get_file_as_string(abs_dir.path_join(fn)))
		if typeof(su) != TYPE_DICTIONARY:
			continue
		var cards := String(su.get("config", {}).get("cards", ""))
		var spec := RA.solo_spec(cards)
		if not bool(spec.get("is_base", false)):
			continue   # 仅 base 档(solobase_);进化档走 analyze_dominance
		var wid: String = spec["weapon_id"]
		var events := RA.events_from_jsonl(FileAccess.get_file_as_string(abs_dir.path_join(base + ".events.jsonl")))
		var ticks := RA.tick_rows_from_csv(FileAccess.get_file_as_string(abs_dir.path_join(base + ".tick.csv")))
		var t_anchor := RA.max_level_time(events, wid)   # 满级锚(非进化)
		var win := RA.window_rows(ticks, t_anchor)
		var m := RA.window_metrics(win, t_anchor, float(su.get("survived_s", 0.0)), String(su.get("outcome", "")))
		if not by_wid.has(wid):
			by_wid[wid] = []
		by_wid[wid].append(m)
	var summary := {}
	var roles := {}
	for wid in by_wid:
		var key: String = "base_" + String(wid)
		summary[key] = RA.summarize_evolution(by_wid[wid])
		roles[key] = RA.base_role_for(String(wid))   # base 形态角色:frostbite/maul=control、aura=defense → 清场带只含 explosion/lightning
	# 角色感知清场组判据(P3c):清场轴 backlog 中位仅在 clear 角色 ∩ 达满级组内取;reached=满级达成率。
	var flags := RA.flag_dominance(summary, 0.35, roles)
	# 主轴=backlog(反向:低=强清场);reached=满级达成率;clear_eff/kpm 为 context。
	print("base_weapon,role,n,reached,backlog,backlog_dev,clear_eff(ctx),kpm(ctx),hp_min,verdict")
	for k in flags:
		var s = summary[k]
		var nf = flags[k]
		print("%s,%s,%d,%.2f,%.0f,%+.2f,%.2f,%.0f,%.2f,%s" % [
			k, String(nf["role"]), int(s["n"]), float(s["reached_ratio"]), float(s["backlog_mean_med"]),
			float(nf["backlog_dev"]), float(s["clear_eff_med"]), float(s["kpm_post_med"]),
			float(s["hp_min_post_med"]), String(nf["verdict"])])
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
