# P3c 支配判据治本 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development 或 superpowers:executing-plans 逐 task 实现。步骤用 checkbox（`- [ ]`）跟踪。

**Goal:** 治本 P3b 残留——`flag_dominance` 改角色感知清场组 + 未达过滤（消 thunderstorm/earthshatter 假阳），nuke 二连爆不叠第二团地火（保 P4 削真残留）。

**Architecture:** A 判据层（`run_analysis.gd` 纯函数 + `analyze_dominance.gd` 工具，零游戏改动，对现存遥测重算）；B 游戏层（`explosion_weapon.gd` script 行为，nuke 数值零改）。

**Tech Stack:** Godot 4.7 GDScript / gdUnit4 headless。

## Global Constraints

- 引擎 Godot 4.7；测试命令 `& $Godot --headless --path <repo> -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`。
- **跑 headless 前先关编辑器**（LimboAI 双实例 DLL 冲突）。
- **禁 `git add -A`**：仓库 ~2500 预存未追踪文件 + 预存改动 .tscn/.import/project.godot 是用户决策；每 task 只 add 本 task 触及文件。
- 守 C4（质变守恒，nuke `.tres` 零改）/ P4（二连爆质变保留）/ C5（聚合稳定）/ C6（改后跑所有相关套件 + 核对用例数防截断）。
- 简体中文提交信息；提交尾 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`。

---

### Task 1: 判据 v2 纯函数（角色映射 + 未达过滤 + 角色组中位）

**Files:**
- Modify: `tools/run_analysis.gd`（加 `REACH_MIN`/`EVOLUTION_ROLE`/`roles_for`；改 `flag_dominance` 加 `roles` 参 + 未达过滤 + 角色组）
- Test: `tests/test_run_analysis.gd`

**Interfaces:**
- Produces: `RA.REACH_MIN: float`、`RA.EVOLUTION_ROLE: Dictionary`、`RA.roles_for(by_evo) -> Dictionary`、`RA.flag_dominance(by_evo, band=0.35, roles={}) -> Dictionary`（每项加 `"role"` 键）。
- Consumes（Task 3）：`analyze_dominance.gd` 调 `RA.flag_dominance(summary, 0.35, RA.roles_for(summary))`。

- [ ] **Step 1: 写失败测试**（`roles_for` + 角色组 + 未达过滤 + 回归）

```gdscript
# ── P3c 单元:判据 v2 角色感知 + 未达过滤 ──────────────────────────────────
func test_roles_for_maps_evolve_keys() -> void:
	var r := RA.roles_for({"evolve_explosion": {}, "evolve_knife": {}, "evolve_unknown": {}})
	assert_str(String(r["evolve_explosion"])).is_equal("clear")
	assert_str(String(r["evolve_knife"])).is_equal("single")
	assert_str(String(r["evolve_unknown"])).is_equal("clear")  # 未知默认 clear

func test_flag_dominance_role_aware_excludes_nonclear_from_band() -> void:
	# 非清场角色高 backlog(像 aura175/boomerang98) 不进清场中位、不判 OP;
	# 清场专精低 backlog 仅与同类比 → 落带 ok(不再被弱进化基准误判)。
	var by := {
		"evolve_explosion": {"clear_eff_med": 19.0, "backlog_mean_med": 14.0,  "survived_post_med": 440.0, "hp_min_post_med": 0.87, "reached_ratio": 1.0, "death_ratio": 0.0},
		"evolve_lightning": {"clear_eff_med": 13.0, "backlog_mean_med": 19.0,  "survived_post_med": 460.0, "hp_min_post_med": 0.92, "reached_ratio": 1.0, "death_ratio": 0.0},
		"evolve_maul":      {"clear_eff_med": 9.0,  "backlog_mean_med": 24.0,  "survived_post_med": 460.0, "hp_min_post_med": 0.88, "reached_ratio": 1.0, "death_ratio": 0.0},
		"evolve_boomerang": {"clear_eff_med": 2.0,  "backlog_mean_med": 98.0,  "survived_post_med": 400.0, "hp_min_post_med": 0.70, "reached_ratio": 1.0, "death_ratio": 0.1},
	}
	var roles := RA.roles_for(by)
	var f := RA.flag_dominance(by, 0.35, roles)
	# 清场组 {14,19,24} 中位 19,带 [12.35,25.65];三清场专精全落带 → 无 OP
	assert_str(String(f["evolve_lightning"]["verdict"])).is_equal("ok")
	assert_str(String(f["evolve_maul"]["verdict"])).is_equal("ok")
	# boomerang(非清场)高 backlog 不判 OP、role 记 single、不参清场轴
	assert_str(String(f["evolve_boomerang"]["verdict"])).is_not_equal("OP")
	assert_str(String(f["evolve_boomerang"]["role"])).is_equal("single")
	assert_str(String(f["evolve_boomerang"]["clear_axis"])).is_equal("na")

func test_flag_dominance_reached_filter_excludes_zero_backlog() -> void:
	# 未达进化(reached=0、backlog=0) 不污染清场组中位:加它前后,达进化 verdict 不变。
	var base := {
		"evolve_explosion": {"clear_eff_med": 19.0, "backlog_mean_med": 14.0, "survived_post_med": 440.0, "hp_min_post_med": 0.87, "reached_ratio": 1.0, "death_ratio": 0.0},
		"evolve_lightning": {"clear_eff_med": 13.0, "backlog_mean_med": 19.0, "survived_post_med": 460.0, "hp_min_post_med": 0.92, "reached_ratio": 1.0, "death_ratio": 0.0},
		"evolve_maul":      {"clear_eff_med": 9.0,  "backlog_mean_med": 24.0, "survived_post_med": 460.0, "hp_min_post_med": 0.88, "reached_ratio": 1.0, "death_ratio": 0.0},
	}
	var with_unreached := base.duplicate(true)
	with_unreached["evolve_knife"] = {"clear_eff_med": 0.0, "backlog_mean_med": 0.0, "survived_post_med": 0.0, "hp_min_post_med": 0.0, "reached_ratio": 0.0, "death_ratio": 1.0}
	var fa := RA.flag_dominance(base, 0.35, RA.roles_for(base))
	var fb := RA.flag_dominance(with_unreached, 0.35, RA.roles_for(with_unreached))
	# knife 未达 → weak;且不把清场组中位拖向 0 → maul verdict 两次一致
	assert_str(String(fb["evolve_knife"]["verdict"])).is_equal("weak")
	assert_str(String(fb["evolve_maul"]["verdict"])).is_equal(String(fa["evolve_maul"]["verdict"]))
```

- [ ] **Step 2: 跑测试验证失败**

Run: `... -a res://tests/test_run_analysis.gd`
Expected: FAIL（`roles_for` 未定义 / `flag_dominance` 无第三参或无 `role`/`na`）。

- [ ] **Step 3: 实现**（run_analysis.gd）

加常量（`BACKLOG_FLOOR` 下方）：
```gdscript
const REACH_MIN: float = 0.5   # 达进化比例下沿;低于此 → 基准不计 + verdict weak

# 进化角色(设计意图,独立于 backlog 测量,非循环):clear=AoE 区域清场专精。
const EVOLUTION_ROLE := {
	"aura": "clear", "frostbite": "clear", "explosion": "clear",
	"lightning": "clear", "maul": "clear", "whip": "clear",
	"boomerang": "single", "knife": "single",
	"orb": "control", "gravity_well": "control",
	"reanimate": "summon",
}

# by_evo 键("evolve_<wid>") → 角色映射,供 flag_dominance 角色组。
static func roles_for(by_evo: Dictionary) -> Dictionary:
	var out := {}
	for k in by_evo:
		out[k] = EVOLUTION_ROLE.get(String(k).trim_prefix("evolve_"), "clear")
	return out
```

替换 `flag_dominance`（加 `roles` 参 + 未达过滤 + 角色组清场中位 + `role`/`na`）：
```gdscript
# 支配判据 v2(P3c 治本):清场轴 backlog 仅在「清场角色 ∩ 达进化」组内取中位 → 修跨角色假阳;
# 未达进化(reached<REACH_MIN,backlog 退化 0)不计基准 → 修无数据污染。roles 空 → 退化旧单组(回归兼容)。
static func flag_dominance(by_evo: Dictionary, band: float = 0.35, roles: Dictionary = {}) -> Dictionary:
	var reached_keys: Array = []
	for k in by_evo:
		if float(by_evo[k].get("reached_ratio", 1.0)) >= REACH_MIN:
			reached_keys.append(k)
	var surv_med := _axis_median_keys(by_evo, reached_keys, "survived_post_med")
	var hp_med := _axis_median_keys(by_evo, reached_keys, "hp_min_post_med")
	var clear_med := _axis_median_keys(by_evo, reached_keys, "clear_eff_med")
	var clearing_keys: Array = []
	for k in reached_keys:
		if roles.is_empty() or String(roles.get(k, "clear")) == "clear":
			clearing_keys.append(k)
	var backlog_med := _axis_median_keys(by_evo, clearing_keys, "backlog_mean_med")
	var flags := {}
	for k in by_evo:
		var r = by_evo[k]
		var role := String(roles.get(k, "clear"))
		var is_clear := role == "clear"
		var backlog := float(r["backlog_mean_med"])
		var surv := float(r["survived_post_med"])
		var hp := float(r["hp_min_post_med"])
		var clear := float(r["clear_eff_med"])
		var clear_v := "na"
		if is_clear:
			var backlog_raw := _band_verdict(backlog, backlog_med, band)
			clear_v = ("high" if backlog_raw == "low" else ("low" if backlog_raw == "high" else "ok"))
		var surv_v := _band_verdict(surv, surv_med, band)
		var hp_v := _band_verdict(hp, hp_med, band)
		var reached := float(r.get("reached_ratio", 1.0))
		var death := float(r.get("death_ratio", 0.0))
		var low_axes := (1 if clear_v == "low" else 0) + (1 if surv_v == "low" else 0) + (1 if hp_v == "low" else 0)
		var verdict := "ok"
		if reached < REACH_MIN or (death > 0.5 and surv_v == "low"):
			verdict = "weak"
		elif low_axes >= 2:
			verdict = "weak"
		elif is_clear and clear_v == "high" and hp_v != "low":
			verdict = "OP"
		flags[k] = {
			"verdict": verdict, "role": role,
			"clear_axis": clear_v, "backlog_dev": _effect(backlog, backlog_med),
			"surv_axis": surv_v, "surv_dev": _effect(surv, surv_med),
			"hp_axis": hp_v, "hp_dev": _effect(hp, hp_med),
			"clear_eff_ctx": clear, "clear_eff_dev": _effect(clear, clear_med),
			"reached_ratio": reached, "death_ratio": death,
		}
	return flags
```

加 keys 版中位助手（`_axis_median` 下方）：
```gdscript
static func _axis_median_keys(by_evo: Dictionary, keys: Array, key: String) -> float:
	var vals: Array = []
	for k in keys:
		vals.append(float(by_evo[k][key]))
	return median(vals)
```

- [ ] **Step 4: 跑测试验证通过**

Run: `... -a res://tests/test_run_analysis.gd`
Expected: PASS（新 3 测 + 旧 flag_dominance 3 测全绿）。

- [ ] **Step 5: 提交**

```bash
git add tools/run_analysis.gd tests/test_run_analysis.gd
git commit -m "feat(p3c): 支配判据 v2 角色感知清场组+未达过滤(flag_dominance roles 参)"
```

---

### Task 2: analyze_dominance 工具传角色

**Files:**
- Modify: `tools/analyze_dominance.gd:41`（`flag_dominance(summary)` → `flag_dominance(summary, 0.35, RA.roles_for(summary))`；表头/打印加 role 列可选）

**Interfaces:**
- Consumes: `RA.flag_dominance(summary, 0.35, RA.roles_for(summary))`（Task 1）。

- [ ] **Step 1: 改工具调用**

`tools/analyze_dominance.gd` 第 41 行：
```gdscript
	var new_flags := RA.flag_dominance(summary, 0.35, RA.roles_for(summary))
```
打印行加 role（第 44 行表头加 `,role`、第 49-52 行格式串加 `%s` 取 `String(nf["role"])`）。

- [ ] **Step 2: 提交**

```bash
git add tools/analyze_dominance.gd
git commit -m "feat(p3c): analyze_dominance 传角色映射给判据 v2 + role 列"
```

---

### Task 3: A 验证 — 对现存 p3b_solo 零重跑重算

**Files:** 无（纯重算现存遥测）。

- [ ] **Step 1: 关编辑器后重算**（headless，单实例）

Run: `& $Godot --headless --path <repo> -s res://tools/analyze_dominance.gd -- --dir=telemetry/p3b_solo --report=telemetry/p3b_solo/dominance_v2.json`

- [ ] **Step 2: 核对 verdict**

预期（spec §2.3）：`evolve_lightning`(thunderstorm) verdict **OP→ok**、`evolve_maul`(earthshatter) ok、`evolve_explosion`(nuke) 仍 OP（隔离真残留）、非清场角色（boomerang/gravity/reanimate）非 OP、knife/orb/whip weak。打印列肉眼核对 + 读 `dominance_v2.json`。

---

### Task 4: B — nuke 二连爆不叠第二团地火（P4 保形）

**Files:**
- Modify: `scenes/weapons/explosion/explosion_weapon.gd`（`_spawn_explosion` 加 `lay_field` 参 + 守卫；二连爆调用传 `false`）
- Test: `tests/test_weapons_w3b.gd`

**Interfaces:**
- Produces: `_spawn_explosion(center: Vector2, lay_field: bool = true)`。

- [ ] **Step 1: 写失败测试**（explosion 行为）

```gdscript
# ── P3c:nuke 二连爆不叠第二团地火(保 P4) ──────────────────────────────────
func test_explosion_secondary_skips_burn_field() -> void:
	var w := ExplosionWeapon.new()
	add_child(w)
	w.burn_dps = 10.0
	w.field_dur = 3.0
	# 主爆铺地火、二连爆不铺:数 ysort 下 BurnField
	w._spawn_explosion(Vector2(640, 360), true)
	var after_primary := _count_burn_fields(w)
	w._spawn_explosion(Vector2(640, 360), false)
	var after_secondary := _count_burn_fields(w)
	assert_int(after_primary).is_equal(1)            # 主爆铺一团
	assert_int(after_secondary).is_equal(after_primary)  # 二连爆不增(仍 1)
	w.queue_free()

func _count_burn_fields(w: ExplosionWeapon) -> int:
	var n := 0
	for c in w.get_ysort().get_children():
		if c is BurnField:
			n += 1
	return n
```

> 注：`get_ysort()` 与 `BurnField` 类需在测试上下文可达；若 `BurnField` 无 `class_name`，改用 `c.get_script() == w.BURN_FIELD` 判定（读 explosion_weapon.gd 确认后定）。

- [ ] **Step 2: 跑测试验证失败**

Run: `... -a res://tests/test_weapons_w3b.gd`
Expected: FAIL（`_spawn_explosion` 不接 2 参 / 二连爆仍铺地火 → after_secondary=2）。

- [ ] **Step 3: 实现**（explosion_weapon.gd）

`_spawn_explosion` 签名 + 地火守卫：
```gdscript
func _spawn_explosion(center: Vector2, lay_field: bool = true) -> void:
	# ...（explosion 实例化、detonate 不变）...
	if lay_field and burn_dps > 0.0 and field_dur > 0.0:
		# ...（BurnField 生成不变）...
```
`attack()` 二连爆调用传 `false`：
```gdscript
	for i in range(secondary_count):
		var c := center
		get_tree().create_timer(secondary_delay * float(i + 1)).timeout.connect(
			func() -> void: _spawn_explosion(c, false))
```

- [ ] **Step 4: 跑测试验证通过**

Run: `... -a res://tests/test_weapons_w3b.gd`
Expected: PASS。

- [ ] **Step 5: 契约回归（C4 nuke 不变）**

Run: `... -a res://tests/test_evolution_contracts.gd`
Expected: PASS 13/13（nuke `.tres` 数值零改 → `test_nuke_clearing_ge_base_l3` 绿）。

- [ ] **Step 6: 提交**

```bash
git add scenes/weapons/explosion/explosion_weapon.gd tests/test_weapons_w3b.gd
git commit -m "feat(p3c): nuke 二连爆不叠第二团地火(保二连爆质变/去翻倍持续清场,守 P4/C4)"
```

---

### Task 5: B 验证 — explosion solo 重跑 + v2 重算

**Files:** 无（campaign + 重算）。

- [ ] **Step 1: 关编辑器后 explosion solo 重跑**

Run: `pwsh tools/run_p2a_campaign.ps1 -Weapons explosion -OutDir telemetry/p3c_nuke -Seeds 7,42,101,1,2,3,4,5`（bot=kite/fast=8/maxtime=600）

- [ ] **Step 2: v2 重算**

Run: `& $Godot --headless --path <repo> -s res://tools/analyze_dominance.gd -- --dir=telemetry/p3c_nuke --report=telemetry/p3c_nuke/dominance_v2.json`

> 注:单跑 explosion 时清场组只 1 员 → 带=自身,无法判 OP。核对方式 = 比对 nuke backlog 由 p3b_solo 的 11.69 升向 p3b 清场组带 [12.70, 26.38]（用 p3b_solo 其余清场专精 backlog 作固定参照,或把 p3c_nuke 的 nuke 摘出与 p3b_solo 其余进化合并重算）。

- [ ] **Step 3: 核对**

nuke backlog 升（去第二团地火 → 清场降）。理想落带 [12.70, 26.38] → v2 ok；若过冲偏高（偏弱）诚实记（nuke 数值地板,二连爆地火唯一 P4 内杠杆）。

---

### Task 6: 全量回归 + C6 核数 + C5

- [ ] **Step 1: 关编辑器后全量 gdUnit**

Run: `& $Godot --headless --path <repo> -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: 全绿 0 error；**核对用例数**（基线 550 + 新 3 判据单测 + 1 explosion 行为 = 554，GREEN 态核对防截断，C6）。

- [ ] **Step 2: C5 聚合稳定**

explosion 或 mix 同种子两跑聚合稳定（沿用 P2b「聚合稳定非逐字节」裁决）。

---

### Task 7: 后衡报告

**Files:**
- Create: `docs/reviews/2026-06-21-dominance-criterion-治本-p3c-report.md`

- [ ] **Step 1: 写报告**（含真根因诊断纠正 P3b §2a、v2 重算前后对照、nuke 前后 backlog、退出判据核对、残留/下一步）

- [ ] **Step 2: 提交**

```bash
git add docs/reviews/2026-06-21-dominance-criterion-治本-p3c-report.md
git commit -m "docs(p3c): 支配判据治本后衡报告(假阳消除+nuke 真残留治本)"
```

## Self-Review

- **Spec 覆盖**：A 判据 v2（Task 1-3）/ B nuke（Task 4-5）/ 回归（Task 6）/ 报告（Task 7）全覆盖 spec §2-6。✅
- **占位符**：无 TBD；代码块完整。Task 4 Step 1 的 `BurnField` 判定法标注「读源确认后定」——实现时先读 explosion_weapon.gd 顶部确认 `BurnField` 是否有 class_name，二选一。
- **类型一致**：`flag_dominance(by_evo, band, roles)`、`roles_for`、`_axis_median_keys`、`_spawn_explosion(center, lay_field)` 跨 task 签名一致。✅
