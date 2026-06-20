# tools/run_analysis.gd
# 平衡分析纯函数核。无 IO、无场景。analyze_runs.gd 与单测共用。
extends RefCounted

const BACKLOG_FLOOR: float = 5.0   # clear_eff 分母地板:强武器清空场地致 backlog→0 时防爆(P3 验证闸复核;若多进化命中地板,主轴降级为 backlog_mean)

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

# ── P2a 进化窗口分析(纯函数) ─────────────────────────────────────────────────

# 解析 tick CSV 文本为行字典数组。首行=表头,其余=数据行(值保留字符串,调用方按需转型)。
static func tick_rows_from_csv(text: String) -> Array:
	var lines := text.split("\n", false)
	if lines.size() < 2:
		return []
	var header := lines[0].split(",")
	var rows: Array = []
	for i in range(1, lines.size()):
		var parts := lines[i].split(",")
		if parts.size() != header.size():
			continue
		var row := {}
		for j in range(header.size()):
			row[header[j]] = parts[j]
		rows.append(row)
	return rows

# 单武器档名 → 规格。solofloor_ 先于 solo_ 匹配(更长前缀)。纯字符串解析,无 autoload 依赖,
# 供 run_harness(运行时授武器)与 analyze_evolutions(-s 脚本,不能 preload autoload)共用。
# {"is_solo": bool, "is_floor": bool, "weapon_id": String}。非单武器档 → is_solo=false。
static func solo_spec(cards_name: String) -> Dictionary:
	if cards_name.begins_with("solofloor_"):
		return {"is_solo": true, "is_floor": true, "weapon_id": cards_name.substr(10)}
	if cards_name.begins_with("solo_"):
		return {"is_solo": true, "is_floor": false, "weapon_id": cards_name.substr(5)}
	return {"is_solo": false, "is_floor": false, "weapon_id": ""}

# 混编档名 → 规格。mixbase=纯底盘(无目标);mix_<wid>=底盘+目标武器。
# {"is_mix": bool, "is_base": bool, "target": String}。供 harness(授武器)与 A/B 分析共用。
static func mix_spec(cards_name: String) -> Dictionary:
	if cards_name == "mixbase":
		return {"is_mix": true, "is_base": true, "target": ""}
	if cards_name.begins_with("mix_"):
		return {"is_mix": true, "is_base": false, "target": cards_name.substr(4)}
	return {"is_mix": false, "is_base": false, "target": ""}

# 解析 events JSONL 文本为字典数组(逐行 JSON.parse,跳过非字典行)。
static func events_from_jsonl(text: String) -> Array:
	var out: Array = []
	for line in text.split("\n", false):
		var v = JSON.parse_string(line)
		if typeof(v) == TYPE_DICTIONARY:
			out.append(v)
	return out

# 进化解锁时刻:首个 type=="level_up" 且 picked=="evolve_"+weapon_id 的 t。无 → -1.0。
static func evolution_unlock_time(events: Array, weapon_id: String) -> float:
	var target := "evolve_" + weapon_id
	for e in events:
		if String(e.get("type", "")) == "level_up" and String(e.get("picked", "")) == target:
			return float(e.get("t", -1.0))
	return -1.0

# 进化后窗口:t >= t_evo 的 tick 行。t_evo<0(未达进化)→ 空数组。
static func window_rows(tick_rows: Array, t_evo: float) -> Array:
	if t_evo < 0.0:
		return []
	var out: Array = []
	for row in tick_rows:
		if float(row.get("t", 0.0)) >= t_evo:
			out.append(row)
	return out

# 后期窗口三轴度量。win_rows 空(未达进化)→ reached_evolution=false。
# kpm_post = 窗口内 kills_total 增量 / 窗口时长 × 60;hp_min_post = 窗口内 hp_pct 最小;
# danger_mean_post = 窗口内 danger_ps 均值;survived_post = t_end - t_evo。
static func window_metrics(win_rows: Array, t_evo: float, t_end: float, outcome: String) -> Dictionary:
	if win_rows.is_empty():
		return {"reached_evolution": false, "kpm_post": 0.0, "hp_min_post": 0.0,
				"danger_mean_post": 0.0, "survived_post": 0.0, "backlog_mean": 0.0,
				"clear_eff": 0.0, "t_evo": t_evo, "outcome": outcome}
	var k0 := float(win_rows[0].get("kills_total", 0))
	var k1 := float(win_rows[win_rows.size() - 1].get("kills_total", 0))
	var win_dur := maxf(t_end - t_evo, 0.001)
	var hp_min := 1.0
	var danger_sum := 0.0
	var backlog_sum := 0.0
	for row in win_rows:
		hp_min = minf(hp_min, float(row.get("hp_pct", 1.0)))
		danger_sum += float(row.get("danger_ps", 0.0))
		backlog_sum += float(row.get("enemies_alive", 0))
	var kpm_post := (k1 - k0) / win_dur * 60.0
	var backlog_mean := backlog_sum / win_rows.size()
	return {
		"reached_evolution": true,
		"kpm_post": kpm_post,
		"hp_min_post": hp_min,
		"danger_mean_post": danger_sum / win_rows.size(),
		"survived_post": win_dur,
		"backlog_mean": backlog_mean,
		"clear_eff": kpm_post / maxf(backlog_mean, BACKLOG_FLOOR),
		"t_evo": t_evo,
		"outcome": outcome,
	}

# 聚合一个进化的多 run 窗口度量:三数值轴取中位(仅对已达进化的 run),reached/death 取比例。
static func summarize_evolution(metrics_list: Array) -> Dictionary:
	var n := metrics_list.size()
	var kpm: Array = []
	var hpmin: Array = []
	var surv: Array = []
	var clear: Array = []
	var backlog: Array = []
	var tevo: Array = []
	var reached_count := 0
	var death_count := 0
	for m in metrics_list:
		if bool(m.get("reached_evolution", false)):
			reached_count += 1
			kpm.append(float(m.get("kpm_post", 0.0)))
			hpmin.append(float(m.get("hp_min_post", 0.0)))
			surv.append(float(m.get("survived_post", 0.0)))
			clear.append(float(m.get("clear_eff", 0.0)))
			backlog.append(float(m.get("backlog_mean", 0.0)))
			tevo.append(float(m.get("t_evo", 0.0)))
		if String(m.get("outcome", "")) == "death":
			death_count += 1
	return {
		"n": n,
		"reached_ratio": float(reached_count) / float(maxi(n, 1)),
		"death_ratio": float(death_count) / float(maxi(n, 1)),
		"kpm_post_med": median(kpm),
		"hp_min_post_med": median(hpmin),
		"survived_post_med": median(surv),
		"clear_eff_med": median(clear),
		"backlog_mean_med": median(backlog),
		"t_evo_med": median(tevo),
	}

# 多轴判据:对 kpm/survived/hp_min 三数值轴各算跨进化中位 ±band。
# OP = kpm 高 且 生存非劣;weak = ≥2 轴低 或 多数未达进化 或(多数死亡且生存低)。
# 安全轴(hp_min)因 dodge bot 防御饱和,不作 OP 必要条件(spec 缺口 B)。
static func flag_multi_axis(by_evo: Dictionary, band: float = 0.35) -> Dictionary:
	var kpm_med := _axis_median(by_evo, "kpm_post_med")
	var surv_med := _axis_median(by_evo, "survived_post_med")
	var hp_med := _axis_median(by_evo, "hp_min_post_med")
	var flags := {}
	for k in by_evo:
		var r = by_evo[k]
		var kpm := float(r["kpm_post_med"])
		var surv := float(r["survived_post_med"])
		var hp := float(r["hp_min_post_med"])
		var kpm_v := _band_verdict(kpm, kpm_med, band)
		var surv_v := _band_verdict(surv, surv_med, band)
		var hp_v := _band_verdict(hp, hp_med, band)
		var reached := float(r.get("reached_ratio", 1.0))
		var death := float(r.get("death_ratio", 0.0))
		var low_axes := (1 if kpm_v == "low" else 0) + (1 if surv_v == "low" else 0) + (1 if hp_v == "low" else 0)
		var verdict := "ok"
		if reached < 0.5 or (death > 0.5 and surv_v == "low"):
			verdict = "weak"
		elif low_axes >= 2:
			verdict = "weak"
		elif kpm_v == "high" and surv_v != "low":
			verdict = "OP"
		flags[k] = {
			"verdict": verdict,
			"kpm_axis": kpm_v, "kpm_eff": _effect(kpm, kpm_med),
			"surv_axis": surv_v, "surv_eff": _effect(surv, surv_med),
			"hp_axis": hp_v, "hp_eff": _effect(hp, hp_med),
			"reached_ratio": reached, "death_ratio": death,
		}
	return flags

# 支配判据(P3,验证闸反馈后定稿):清场强度以 backlog(全场存活敌均值,反向:低=强清场)为主轴。
# 为何用 backlog 而非 clear_eff(=kpm/backlog)定 OP:clear_eff 分子的 kpm 仍含「生存时长×密度」污染
# ——召唤流(horde)活进后期高密窗口→kpm 假高→clear_eff 假高(实测 p2b_main reanimate 误判 OP)。
# backlog 是瞬时量,无累积速率/生存污染,且密度污染天然反向(swarm 堆积→backlog 高→清场弱)。
# 故 clear_eff 仅作 context 列;backlog 反向定清场轴。详见 docs/reviews/2026-06-20-dominance-criteria-report.md §1。
# OP = 清场强(backlog 低于带)且 安全非劣(hp 非 low);weak = reached<0.5 或(death>0.5 且 surv low)或 ≥2 可信轴低。
static func flag_dominance(by_evo: Dictionary, band: float = 0.35) -> Dictionary:
	var backlog_med := _axis_median(by_evo, "backlog_mean_med")
	var surv_med := _axis_median(by_evo, "survived_post_med")
	var hp_med := _axis_median(by_evo, "hp_min_post_med")
	var clear_med := _axis_median(by_evo, "clear_eff_med")
	var flags := {}
	for k in by_evo:
		var r = by_evo[k]
		var backlog := float(r["backlog_mean_med"])
		var surv := float(r["survived_post_med"])
		var hp := float(r["hp_min_post_med"])
		var clear := float(r["clear_eff_med"])
		# 清场强度 = backlog 反向:低于带=强(clear_axis="high"),高于带=弱(="low")。
		var backlog_raw := _band_verdict(backlog, backlog_med, band)
		var clear_v := ("high" if backlog_raw == "low" else ("low" if backlog_raw == "high" else "ok"))
		var surv_v := _band_verdict(surv, surv_med, band)
		var hp_v := _band_verdict(hp, hp_med, band)
		var reached := float(r.get("reached_ratio", 1.0))
		var death := float(r.get("death_ratio", 0.0))
		var low_axes := (1 if clear_v == "low" else 0) + (1 if surv_v == "low" else 0) + (1 if hp_v == "low" else 0)
		var verdict := "ok"
		if reached < 0.5 or (death > 0.5 and surv_v == "low"):
			verdict = "weak"
		elif low_axes >= 2:
			verdict = "weak"
		elif clear_v == "high" and hp_v != "low":
			verdict = "OP"
		flags[k] = {
			"verdict": verdict,
			"clear_axis": clear_v, "backlog_dev": _effect(backlog, backlog_med),
			"surv_axis": surv_v, "surv_dev": _effect(surv, surv_med),
			"hp_axis": hp_v, "hp_dev": _effect(hp, hp_med),
			"clear_eff_ctx": clear, "clear_eff_dev": _effect(clear, clear_med),
			"reached_ratio": reached, "death_ratio": death,
		}
	return flags

static func _axis_median(by_evo: Dictionary, key: String) -> float:
	var vals: Array = []
	for k in by_evo:
		vals.append(float(by_evo[k][key]))
	return median(vals)

static func _band_verdict(v: float, m: float, band: float) -> String:
	if m <= 0.0:
		return "ok"
	if v > m * (1.0 + band):
		return "high"
	if v < m * (1.0 - band):
		return "low"
	return "ok"

# 效应量:相对跨进化中位的偏离(v/m - 1)。
static func _effect(v: float, m: float) -> float:
	if m <= 0.0:
		return 0.0
	return v / m - 1.0
