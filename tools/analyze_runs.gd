# tools/analyze_runs.gd —— headless 运行: -s res://tools/analyze_runs.gd -- --dir=... --report=...
extends SceneTree

const RA := preload("res://tools/run_analysis.gd")

func _initialize() -> void:
	var cfg := _parse(OS.get_cmdline_user_args())
	var dir_rel: String = cfg.get("dir", "telemetry/ab")
	var report_rel: String = cfg.get("report", dir_rel + "/report.json")
	var abs_dir := ProjectSettings.globalize_path(_res(dir_rel))
	var by_profile := {}
	var d := DirAccess.open(abs_dir)
	if d == null:
		push_error("analyze_runs: 打不开目录 %s" % abs_dir)
		quit(1)
		return
	for fn in d.get_files():
		if not fn.ends_with(".summary.json"):
			continue
		var txt := FileAccess.get_file_as_string(abs_dir.path_join(fn))
		var su = JSON.parse_string(txt)
		if typeof(su) != TYPE_DICTIONARY:
			continue
		var prof := _profile_of(fn)
		if not by_profile.has(prof):
			by_profile[prof] = []
		by_profile[prof].append(su)
	var out := {}
	for prof in by_profile:
		out[prof] = RA.summarize_profile(by_profile[prof])
	var flags := RA.flag_off_band(out)
	print("profile,n,survived_med,kills_per_min_med,hp_pct_min_med,danger_med,verdict")
	for prof in out:
		var r = out[prof]
		print("%s,%d,%.0f,%.2f,%.3f,%.1f,%s" % [
			prof, int(r["n"]), float(r["survived_med"]), float(r["kills_per_min_med"]),
			float(r["hp_pct_min_med"]), float(r["danger_med"]), String(flags[prof]["verdict"])])
	var f := FileAccess.open(_res(report_rel), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"summary": out, "flags": flags}, "\t"))
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

# "solo_knife_s3.summary.json" → "solo_knife"(末尾 _s<digits> 截掉)。
func _profile_of(fn: String) -> String:
	var base := fn.replace(".summary.json", "")
	var idx := base.rfind("_s")
	return base.substr(0, idx) if idx > 0 else base
