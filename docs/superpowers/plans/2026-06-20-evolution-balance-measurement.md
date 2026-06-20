# P2a · 进化平衡测量与诊断 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: 用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现本计划。步骤用 `- [ ]` 复选框跟踪。

**Goal:** 不动任何游戏数值，只补「solo 隔离闸」+「进化窗口分段 + 多轴判据」分析层，跑 11 进化 × 8 种子 campaign，产出数据背书的进化支配性报告（= P2b 复衡 spec 的输入）。

**Architecture:** 两块改动。① **harness 隔离闸**（`card_pool.gd` 加 `banish_other_weapons` + `run_harness.gd` 一行接线）让 solo build 纯净。② **分析层**（`run_analysis.gd` 纯函数核加窗口分段/多轴判据 + 新 IO 壳 `analyze_evolutions.gd`）。全程 TDD，纯函数先红后绿；campaign 跑既有 dodge 探针管线。**零游戏平衡改动。**

**Tech Stack:** Godot 4.7 / GDScript / gdUnit4（headless）/ PowerShell（批跑）。

## Global Constraints

- **上位 spec:** [docs/superpowers/specs/2026-06-20-evolution-balance-measurement-design.md](../specs/2026-06-20-evolution-balance-measurement-design.md)（本计划实现其全部组件）。
- **测试命令**（单套件，PowerShell）：
  ```
  & "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_run_analysis.gd
  ```
  末尾 `-a res://tests/<file>.gd` 换套件，`-a res://tests` 跑全量。
- **`--ignoreHeadlessMode` 必加**，否则 gdUnit abort 退出码 103。
- **gdUnit 截断陷阱**：某测试解析/脚本错误会**静默截断**其后测试发现。每次跑完**核对发现用例数**（Task 0 记录基线），不能只看"全绿"；总数不升反降 → 有解析错误先修。新增测试排套件**末尾**。
- **确定性（C5）**：分析层全是纯函数，无 RNG/时间依赖。campaign 用 `--fixed-fps 60`（**非** `--fast`）。隔离闸只改 bot solo 路径，真人/默认档不受影响。
- **零游戏平衡改动**：本计划不碰任何 `.tres` 数值、不改武器/状态逻辑。复衡是 P2b。
- **注释/文案一律简体中文**（全仓库约定）。
- **跑 campaign / headless 前先关编辑器**（CLAUDE.md LimboAI 双实例陷阱）。
- **提交规范**：conventional commits；agent 执行追加 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer。**只 `git add` 本任务明确列出的文件，禁止 `git add -A`**（仓库有大量预存未追踪文件 + telemetry 输出，收录是用户决策）。**telemetry/ 输出不提交。**

---

## Task 0: 建分支 + 记录基线用例数

当前在 `master`，先开特性分支。

- [ ] **Step 1: 建并切到特性分支**

```
git checkout -b feat/p2a-evolution-measurement
```

- [ ] **Step 2: 跑全量基线，记录用例总数**

Run:
```
& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: 全绿；**记下用例总数 `BASELINE`**（后续每加一批测试，总数应只增不减）。

---

## Task 1: `CardPool.banish_other_weapons()` — solo 隔离闸

**Files:**
- Modify: `autoloads/card_pool.gd`（`banish()` 下方新增 `banish_other_weapons()`）
- Test: `tests/test_card_pool.gd`（文件末尾追加）

**Interfaces:**
- Consumes: 现有 `_runtime_cards`、`banish()`。
- Produces: `CardPool.banish_other_weapons(keep_id: String) -> void` —— banish 掉除 `keep_id` 外的全部 `type=="weapon"` 卡。

- [ ] **Step 1: 写失败测试**（追加到 `tests/test_card_pool.gd` 末尾）

```gdscript
# ── P2a 单元:solo 隔离闸 ──────────────────────────────────────────────────
func test_banish_other_weapons_excludes_foreign() -> void:
	CardPool.reset_run()
	CardPool.banish_other_weapons("explosion")
	var cards := CardPool.pick(_player, 99)
	for c in cards:
		if String(c.get("type", "")) == "weapon":
			assert_str(String(c["id"])).is_equal("explosion")
	CardPool.reset_run()

func test_banish_other_weapons_keeps_target_offerable() -> void:
	CardPool.reset_run()
	CardPool.banish_other_weapons("explosion")
	var cards := CardPool.pick(_player, 99)  # explosion 未持有 → 仍应可被提供
	var found := false
	for c in cards:
		if String(c["id"]) == "explosion":
			found = true
	assert_bool(found).is_true()
	CardPool.reset_run()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_card_pool.gd`
Expected: FAIL —— `Invalid call. Nonexistent function 'banish_other_weapons'`。

- [ ] **Step 3: 实现**（在 `card_pool.gd` 的 `func banish(` / `func reset_run(` 附近插入）

```gdscript
# solo 隔离:banish 掉除 keep_id 外的全部 base 武器卡,使 pick() 永不提供外来武器。
# 外来武器被 ban → 永不 owned → 其升级(upgrade:<w>)永不就绪 → solo build 纯净。
# 目标武器/升级/perk/目标进化不受影响。仅 RunHarness solo 路径调用。
func banish_other_weapons(keep_id: String) -> void:
	for card in _runtime_cards:
		if String(card.get("type", "")) == "weapon" and String(card["id"]) != keep_id:
			banish(String(card["id"]))
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_card_pool.gd`
Expected: PASS —— 全绿，总用例数 = 原 + 2。

- [ ] **Step 5: 提交**

```
git add autoloads/card_pool.gd tests/test_card_pool.gd
git commit -m "feat(cardpool): banish_other_weapons 解决 solo 隔离泄漏(外来武器不进池)"
```

---

## Task 2: 接线进 `RunHarness._grant_solo_weapon` + 实跑验证纯净

**Files:**
- Modify: `autoloads/run_harness.gd`（`_grant_solo_weapon()` 末尾加一行）

**Interfaces:**
- Consumes: `CardPool.banish_other_weapons()`（Task 1）。
- Produces: solo 档实跑的 build **不含外来武器**。

> 本任务交付物 = 「solo run 产出纯净 build」,由真实跑验证(非 gdUnit;`_grant_solo_weapon` 私有且依赖完整场景)。

- [ ] **Step 1: 实现**（改 `run_harness.gd` 的 `_grant_solo_weapon`，[L246](../../../autoloads/run_harness.gd#L246)）

把：
```gdscript
	CardPool.apply({"id": wid}, p)
```
改为：
```gdscript
	CardPool.apply({"id": wid}, p)
	CardPool.banish_other_weapons(wid)   # solo 隔离:外来武器永不进池(防 choose_card offered[0] 兜底污染)
```

- [ ] **Step 2: 关编辑器，实跑一发 solo_explosion 验证纯净**

Run（PowerShell）:
```
& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --fixed-fps 60 --path "D:\Workspace\GAME\game_0_vsl" -- --bot=kite --cards=solo_explosion --seed=7 --fast=8 --maxtime=600 --out=telemetry/p2a_smoke/solo_explosion_s7
```
Expected: `[RunHarness] 终局=victory` 或 `death`，正常退出。

- [ ] **Step 3: 核对 build 无外来武器**

读 `telemetry/p2a_smoke/solo_explosion_s7.summary.json` 的 `build`。
Expected: build 里**不含** `knife`/`gravity_well`/`boomerang` 等**外来 base 武器**（`knife_2/_3` 等升级也不应出现，因外来武器未持有）；应含 `explosion_2`/`explosion_3`/`evolve_explosion` + perk/synergy。
> 对照 Task 0 前的 `telemetry/p2a_probe/solo_explosion_s7.summary.json`（混进了 knife_3/gravity_well_3）——本次应纯净。

- [ ] **Step 4: 提交**

```
git add autoloads/run_harness.gd
git commit -m "feat(bot): solo 档开局隔离外来武器,build 纯净(per-evolution 数据有效)"
```

---

## Task 3: tick/events 纯解析函数

**Files:**
- Modify: `tools/run_analysis.gd`（新增两个纯静态解析函数）
- Test: `tests/test_run_analysis.gd`（末尾追加）

**Interfaces:**
- Produces:
  - `RA.tick_rows_from_csv(text: String) -> Array` —— CSV 文本 → 行字典数组（键=表头列名，值=字符串）。
  - `RA.events_from_jsonl(text: String) -> Array` —— JSONL 文本 → 字典数组。

- [ ] **Step 1: 写失败测试**（追加末尾）

```gdscript
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_run_analysis.gd`
Expected: FAIL —— `Nonexistent function 'tick_rows_from_csv'`。

- [ ] **Step 3: 实现**（在 `run_analysis.gd` 的 `median()` 上方或文件靠前处插入）

```gdscript
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

# 解析 events JSONL 文本为字典数组(逐行 JSON.parse,跳过非字典行)。
static func events_from_jsonl(text: String) -> Array:
	var out: Array = []
	for line in text.split("\n", false):
		var v = JSON.parse_string(line)
		if typeof(v) == TYPE_DICTIONARY:
			out.append(v)
	return out
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_run_analysis.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```
git add tools/run_analysis.gd tests/test_run_analysis.gd
git commit -m "feat(analysis): tick CSV / events JSONL 纯解析函数(供窗口分段)"
```

---

## Task 4: 进化解锁时刻 + 窗口切分

**Files:**
- Modify: `tools/run_analysis.gd`
- Test: `tests/test_run_analysis.gd`

**Interfaces:**
- Produces:
  - `RA.evolution_unlock_time(events: Array, weapon_id: String) -> float` —— 首个 `picked=="evolve_"+weapon_id` 的 level_up 的 `t`；无 → `-1.0`。
  - `RA.window_rows(tick_rows: Array, t_evo: float) -> Array` —— `t >= t_evo` 的行；`t_evo<0` → `[]`。

- [ ] **Step 1: 写失败测试**（追加末尾）

```gdscript
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_run_analysis.gd`
Expected: FAIL —— `Nonexistent function 'evolution_unlock_time'`。

- [ ] **Step 3: 实现**（追加到 `run_analysis.gd`）

```gdscript
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_run_analysis.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```
git add tools/run_analysis.gd tests/test_run_analysis.gd
git commit -m "feat(analysis): evolution_unlock_time + window_rows 进化窗口切分"
```

---

## Task 5: 后期窗口三轴度量

**Files:**
- Modify: `tools/run_analysis.gd`
- Test: `tests/test_run_analysis.gd`

**Interfaces:**
- Consumes: `window_rows()`（Task 4）。
- Produces: `RA.window_metrics(win_rows: Array, t_evo: float, t_end: float, outcome: String) -> Dictionary`
  —— 键：`reached_evolution`(bool)、`kpm_post`、`hp_min_post`、`danger_mean_post`、`survived_post`、`outcome`。

- [ ] **Step 1: 写失败测试**（追加末尾）

```gdscript
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_run_analysis.gd`
Expected: FAIL —— `Nonexistent function 'window_metrics'`。

- [ ] **Step 3: 实现**（追加到 `run_analysis.gd`）

```gdscript
# 后期窗口三轴度量。win_rows 空(未达进化)→ reached_evolution=false。
# kpm_post = 窗口内 kills_total 增量 / 窗口时长 × 60；hp_min_post = 窗口内 hp_pct 最小；
# danger_mean_post = 窗口内 danger_ps 均值；survived_post = t_end - t_evo。
static func window_metrics(win_rows: Array, t_evo: float, t_end: float, outcome: String) -> Dictionary:
	if win_rows.is_empty():
		return {"reached_evolution": false, "kpm_post": 0.0, "hp_min_post": 0.0,
				"danger_mean_post": 0.0, "survived_post": 0.0, "outcome": outcome}
	var k0 := float(win_rows[0].get("kills_total", 0))
	var k1 := float(win_rows[win_rows.size() - 1].get("kills_total", 0))
	var win_dur := maxf(t_end - t_evo, 0.001)
	var hp_min := 1.0
	var danger_sum := 0.0
	for row in win_rows:
		hp_min = minf(hp_min, float(row.get("hp_pct", 1.0)))
		danger_sum += float(row.get("danger_ps", 0.0))
	return {
		"reached_evolution": true,
		"kpm_post": (k1 - k0) / win_dur * 60.0,
		"hp_min_post": hp_min,
		"danger_mean_post": danger_sum / win_rows.size(),
		"survived_post": win_dur,
		"outcome": outcome,
	}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_run_analysis.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```
git add tools/run_analysis.gd tests/test_run_analysis.gd
git commit -m "feat(analysis): window_metrics 后期窗口三轴(kpm/hp_min/danger/survived)"
```

---

## Task 6: 跨种子聚合 + 多轴判据

**Files:**
- Modify: `tools/run_analysis.gd`
- Test: `tests/test_run_analysis.gd`

**Interfaces:**
- Consumes: `median()`、`window_metrics()` 输出。
- Produces:
  - `RA.summarize_evolution(metrics_list: Array) -> Dictionary` —— 键：`n`、`reached_ratio`、`death_ratio`、`kpm_post_med`、`hp_min_post_med`、`survived_post_med`（中位仅对已达进化的 run 算）。
  - `RA.flag_multi_axis(by_evo: Dictionary, band: float = 0.35) -> Dictionary` —— 每进化：`verdict`(OP/weak/ok) + 三轴值/verdict/效应量 + reached/death 比例。

- [ ] **Step 1: 写失败测试**（追加末尾）

```gdscript
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_run_analysis.gd`
Expected: FAIL —— `Nonexistent function 'summarize_evolution'`。

- [ ] **Step 3: 实现**（追加到 `run_analysis.gd`）

```gdscript
# 聚合一个进化的多 run 窗口度量:三数值轴取中位(仅对已达进化的 run),reached/death 取比例。
static func summarize_evolution(metrics_list: Array) -> Dictionary:
	var n := metrics_list.size()
	var kpm: Array = []
	var hpmin: Array = []
	var surv: Array = []
	var reached_count := 0
	var death_count := 0
	for m in metrics_list:
		if bool(m.get("reached_evolution", false)):
			reached_count += 1
			kpm.append(float(m.get("kpm_post", 0.0)))
			hpmin.append(float(m.get("hp_min_post", 0.0)))
			surv.append(float(m.get("survived_post", 0.0)))
		if String(m.get("outcome", "")) == "death":
			death_count += 1
	return {
		"n": n,
		"reached_ratio": float(reached_count) / float(maxi(n, 1)),
		"death_ratio": float(death_count) / float(maxi(n, 1)),
		"kpm_post_med": median(kpm),
		"hp_min_post_med": median(hpmin),
		"survived_post_med": median(surv),
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_run_analysis.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```
git add tools/run_analysis.gd tests/test_run_analysis.gd
git commit -m "feat(analysis): summarize_evolution + flag_multi_axis 多轴透明判据"
```

---

## Task 7: `analyze_evolutions.gd` IO 壳 + 实数据验证

**Files:**
- Create: `tools/analyze_evolutions.gd`
- 验证数据：`telemetry/p2a_smoke/`（Task 2 产出）

**Interfaces:**
- Consumes: `RA.events_from_jsonl/tick_rows_from_csv/evolution_unlock_time/window_rows/window_metrics/summarize_evolution/flag_multi_axis`。
- Produces: 读 `--dir` 下全部 `solo_*` run 的 summary+tick+events → 按武器分组切窗口 → 出 `report.json` + 控制台表。

> IO 壳无纯函数可单测(全是文件读写),由**在实数据上跑通**验证(端到端)。逻辑正确性已由 Task 3–6 的纯函数单测覆盖。

- [ ] **Step 1: 创建 `tools/analyze_evolutions.gd`**

```gdscript
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
		if not cards.begins_with("solo_"):
			continue
		var wid := cards.substr(5)
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
```

- [ ] **Step 2: 在 Task 2 的 smoke 数据上跑通**

Run:
```
& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://tools/analyze_evolutions.gd -- --dir=telemetry/p2a_smoke
```
Expected: 控制台打出含 `evolve_explosion` 的一行，`reached=1.00`、`verdict` 非空（单进化时跨档中位=自身 → ok）；生成 `telemetry/p2a_smoke/report.json`。

- [ ] **Step 3: 提交**

```
git add tools/analyze_evolutions.gd
git commit -m "feat(analysis): analyze_evolutions IO 壳(读 run→切窗口→多轴报告)"
```

---

## Task 8: P2a campaign 批跑脚本

**Files:**
- Create: `tools/run_p2a_campaign.ps1`

**Interfaces:**
- Produces: 11 solo 档 × N 种子批跑到 `telemetry/p2a/`，再调 `analyze_evolutions` 出报告。

- [ ] **Step 1: 创建 `tools/run_p2a_campaign.ps1`**

```powershell
# tools/run_p2a_campaign.ps1 — P2a 进化平衡 campaign:11 solo 档 × 种子,dodge 探针,出多轴报告。
# 跑前先关编辑器(LimboAI 双实例陷阱)。
param(
	[string]$Godot = "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe",
	[string]$Proj = "D:\Workspace\GAME\game_0_vsl",
	[int[]]$Seeds = @(7, 42, 101, 1, 2, 3, 4, 5),
	[string[]]$Weapons = @("knife","whip","boomerang","explosion","aura","lightning","orb","maul","frostbite","gravity_well","reanimate"),
	[double]$MaxTime = 600,
	[double]$Fast = 8,
	[string]$OutDir = "telemetry/p2a"
)
foreach ($w in $Weapons) {
	foreach ($s in $Seeds) {
		$out = "$OutDir/solo_${w}_s${s}"
		Write-Host "[P2a] solo_$w seed=$s"
		& $Godot --headless --fixed-fps 60 --path $Proj -- --bot=kite --cards=solo_$w --seed=$s --fast=$Fast --maxtime=$MaxTime --out=$out
	}
}
Write-Host "[P2a] campaign 完成。分析:"
& $Godot --headless --path $Proj -s res://tools/analyze_evolutions.gd -- --dir=$OutDir
```

- [ ] **Step 2: 提交**

```
git add tools/run_p2a_campaign.ps1
git commit -m "feat(tools): P2a campaign 批跑脚本(11 solo × 8 种子 + 多轴分析)"
```

---

## Task 9: 跑 campaign + 产出支配性报告（P2a 交付物）

**Files:**
- 产出：`telemetry/p2a/report.json`（不提交）
- Create: `docs/reviews/2026-06-20-evolution-dominance-report.md`（提交）

> 这是 P2a 的最终交付,非 TDD。跑既有管线 + 写叙事报告。**跑前关编辑器。**

- [ ] **Step 1: 跑全 campaign（11×8，约 1–1.3h 墙钟）**

Run（PowerShell，先关编辑器）:
```
& "D:\Workspace\GAME\game_0_vsl\tools\run_p2a_campaign.ps1"
```
> 如需先验管线，传 3 种子小批：`& tools\run_p2a_campaign.ps1 -Seeds 7,42,101`。
Expected: `telemetry/p2a/` 下生成 88 组 `solo_<w>_s<n>.{summary.json,tick.csv,events.jsonl}`；末尾打出多轴表 + `report.json`。

- [ ] **Step 2: 核对数据完整性**

检查 `telemetry/p2a/report.json`：每个 `evolve_<w>` 的 `n==8`、`reached_ratio` 合理（多数应 >0；若某进化 `reached_ratio` 很低 → 该 solo 档到不了进化，本身是强 weak 信号，记录之）。
> 若某武器全部未达进化（`reached_ratio==0`）→ 排查该 solo 档（perk 阈值/武器机制），在报告中单列为"未达进化"，不阻塞其余分析。

- [ ] **Step 3: 写支配性报告 `docs/reviews/2026-06-20-evolution-dominance-report.md`**

报告须含（基于 `report.json` 实数据）：
1. **多轴总表**：11 进化 × (n / reached_ratio / kpm_post_med + 效应量 / survived_post_med / hp_min_post_med / 各轴 verdict / 综合 verdict)。
2. **OP 榜**：综合 OP 的进化，按 kpm 效应量降序；标注偏在哪轴。
3. **weak 榜**：综合 weak 的进化；区分"到不了进化(reached 低)"vs"到了但弱(kpm/生存低)"。
4. **坍缩三类对账**：`evolve_explosion`(nuke=全屏覆盖②) / `evolve_knife`(thousand_edge=绕冷却③) 是否被判 OP？命中即标"坍缩原型,P2b 重点"。
5. **数值倒退核对**：对各 run 抽查进化前满级窗口 vs 进化后窗口的 kpm/dmg（血鞭 `evolve_whip`、炼狱 `evolve_aura` 嫌疑），记录是否倒退。
6. **P2b 输入清单**：每个 off-band 进化 → 偏在哪轴 → 建议复衡杠杆方向（不含具体数值,数值是 P2b）。
7. **方法学限制**（照搬 spec 缺口 B）：安全轴因 dodge bot 防御饱和,OP 主靠 kpm + 生存。

- [ ] **Step 4: 提交报告**

```
git add docs/reviews/2026-06-20-evolution-dominance-report.md
git commit -m "docs(review): P2a 进化支配性报告(11进化多轴遥测,P2b 复衡输入)"
```

---

## 最终验证

- [ ] **Step 1: 全量套件绿 + 核对用例数**

Run:
```
& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: 全绿，用例总数 = Task 0 `BASELINE` + **12**（Task1:2 + Task3:2 + Task4:4 + Task5:2 + Task6:2）。**总数不升反降 → 套件解析错误被静默截断,先修。**

- [ ] **Step 2: C5 聚合稳定复验**

同种子(如 seed 7)重跑 1 个 solo 档两次(`solo_explosion`)，比对窗口三轴中位漂移 < 噪声（非逐字节）。
> 进化窗口分段 + 中位聚合对 13-文件非确定性鲁棒；此步兜底确认。

- [ ] **Step 3: 退出判据核验**（对照 spec §7）

1. solo 隔离闸上线 + TDD 锁定 ✅（Task 1+2）
2. 11 进化全部 8 种子 × 窗口数据 ✅（Task 9）
3. 多轴判据上线 + TDD 锁定 ✅（Task 3–6）
4. 支配性报告产出（三轴 verdict + 效应量 + 坍缩三类对账 + 倒退核对）✅（Task 9）
5. 全量绿 + C5 聚合稳定 ✅（最终验证 1+2）
→ **P2b 据报告立复衡 spec。**

---

## Spec 覆盖自检（计划作者已核）

| spec §4 组件 | 对应任务 | 覆盖 |
|---|---|---|
| 组件1 solo 隔离闸（修缺口 A） | Task 1+2 | ✅ |
| 组件2 进化窗口分段 | Task 3+4+5 | ✅ |
| 组件3 多轴透明判据（修缺口 B 记录） | Task 6 | ✅ |
| 组件4 支配性报告 + 叙事核对 | Task 7（壳）+ Task 9（报告） | ✅ |
| §3 测量配方（fast=8/fixed-fps60/8种子） | Task 8 脚本 | ✅ |
| §6 测试（纯函数 TDD + 隔离 + 截断核对 + C5） | 各任务 + 最终验证 | ✅ |
| §7 退出判据 5 项 | 最终验证 Step 3 | ✅ |
| §8 不做（零平衡改动） | 全程约束 | ✅ |

---

## 执行方式（下个会话选一）

**1. Subagent-Driven（推荐）** —— 每任务派新 subagent，任务间复审，迭代快。需 `superpowers:subagent-driven-development`。
> 注意 Task 2/7/9 含 headless 实跑（需关编辑器 + 较长墙钟），适合主会话内执行而非纯 subagent。

**2. Inline Execution** —— 本会话内批量执行，带检查点。需 `superpowers:executing-plans`。
