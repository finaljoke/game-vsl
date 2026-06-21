# base 清场组差异化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 判据轻量重桶（base 形态角色映射，清场带只含 explosion/lightning）+ frostbite 控场预算搬移（伤害↓/控制↑）+ blizzard 连带守 C4，坐实 frostbite「控场非清场」身份并消除桌桶假阳。

**Architecture:** 两块独立改动——① 纯分析层（`run_analysis.gd` 加 `BASE_ROLE`/`base_role_for`，`analyze_base_clear.gd` 改用之）零游戏码；② 游戏数据（`frostbite.tres`/`blizzard.tres` 两个 .tres）+ 测试值同步 + C4 守恒契约。数值由 bot 遥测 A/B 定量。

**Tech Stack:** Godot 4.7 GDScript / gdUnit4 headless / PowerShell bot 遥测管线。

## Global Constraints

- 引擎 Godot 4.7；gdUnit 命令 `& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "d:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`。
- 跑 headless 前先关编辑器（LimboAI 双实例陷阱）；bot 遥测必带 `--fixed-fps 60`（C5 确定性）。
- C6：gdUnit 截断陷阱——新增/风险测试排套件末，每次核对发现测试数（当前基线 **562**）。
- C4：进化必 ≥ base（blizzard 控制/伤害 ≥ frostbite L3）。
- **提交策略**：本会话内容广度批次暂不提交（用户「commit only when asked」）；plan 内 commit 步骤改为「暂存待批」——实现时跑测试到绿即止，不 `git commit`，留工作树由用户统一决定。
- 全程基准对照 spec：[2026-06-21-base-clear-differentiation-design.md](../specs/2026-06-21-base-clear-differentiation-design.md)。

---

### Task 1: 判据轻量重桶（base 形态角色映射，纯分析层 TDD）

**Files:**
- Modify: `tools/run_analysis.gd`（加 `BASE_ROLE` const + `base_role_for()`）
- Modify: `tools/analyze_base_clear.gd`（roles 构建改用 `base_role_for`）
- Test: `tests/test_run_analysis.gd`（排套件末）

**Interfaces:**
- Produces: `RA.BASE_ROLE: Dictionary`；`RA.base_role_for(wid: String) -> String`（base 形态角色，覆盖优先、回退 `EVOLUTION_ROLE`、再回退 `"clear"`）。
- Consumes: 既有 `RA.EVOLUTION_ROLE`、`RA.flag_dominance(by_evo, band, roles)`（P3c 角色感知，已支持非 clear 角色 clear_axis=na）。

- [ ] **Step 1: 写失败测试**（追加到 `tests/test_run_analysis.gd` 末尾）

```gdscript
# ── 内容广度 base 清场组差异化:base 形态角色映射 ─────────────────────────────
func test_base_role_for_overrides_and_fallback() -> void:
	assert_str(RA.base_role_for("explosion")).is_equal("clear")
	assert_str(RA.base_role_for("lightning")).is_equal("clear")
	assert_str(RA.base_role_for("frostbite")).is_equal("control")  # base 控场(进化 blizzard 才清场)
	assert_str(RA.base_role_for("maul")).is_equal("control")       # base 重控(进化 earthshatter 才清场)
	assert_str(RA.base_role_for("aura")).is_equal("defense")
	assert_str(RA.base_role_for("boomerang")).is_equal("single")   # 未覆盖 → 回退 EVOLUTION_ROLE
	assert_str(RA.base_role_for("zzz_unknown")).is_equal("clear")  # 全未知 → 默认 clear

func test_flag_dominance_base_roles_clear_band_two_specialists() -> void:
	# base 清场带只含 explosion/lightning;frostbite/maul/aura 重桶为非清场 → clear_axis=na、不判清场 OP
	var by := {
		"base_explosion": {"clear_eff_med": 14.0, "backlog_mean_med": 16.8,  "survived_post_med": 440.0, "hp_min_post_med": 0.66, "reached_ratio": 1.0, "death_ratio": 0.0},
		"base_lightning": {"clear_eff_med": 13.0, "backlog_mean_med": 26.4,  "survived_post_med": 460.0, "hp_min_post_med": 0.90, "reached_ratio": 1.0, "death_ratio": 0.0},
		"base_frostbite": {"clear_eff_med": 10.0, "backlog_mean_med": 30.0,  "survived_post_med": 440.0, "hp_min_post_med": 0.80, "reached_ratio": 1.0, "death_ratio": 0.0},
		"base_maul":      {"clear_eff_med": 2.0,  "backlog_mean_med": 137.0, "survived_post_med": 460.0, "hp_min_post_med": 0.86, "reached_ratio": 1.0, "death_ratio": 0.0},
		"base_aura":      {"clear_eff_med": 2.0,  "backlog_mean_med": 168.0, "survived_post_med": 400.0, "hp_min_post_med": 0.78, "reached_ratio": 1.0, "death_ratio": 0.0},
	}
	var roles := {}
	for k in by:
		roles[k] = RA.base_role_for(String(k).trim_prefix("base_"))
	var f := RA.flag_dominance(by, 0.35, roles)
	# 清场带 {16.8,26.4} 中位 21.6,带[14.04,29.16] → explosion 16.8 落带内 ok(不再被 maul/aura 拉高中位误判 OP)
	assert_str(String(f["base_explosion"]["verdict"])).is_equal("ok")
	assert_str(String(f["base_lightning"]["verdict"])).is_equal("ok")
	assert_str(String(f["base_frostbite"]["clear_axis"])).is_equal("na")
	assert_str(String(f["base_maul"]["clear_axis"])).is_equal("na")
	assert_str(String(f["base_aura"]["clear_axis"])).is_equal("na")
```

- [ ] **Step 2: 跑测试验证失败**

Run: `... -a res://tests/test_run_analysis.gd`
Expected: 解析错误「Static function "base_role_for()" not found」（RED 信号=函数未建）。

- [ ] **Step 3: 实现 `BASE_ROLE` + `base_role_for`**（`tools/run_analysis.gd`，加在 `EVOLUTION_ROLE`/`roles_for` 之后）

```gdscript
# base 形态角色(覆盖 EVOLUTION_ROLE):base 与进化角色可不同——frostbite/maul base 是控场,进化(blizzard/
# earthshatter)才成清场;aura 两形态都防御。供 analyze_base_clear 角色感知重桶,使 base 清场带只含真清场专精。
const BASE_ROLE := {
	"explosion": "clear", "lightning": "clear",
	"frostbite": "control", "maul": "control",
	"aura": "defense",
}

# base 形态角色:BASE_ROLE 覆盖优先 → 回退 EVOLUTION_ROLE → 默认 clear。
static func base_role_for(wid: String) -> String:
	return BASE_ROLE.get(wid, EVOLUTION_ROLE.get(wid, "clear"))
```

- [ ] **Step 4: 跑测试验证通过**

Run: `... -a res://tests/test_run_analysis.gd`
Expected: PASS（含两条新测）。

- [ ] **Step 5: analyze_base_clear 改用 base_role_for**（`tools/analyze_base_clear.gd`，roles 构建那行）

把
```gdscript
		roles[key] = RA.EVOLUTION_ROLE.get(wid, "clear")
```
改为
```gdscript
		roles[key] = RA.base_role_for(String(wid))   # base 形态角色:frostbite/maul=control、aura=defense → 清场带只含 explosion/lightning
```

- [ ] **Step 6: 跑全量 gdUnit 核对无回归 + 测数**

Run: `... -a res://tests`
Expected: Overall Summary `564 test cases | 0 failures`（562 + 2 新），39/39 套件。

---

### Task 2: frostbite 控场预算搬移 + blizzard 连带 + 值断言同步 + C4 契约

**Files:**
- Modify: `data/weapons/frostbite.tres`（L1/L2/L3 damage↓、slow/freeze↑）
- Modify: `data/weapons/blizzard.tres`（控制↑ 守 ≥ frostbite）
- Modify: `tests/test_weapons_w2.gd`（frostbite L1 值断言同步）
- Test: `tests/test_evolution_contracts.gd`（加 blizzard ≥ frostbite C4 契约）

**Interfaces:**
- Consumes: 既有 `_evo(id)`/`_l3(id)` 助手（test_evolution_contracts，读 WeaponDB 对应 .tres 的 levels），既有 frostbite 机制（densest_center + slow→freeze 链，脚本不动）。
- Produces: 新 frostbite/blizzard 数值（起始假设，Task 3 A/B 定量）。

- [ ] **Step 1: 写 C4 守恒契约（失败测试）**（追加到 `tests/test_evolution_contracts.gd` 的 P3b 守恒契约区）

```gdscript
# ── blizzard ≥ frostbite L3(冰系控场身份:进化控制/伤害不弱于 base) ──
func test_blizzard_control_ge_base_l3() -> void:
	var blz := _evo("blizzard")
	var l3 := _l3("frostbite")
	assert_float(float(blz["damage"])).is_greater_equal(float(l3["damage"]))          # 伤害 ≥ base
	assert_float(float(blz["slow_factor"])).is_less_equal(float(l3["slow_factor"]))    # 减速 ≥ base(低=更强)
	assert_float(float(blz["slow_dur"])).is_greater_equal(float(l3["slow_dur"]))       # 减速时长 ≥ base
	assert_float(float(blz["freeze_dur"])).is_greater_equal(float(l3["freeze_dur"]))   # 冻结时长 ≥ base
	assert_float(float(blz["area"])).is_greater_equal(float(l3["area"]))               # 覆盖 ≥ base
```

- [ ] **Step 2: 跑该契约验证当前失败**

Run: `... -a res://tests/test_evolution_contracts.gd`
Expected: FAIL —— 现 blizzard slow_factor 0.45 ≤ frostbite L3 0.45 成立但 slow_dur 2.0≥2.0、freeze 1.0≥1.0 边界相等会过；**先改 frostbite（Step 3）使其控制超过 blizzard → 契约转 FAIL**，再改 blizzard（Step 4）转 PASS。（若 Step 2 此刻意外全过，说明边界相等，仍按 Step 3/4 推进。）

- [ ] **Step 3: 改 frostbite.tres（预算搬移）**

把 `data/weapons/frostbite.tres` 的 `levels` 三档改为（仅列改动字段，area/cooldown 不变）：

```
L1: "damage": 9.0,  "slow_factor": 0.5,  "slow_dur": 1.8, "freeze_dur": 0.7
L2: "damage": 10.0, "slow_factor": 0.42, "slow_dur": 2.2, "freeze_dur": 0.9
L3: "damage": 11.0, "slow_factor": 0.35, "slow_dur": 2.5, "freeze_dur": 1.1
```

- [ ] **Step 4: 改 blizzard.tres（连带上调控制，守 ≥ frostbite L3）**

把 `data/weapons/blizzard.tres` 的 `levels[0]` 改：`"slow_factor": 0.30`、`"slow_dur": 2.8`、`"freeze_dur": 1.3`（damage 20 / area 130 / field_dur 3.0 / cooldown 2.0 不变）。

- [ ] **Step 5: 跑 C4 契约验证通过**

Run: `... -a res://tests/test_evolution_contracts.gd`
Expected: PASS（blizzard 0.30≤0.35 / 2.8≥2.5 / 1.3≥1.1 / 20≥11 / 130≥110）。

- [ ] **Step 6: 同步 frostbite L1 值断言**

读 `tests/test_weapons_w2.gd` 的 `test_frostbite_reflects_level1_fields`，把其对 L1 `damage`(13→9)与 `slow_factor`(0.6→0.5) 的断言改为新值（其余字段若有断言同改；行为测 `test_frostbite_slows_then_freezes_on_second_hit` 机制不变，注入值无关，不必改）。

- [ ] **Step 7: 跑全量 gdUnit 核对绿 + 测数**

Run: `... -a res://tests`
Expected: Overall Summary `565 test cases | 0 failures`（564 + 1 C4 契约），39/39 套件。若有红=值断言遗漏，定位补改。

---

### Task 3: A/B 遥测验证 + 数值定量迭代（C5）

**Files:** 无代码改动（除非迭代回 Task 2 调数值）。产出 `telemetry/base_clear/`、`telemetry/frostbite_recheck/` + 控制台支配表。

- [ ] **Step 1: 重测 base 清场组（含新 frostbite + 重桶）**

先关编辑器。Run:
```
& "D:\Workspace\GAME\game_0_vsl\tools\run_base_clear_campaign.ps1" -Weapons @("frostbite")
```
（重跑 solobase_frostbite ×5 覆盖，余 4 武器数据有效；脚本末自动 `analyze_base_clear` 全组。）

Expected/验收：base 清场带 = {explosion, lightning} 双 **ok**；frostbite/maul/aura `verdict` 非 clear-OP（clear_axis na）；**frostbite backlog 明显升**（清场降，与 explosion 分明）；frostbite 仍存活（hp_min 非崩、未大量 death）。

- [ ] **Step 2: 判定迭代**

- 若 frostbite backlog 升幅过小（仍像清场武器）→ 回 Task 2 再降 damage 或加强 slow，重跑 Step 1。
- 若 frostbite 存活崩（hp_min<0.3 或多 death）→ 控制不足补偿伤害损失 → 回 Task 2 略回伤害或加强 slow/freeze，重跑。
- 收敛判据：frostbite backlog 明显高于 explosion（≥ ~30，离开「强清场」区）且存活健康。

- [ ] **Step 3: 复测 blizzard 进化支配（控制 buff 不致 OP）**

复用 p3b_solo 有效数据复跑 solo_frostbite ×8 → analyze_dominance：
```powershell
$Godot="C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe"; $Proj="D:\Workspace\GAME\game_0_vsl"
$dst="$Proj\telemetry\frostbite_recheck"; if(Test-Path $dst){Remove-Item $dst -Recurse -Force}; Copy-Item "$Proj\telemetry\p3b_solo" $dst -Recurse -Force
foreach($s in 7,42,101,1,2,3,4,5){ & $Godot --headless --fixed-fps 60 --path $Proj -- --bot=kite --cards=solo_frostbite --seed=$s --fast=8 --maxtime=600 --out=telemetry/frostbite_recheck/solo_frostbite_s$s }
& $Godot --headless --path $Proj -s res://tools/analyze_dominance.gd -- --dir=telemetry/frostbite_recheck --report=telemetry/frostbite_recheck/dominance_report.json
```
Expected/验收：blizzard（evolve_frostbite）verdict **ok**（控制 buff 只增控不增清场 → backlog 不应明显下窜成 OP）。若意外 OP → 回 Task 2 收一点 blizzard 控制（仍守 ≥ frostbite）。

---

### Task 4: 最终验证 + 报告 + 记忆

**Files:**
- Create: `docs/reviews/2026-06-21-base-clear-differentiation-report.md`
- Modify: 记忆 `MEMORY.md` + `project_combat_spec_and_plan.md`

- [ ] **Step 1: 全量 gdUnit 终检**

Run: `... -a res://tests`
Expected: `565 test cases | 0 failures`，39/39 套件，无截断（C6）。

- [ ] **Step 2: 写报告**（仿 [explosion 报告](../../reviews/2026-06-21-explosion-base-clear-content-breadth-report.md) 骨架）

§0 一句话结论 / §1 判据重桶（前后清场带对照）/ §2 frostbite 预算搬移 + A/B 前后 backlog / §3 blizzard 连带 + C4 守恒 / §4 退出判据对照 spec / §5 残留（全 §5② 多轴未补）。填入 Task 3 实测数。

- [ ] **Step 3: 更新记忆**

`MEMORY.md` 战斗系统条目尾 + `project_combat_spec_and_plan.md` 加本轮小节（判据轻量重桶 + frostbite 控场化 + blizzard 连带；残留=全多轴）。

- [ ] **Step 4: 汇报工作树状态**

列改动文件（2 .tres + 2 tools + 3 tests + 2 docs + 记忆），提醒整批未提交，问用户是否统一提交。

## Self-Review

- **Spec coverage**：§2 判据重桶=Task 1；§3 frostbite=Task 2 Step 3 + Task 3；§4 blizzard=Task 2 Step 4 + Task 3 Step 3；§5 验证=Task 2/3/4；§6 退出判据全有对应 Task；§7 不做=记残留（Task 4 报告）。无缺口。
- **Placeholder scan**：数值均具体（frostbite/blizzard 起始值 + A/B 收敛判据）；测试代码完整给出。
- **Type consistency**：`base_role_for(String)->String`、`BASE_ROLE` 全程一致；`flag_dominance(by,band,roles)` 签名与现有一致。
