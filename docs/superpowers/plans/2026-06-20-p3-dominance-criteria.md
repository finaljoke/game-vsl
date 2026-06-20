# P3 判据闭环 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用密度/时长鲁棒的「清场效率 clear_eff」支配判据替换失真的 kpm，在现存遥测上证伪式验证，给 P2b 悬置的 verdict 下终判，并以真混编 A/B 边际归因终判 thousand_edge/mega_orb。

**Architecture:** 三单元、纯函数优先。单元 1 在 `tools/run_analysis.gd`（无 IO 纯模块）扩出 `clear_eff`/`backlog_mean`/`t_evo` 度量与 `flag_dominance` 判据（TDD）。单元 2 写 `tools/analyze_dominance.gd`（`-s` IO 壳）对**现存** p2a/p2b 遥测**零重跑**重算，跑可证伪验证闸。单元 3 在 `run_harness.gd` 加 `mix_` 混编机架（底盘 + 目标 A/B），新跑 thousand_edge/mega_orb + explosion 控制组，边际归因下终判。

**Tech Stack:** Godot 4.7 GDScript；gdUnit4（headless）；PowerShell campaign 脚本；遥测 tick CSV / events JSONL / summary JSON。

## Global Constraints

- **引擎 Godot 4.7**；CLI 一律用 `C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe`（GUI 版 headless 抓不到 stdout）。
- **跑任何 headless（测试/campaign）前先关 Godot 编辑器**（LimboAI 双实例 DLL 冲突陷阱）。
- **确定性靠 `--fixed-fps 60`**（不是 `--fast`）；campaign 配方 `--bot=kite --fast=8 --maxtime=600`，种子 `7 42 101 1 2 3 4 5`（同 P2a/P2b）。
- **C6 截断陷阱**：新测试**排套件末尾**；GREEN 态**核对发现用例数 == 预期**，别只看全绿。
- **本轮零数值改动**（测量+终判）：任何确认的真 OP → 记 **P3b** 输入，不在本 plan 调数值。基线全量绿测数 = **527**（P2b 末）。
- gdUnit 全量：`& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`（**必须 `--ignoreHeadlessMode`**，否则退出码 103）。
- 单文件套件：上行把 `-a res://tests` 换成 `-a res://tests/test_run_analysis.gd`。
- 上位 spec：[docs/superpowers/specs/2026-06-20-p3-dominance-criteria-design.md](../specs/2026-06-20-p3-dominance-criteria-design.md)。别 `git add -A`（仓库 ~2500 未追踪文件）；每任务只 add 该任务碰的文件。

---

### Task 0: 建分支

- [ ] **Step 1: 从 master 建分支**

```bash
git checkout master && git checkout -b feat/p3-dominance-criteria
```

- [ ] **Step 2: 确认干净起点**

Run: `git status --short && git log --oneline -1`
Expected: 工作区无未提交的 tracked 改动（未追踪文件无妨）；HEAD = `be371de docs(spec): P3 判据闭环设计...`

---

### Task 1: clear_eff / backlog_mean / t_evo 窗口度量（单元 1）

**Files:**
- Modify: `tools/run_analysis.gd`（`window_metrics`，加 `BACKLOG_FLOOR` 常量）
- Test: `tests/test_run_analysis.gd`（末尾追加）

**Interfaces:**
- Consumes: 现有 `window_metrics(win_rows: Array, t_evo: float, t_end: float, outcome: String) -> Dictionary`、tick 行字典（`enemies_alive` 列为字符串数字）。
- Produces: `window_metrics` 返回 dict **新增** 键 `backlog_mean: float`、`clear_eff: float`、`t_evo: float`；模块常量 `BACKLOG_FLOOR: float`。

- [ ] **Step 1: 写失败测试**（追加到 `tests/test_run_analysis.gd` 末尾）

```gdscript
# ── P3 单元:clear_eff / backlog_mean / t_evo ─────────────────────────────────
func test_window_metrics_backlog_and_clear_eff() -> void:
	# t_evo=200,t_end=260→win_dur=60;kills 100→280=180→kpm_post=180;
	# enemies_alive 均值=(150+90)/2=120;clear_eff=180/max(120,FLOOR)=1.5
	var win := [
		{"t": "200.0", "kills_total": "100", "hp_pct": "0.9", "danger_ps": "0.0", "enemies_alive": "150"},
		{"t": "260.0", "kills_total": "280", "hp_pct": "0.7", "danger_ps": "2.0", "enemies_alive": "90"},
	]
	var m := RA.window_metrics(win, 200.0, 260.0, "death")
	assert_float(m["backlog_mean"]).is_equal_approx(120.0, 0.001)
	assert_float(m["clear_eff"]).is_equal_approx(1.5, 0.001)
	assert_float(m["t_evo"]).is_equal_approx(200.0, 0.001)

func test_window_metrics_clear_eff_floor_guards_low_backlog() -> void:
	# backlog 均值=2 < FLOOR;kills 0→30=30/60s*60=30 kpm;clear_eff=30/FLOOR(非 30/2)
	var win := [
		{"t": "200.0", "kills_total": "0", "hp_pct": "1.0", "danger_ps": "0.0", "enemies_alive": "2"},
		{"t": "260.0", "kills_total": "30", "hp_pct": "1.0", "danger_ps": "0.0", "enemies_alive": "2"},
	]
	var m := RA.window_metrics(win, 200.0, 260.0, "victory")
	assert_float(m["clear_eff"]).is_equal_approx(30.0 / RA.BACKLOG_FLOOR, 0.001)

func test_clear_eff_inverts_swarm_chipping() -> void:
	# swarm:高 kpm(600) 但满场积压 200 → clear_eff=600/200=3
	# clean:中 kpm(300) 低积压 20 → clear_eff=300/20=15(更强,尽管 kpm 更低)
	var swarm := [{"t": "100.0", "kills_total": "0", "enemies_alive": "200"},
		{"t": "160.0", "kills_total": "600", "enemies_alive": "200"}]
	var clean := [{"t": "100.0", "kills_total": "0", "enemies_alive": "20"},
		{"t": "160.0", "kills_total": "300", "enemies_alive": "20"}]
	var ms := RA.window_metrics(swarm, 100.0, 160.0, "victory")
	var mc := RA.window_metrics(clean, 100.0, 160.0, "victory")
	assert_float(ms["kpm_post"]).is_greater(mc["kpm_post"])      # kpm 误把 swarm 排前
	assert_float(mc["clear_eff"]).is_greater(ms["clear_eff"])    # clear_eff 反转:clean 更强

func test_window_metrics_unreached_has_zero_clear_eff() -> void:
	var m := RA.window_metrics([], -1.0, 100.0, "death")
	assert_bool(m["reached_evolution"]).is_false()
	assert_float(m["clear_eff"]).is_equal(0.0)
	assert_float(m["backlog_mean"]).is_equal(0.0)
```

- [ ] **Step 2: 跑测试确认失败**

Run（单文件套件，见 Global Constraints）：`... -a res://tests/test_run_analysis.gd`
Expected: 上述 4 个新测试 FAIL（`clear_eff`/`backlog_mean`/`BACKLOG_FLOOR` 不存在）；旧测试仍绿。

- [ ] **Step 3: 实现**

在 `tools/run_analysis.gd` 顶部（`extends RefCounted` 之后）加常量：

```gdscript
const BACKLOG_FLOOR: float = 5.0   # clear_eff 分母地板:强武器清空场地致 backlog→0 时防爆(Task 5 验证闸复核;若多进化命中地板,主轴降级为 backlog_mean)
```

把 `window_metrics` 整体替换为：

```gdscript
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/test_run_analysis.gd`
Expected: 全绿；核对发现用例数 = 原 17 + 4 = **21**（旧 `test_window_metrics_*` 仍绿，未破坏）。

- [ ] **Step 5: 提交**

```bash
git add tools/run_analysis.gd tests/test_run_analysis.gd
git commit -m "feat(p3): window_metrics 增 clear_eff/backlog_mean/t_evo(密度鲁棒判据)"
```

---

### Task 2: summarize_evolution 聚合新轴中位（单元 1）

**Files:**
- Modify: `tools/run_analysis.gd`（`summarize_evolution`）
- Test: `tests/test_run_analysis.gd`（末尾追加）

**Interfaces:**
- Consumes: Task 1 的 metrics dict（含 `clear_eff`/`backlog_mean`/`t_evo`）。
- Produces: `summarize_evolution` 返回 dict **新增** `clear_eff_med`、`backlog_mean_med`、`t_evo_med`（仅对 reached 的 run 取中位）。

- [ ] **Step 1: 写失败测试**（追加末尾）

```gdscript
func test_summarize_evolution_aggregates_new_axes() -> void:
	var ms := [
		{"reached_evolution": true, "kpm_post": 100.0, "hp_min_post": 0.9, "survived_post": 300.0,
			"clear_eff": 10.0, "backlog_mean": 10.0, "t_evo": 180.0, "outcome": "victory"},
		{"reached_evolution": true, "kpm_post": 140.0, "hp_min_post": 0.8, "survived_post": 360.0,
			"clear_eff": 14.0, "backlog_mean": 20.0, "t_evo": 220.0, "outcome": "victory"},
		{"reached_evolution": false, "kpm_post": 0.0, "hp_min_post": 0.0, "survived_post": 0.0,
			"clear_eff": 0.0, "backlog_mean": 0.0, "t_evo": -1.0, "outcome": "death"},
	]
	var s := RA.summarize_evolution(ms)
	assert_float(s["clear_eff_med"]).is_equal_approx(12.0, 0.001)     # median(10,14)
	assert_float(s["backlog_mean_med"]).is_equal_approx(15.0, 0.001)  # median(10,20)
	assert_float(s["t_evo_med"]).is_equal_approx(200.0, 0.001)        # median(180,220),未达不计
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/test_run_analysis.gd`
Expected: 新测试 FAIL（键不存在）。

- [ ] **Step 3: 实现** — 把 `summarize_evolution` 整体替换为：

```gdscript
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/test_run_analysis.gd`
Expected: 全绿；旧 `test_summarize_evolution_aggregates_medians_and_ratios` 仍绿（未改其断言）。发现用例数 = **22**。

- [ ] **Step 5: 提交**

```bash
git add tools/run_analysis.gd tests/test_run_analysis.gd
git commit -m "feat(p3): summarize_evolution 聚合 clear_eff/backlog/t_evo 中位"
```

---

### Task 3: flag_dominance 支配判据（单元 1）

**Files:**
- Modify: `tools/run_analysis.gd`（新增 `flag_dominance`；保留旧 `flag_multi_axis` 不删）
- Test: `tests/test_run_analysis.gd`（末尾追加）

**Interfaces:**
- Consumes: `summarize_evolution` 输出（含 `clear_eff_med`/`backlog_mean_med`/`survived_post_med`/`hp_min_post_med`/`reached_ratio`/`death_ratio`）；现有私有 `_axis_median`/`_band_verdict`/`_effect`。
- Produces: `flag_dominance(by_evo: Dictionary, band: float = 0.35) -> Dictionary`，每进化键 → `{verdict, clear_axis, clear_dev, surv_axis, surv_dev, hp_axis, hp_dev, backlog_axis, backlog_dev, reached_ratio, death_ratio}`。`verdict ∈ {OP, weak, ok}`。

- [ ] **Step 1: 写失败测试**（追加末尾）

```gdscript
func test_flag_dominance_uses_clear_eff_not_kpm() -> void:
	# swarm:clear_eff 低(3) + backlog 巨(200) → 不 OP(纵 kpm 在真实跑里高)
	# op:clear_eff 高(18) + 安全非劣 → OP;clean/mid:clear_eff 中(9) → ok
	var by := {
		"evolve_swarm": {"clear_eff_med": 3.0,  "backlog_mean_med": 200.0, "survived_post_med": 450.0, "hp_min_post_med": 0.74, "reached_ratio": 1.0, "death_ratio": 0.0},
		"evolve_clean": {"clear_eff_med": 9.0,  "backlog_mean_med": 30.0,  "survived_post_med": 400.0, "hp_min_post_med": 0.70, "reached_ratio": 1.0, "death_ratio": 0.1},
		"evolve_mid":   {"clear_eff_med": 9.0,  "backlog_mean_med": 30.0,  "survived_post_med": 400.0, "hp_min_post_med": 0.70, "reached_ratio": 1.0, "death_ratio": 0.1},
		"evolve_op":    {"clear_eff_med": 18.0, "backlog_mean_med": 12.0,  "survived_post_med": 430.0, "hp_min_post_med": 0.85, "reached_ratio": 1.0, "death_ratio": 0.0},
	}
	var f := RA.flag_dominance(by, 0.35)
	assert_str(String(f["evolve_op"]["verdict"])).is_equal("OP")
	assert_str(String(f["evolve_swarm"]["verdict"])).is_not_equal("OP")   # 反转:高 kpm/积压 不再误报 OP
	assert_str(String(f["evolve_clean"]["verdict"])).is_equal("ok")

func test_flag_dominance_weak_on_low_reached() -> void:
	var by := {
		"evolve_a":    {"clear_eff_med": 10.0, "backlog_mean_med": 30.0, "survived_post_med": 400.0, "hp_min_post_med": 0.8, "reached_ratio": 1.0, "death_ratio": 0.1},
		"evolve_b":    {"clear_eff_med": 10.0, "backlog_mean_med": 30.0, "survived_post_med": 400.0, "hp_min_post_med": 0.8, "reached_ratio": 1.0, "death_ratio": 0.1},
		"evolve_weak": {"clear_eff_med": 4.0,  "backlog_mean_med": 90.0, "survived_post_med": 120.0, "hp_min_post_med": 0.2, "reached_ratio": 0.3, "death_ratio": 0.8},
	}
	var f := RA.flag_dominance(by, 0.35)
	assert_str(String(f["evolve_weak"]["verdict"])).is_equal("weak")     # reached<0.5

func test_flag_dominance_backlog_axis_inverted() -> void:
	# backlog 低于带 → 清场强 → backlog_axis="high";高于带 → "low"
	var by := {
		"evolve_lo": {"clear_eff_med": 10.0, "backlog_mean_med": 10.0,  "survived_post_med": 400.0, "hp_min_post_med": 0.8, "reached_ratio": 1.0, "death_ratio": 0.0},
		"evolve_md": {"clear_eff_med": 10.0, "backlog_mean_med": 100.0, "survived_post_med": 400.0, "hp_min_post_med": 0.8, "reached_ratio": 1.0, "death_ratio": 0.0},
		"evolve_hi": {"clear_eff_med": 10.0, "backlog_mean_med": 200.0, "survived_post_med": 400.0, "hp_min_post_med": 0.8, "reached_ratio": 1.0, "death_ratio": 0.0},
	}
	var f := RA.flag_dominance(by, 0.35)
	assert_str(String(f["evolve_lo"]["backlog_axis"])).is_equal("high")  # 积压小=清场强
	assert_str(String(f["evolve_hi"]["backlog_axis"])).is_equal("low")   # 积压大=清场弱
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/test_run_analysis.gd`
Expected: 3 个新测试 FAIL（`flag_dominance` 不存在）。

- [ ] **Step 3: 实现** — 在 `flag_multi_axis` 之后、`_axis_median` 之前插入：

```gdscript
# 支配判据(P3):以 clear_eff(密度/时长鲁棒)为主轴替 kpm。
# OP = clear_eff 高 且 安全非劣(hp_min 非 low);weak = reached<0.5 或(death>0.5 且 surv low)或 ≥2 可信轴低。
# backlog 反向作辅证(低积压=清场强),不单独定 OP。kpm 不入判据(降级为分析器 context 列)。
static func flag_dominance(by_evo: Dictionary, band: float = 0.35) -> Dictionary:
	var clear_med := _axis_median(by_evo, "clear_eff_med")
	var surv_med := _axis_median(by_evo, "survived_post_med")
	var hp_med := _axis_median(by_evo, "hp_min_post_med")
	var backlog_med := _axis_median(by_evo, "backlog_mean_med")
	var flags := {}
	for k in by_evo:
		var r = by_evo[k]
		var clear := float(r["clear_eff_med"])
		var surv := float(r["survived_post_med"])
		var hp := float(r["hp_min_post_med"])
		var backlog := float(r["backlog_mean_med"])
		var clear_v := _band_verdict(clear, clear_med, band)
		var surv_v := _band_verdict(surv, surv_med, band)
		var hp_v := _band_verdict(hp, hp_med, band)
		var backlog_raw := _band_verdict(backlog, backlog_med, band)   # 反向:低积压=强
		var backlog_v := ("high" if backlog_raw == "low" else ("low" if backlog_raw == "high" else "ok"))
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
			"clear_axis": clear_v, "clear_dev": _effect(clear, clear_med),
			"surv_axis": surv_v, "surv_dev": _effect(surv, surv_med),
			"hp_axis": hp_v, "hp_dev": _effect(hp, hp_med),
			"backlog_axis": backlog_v, "backlog_dev": _effect(backlog, backlog_med),
			"reached_ratio": reached, "death_ratio": death,
		}
	return flags
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/test_run_analysis.gd`
Expected: 全绿；发现用例数 = **25**（22 + 3）。旧 `test_flag_multi_axis_*` 仍绿。

- [ ] **Step 5: 提交**

```bash
git add tools/run_analysis.gd tests/test_run_analysis.gd
git commit -m "feat(p3): flag_dominance 支配判据(clear_eff 主轴,kpm 出局,backlog 反向辅证)"
```

---

### Task 4: analyze_dominance.gd 重算壳（单元 2）

**Files:**
- Create: `tools/analyze_dominance.gd`

**Interfaces:**
- Consumes: `tools/run_analysis.gd` 全部纯函数；现存遥测目录的 `*.summary.json` / `*.events.jsonl` / `*.tick.csv`。
- Produces: stdout 表（每进化 1 行,新旧 verdict 对照）；`<dir>/dominance_report.json`（`{summary, new_flags, old_flags}`）。CLI：`-s res://tools/analyze_dominance.gd -- --dir=<dir> [--report=<path>]`。

- [ ] **Step 1: 写脚本**（新建文件，内容如下完整写入）

```gdscript
# tools/analyze_dominance.gd —— headless: -s res://tools/analyze_dominance.gd -- --dir=telemetry/p2a [--report=...]
# P3 单元2:对现存 solo_* 遥测零重跑重算新支配指标(clear_eff/backlog),打印 新(clear_eff)vs 旧(kpm)verdict 对照。
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
	var new_flags := RA.flag_dominance(summary)
	var old_flags := RA.flag_multi_axis(summary)
	print("evolution,n,reached,clear_eff,clear_dev,backlog,kpm(ctx),hp_min,verdict_new,verdict_old")
	for k in new_flags:
		var s = summary[k]
		var nf = new_flags[k]
		var of = old_flags[k]
		print("%s,%d,%.2f,%.2f,%+.2f,%.0f,%.0f,%.2f,%s,%s" % [
			k, int(s["n"]), float(s["reached_ratio"]), float(s["clear_eff_med"]),
			float(nf["clear_dev"]), float(s["backlog_mean_med"]), float(s["kpm_post_med"]),
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
```

- [ ] **Step 2: 冒烟运行（确认脚本不报解析错、能出表）**

Run: `& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://tools/analyze_dominance.gd -- --dir=telemetry/p2a`
Expected: 打印表头 `evolution,n,reached,clear_eff,...` + 11 行（每 solo 进化一行）；无 push_error；生成 `telemetry/p2a/dominance_report.json`。

- [ ] **Step 3: 提交**

```bash
git add tools/analyze_dominance.gd
git commit -m "feat(p3): analyze_dominance 壳(现存遥测零重跑重算 clear_eff,新旧 verdict 对照)"
```

---

### Task 5: 验证闸 + BACKLOG_FLOOR 标定（单元 2，可证伪）

**Files:**
- Modify: `tools/run_analysis.gd`（仅当验证闸要求时调 `BACKLOG_FLOOR`）
- Create: `docs/reviews/2026-06-20-dominance-criteria-report.md`（§1 验证闸；§2/§3 后续任务填）

**这是测量/验证任务，不是 TDD。** 验证闸是 spec §3 单元 2 的可证伪退出闸。

- [ ] **Step 1: 关编辑器，重算 p2a + p2b_main**

Run（两条）：
```
& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://tools/analyze_dominance.gd -- --dir=telemetry/p2a --report=telemetry/p2a/dominance_report.json
& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://tools/analyze_dominance.gd -- --dir=telemetry/p2b_main --report=telemetry/p2b_main/dominance_report.json
```
Expected: 各打印 11 行 verdict 对照表。

- [ ] **Step 2: 核验证闸（逐条对照 spec §3 ground truth），记录到报告**

把两次 stdout 表拷进报告 §1，**逐条核**：
- **cyclone**：`verdict_new` 不是 weak、`clear_eff` 落跨进化中带（`clear_dev` 接近 0，|dev|<band=0.35）。✅ 锚点。
- **inferno_aura**：`verdict_new` **不是 OP**（旧 `verdict_old` 在 p2b_main 可能是 OP——这正是 kpm 误报，新判据须纠正）。
- **horde(reanimate)**：`verdict_new` **不是 OP**。
- **8 未动进化**（explosion/frostbite/gravity_well/lightning/maul/whip + knife/orb 若 reached=0 标注不可测）：`verdict_new` 与旧 kpm 未污染处一致、在带内。
- **分母地板核查**：报告记下每进化 `backlog`(=backlog_mean_med)。若**有进化 backlog < BACKLOG_FLOOR(5.0)** → 地板被激活、clear_eff 偏置 → 处置见 Step 3。

- [ ] **Step 3: 闸判定与处置**

- **闸通过**（cyclone 中带 + aura/horde 非 OP + 8 在带内 + 无进化命中地板）→ `BACKLOG_FLOOR` 维持 5.0，报告 §1 写「验证闸通过」，进 Step 4。
- **地板被激活**（某进化 backlog < 5.0，多为强清场把场清空）→ 这是预期的「强武器」信号、非错误；报告披露哪些命中地板、其 clear_eff 用了地板值。**仅当 ≥3 个进化命中地板致 clear_eff 区分度塌掉**才回炉：主轴降级为 `backlog_mean_med`（越低越强），改 `flag_dominance` 以 backlog 反向为主判据（clear_eff 转辅证），并补一条对应 TDD（仿 Task 3）。
- **闸失败**（新判据仍把 aura/horde 判 OP，或把 cyclone 判出带）→ **不带病前进**。诊断：看 aura/horde 的 `clear_dev`——若仍 high，说明 backlog 归一不足，试 (a) clear_eff 改用 `enemies_near` 而非 `enemies_alive`（玩家身边密度，对 kite-away 的 aura 更敏感），或 (b) 主轴换 backlog 反向。改后重跑本任务。把失败诊断与最终选型写进报告 §1。

- [ ] **Step 4: 报告骨架落库 + 提交**

新建 `docs/reviews/2026-06-20-dominance-criteria-report.md`，含：标题/定位（承 spec）、§0 一句话、§1 验证闸（两表 + 逐条核验 + 地板核查 + 闸判定）、§2 P2b 悬置 verdict 终判（占位「见 Task 5 Step 5」）、§3 混编 A/B（占位「Task 10」）、§4 退出判据核对（占位）。

- [ ] **Step 5: P2b 悬置 verdict 终判（报告 §2）**

据 §1 通过的新判据，对 P2b 报告 §2/§5 悬置的 verdict 列下终判，逐条写入 §2：
- cyclone：新判据 verdict_new = ?（期望 ok/中带）→ 终判「落带，定稿」。
- inferno_aura：verdict_new = ?（期望非 OP）→ 终判「kpm 779 确为 AoE 假象，clear_eff 下落带/中游，复衡奏效」。
- horde：verdict_new = ?（期望非 OP，或 weak-by-reached）→ 终判「kpm 277 为生存时长假象，非支配」。
- 8 未动进化：一致性结论。

```bash
git add tools/run_analysis.gd docs/reviews/2026-06-20-dominance-criteria-report.md
git commit -m "docs(p3): 验证闸通过 + BACKLOG_FLOOR 标定 + P2b 悬置 verdict 终判"
```

> ⚠ 单元 2 的验证闸是单元 3 的**前置**：闸未过不进混编（否则又是据失真判据测量）。Step 3 回炉分支若触发，先闭环再继续。

---

### Task 6: mix_spec 混编档名解析（单元 3）

**Files:**
- Modify: `tools/run_analysis.gd`（新增 `mix_spec`）
- Test: `tests/test_run_analysis.gd`（末尾追加）

**Interfaces:**
- Produces: `mix_spec(cards_name: String) -> Dictionary` = `{"is_mix": bool, "is_base": bool, "target": String}`。`mixbase`→base；`mix_<wid>`→target=wid；其余→is_mix=false。

- [ ] **Step 1: 写失败测试**（追加末尾）

```gdscript
# ── P3 单元3:混编档名解析 ───────────────────────────────────────────────────
func test_mix_spec_base() -> void:
	var s := RA.mix_spec("mixbase")
	assert_bool(s["is_mix"]).is_true()
	assert_bool(s["is_base"]).is_true()
	assert_str(String(s["target"])).is_equal("")

func test_mix_spec_target() -> void:
	var s := RA.mix_spec("mix_knife")
	assert_bool(s["is_mix"]).is_true()
	assert_bool(s["is_base"]).is_false()
	assert_str(String(s["target"])).is_equal("knife")

func test_mix_spec_non_mix() -> void:
	assert_bool(RA.mix_spec("solo_aura")["is_mix"]).is_false()
	assert_bool(RA.mix_spec("default")["is_mix"]).is_false()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/test_run_analysis.gd`
Expected: 3 新测试 FAIL（`mix_spec` 不存在）。

- [ ] **Step 3: 实现** — 在 `solo_spec` 之后插入：

```gdscript
# 混编档名 → 规格。mixbase=纯底盘(无目标);mix_<wid>=底盘+目标武器。
# {"is_mix": bool, "is_base": bool, "target": String}。供 harness(授武器)与 A/B 分析共用。
static func mix_spec(cards_name: String) -> Dictionary:
	if cards_name == "mixbase":
		return {"is_mix": true, "is_base": true, "target": ""}
	if cards_name.begins_with("mix_"):
		return {"is_mix": true, "is_base": false, "target": cards_name.substr(4)}
	return {"is_mix": false, "is_base": false, "target": ""}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/test_run_analysis.gd`
Expected: 全绿；发现用例数 = **28**（25 + 3）。

- [ ] **Step 5: 提交**

```bash
git add tools/run_analysis.gd tests/test_run_analysis.gd
git commit -m "feat(p3): mix_spec 混编档名解析(mixbase/mix_<wid>)"
```

---

### Task 7: mix_profile 混编选卡优先表（单元 3）

**Files:**
- Modify: `autoloads/run_harness.gd`（加 `MIX_CHASSIS`/`MIX_CHASSIS_PERK_HP_STACKS` 常量 + `mix_profile`）
- Test: `tests/test_run_harness.gd`（末尾追加）

**Interfaces:**
- Consumes: 现有 `SOLO_PERKS` 字典。
- Produces: `RunHarness.mix_profile(target: String, target_evo_perk: String) -> Array`（选卡优先表：目标满级→进化→进化 perk，其次底盘武器，再生存兜底；**不含 `type:weapon`** 故不拿外来武器）；常量 `MIX_CHASSIS: Array`、`MIX_CHASSIS_PERK_HP_STACKS: int`。

> 注：先确认测试文件名。若 `tests/test_run_harness.gd` 不存在，用 `find . -name 'test_run_harness*'` 定位现有 harness 套件（compute_kite_dir/choose_card 的测试所在），把新测试追加到那个文件。

- [ ] **Step 1: 写失败测试**（追加到 harness 测试套件末尾）

```gdscript
# ── P3:混编优先表 ───────────────────────────────────────────────────────────
func test_mix_profile_target_first_then_chassis() -> void:
	var p := RunHarness.mix_profile("knife", "perk_attack")
	# 目标武器及其进化链排在底盘之前
	assert_int(p.find("knife")).is_less(p.find("frostbite"))
	assert_int(p.find("evolve_knife")).is_greater_equal(0)
	assert_int(p.find("perk_attack")).is_greater_equal(0)
	# 不含通用 type:weapon(否则拿外来武器污染混编)
	assert_bool(p.has("type:weapon")).is_false()

func test_mix_profile_base_has_no_target() -> void:
	var p := RunHarness.mix_profile("", "perk_hp")
	assert_bool(p.has("frostbite")).is_true()        # 底盘仍在
	assert_bool(p.has("evolve_")).is_false()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/test_run_harness.gd`（或定位到的文件）
Expected: FAIL（`mix_profile`/`MIX_CHASSIS` 不存在）。

- [ ] **Step 3: 实现** — 在 `run_harness.gd` 的 `FLOOR_PERK_HP_STACKS` 常量附近加：

```gdscript
const MIX_CHASSIS: Array = ["frostbite"]          # 生存底盘武器:控制(slow)、低清场,留 headroom 给目标
const MIX_CHASSIS_PERK_HP_STACKS: int = 5         # 底盘防御垫(A/B 两臂同垫,delta 抵消;让 base 脆武器活到进化)
```

在 `solo_profile` 之后加：

```gdscript
# 混编优先表:目标武器优先(满级→进化→进化 perk),其次底盘武器维护,再生存兜底。
# 不含通用 type:weapon → bot 不拿外来武器,保证「底盘 + 目标」纯净。target=="" 即纯底盘(mixbase)。
static func mix_profile(target: String, target_evo_perk: String) -> Array:
	var p: Array = []
	if target != "":
		p.append_array([target, target + "_2", target + "_3", "evolve_" + target, target_evo_perk])
	for w in MIX_CHASSIS:
		p.append_array([w, w + "_2", w + "_3"])
	p.append_array(["synergy_lifesteal", "perk_hp", "perk_heal", "type:upgrade", "type:synergy", "type:perk"])
	return p
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/test_run_harness.gd`
Expected: 全绿；核对该套件发现用例数 = 原数 + 2。

- [ ] **Step 5: 提交**

```bash
git add autoloads/run_harness.gd tests/test_run_harness.gd
git commit -m "feat(p3): mix_profile 混编优先表 + MIX_CHASSIS 底盘常量"
```

---

### Task 8: 混编授予接线 + banish_weapons_except（单元 3）

**Files:**
- Modify: `autoloads/card_pool.gd`（`banish_other_weapons` 委托新 `banish_weapons_except`）
- Modify: `autoloads/run_harness.gd`（`profile_for` 加 mix 分支；`_grant_solo_weapon`→`_grant_initial_loadout` 分流 solo/mix；`_physics_process` 调用点改名）
- Test: `tests/test_card_pool.gd`（末尾追加 banish 集合测试）

**Interfaces:**
- Consumes: Task 6 `mix_spec`、Task 7 `mix_profile`/`MIX_CHASSIS`/`MIX_CHASSIS_PERK_HP_STACKS`；现有 `CardPool.apply`/`banish`/`_runtime_cards`/`Player.owned_weapons`/`has_weapon`。
- Produces: `CardPool.banish_weapons_except(keep_ids: Array) -> void`；harness 在 mix 档开局授「底盘 + 目标」并 banish 其余武器。

- [ ] **Step 1: 写失败测试**（追加 `tests/test_card_pool.gd` 末尾）

```gdscript
func test_banish_weapons_except_keeps_set() -> void:
	CardPool.reset_run()
	CardPool.banish_weapons_except(["frostbite", "knife"])
	# 保留集内武器不被 ban;集外武器被 ban
	assert_bool(CardPool.is_banished("aura")).is_true()
	assert_bool(CardPool.is_banished("frostbite")).is_false()
	assert_bool(CardPool.is_banished("knife")).is_false()
```

> 若 `CardPool` 无 `is_banished()` 读取器，本步同时加一个：`func is_banished(id: String) -> bool: return _banished.get(id, false)`（在 `banish()` 附近），并把它纳入本任务提交。

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/test_card_pool.gd`
Expected: FAIL（`banish_weapons_except` 不存在）。

- [ ] **Step 3: 实现 card_pool** — 把 `banish_other_weapons` 替换为委托 + 新方法：

```gdscript
# solo 隔离:banish 掉除 keep_id 外的全部 base 武器卡(委托集合版)。
func banish_other_weapons(keep_id: String) -> void:
	banish_weapons_except([keep_id])

# 混编隔离:banish 掉 keep_ids 之外的全部 base 武器卡,使 pick() 永不提供外来武器。
func banish_weapons_except(keep_ids: Array) -> void:
	for card in _runtime_cards:
		if String(card.get("type", "")) == "weapon" and not keep_ids.has(String(card["id"])):
			banish(String(card["id"]))
```

（如 Step 1 需要，加 `func is_banished(id: String) -> bool: return _banished.get(id, false)`。）

- [ ] **Step 4: 跑 card_pool 测试确认通过**

Run: `... -a res://tests/test_card_pool.gd`
Expected: 全绿；`test_banish_other_weapons_*`（若存在）仍绿（委托不改行为）。

- [ ] **Step 5: 实现 harness 接线** — `profile_for` 替换为：

```gdscript
static func profile_for(name: String) -> Array:
	var spec := solo_spec(name)
	if spec["is_solo"]:
		var wid: String = spec["weapon_id"]
		return solo_profile(wid, String(SOLO_PERKS.get(wid, "perk_hp")))
	var mspec := RunAnalysis.mix_spec(name)
	if mspec["is_mix"]:
		var t: String = mspec["target"]
		return mix_profile(t, String(SOLO_PERKS.get(t, "perk_hp")))
	return PROFILES.get(name, DEFAULT_PROFILE)
```

`_physics_process` 里的授予门 `_solo_weapon_granted` 调用点改名（保持变量名亦可，仅函数改名）：

```gdscript
	if not _solo_weapon_granted:
		_solo_weapon_granted = true
		_grant_initial_loadout(p)
```

把 `_grant_solo_weapon` 重命名为 `_grant_initial_loadout` 并分流（solo 体保持原样移入 `_grant_solo`）：

```gdscript
func _grant_initial_loadout(p: Player) -> void:
	var spec := solo_spec(_cards_name_val)
	if spec["is_solo"]:
		_grant_solo(p, spec)
		return
	var mspec := RunAnalysis.mix_spec(_cards_name_val)
	if mspec["is_mix"]:
		_grant_mix(p, mspec)

# 原 _grant_solo_weapon 函数体原样搬入(spec 参数已算好,省去重复 solo_spec)。
func _grant_solo(p: Player, spec: Dictionary) -> void:
	var wid: String = spec["weapon_id"]
	if wid == "" or p == null:
		return
	for owned_id in p.owned_weapons.keys():
		if owned_id != wid:
			var node = p.owned_weapons[owned_id].get("node")
			if is_instance_valid(node):
				node.queue_free()
			p.owned_weapons.erase(owned_id)
	if not p.has_weapon(wid):
		CardPool.apply({"id": wid}, p)
	CardPool.banish_other_weapons(wid)
	if spec["is_floor"]:
		for _i in range(FLOOR_PERK_HP_STACKS):
			CardPool.apply({"id": "perk_hp"}, p)

# 混编:授「底盘 + 目标」,banish 其余武器,底盘授防御垫(A/B 两臂同垫)。
func _grant_mix(p: Player, mspec: Dictionary) -> void:
	if p == null:
		return
	var target: String = mspec["target"]
	var loadout := MIX_CHASSIS.duplicate()
	if target != "" and not loadout.has(target):
		loadout.append(target)
	for owned_id in p.owned_weapons.keys():
		if not loadout.has(owned_id):
			var node = p.owned_weapons[owned_id].get("node")
			if is_instance_valid(node):
				node.queue_free()
			p.owned_weapons.erase(owned_id)
	for wid in loadout:
		if not p.has_weapon(wid):
			CardPool.apply({"id": wid}, p)
	CardPool.banish_weapons_except(loadout)
	for _i in range(MIX_CHASSIS_PERK_HP_STACKS):
		CardPool.apply({"id": "perk_hp"}, p)
```

- [ ] **Step 6: 全量 gdUnit 回归（确认接线未破坏既有）**

Run: `& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: 全绿；核对发现总用例数 = **527 基线 + 本分支累计新增（Task1:+4, T2:+1, T3:+3, T6:+3, T7:+2, T8:+1 = +14）= 541**。若数字不符 → 截断陷阱，排查（C6）。

- [ ] **Step 7: 提交**

```bash
git add autoloads/card_pool.gd autoloads/run_harness.gd tests/test_card_pool.gd
git commit -m "feat(p3): 混编授予接线(_grant_mix 底盘+目标)+banish_weapons_except 集合隔离"
```

---

### Task 9: 底盘标定冒烟（单元 3，窄缝验证）

**Files:** 无代码改动（纯冒烟测量）；若标定不过则改 `run_harness.gd` 的 `MIX_CHASSIS`/`MIX_CHASSIS_PERK_HP_STACKS`。

**目的：** 验证底盘满足两条硬约束——① 让 knife/orb **活到各自 t_evo**；② **不自身清空场地**（留 headroom 给目标，否则 A/B delta 被掩盖）。这是 spec §6 标的「窄缝」风险。

- [ ] **Step 1: 关编辑器，单种子三跑冒烟**

Run（seed 7）：
```
& $Godot --headless --fixed-fps 60 --path D:\Workspace\GAME\game_0_vsl -- --bot=kite --cards=mixbase    --seed=7 --fast=8 --maxtime=600 --out=telemetry/p3_smoke/mixbase_s7
& $Godot --headless --fixed-fps 60 --path D:\Workspace\GAME\game_0_vsl -- --bot=kite --cards=mix_knife --seed=7 --fast=8 --maxtime=600 --out=telemetry/p3_smoke/mix_knife_s7
& $Godot --headless --fixed-fps 60 --path D:\Workspace\GAME\game_0_vsl -- --bot=kite --cards=mix_orb   --seed=7 --fast=8 --maxtime=600 --out=telemetry/p3_smoke/mix_orb_s7
```
Expected: 各自打印 `[RunHarness] bot=kite cards=mix... ` 起始行 + `[RunHarness] 终局=...`。

- [ ] **Step 2: 核约束①——目标可达进化**

检查 `telemetry/p3_smoke/mix_knife_s7.events.jsonl` 含 `{"type":"level_up",...,"picked":"evolve_knife"}`、`mix_orb_s7.events.jsonl` 含 `picked":"evolve_orb"`。
- 都含 → 约束① 过。
- 缺 → 底盘续航不足或目标进化 perk 没堆够。提高 `MIX_CHASSIS_PERK_HP_STACKS`（如 7），或在 `MIX_CHASSIS` 加第二件保命武器（如 `aura`），重跑 Step 1。**注意**:加 aura 会抬底盘清场，需 Step 3 复核约束②。

- [ ] **Step 3: 核约束②——底盘留 headroom（不自身清场）**

看 `telemetry/p3_smoke/mixbase_s7.tick.csv` 后期（t>200s）`enemies_alive` 列:应**显著 > 0**（如 ≥30,表示底盘没清空场地、有敌可供目标清）。
- 若 mixbase 后期 `enemies_alive` 也大（场地满）→ 好,有 headroom。
- 若 mixbase 后期 `enemies_alive` ≈ 0（底盘自己清空了场地）→ 底盘清场太强,A/B delta 会被地板掩盖。换更弱清场的底盘（如 frostbite 不升级,或只留控制不留输出),重跑。

- [ ] **Step 4: 标定结论入报告 §3 前言 + 提交（若改了常量）**

把最终底盘配置（MIX_CHASSIS、perk_hp 层数）、两约束的冒烟证据写进报告 §3 前言。
```bash
# 仅当 Step 2/3 触发了常量改动:
git add autoloads/run_harness.gd docs/reviews/2026-06-20-dominance-criteria-report.md
git commit -m "chore(p3): 底盘标定(MIX_CHASSIS 满足可达+headroom 双约束)"
```

> ⚠ 若 knife/orb 即便加保命底盘仍够不到进化（同 P2b §4 base 太脆）：**披露**该结论，A/B 改测「能到的种子子集」并在报告标注 n；把「base Act1 可达性」记为内容广度阶段问题（非进化平衡），不在本 plan 解决。

---

### Task 10: A/B 边际归因 campaign + 分析 + 终判（单元 3）

**Files:**
- Create: `tools/run_p3_mix_campaign.ps1`
- Create: `tools/analyze_mix_ab.gd`
- Modify: `docs/reviews/2026-06-20-dominance-criteria-report.md`（§3 混编 A/B 终判）

**Interfaces:**
- Consumes: `run_analysis.gd`（`mix_spec`/`evolution_unlock_time`/`window_rows`/`window_metrics`/`median`）；campaign 产出的 `mixbase_s*` / `mix_<t>_s*` 遥测。
- Produces: 每目标的 `clear_eff(mix)` / `clear_eff(mixbase 同窗)` / **delta（边际支配）** / reached / hp_min；含 **explosion 控制组** 作均衡参照。

> A/B 设计：同种子下，目标进化窗 `[t_evo, end]`（t_evo 取自 `mix_<target>`）内，比 `mix_<target>` 与 `mixbase` 的 clear_eff。`delta = mix − mixbase` = 目标进化在该窗的**边际清场支配**。**explosion**（solo 中带、必达进化）作控制：`delta_target` 显著 > `delta_explosion` ⇒ 目标进化「绕冷却/超额」支配嫌疑。

- [ ] **Step 1: 写 campaign 脚本**（新建 `tools/run_p3_mix_campaign.ps1`）

```powershell
# tools/run_p3_mix_campaign.ps1 — P3 混编 A/B:mixbase 基线 + 目标(knife/orb)+ explosion 控制组。
# 跑前先关编辑器(LimboAI 双实例陷阱)。
param(
	[string]$Godot = "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe",
	[string]$Proj = "D:\Workspace\GAME\game_0_vsl",
	[int[]]$Seeds = @(7, 42, 101, 1, 2, 3, 4, 5),
	[string[]]$Targets = @("knife", "orb", "explosion"),
	[double]$MaxTime = 600,
	[double]$Fast = 8,
	[string]$OutDir = "telemetry/p3_mix"
)
# 基线:纯底盘
foreach ($s in $Seeds) {
	$out = "$OutDir/mixbase_s${s}"
	Write-Host "[P3-mix] mixbase seed=$s"
	& $Godot --headless --fixed-fps 60 --path $Proj -- --bot=kite --cards=mixbase --seed=$s --fast=$Fast --maxtime=$MaxTime --out=$out
}
# 处理组:底盘 + 目标
foreach ($t in $Targets) {
	foreach ($s in $Seeds) {
		$out = "$OutDir/mix_${t}_s${s}"
		Write-Host "[P3-mix] mix_$t seed=$s"
		& $Godot --headless --fixed-fps 60 --path $Proj -- --bot=kite --cards=mix_$t --seed=$s --fast=$Fast --maxtime=$MaxTime --out=$out
	}
}
Write-Host "[P3-mix] campaign 完成。A/B 分析:"
& $Godot --headless --path $Proj -s res://tools/analyze_mix_ab.gd -- --dir=$OutDir
```

- [ ] **Step 2: 写 A/B 分析脚本**（新建 `tools/analyze_mix_ab.gd`）

```gdscript
# tools/analyze_mix_ab.gd —— headless: -s res://tools/analyze_mix_ab.gd -- --dir=telemetry/p3_mix
# P3 单元3:A/B 边际归因。对每 mix_<target>,取其进化窗 [t_evo,end],比同种子 mixbase 同窗 clear_eff,出 delta。
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
	# 按 (kind, target, seed) 归档 summary 文件名 base
	var runs := {}   # "<cards>_s<seed>" → base
	for fn in d.get_files():
		if fn.ends_with(".summary.json"):
			runs[fn.replace(".summary.json", "")] = true
	# 收集目标集
	var targets := {}
	for base in runs:
		var ms := RA.mix_spec(_cards_of(abs_dir, base))
		if ms["is_mix"] and not ms["is_base"]:
			targets[String(ms["target"])] = true
	print("target,n_reached,clear_eff_mix_med,clear_eff_base_med,delta_med,hp_min_med,reached")
	var report := {}
	for t in targets:
		var deltas: Array = []
		var mixv: Array = []
		var basev: Array = []
		var hpv: Array = []
		var reached := 0
		var total := 0
		for base in runs:
			if not base.begins_with("mix_%s_s" % t):
				continue
			total += 1
			var seed_tag := base.substr(base.rfind("_s"))   # "_s7"
			var base_run := "mixbase" + seed_tag
			if not runs.has(base_run):
				continue
			var ev := RA.events_from_jsonl(FileAccess.get_file_as_string(abs_dir.path_join(base + ".events.jsonl")))
			var t_evo := RA.evolution_unlock_time(ev, t)
			if t_evo < 0.0:
				continue   # 该种子目标没进化,不计入(reached 另计)
			reached += 1
			var ce_mix := _clear_eff_in_window(abs_dir, base, t_evo)
			var ce_base := _clear_eff_in_window(abs_dir, base_run, t_evo)
			mixv.append(ce_mix)
			basev.append(ce_base)
			deltas.append(ce_mix - ce_base)
			hpv.append(_hp_min_in_window(abs_dir, base, t_evo))
		var row := {
			"n_reached": reached,
			"clear_eff_mix_med": RA.median(mixv),
			"clear_eff_base_med": RA.median(basev),
			"delta_med": RA.median(deltas),
			"hp_min_med": RA.median(hpv),
			"reached": float(reached) / float(maxi(total, 1)),
		}
		report[t] = row
		print("%s,%d,%.2f,%.2f,%+.2f,%.2f,%.2f" % [t, reached, row["clear_eff_mix_med"],
			row["clear_eff_base_med"], row["delta_med"], row["hp_min_med"], row["reached"]])
	var f := FileAccess.open(_res(dir_rel + "/mix_ab_report.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	quit()

func _cards_of(abs_dir: String, base: String) -> String:
	var su = JSON.parse_string(FileAccess.get_file_as_string(abs_dir.path_join(base + ".summary.json")))
	return String(su.get("config", {}).get("cards", "")) if typeof(su) == TYPE_DICTIONARY else ""

func _clear_eff_in_window(abs_dir: String, base: String, t_evo: float) -> float:
	var su = JSON.parse_string(FileAccess.get_file_as_string(abs_dir.path_join(base + ".summary.json")))
	var t_end := float(su.get("survived_s", 0.0)) if typeof(su) == TYPE_DICTIONARY else 0.0
	var ticks := RA.tick_rows_from_csv(FileAccess.get_file_as_string(abs_dir.path_join(base + ".tick.csv")))
	var win := RA.window_rows(ticks, t_evo)
	return float(RA.window_metrics(win, t_evo, t_end, "").get("clear_eff", 0.0))

func _hp_min_in_window(abs_dir: String, base: String, t_evo: float) -> float:
	var su = JSON.parse_string(FileAccess.get_file_as_string(abs_dir.path_join(base + ".summary.json")))
	var t_end := float(su.get("survived_s", 0.0)) if typeof(su) == TYPE_DICTIONARY else 0.0
	var ticks := RA.tick_rows_from_csv(FileAccess.get_file_as_string(abs_dir.path_join(base + ".tick.csv")))
	var win := RA.window_rows(ticks, t_evo)
	return float(RA.window_metrics(win, t_evo, t_end, "").get("hp_min_post", 1.0))

func _parse(args: Array) -> Dictionary:
	var cfg := {}
	for raw in args:
		var a := String(raw)
		if a.begins_with("--dir="):
			cfg["dir"] = a.split("=")[1]
	return cfg

func _res(p: String) -> String:
	return p if (p.begins_with("res://") or p.begins_with("user://")) else "res://" + p
```

- [ ] **Step 3: 冒烟 A/B 分析脚本（用 Task 9 的 p3_smoke 单种子，先验脚本不崩）**

Run: `& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://tools/analyze_mix_ab.gd -- --dir=telemetry/p3_smoke`
Expected: 打印表头 + knife/orb 行（单种子,n_reached≤1）；无 push_error。修脚本至跑通。

- [ ] **Step 4: 跑全 A/B campaign（关编辑器；约 24 局 ×≤600s/fast8，留足时间）**

Run: `& D:\Workspace\GAME\game_0_vsl\... ` →
```
pwsh -File D:\Workspace\GAME\game_0_vsl\tools\run_p3_mix_campaign.ps1
```
Expected: 逐局 `[P3-mix] ...` 日志；末尾 A/B 表（knife/orb/explosion 三行）。

- [ ] **Step 5: 终判写报告 §3**

据 A/B 表对每目标下终判：
- **reached**：knife/orb 在混编下的 reached（对比 P2b 地板档 0.25/0.13）。若仍低 → 披露 n + 记 base 可达性（Task 9 ⚠）。
- **thousand_edge(knife)「绕冷却 OP」假说**：`delta_med(knife)` vs `delta_med(explosion)` 控制。delta_knife 显著高（如 > explosion 的 1.35×）+ 安全非劣 → **OP-suspect → 记 P3b 输入**；否则 → **假说证伪,均衡**。
- **mega_orb(orb)**：同法对 delta_orb 判定。
- 明确：**本轮不调数值**；任何 OP-suspect 记 P3b。

- [ ] **Step 6: 提交**

```bash
git add tools/run_p3_mix_campaign.ps1 tools/analyze_mix_ab.gd docs/reviews/2026-06-20-dominance-criteria-report.md
git commit -m "feat(p3): 混编 A/B 边际归因(campaign+analyze_mix_ab)+thousand_edge/mega_orb 终判"
```

---

### Task 11: 全量验证 + 确定性 + 报告定稿（退出判据）

**Files:**
- Modify: `docs/reviews/2026-06-20-dominance-criteria-report.md`（§4 退出判据核对 + §0 一句话定稿）

- [ ] **Step 1: 全量 gdUnit 绿 + 用例数核对（C6）**

Run: `& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: 全绿；发现总用例数 = **541**（527 + 14；与 Task 8 Step 6 一致，无新增测试任务在 8 之后）。数字不符 → 截断排查。

- [ ] **Step 2: C5 确定性——现存重算逐值复现**

Run（同一目录跑两次 analyze_dominance，比对报告 json）：
```
& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://tools/analyze_dominance.gd -- --dir=telemetry/p2a --report=telemetry/p2a/dom_a.json
& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://tools/analyze_dominance.gd -- --dir=telemetry/p2a --report=telemetry/p2a/dom_b.json
```
比对：`Compare-Object (Get-Content telemetry/p2a/dom_a.json) (Get-Content telemetry/p2a/dom_b.json)`
Expected: 无差异（纯离线重算无随机 → 逐字节一致）。

- [ ] **Step 3: C5 确定性——混编同种子聚合稳定**

Run（mix_knife seed 7 两跑，比 summary 聚合）：
```
& $Godot --headless --fixed-fps 60 --path D:\Workspace\GAME\game_0_vsl -- --bot=kite --cards=mix_knife --seed=7 --fast=8 --maxtime=600 --out=telemetry/p3_det/a
& $Godot --headless --fixed-fps 60 --path D:\Workspace\GAME\game_0_vsl -- --bot=kite --cards=mix_knife --seed=7 --fast=8 --maxtime=600 --out=telemetry/p3_det/b
```
比对 summary 的 outcome/final_level/kills（后期有界不确定按 P2b 用户裁决，要求**聚合等价**非逐字节）。Expected: outcome 同、final_level 同、kills 接近（差异 < 噪声）。把结论写报告。

- [ ] **Step 4: 报告 §4 退出判据核对 + §0 定稿**

照 spec §4 六条退出判据逐条核对填表（判据实装+TDD绿 / 验证闸通过 / P2b 悬置终判 / thousand_edge·mega_orb 终判 / 全量绿+C6+C5 / 后衡报告 + P3b 输入清单）。写 §0 一句话结论。

- [ ] **Step 5: 提交**

```bash
git add docs/reviews/2026-06-20-dominance-criteria-report.md
git commit -m "docs(p3): 退出判据核对 + C5 确定性 + 报告定稿(判据闭环完成)"
```

- [ ] **Step 6: 完成分支处置**

调用 `superpowers:finishing-a-development-branch` 决定合并方式（对齐 P2a/P2b：FF 合并 master + 删分支）。

---

## Self-Review

**1. Spec 覆盖**（逐条对 spec）：
- spec §3 单元1（判据改进）→ Task 1/2/3 ✅
- spec §3 单元2（验证闸+重算报告，零重跑）→ Task 4/5 ✅
- spec §3 单元3（真混编 A/B）→ Task 6/7/8/9/10 ✅
- spec §4 退出判据 6 条 → Task 11 Step 4 逐条核对 ✅
- spec §6 风险（分母地板/chassis 窄缝/闸失败/截断/确定性）→ Task 5 Step 3、Task 9、Task 8 Step 6、Task 11 ✅
- spec §5 范围边界（不调数值，OP→P3b）→ Global Constraints + Task 10 Step 5 ✅

**2. Placeholder 扫描**：无 TBD/TODO；报告分节占位是「执行时按实测填」的产物章节，非计划缺口（每节有明确填充指令与判据）。BACKLOG_FLOOR=5.0 与 MIX_CHASSIS 是显式初值 + 标定步骤（Task 5/9），非占位。

**3. 类型一致性**：`clear_eff`/`backlog_mean`/`t_evo`（metrics dict，Task1）→ `clear_eff_med`/`backlog_mean_med`/`t_evo_med`（summarize，Task2）→ `flag_dominance` 读 `clear_eff_med`/`backlog_mean_med` 出 `clear_dev`/`backlog_dev`（Task3）一致；`mix_spec` 返回 `{is_mix,is_base,target}`（Task6）被 `profile_for`/`_grant_mix`（Task8）与 `analyze_mix_ab`（Task10）一致消费；`banish_weapons_except(keep_ids)`（Task8）被 `_grant_mix`/`banish_other_weapons` 一致调用。✅
