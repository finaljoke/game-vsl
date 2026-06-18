# 武器军械库重做 W4：遥测 A/B 平衡 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用既有 bot/telemetry 管线把重做后军械库的「草案基线数值」调成「实测平衡」——为每把武器造单武器 bot 档、跑确定性 A/B 矩阵（多种子）、用纯函数分析工具读 `summary.json` 算跨武器功率中位数并标出过强/过弱武器，据此微调 `data/weapons/*.tres` 的 `levels` 数值并复跑收敛。

**Architecture:** 不改游戏机制，只动「测量工具 + 数据数值」。新增**单武器 bot 档**（`RunHarness.profile_for("solo_<id>")` 生成「拿该武器→堆其进化 perk→进化→升级→生存兜底」的优先表），让 bot 围绕单把武器成型从而隔离评估。新增纯函数分析核 `RunAnalysis`（中位数 / 击杀每分钟 / 跨武器 off-band 判定）+ 一个 headless 分析工具 `tools/analyze_runs.gd` 读 `telemetry/**.summary.json` 出对比表与 `report.json`。新增 PowerShell 编排脚本跑「档 × 种子」矩阵。调参是据分析输出改 `.tres` 数值的迭代循环，带明确验收带宽。

**Tech Stack:** Godot 4.6.3 · GDScript · gdUnit4 · 既有 `RunHarness`/`RunRecorder`/`DebugMetrics` 遥测管线 · PowerShell 编排。

## Global Constraints

逐条来自 spec §6.4/§11、记忆 `project_vsl_bot_telemetry`、以及管线现状，每任务隐含遵守：

- **引擎 Godot 4.6.3**；gdUnit4 测试 **必须** `--ignoreHeadlessMode`。
- **确定性靠引擎参数 `--fixed-fps 60`（不是 `--fast`）**：根因是 spawner 帧时间 RNG 节拍；A/B 一切对比必须在 `--fixed-fps 60` 下跑，否则同种子两跑会分叉、对比无意义。`--fast=<n>`（time_scale）只用于加速吞吐，与确定性正交。
- **bot 模式 CLI（既有 `RunHarness.parse_args`，用户参数在 `--` 之后）**：`--bot[=kite|still]`、`--cards=<profile>`、`--seed=<int>`、`--fast=<float>`、`--out=<path>`、`--maxtime=<秒>`。无 `--bot` 时管线全惰性（真人游玩零影响）——本波所有改动不得破坏这条。
- **遥测产物（既有 `RunRecorder`，勿改格式）**：`<out>.tick.csv`、`<out>.events.jsonl`、`<out>.summary.json`。分析只**读** `summary.json`：键含 `outcome / survived_s / final_level / kills / dmg_dealt_total / dmg_taken_total / hp_pct_avg / hp_pct_min / danger_total_s / build / seed / config`。
- **只调数值，不改机制**：本波改 `data/weapons/*.tres` 的 `levels[]` 内 `damage/cooldown/...` 等**平衡数值**；不改武器脚本逻辑、不改 W0 原语、不改卡条件。
- **改到「被测试断言的字段」必须同步改测试**：W1/W2/W3 的部分测试断言了具体数值（如 whip arc=100、knife cooldown=0.5）。若调参动到这些**契约字段**，对应测试随之更新（属本波合法改动）；纯**平衡字段**（多数 damage）一般无断言。
- **telemetry/ 已 gitignore**（既有）：运行产物不入库；只提交工具、档、测试、最终 `.tres` 数值与一份平衡报告 md。
- **测试约定**：`extends GdUnitTestSuite`；纯逻辑用 `const X := preload(...)`。

**前置依赖：** 必须先完成 **W0/W1/W2/W3a/W3b**（全部 11 把武器 + 进化已实现入库）。VFX 波次与本波正交（FX 不影响数值），可先可后。

**核心运行命令**（PowerShell）：

- 跑一局 bot（确定性）：

```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --fixed-fps 60 --path "D:\Workspace\GAME\game_0_vsl" -- --bot=kite --cards=solo_knife --seed=1 --fast=8 --maxtime=600 --out=telemetry/ab/solo_knife_s1
```

- 跑 gdUnit 测试：

```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<TEST_FILE>.gd
```

---

## File Structure

**新建**

- `tools/run_analysis.gd` — `RunAnalysis`：纯函数分析核（中位数 / 击杀每分钟 / 跨武器 off-band 判定）。无 IO、无场景。
- `tools/analyze_runs.gd` — headless 分析工具（`extends SceneTree`）：读 `telemetry/**.summary.json` → 按档分组 → `RunAnalysis` 汇总 → 打印对比表 + 写 `report.json`。
- `tools/run_ab_matrix.ps1` — PowerShell 编排：对「档 × 种子」矩阵逐一启动确定性 bot 局。
- `tests/test_run_harness_profiles.gd` — `profile_for` / `solo_profile` + `choose_card` 纯测。
- `tests/test_run_analysis.gd` — `RunAnalysis` 纯测。
- `docs/superpowers/plans/2026-06-17-weapon-arsenal-w4-balance-report.md` — 最终平衡报告（任务 8 产出）。

**修改**

- `autoloads/run_harness.gd` — 新增 `SOLO_PERKS` + `solo_profile` + `profile_for`；`_ready` 改用 `profile_for(cfg["cards"])`。
- `data/weapons/*.tres` — 据分析迭代微调 `levels[]` 平衡数值（任务 7-8）。

---

## Task 1: 单武器 bot 档（隔离评估每把武器）

**Files:**
- Modify: `autoloads/run_harness.gd`
- Test: `tests/test_run_harness_profiles.gd`

**Interfaces:**
- Produces:
  - `const SOLO_PERKS: Dictionary` — 武器 id → 其进化所需 perk（来自 spec §6.4 表）。
  - `static func solo_profile(weapon_id: String, evo_perk: String) -> Array` — 单武器优先表。
  - `static func profile_for(name: String) -> Array` — `"solo_<id>"` → `solo_profile`；其余回退 `PROFILES`/`DEFAULT_PROFILE`。
- Consumes: 既有 `choose_card`（纯）。

- [x] **Step 1: 写失败测试**

`tests/test_run_harness_profiles.gd`：

```gdscript
extends GdUnitTestSuite

const Harness := preload("res://autoloads/run_harness.gd")

func test_solo_profile_takes_weapon_first() -> void:
	var prof := Harness.solo_profile("knife", "perk_attack")
	var offered := [{"id": "perk_hp", "type": "perk"}, {"id": "knife", "type": "weapon"}]
	assert_str(String(Harness.choose_card(offered, prof)["id"])).is_equal("knife")

func test_solo_profile_prefers_evo_perk_over_survival() -> void:
	# 进化 perk 优先于通用生存 perk → 保证能堆到 evolve_ready 阈值。
	var prof := Harness.solo_profile("knife", "perk_attack")
	var offered := [{"id": "perk_hp", "type": "perk"}, {"id": "perk_attack", "type": "perk"}]
	assert_str(String(Harness.choose_card(offered, prof)["id"])).is_equal("perk_attack")

func test_solo_profile_takes_evolution_when_offered() -> void:
	var prof := Harness.solo_profile("knife", "perk_attack")
	var offered := [{"id": "perk_attack", "type": "perk"}, {"id": "evolve_knife", "type": "evolution"}]
	assert_str(String(Harness.choose_card(offered, prof)["id"])).is_equal("evolve_knife")

func test_profile_for_solo_dispatch() -> void:
	var prof := Harness.profile_for("solo_whip")
	assert_bool(prof.is_empty()).is_false()
	assert_str(String(prof[0])).is_equal("whip")

func test_profile_for_default_fallback() -> void:
	assert_array(Harness.profile_for("default")).is_equal(Harness.DEFAULT_PROFILE)
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_run_harness_profiles.gd`
Expected: FAIL — `solo_profile`/`profile_for`/`SOLO_PERKS` 未定义。

- [x] **Step 3: 改 `autoloads/run_harness.gd`**

3a. 在 `PROFILES` 常量附近新增（武器→进化 perk 来自 spec §6.4）：

```gdscript
# 每把武器进化所需 perk(spec §6.4)。供单武器档堆到 evolve_ready。
# 新武器(maul/frostbite/gravity_well/reanimate)的 id 以 W2/W3a 实际为准;不存在时该项仅未被用到,无害。
const SOLO_PERKS := {
	"knife": "perk_attack", "whip": "perk_attack", "boomerang": "perk_speed",
	"explosion": "perk_damage", "aura": "perk_hp", "lightning": "perk_attack", "orb": "perk_hp",
	"maul": "perk_hp", "frostbite": "perk_attack", "gravity_well": "perk_speed", "reanimate": "perk_hp",
}

# 单武器优先表:拿武器 → 升级 → (就绪即)进化 → 堆进化 perk → 生存兜底。
# 不含通用 type:weapon,故 bot 不会拿别的武器,保证单武器隔离。
static func solo_profile(weapon_id: String, evo_perk: String) -> Array:
	return [
		weapon_id,
		weapon_id + "_2", weapon_id + "_3",
		"evolve_" + weapon_id,
		evo_perk,
		"synergy_lifesteal", "perk_hp", "perk_heal",
		"type:upgrade", "type:synergy", "type:perk",
	]

static func profile_for(name: String) -> Array:
	if name.begins_with("solo_"):
		var wid := name.substr(5)
		return solo_profile(wid, String(SOLO_PERKS.get(wid, "perk_hp")))
	return PROFILES.get(name, DEFAULT_PROFILE)
```

3b. `_ready()` 里把 `_profile = PROFILES.get(cfg["cards"], DEFAULT_PROFILE)` 改为：

```gdscript
	_profile = profile_for(cfg["cards"])
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_run_harness_profiles.gd` → PASS。

```powershell
git add autoloads/run_harness.gd tests/test_run_harness_profiles.gd
git commit -m @'
feat(telemetry): 单武器 bot 档 solo_<id>(隔离评估每把武器)

profile_for 派发 solo_profile:拿武器→升级→进化→堆进化perk→生存兜底。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 2: `RunAnalysis` 纯函数分析核

**Files:**
- Create: `tools/run_analysis.gd`
- Test: `tests/test_run_analysis.gd`

**Interfaces:**
- Produces（全 `static`）：
  - `median(values: Array) -> float`
  - `kills_per_min(summary: Dictionary) -> float`
  - `summarize_profile(summaries: Array) -> Dictionary` → `{n, survived_med, kills_per_min_med, hp_pct_min_med, danger_med}`
  - `flag_off_band(by_profile: Dictionary, band: float = 0.35) -> Dictionary` → 每档 `{kills_per_min_med, cross_median, verdict∈{ok,OP,weak}}`

- [x] **Step 1: 写失败测试**

`tests/test_run_analysis.gd`：

```gdscript
extends GdUnitTestSuite

const RA := preload("res://tools/run_analysis.gd")

func test_median_odd() -> void:
	assert_float(RA.median([3, 1, 2])).is_equal(2.0)

func test_median_even() -> void:
	assert_float(RA.median([1, 2, 3, 4])).is_equal(2.5)

func test_kills_per_min() -> void:
	assert_float(RA.kills_per_min({"kills": 120, "survived_s": 120.0})).is_equal(60.0)

func test_summarize_profile() -> void:
	var s := RA.summarize_profile([
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
	var f := RA.flag_off_band(by, 0.35)
	assert_str(String(f["c"]["verdict"])).is_equal("OP")
	assert_str(String(f["d"]["verdict"])).is_equal("weak")
	assert_str(String(f["a"]["verdict"])).is_equal("ok")
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_run_analysis.gd` → FAIL（`tools/run_analysis.gd` 不存在）。

- [x] **Step 3: 写 `tools/run_analysis.gd`**

```gdscript
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
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_run_analysis.gd` → PASS。

```powershell
git add tools/run_analysis.gd tests/test_run_analysis.gd
git commit -m @'
feat(telemetry): RunAnalysis 纯分析核(中位数/击杀每分/跨武器 off-band)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 3: `analyze_runs.gd` headless 分析工具

**Files:**
- Create: `tools/analyze_runs.gd`
- Test: 烟测（无单测——纯 IO 编排，逻辑已在 Task 2 覆盖）

**Interfaces:**
- 用法：`Godot --headless --path <proj> -s res://tools/analyze_runs.gd -- --dir=telemetry/ab --report=telemetry/ab/report.json`
- 读 `<dir>/*.summary.json`，按文件名 `<profile>_s<seed>.summary.json` 的 `<profile>` 分组，`RunAnalysis.summarize_profile` + `flag_off_band`，打印 CSV 风格表，写 `report.json`。

- [x] **Step 1: 写 `tools/analyze_runs.gd`**

```gdscript
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
```

- [x] **Step 2: 烟测（造两个假 summary 跑工具）**

```powershell
$proj = "D:\Workspace\GAME\game_0_vsl"
New-Item -ItemType Directory -Force "$proj\telemetry\smoke" | Out-Null
'{"survived_s":120.0,"kills":120,"hp_pct_min":0.4,"danger_total_s":5.0}' | Set-Content "$proj\telemetry\smoke\solo_knife_s1.summary.json"
'{"survived_s":120.0,"kills":40,"hp_pct_min":0.6,"danger_total_s":2.0}'  | Set-Content "$proj\telemetry\smoke\solo_orb_s1.summary.json"
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path $proj -s res://tools/analyze_runs.gd -- --dir=telemetry/smoke --report=telemetry/smoke/report.json
```
Expected: 打印两行表（solo_knife / solo_orb，各 n=1），生成 `telemetry/smoke/report.json`，其中 solo_knife `verdict` 相对中位数偏高、solo_orb 偏低（band 内则 ok——单样本只验工具能跑通）。

- [x] **Step 3: 提交**

```powershell
git add tools/analyze_runs.gd
git commit -m @'
feat(telemetry): analyze_runs headless 工具(读 summary→跨武器对比表+report.json)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 4: A/B 矩阵编排脚本

**Files:**
- Create: `tools/run_ab_matrix.ps1`

**Interfaces:**
- 对「档 × 种子」逐一启动确定性 bot 局，全部 `--fixed-fps 60`，产物落 `telemetry/ab/<profile>_s<seed>.*`。

- [x] **Step 1: 写 `tools/run_ab_matrix.ps1`**

```powershell
# tools/run_ab_matrix.ps1 — 跑「单武器档 × 种子」确定性 A/B 矩阵。
param(
	[string]$Godot = "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe",
	[string]$Proj = "D:\Workspace\GAME\game_0_vsl",
	[int[]]$Seeds = @(1, 2, 3, 4, 5),
	[string[]]$Profiles = @("solo_knife","solo_whip","solo_boomerang","solo_explosion","solo_aura","solo_lightning","solo_orb","solo_maul","solo_frostbite","solo_gravity_well","solo_reanimate"),
	[double]$MaxTime = 600,
	[double]$Fast = 8,
	[string]$OutDir = "telemetry/ab"
)
foreach ($prof in $Profiles) {
	foreach ($s in $Seeds) {
		$out = "$OutDir/${prof}_s${s}"
		Write-Host "[A/B] $prof seed=$s"
		& $Godot --headless --fixed-fps 60 --path $Proj -- --bot=kite --cards=$prof --seed=$s --fast=$Fast --maxtime=$MaxTime --out=$out
	}
}
Write-Host "[A/B] 完成。分析: -s res://tools/analyze_runs.gd -- --dir=$OutDir"
```

> `--fixed-fps 60` 是确定性必需；`--fast 8` 仅加速 wall-clock（同 fixed-fps 下增大每秒模拟时间）。`--maxtime 600`=每局封顶 10 分钟游戏时间，避免无限局。武器 id 以 W2/W3a 实际为准，缺失的 `solo_*` 局会自然死亡/空跑，分析时剔除。

- [x] **Step 2: 烟测（缩小矩阵确认能跑出产物）**

```powershell
pwsh -File "D:\Workspace\GAME\game_0_vsl\tools\run_ab_matrix.ps1" -Seeds 1 -Profiles solo_knife -MaxTime 60
```
Expected: 生成 `telemetry/ab/solo_knife_s1.summary.json`（含 outcome/survived_s/kills 等）。

- [x] **Step 3: 提交**

```powershell
git add tools/run_ab_matrix.ps1
git commit -m @'
chore(telemetry): A/B 矩阵编排脚本(档×种子,确定性 --fixed-fps 60)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 5: 确定性守卫（A/B 前置闸门）

**Files:** 无新增；验证流程。

> 重做引入大量新代码（状态 tick、击退衰减、召唤 AI、新粒子）。若任何一处用了帧时间 / `Math.random` 风味的非定序遍历，会重蹈 spawner RNG 节拍覆辙，使 A/B 不可信。**先验确定性再信数值。**

- [x] **Step 1: 同 (档, 种子) 跑两次**

```powershell
$g = "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe"; $p = "D:\Workspace\GAME\game_0_vsl"
& $g --headless --fixed-fps 60 --path $p -- --bot=kite --cards=solo_knife --seed=7 --fast=8 --maxtime=300 --out=telemetry/det/a
& $g --headless --fixed-fps 60 --path $p -- --bot=kite --cards=solo_knife --seed=7 --fast=8 --maxtime=300 --out=telemetry/det/b
```

- [x] **Step 2: diff summary（必须完全一致）**

```powershell
$d = Compare-Object (Get-Content "$p\telemetry\det\a.summary.json") (Get-Content "$p\telemetry\det\b.summary.json")
if ($null -eq $d) { Write-Host "DETERMINISTIC ✓" } else { Write-Host "NON-DETERMINISTIC ✗"; $d }
```
Expected: `DETERMINISTIC ✓`（`config` 不含 `out`，两文件应逐行相同）。

- [x] **Step 3（仅当非确定）：定位并修根因**

非确定 → 在新代码里找：`get_nodes_in_group` 结果直接参与浮点累加/选择而未先定序（参考 `RunHarness.compute_kite_dir` 的「先按位置排序」做法）、用 `Time.get_ticks_msec()` 驱动游戏逻辑（如 `orb_shield` 的轨道角——纯视觉可容忍，但若驱动命中判定则不可）、或 `randf()` 未走统一种子。修复后回 Step 1 复验。**确定性不绿，不进 Task 6。**

> 本任务无代码产物则不提交；若修了确定性 bug，随该修复一起提交并补一句 commit 说明。

---

## Task 6: 跑全 A/B 矩阵 + 分析

**Files:** 无新增；产出 `telemetry/ab/report.json`（gitignore，不入库）。

- [x] **Step 1: 跑矩阵**（11 档 × ≥5 种子；多种子压平 RNG 方差）

```powershell
pwsh -File "D:\Workspace\GAME\game_0_vsl\tools\run_ab_matrix.ps1" -Seeds 1,2,3,4,5,6,7,8
```

- [x] **Step 2: 分析**

```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://tools/analyze_runs.gd -- --dir=telemetry/ab --report=telemetry/ab/report.json
```

- [x] **Step 3: 记录基线对比表**

把打印表（每档 `survived_med / kills_per_min_med / hp_pct_min_med / danger_med / verdict`）抄进 Task 8 的报告草稿。对照**验收带宽**（下）标注每档：

**验收带宽（本波目标，可据手感复议）：**
- **功率平价**：每档 `kills_per_min_med` 落在全档中位数 **±35%**（`flag_off_band` 默认）。`OP` / `weak` 均需调。
- **可生存性**：单武器 + 生存兜底 build 下，`survived_med` 应达到 `--maxtime`（即活满全程）。活不满 → 该武器**防御性偏弱**或太吃操作，调其清场/控制。
- **威胁合理**：`hp_pct_min_med` 不应长期贴近 0（无惊险=太强；秒贴 0=太险）；`danger_med`（危险秒累计）做参考。
- **进化提升**：进化 build（活到进化后段）`kills_per_min` 应**高于**同武器基础段一个有感差值，但不破 OP 上限——进化是质变增强，非象征。

- [x] **Step 4（无入库产物）**：本任务只产 gitignore 的 telemetry；分析结论进 Task 8 报告。

---

## Task 7: 调参循环（改 .tres → 复跑 → 收敛）

**Files:**
- Modify: `data/weapons/*.tres`（仅 off-band 武器的 `levels[]` 平衡数值）
- Modify（仅当动到契约字段）：对应 W1/W2/W3 测试

> 迭代式：每轮只调**少数** off-band 武器，复跑其档 + 复验确定性，避免一次改太多无法归因。

- [x] **Step 1: 选本轮要调的武器**

从 Task 6 表取 `verdict != ok` 的档。`OP` → 降该武器 `levels[].damage`（或升 `cooldown`）；`weak` → 反向。每轮调幅先 **±10~15%**，避免过冲。

- [x] **Step 2: 改 `.tres`**

例（飞刀判 OP，降 L3 伤害）——编辑 `data/weapons/knife.tres` 的 `levels` 第 3 项 `damage`：从草案值乘 ~0.88。**只改平衡数值**，不动 `id/cooldown 之外的契约`。

> 若调的字段被测试断言（如 `knife_3` 的 cooldown=0.3、whip arc=100），同步更新该断言（本波合法）；纯 damage 字段一般无断言。改完先跑该武器的 W1/W2/W3 测试确认不回归：
> `… -a res://tests/test_card_pool.gd`（及相关 weapon 测试）→ PASS。

- [x] **Step 3: 复验确定性 + 复跑该档**

```powershell
$g="C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe"; $p="D:\Workspace\GAME\game_0_vsl"
# 该武器档复跑(多种子)
pwsh -File "$p\tools\run_ab_matrix.ps1" -Profiles solo_knife -Seeds 1,2,3,4,5,6,7,8 -OutDir telemetry/ab2
& $g --headless --path $p -s res://tools/analyze_runs.gd -- --dir=telemetry/ab2 --report=telemetry/ab2/report.json
```
确认该档 `verdict` 回到 `ok`，且未把别的档挤出带宽（若怀疑联动，重跑全矩阵）。

- [x] **Step 4: 提交本轮数值**

```powershell
git add data/weapons/knife.tres   # 本轮实际改的 .tres(+ 同步的测试,若有)
git commit -m @'
balance(weapons): 飞刀 L3 伤害 -12%(A/B 判 OP,回中位带宽)

依据 telemetry 8 种子中位 kills/min。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

- [x] **Step 5: 循环**

回 Task 6 全矩阵复跑 → 重算 → 仍有 off-band 则回本任务再调一轮。**收敛判据**：全 11 档 `verdict=ok` 且都满足可生存性/威胁带宽（或剩余偏差已属设计取舍，在报告里说明）。

---

## Task 8: 平衡报告 + 收尾

**Files:**
- Create: `docs/superpowers/plans/2026-06-17-weapon-arsenal-w4-balance-report.md`

- [x] **Step 1: 写报告**

含：最终全矩阵对比表（每档 survived/kills_per_min/hp_min/danger/verdict）、各轮调参记录（武器 / 字段 / 旧→新值 / 依据）、收敛后仍存的有意取舍、确定性已绿的确认、复现命令（矩阵 + 分析）。

- [x] **Step 2: 跑全量测试确认数值改动无回归**

Run: `… -a res://tests`
Expected: 全绿（调参同步更新了被断言的契约字段；纯 damage 改动无断言）。

- [x] **Step 3: 提交报告**

```powershell
git add docs/superpowers/plans/2026-06-17-weapon-arsenal-w4-balance-report.md
git commit -m @'
docs(balance): W4 遥测 A/B 平衡报告(最终数值+调参记录+复现命令)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Self-Review

**1. Spec 覆盖（§6.4「平衡定位」/ §11「可被遥测验证,确定性须 --fixed-fps 60」）：**

| spec 要求 | 落地 |
|---|---|
| 数值为草案基线,最终由 bot/telemetry A/B 确认 | Task 6-8 跑矩阵→分析→调 `.tres`→收敛报告 |
| 确定性靠引擎参数 `--fixed-fps 60` | 全 A/B 命令带 `--fixed-fps 60`；Task 5 确定性守卫为前置闸门 |
| 每把武器有清晰平衡定位 | Task 1 单武器档隔离评估每把；Task 6 验收带宽含进化提升 |
| 复用既有管线(RunHarness/RunRecorder/DebugMetrics) | 只**读** summary.json、只**扩** profile，不改管线格式 |

**2. Placeholder 扫描：** 无 TBD。Task 6-8 是测量/调参流程（其本质即「跑→看→调」循环，非可预写死的代码），但每步给了**确切命令 + 验收带宽 + 收敛判据**，非含糊。`solo_*` 新武器 id 标注「以 W2/W3a 实际为准」是显式依赖。

**3. 类型一致性核对：**
- `RunHarness.solo_profile(String, String) -> Array`、`profile_for(String) -> Array`、`SOLO_PERKS`(dict) 在 Task 1 定义、测试引用一致；`choose_card`/`DEFAULT_PROFILE`/`PROFILES` 为既有。
- `RunAnalysis.median/kills_per_min/summarize_profile/flag_off_band` 签名在 Task 2 定义、Task 3 工具与测试引用一致；summary.json 键名（`survived_s/kills/hp_pct_min/danger_total_s`）与 `RunRecorder.finalize` 产出一致。
- CLI 参数（`--bot/--cards/--seed/--fast/--out/--maxtime` + 引擎 `--fixed-fps 60`）与 `RunHarness.parse_args` / `OS.get_cmdline_user_args` 一致。
- 单武器档 id 方案（`<id>` / `<id>_2/_3` / `evolve_<id>` / `type:<type>`）与 `CardPool.CARDS` 及 `choose_card._card_matches` 一致；进化 perk 表 `SOLO_PERKS` 与 spec §6.4 一致。

**4. 诚实性：** A/B 数值的可信前提（确定性）被设为显式闸门（Task 5）；分析为多种子中位数（压平 RNG 方差）；验收带宽与收敛判据写明,未声称「一轮调到完美」。

---

## Execution Handoff

**计划已存 `docs/superpowers/plans/2026-06-17-weapon-arsenal-w4-balance-telemetry.md`，两种执行方式：Subagent-Driven（推荐）/ Inline。**

> **执行前置**：先确认 **W0–W3b 全部武器已实现入库**；建议在专用分支执行。Task 5 确定性守卫不绿则不进 A/B。

**至此整套军械库重做的实现计划全部完成**：W0（底座）· W1（重构 7）· W2（新增 3）· W3a（Reanimate AI 盟友）· W3b（10 进化）· VFX-W1（视效底座）· VFX-W2（逐武器 FX）· VFX-W3（着色器）· W4（遥测 A/B 平衡）。
