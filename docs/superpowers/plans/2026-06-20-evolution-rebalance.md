# P2b 进化复衡 + 可达性地板测量 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 P2a 实测出的 off-band 进化（inferno_aura/cyclone 砍、horde 加强）拉回平衡带，并为三个纯 solo 测不到的进化（thousand_edge/mega_orb/bloody_whip）建立 perk_hp 防御垫地板测量档，全程契约测试锁质变守恒。

**Architecture:** 三类改动汇成一条分支。① 数值复衡（改三个 `.tres`），由契约 gdUnit 守恒测试 + 重跑 campaign 落带验证驱动。② harness 加 `solofloor_` 单武器+防御垫档（纯函数 `solo_spec` 解析 + grant 分支）。③ 分析器 `analyze_evolutions.gd` 复用 `solo_spec` 识别地板档。最终重跑 campaign（11 主档 + 3 地板）出后衡报告，数据闭环迭代到达标。

**Tech Stack:** Godot 4.7 / GDScript / gdUnit4（headless）/ PowerShell campaign 脚本。

## Global Constraints

- 引擎 **Godot 4.7**；Godot 二进制 `C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe`。
- **不变量契约**（基石 spec §6，新内容验收）：**C1** 不动伤害管线（只改数值输入）/ **C4** 进化=质变（复衡后进化仍须严格 ≥ 基础武器满级 L3）/ **C5** 遥测确定性靠 `--fixed-fps 60`（非 `--fast`）/ **C6** 契约 gdUnit 锁 + 跑后精确核对用例数防截断陷阱。
- **复衡哲学**：改的数值是首轮假设，由重跑 campaign 落带判据裁决并迭代；砍到 **+35% 带顶附近**不砍到中位；砍 OP 后用**新跨进化中位**复查 thunderstorm 及原平衡区不被动破带。
- **campaign 命令**：`--headless --fixed-fps 60 --path <proj> -- --bot=kite --cards=<profile> --seed=<s> --fast=8 --maxtime=600 --out=<dir>`。**跑 headless 前先关编辑器**（LimboAI 双实例 dll 冲突陷阱）。
- **gdUnit 基线**：当前 **508 绿**；本计划新增测试后须精确核对新用例数、风险/集成测试排末位（截断陷阱）。
- **仓库纪律**：**不 `git add -A`**（~2500 未追踪文件）；`telemetry/` 已 gitignore，不提交遥测产物；每任务独立提交独立绿测。
- **测试基础设施**：测试内 Player 用 `load("res://scenes/player/player.tscn").instantiate() as Player` + `auto_free` + `add_child` + `await get_tree().process_frame`；`CardPool.apply({"id":"perk_hp"}, p)` 直接生效（`_apply_perk_hp`：`max_hp += 20` 当场补满）。

---

## 文件结构（影响面）

| 文件 | 责任 | 改动 |
|---|---|---|
| `autoloads/run_harness.gd` | bot 编排 | 加纯函数 `solo_spec`、`profile_for`/`_grant_solo_weapon` 改用之、floor 分支授 perk_hp×K |
| `tests/test_run_harness.gd` | harness 单测 | 加 `solo_spec` 单测 + `profile_for` solofloor + floor grant 集成测试 |
| `tools/analyze_evolutions.gd` | 进化窗口分析 IO 壳 | 改用 `Harness.solo_spec` 识别 wid（支持 solofloor_） |
| `tools/run_p2b_floor_campaign.ps1` | 地板 campaign 编排 | 新建，跑 3 地板档 |
| `data/weapons/inferno_aura.tres` | 炼狱光环进化数值 | 砍覆盖密度 |
| `data/weapons/cyclone.tres` | 旋风镖进化数值 | 砍穿透/冷却 |
| `data/weapons/horde.tres` | 群尸进化数值 | 加随从 DPS |
| `tests/test_evolution_contracts.gd` | 质变守恒契约 | 新建，断言三进化 ≥ 基础 L3 |
| `docs/reviews/2026-06-20-evolution-rebalance-report.md` | P2b 后衡交付物 | 新建（Task 8） |

---

## Task 0: 建分支

- [ ] **Step 1: 从 master 建分支**

Run:
```bash
git switch -c feat/p2b-evolution-rebalance
```
Expected: `Switched to a new branch 'feat/p2b-evolution-rebalance'`

- [ ] **Step 2: 确认干净起点**

Run: `git status -sb`
Expected: `## feat/p2b-evolution-rebalance`，无本计划相关改动。

---

## Task 1: harness — `solo_spec` 纯解析 + `solofloor_` 防御垫档

**Files:**
- Modify: `autoloads/run_harness.gd:29-51`（加 `solo_spec`、改 `profile_for`）、`:244-262`（改 `_grant_solo_weapon`）、加常量
- Test: `tests/test_run_harness.gd`

**Interfaces:**
- Produces:
  - `static func solo_spec(cards_name: String) -> Dictionary` → `{"is_solo": bool, "is_floor": bool, "weapon_id": String}`。`solofloor_<w>`→floor；`solo_<w>`→非 floor；其它→is_solo=false。
  - `const FLOOR_PERK_HP_STACKS: int = 5`
  - `profile_for("solofloor_orb")` 返回 orb 的 `solo_profile`（与 `solo_orb` 同卡序）。
  - `_grant_solo_weapon` 对 floor 档在隔离后额外 `CardPool.apply({"id":"perk_hp"}, p)` ×K。
- Consumes（Task 2）：`analyze_evolutions.gd` 调 `Harness.solo_spec(cards)["weapon_id"]`。

- [ ] **Step 1: 写失败单测（solo_spec 解析）**

在 `tests/test_run_harness.gd` 末尾（命令行解析区块之后）追加：
```gdscript
# ── solo_spec 解析(solo_ / solofloor_) ──────────────────────────────────────
func test_solo_spec_plain_solo() -> void:
	var s := Harness.solo_spec("solo_knife")
	assert_bool(s["is_solo"]).is_true()
	assert_bool(s["is_floor"]).is_false()
	assert_str(String(s["weapon_id"])).is_equal("knife")

func test_solo_spec_floor() -> void:
	var s := Harness.solo_spec("solofloor_orb")
	assert_bool(s["is_solo"]).is_true()
	assert_bool(s["is_floor"]).is_true()
	assert_str(String(s["weapon_id"])).is_equal("orb")

func test_solo_spec_non_solo() -> void:
	var s := Harness.solo_spec("default")
	assert_bool(s["is_solo"]).is_false()
	assert_str(String(s["weapon_id"])).is_equal("")

func test_profile_for_solofloor_matches_solo_cards() -> void:
	# 地板档卡优先序与同武器 solo 档一致(地板差别在 grant,不在选卡)
	assert_array(Harness.profile_for("solofloor_orb")).is_equal(Harness.profile_for("solo_orb"))
```

- [ ] **Step 2: 跑测验证失败**

Run（关编辑器后）:
```bash
"C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/test_run_harness.gd
```
Expected: FAIL/解析错误 —— `solo_spec` 未定义（静态调用解析期即报错）。

- [ ] **Step 3: 实现 `solo_spec` + 改 `profile_for`**

在 `run_harness.gd` 的 `SOLO_PERKS` 常量后、`solo_profile` 前加常量：
```gdscript
const FLOOR_PERK_HP_STACKS: int = 5   # solofloor_ 档开局授予的 perk_hp 层数(+100 max HP 生存垫,纯防御不加击杀)
```

把现有 `profile_for`（第 47-51 行）替换为：
```gdscript
# 单武器档名 → 规格。solofloor_ 先于 solo_ 匹配(更长前缀)。
# {"is_solo": bool, "is_floor": bool, "weapon_id": String}。非单武器档 → is_solo=false。
static func solo_spec(cards_name: String) -> Dictionary:
	if cards_name.begins_with("solofloor_"):
		return {"is_solo": true, "is_floor": true, "weapon_id": cards_name.substr(10)}
	if cards_name.begins_with("solo_"):
		return {"is_solo": true, "is_floor": false, "weapon_id": cards_name.substr(5)}
	return {"is_solo": false, "is_floor": false, "weapon_id": ""}

static func profile_for(name: String) -> Array:
	var spec := solo_spec(name)
	if spec["is_solo"]:
		var wid: String = spec["weapon_id"]
		return solo_profile(wid, String(SOLO_PERKS.get(wid, "perk_hp")))
	return PROFILES.get(name, DEFAULT_PROFILE)
```

- [ ] **Step 4: 跑测验证通过**

Run: 同 Step 2 命令。
Expected: PASS（含新增 4 个 solo_spec/profile_for 用例 + 原有全绿）。

- [ ] **Step 5: 写失败集成测试（floor grant 授 perk_hp + 隔离）**

在 `tests/test_run_harness.gd` 末尾追加（**置于文件最末**——集成测试涉 Player/CardPool 全局，风险高排最后防截断）：
```gdscript
# ── solofloor_ 档:隔离非目标武器 + 授 perk_hp 生存垫(集成,排末位) ──────────────
func test_grant_solofloor_isolates_and_grants_hp() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	var p: Player = auto_free(scene.instantiate() as Player)
	add_child(p)
	await get_tree().process_frame
	var hp0 := p.max_hp
	p.owned_weapons["knife"] = {"node": null, "level": 1}   # 注入外来武器,验证被剥离
	var prev_cards := RunHarness._cards_name_val
	RunHarness._cards_name_val = "solofloor_orb"
	RunHarness._grant_solo_weapon(p)
	assert_bool(p.owned_weapons.has("knife")).is_false()      # 外来武器剥离
	assert_bool(p.has_weapon("orb")).is_true()                # 目标授予
	assert_float(p.max_hp).is_equal_approx(hp0 + 100.0, 0.001)  # perk_hp ×5 = +100 max HP
	RunHarness._cards_name_val = prev_cards
	CardPool.reset_run()   # 还原 banish 全局态,防泄漏后续用例
```

- [ ] **Step 6: 跑测验证失败**

Run: 同 Step 2。
Expected: FAIL —— floor 分支未实现，`p.max_hp` 仍为 hp0（未 +100）。

- [ ] **Step 7: 实现 `_grant_solo_weapon` floor 分支**

把现有 `_grant_solo_weapon`（第 246-262 行）替换为：
```gdscript
func _grant_solo_weapon(p: Player) -> void:
	var spec := solo_spec(_cards_name_val)
	if not spec["is_solo"]:
		return
	var wid: String = spec["weapon_id"]
	if wid == "" or p == null:
		return
	# solo 隔离:移除所有非目标已持有武器(含 main.gd 默认授予的起手 knife)。.keys() 是快照,迭代中 erase 安全。
	for owned_id in p.owned_weapons.keys():
		if owned_id != wid:
			var node = p.owned_weapons[owned_id].get("node")
			if is_instance_valid(node):
				node.queue_free()
			p.owned_weapons.erase(owned_id)
	if not p.has_weapon(wid):
		CardPool.apply({"id": wid}, p)   # 目标未持有才授予(避免重复 grant 泄漏旧节点)
	CardPool.banish_other_weapons(wid)   # 外来武器卡永不再被提供
	# 地板档:额外授纯防御垫(perk_hp 只加 HP 不加击杀 → kpm 仍单武器归属),让弱 solo 武器活到进化。
	if spec["is_floor"]:
		for _i in range(FLOOR_PERK_HP_STACKS):
			CardPool.apply({"id": "perk_hp"}, p)
```

- [ ] **Step 8: 跑测验证通过 + 全套件回归**

Run: 同 Step 2（整文件）。
Expected: PASS，全 `test_run_harness.gd` 绿（原 + 新增 5 个）。

- [ ] **Step 9: 提交**

```bash
git add autoloads/run_harness.gd tests/test_run_harness.gd
git commit -m "feat(harness): solo_spec + solofloor_ 防御垫档(perk_hp×5 生存地板)"
```

---

## Task 2: 分析器识别地板档 + 地板 campaign 脚本

**Files:**
- Modify: `tools/analyze_evolutions.gd:25-28`（改 wid 解析）
- Create: `tools/run_p2b_floor_campaign.ps1`

**Interfaces:**
- Consumes: `Harness.solo_spec(cards)`（Task 1）。
- Produces: 地板 telemetry 落 `telemetry/p2b_floor`，可被 `analyze_evolutions --dir=telemetry/p2b_floor` 分析。

- [ ] **Step 1: 改 `analyze_evolutions.gd` 用 solo_spec 解析 wid**

把第 25-28 行：
```gdscript
		var cards := String(su.get("config", {}).get("cards", ""))
		if not cards.begins_with("solo_"):
			continue
		var wid := cards.substr(5)
```
替换为：
```gdscript
		var cards := String(su.get("config", {}).get("cards", ""))
		var spec := RA_HARNESS.solo_spec(cards)
		if not spec["is_solo"]:
			continue
		var wid: String = spec["weapon_id"]
```
并在文件顶部 `const RA :=` 行后加：
```gdscript
const RA_HARNESS := preload("res://autoloads/run_harness.gd")
```
（`solo_spec` 是静态函数，可经脚本资源直调，无需实例化 autoload。）

- [ ] **Step 2: 验证分析器仍能解析旧 solo_ 数据（无回归）**

Run（若 `telemetry/p2a` 仍在；否则跳过，Task 8 全跑时验证）:
```bash
"C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . -s tools/analyze_evolutions.gd -- --dir=telemetry/p2a
```
Expected: 打印进化表头 + 行（与 P2a 报告同 wid 分组），无 `solofloor` 误判。若目录不存在则报错可忽略（Task 8 重建）。

- [ ] **Step 3: 建地板 campaign 脚本**

Create `tools/run_p2b_floor_campaign.ps1`:
```powershell
# tools/run_p2b_floor_campaign.ps1 — P2b 地板 campaign:3 个纯 solo 测不到的进化,加 perk_hp 防御垫(solofloor_)重测。
# 跑前先关编辑器(LimboAI 双实例陷阱)。
param(
	[string]$Godot = "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe",
	[string]$Proj = "D:\Workspace\GAME\game_0_vsl",
	[int[]]$Seeds = @(7, 42, 101, 1, 2, 3, 4, 5),
	[string[]]$Weapons = @("knife", "orb", "whip"),
	[double]$MaxTime = 600,
	[double]$Fast = 8,
	[string]$OutDir = "telemetry/p2b_floor"
)
foreach ($w in $Weapons) {
	foreach ($s in $Seeds) {
		$out = "$OutDir/solofloor_${w}_s${s}"
		Write-Host "[P2b-floor] solofloor_$w seed=$s"
		& $Godot --headless --fixed-fps 60 --path $Proj -- --bot=kite --cards=solofloor_$w --seed=$s --fast=$Fast --maxtime=$MaxTime --out=$out
	}
}
Write-Host "[P2b-floor] campaign 完成。分析(地板辈独立基准):"
& $Godot --headless --path $Proj -s res://tools/analyze_evolutions.gd -- --dir=$OutDir
```

- [ ] **Step 4: 语法自检（脚本可解析）**

Run:
```bash
pwsh -NoProfile -Command "Get-Command -Syntax { . './tools/run_p2b_floor_campaign.ps1' } *> $null; if (\$?) { 'parse-ok' }"
```
Expected: 无 PowerShell 解析错误（实际跑放 Task 8）。若该自检命令本身不便，改用 `pwsh -NoProfile -File tools/run_p2b_floor_campaign.ps1 -Weapons @() ` 空跑确认无语法错。

- [ ] **Step 5: 提交**

```bash
git add tools/analyze_evolutions.gd tools/run_p2b_floor_campaign.ps1
git commit -m "feat(tools): 分析器复用 solo_spec 识别地板档 + 地板 campaign 脚本"
```

---

## Task 3: 质变守恒契约（守 C4，复衡前先锁）

**Files:**
- Create: `tests/test_evolution_contracts.gd`

**Interfaces:**
- Consumes: `WeaponDB.get_data(id) -> WeaponData`，`.levels: Array[Dictionary]`（基础武器末元素=满级 L3；进化武器 levels[0]=单级）。

**说明（TDD 形态）**：这些是**不变量守卫**，对当前数值即绿——其价值是 Task 4-6 改数值时**仍须绿**（证明复衡未把进化砍成退化）。数值平衡本身的 RED→GREEN 驱动是 Task 8 的实测 campaign 落带，不是单测。先建守卫，再在守卫下改数值。

- [ ] **Step 1: 建契约测试文件（对当前数值即绿）**

Create `tests/test_evolution_contracts.gd`:
```gdscript
# tests/test_evolution_contracts.gd
# 质变守恒契约(C4 / 柱 P4):复衡后每个进化仍须在设计意图轴上严格 ≥ 基础武器满级 L3。
# 守卫测试——改 .tres 时仍须绿,防过砍把进化变退化。
extends GdUnitTestSuite

func _evo(id: String) -> Dictionary:
	return WeaponDB.get_data(id).levels[0]   # 进化武器单级

func _l3(id: String) -> Dictionary:
	var lv: Array = WeaponDB.get_data(id).levels
	return lv[lv.size() - 1]                 # 基础武器满级(末元素)

# ── inferno_aura ≥ aura L3(覆盖密度仍占优) ────────────────────────────────
func test_inferno_aura_radius_ge_base_l3() -> void:
	assert_float(float(_evo("inferno_aura")["radius"])).is_greater_equal(float(_l3("aura")["radius"]))

func test_inferno_aura_burn_ge_base_l3() -> void:
	assert_float(float(_evo("inferno_aura")["burn_dps"])).is_greater_equal(float(_l3("aura")["burn_dps"]))

# ── cyclone:多发 + 不慢于 boomerang L3 ───────────────────────────────────
func test_cyclone_is_multishot() -> void:
	assert_int(int(_evo("cyclone")["count"])).is_greater_equal(2)

func test_cyclone_cooldown_le_base_l3() -> void:
	assert_float(float(_evo("cyclone")["cooldown"])).is_less_equal(float(_l3("boomerang")["cooldown"]))

# ── horde 严格强于 reanimate L3 ───────────────────────────────────────────
func test_horde_max_minions_gt_base_l3() -> void:
	assert_int(int(_evo("horde")["max_minions"])).is_greater(int(_l3("reanimate")["max_minions"]))

func test_horde_damage_ge_base_l3() -> void:
	assert_float(float(_evo("horde")["damage"])).is_greater_equal(float(_l3("reanimate")["damage"]))

func test_horde_lifetime_ge_base_l3() -> void:
	assert_float(float(_evo("horde")["lifetime"])).is_greater_equal(float(_l3("reanimate")["lifetime"]))
```

- [ ] **Step 2: 跑测验证（当前数值即绿，守卫建立）**

Run:
```bash
"C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/test_evolution_contracts.gd
```
Expected: PASS（7 用例全绿；当前 170≥130 / 10≥6 / count3≥2 / 0.7≤1.0 / 6>3 / 16≥14 / 18≥11）。

- [ ] **Step 3: 提交**

```bash
git add tests/test_evolution_contracts.gd
git commit -m "test(combat): 进化质变守恒契约(三 off-band 进化 ≥ 基础 L3,守 C4)"
```

---

## Task 4: 砍 inferno_aura（OP +87% → 降覆盖密度）

**Files:**
- Modify: `data/weapons/inferno_aura.tres:15-21`

- [ ] **Step 1: 改数值（首轮假设，覆盖密度主刀）**

把 `data/weapons/inferno_aura.tres` 的 `levels` 块（第 15-21 行）改为：
```
levels = [{
"burn_dps": 7.0,
"cooldown": 0.5,
"damage": 12.0,
"lifesteal_on_hit": 0.25,
"radius": 145.0
}]
```
（radius 170→145 覆盖 ×0.73；burn 10→7；cooldown 0.4→0.5 频率 ×0.8；lifesteal 0.3→0.25。damage 不动。）

- [ ] **Step 2: import 资源 + 跑契约守卫验证未变退化**

Run:
```bash
"C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --import
"C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/test_evolution_contracts.gd
```
Expected: 契约 PASS（radius 145≥130、burn 7≥6 仍守恒）。

- [ ] **Step 3: 提交**

```bash
git add data/weapons/inferno_aura.tres
git commit -m "balance(inferno_aura): 砍覆盖密度(r170→145/burn10→7/cd0.4→0.5),首轮复衡假设"
```

---

## Task 5: 砍 cyclone（OP +53% → 降穿透/冷却）

**Files:**
- Modify: `data/weapons/cyclone.tres:15-23`

- [ ] **Step 1: 改数值（留 count3 旋风身份）**

把 `data/weapons/cyclone.tres` 的 `levels` 块（第 15-23 行）改为：
```
levels = [{
"cooldown": 0.85,
"count": 3,
"damage": 20.0,
"orbit_return": true,
"pierce": 5,
"proj_tint": Color(0.7, 0.95, 1, 1),
"throw_range": 270.0
}]
```
（pierce 8→5；cooldown 0.7→0.85；throw_range 300→270。count/damage/orbit/tint 不动。）

- [ ] **Step 2: import + 契约守卫**

Run:
```bash
"C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --import
"C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/test_evolution_contracts.gd
```
Expected: 契约 PASS（count 3≥2、cooldown 0.85≤1.0 仍守恒）。

- [ ] **Step 3: 提交**

```bash
git add data/weapons/cyclone.tres
git commit -m "balance(cyclone): 降穿透/冷却(pierce8→5/cd0.7→0.85/range300→270),留 count3 身份"
```

---

## Task 6: 加强 horde（真弱 8/8 死 → 堆随从 DPS 间接保命）

**Files:**
- Modify: `data/weapons/horde.tres:15-23`

- [ ] **Step 1: 改数值（DPS 路线,不改 AI/碰撞）**

把 `data/weapons/horde.tres` 的 `levels` 块（第 15-23 行）改为：
```
levels = [{
"cooldown": 2.5,
"damage": 22.0,
"lifetime": 22.0,
"max_minions": 9,
"minion_hp": 35.0,
"minion_speed": 165.0,
"split_chance": 0.5
}]
```
（max_minions 6→9；damage 16→22；minion_speed 130→165；lifetime 18→22；split_chance 0.35→0.5。cooldown/minion_hp 不动——minion_hp 当前无效字段。）

- [ ] **Step 2: import + 契约守卫**

Run:
```bash
"C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --import
"C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/test_evolution_contracts.gd
```
Expected: 契约 PASS（minions 9>3、damage 22≥14、lifetime 22≥11 仍守恒）。

- [ ] **Step 3: 提交**

```bash
git add data/weapons/horde.tres
git commit -m "balance(horde): 堆随从 DPS(minions6→9/dmg16→22/spd130→165/life18→22/split0.35→0.5),首轮加强假设"
```

---

## Task 7: 全量回归门（长 campaign 前的绿测闸）

**Files:** 无改动（验证任务）

- [ ] **Step 1: 跑全量 gdUnit**

Run（关编辑器）:
```bash
"C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests
```
Expected: 全绿。**精确核对用例数 = 508（基线）+ 12 新增 = 520**（Task1 +5：solo_spec×3、profile_for×1、floor grant×1；Task3 +7 契约）。若数字不符→排查截断陷阱（风险测试已排末位）。

- [ ] **Step 2: 确认无解析中止**

核对输出尾部 `Test Suites` / `Tests` 计数与套件数（应为原套件数 +1，即新增 `test_evolution_contracts.gd`）。

- [ ] **Step 3: 提交（若 Step1 暴露需修的测试基线，单独提交修法；否则跳过）**

无改动则不提交。

---

## Task 8: 实测 campaign 验证 + 迭代 + P2b 后衡报告

**Files:**
- Create: `docs/reviews/2026-06-20-evolution-rebalance-report.md`

**说明**：这是数值复衡的**真验证闭环**。重跑 campaign → 看落带 → off-band 则回 Task 4-6 调数值再跑 → 达标后出报告。**跑前关编辑器。**

- [ ] **Step 1: 重跑主 campaign（11 solo，新目录避免 stale 混淆）**

Run（后台，~2h）:
```bash
pwsh -NoProfile -File tools/run_p2a_campaign.ps1 -OutDir telemetry/p2b_main
```
（脚本默认 11 武器 × 8 种子 `--fixed-fps 60 --fast=8 --maxtime=600`，末尾自动跑 analyze_evolutions。）
Expected: 88 run 完成，打印进化表（reached/kpm/effect/verdict）。

- [ ] **Step 2: 跑地板 campaign（3 不可达进化）**

Run:
```bash
pwsh -NoProfile -File tools/run_p2b_floor_campaign.ps1
```
Expected: 24 run 完成，打印地板辈进化表（knife/orb/whip 现应 reached>0）。

- [ ] **Step 3: 判落带 + 迭代**

读 `telemetry/p2b_main/report.json` 的 flags：
- **inferno_aura / cyclone**：verdict 应为 `ok`（kpm 落 ±35% 带内、不掉底）。若仍 `OP`→回 Task 4/5 再砍（如 aura radius 再 −10、cyclone pierce 再 −1）重跑 Step 1。若变 `weak`（过校正掉底）→回调数值。
- **horde**：`reached>0.63` 维持、`death_ratio` 显著降（目标 <0.5）、`survived_post_med`↑、`hp_min_post_med`↑。若仍 8/8 死→按 spec §3c contingency 升级防御杠杆（horde 本体减伤或随从 lifesteal，需改 `reanimate_weapon.gd`/`roaming_minion.gd` + 补契约/单测，作 Task 6b）。
- **新中位复查**：用 p2b_main 新跨进化中位复查 thunderstorm 及五个原平衡区进化无被动破带。
- **地板辈**（p2b_floor）：对三者地板同辈基准判 verdict；仅明显 off-band（effect >+50% 或 <−50% 且 death 高）才回 Task 4-6 式改数值，否则记「P3 真混编遥测」。

每次迭代改 `.tres` 后须：`--import` → 跑契约守卫绿 → 重跑相关档（可只跑改动武器加速，最终全跑）。

- [ ] **Step 4: C5 聚合稳定抽检**

对一个种子两跑 diff（确定性回归）:
```bash
"C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --fixed-fps 60 --path . -- --bot=kite --cards=solo_aura --seed=42 --fast=8 --maxtime=600 --out=telemetry/c5_a
"C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --fixed-fps 60 --path . -- --bot=kite --cards=solo_aura --seed=42 --fast=8 --maxtime=600 --out=telemetry/c5_b
```
比对两 `*.summary.json` 的聚合字段（kills/survived/level）一致（C5 放宽为聚合稳定，非逐字节）。

- [ ] **Step 5: 写 P2b 后衡报告**

Create `docs/reviews/2026-06-20-evolution-rebalance-report.md`，含：① 复衡前后对照表（inferno_aura/cyclone/horde 的 kpm/reached/death/survived/hp_min + verdict，前=P2a 报告值，后=p2b_main）；② 地板辈子表（knife/orb/whip 在 solofloor_ 下的 reached/kpm/verdict + perk_hp×K 偏移 caveat）；③ 新跨进化中位 + thunderstorm/原平衡区破带复查；④ 质变守恒契约核对（7 守卫全绿）；⑤ 退出判据逐条核对（对照 spec §7）；⑥ 残留/转 P3 项（地板辈未定论的进化、horde 若用了 contingency）。

- [ ] **Step 6: 提交报告**

```bash
git add docs/reviews/2026-06-20-evolution-rebalance-report.md
git commit -m "docs(review): P2b 进化复衡后衡报告(落带核对+地板辈子表+中位漂移复查)"
```

---

## Task 9: 收尾（finishing-a-development-branch）

- [ ] **Step 1: 终验全绿**

Run: 全量 gdUnit（同 Task 7 Step1），确认 520 绿无截断。

- [ ] **Step 2: 走 finishing-a-development-branch 技能**

**REQUIRED SUB-SKILL:** Use superpowers:finishing-a-development-branch —— 验证测试 → 检测环境 → 给 4 选项 → 执行（预期合并回 master，FF）。

---

## Self-Review（对照 spec 核查）

- **Spec §3a/3b/3c 复衡** → Task 4/5/6（数值）+ Task 8（落带验证迭代）✅
- **Spec §3d 复衡回归 + 中位漂移复查** → Task 8 Step1/Step3 ✅
- **Spec §4a 地板 harness 档** → Task 1（solo_spec/floor grant）✅
- **Spec §4b 地板判据 + 条件复衡** → Task 2（分析器）+ Task 8 Step2/3（地板辈基准、仅 off-band 才改）✅
- **Spec §5.1 质变守恒契约** → Task 3 ✅
- **Spec §5.2 地板档 harness 逻辑测试** → Task 1 集成测试 ✅
- **Spec §5.3 截断核对** → Task 7（精确 520）✅
- **Spec §6 文件结构** → 文件表逐一对应 ✅
- **Spec §7 退出判据** → Task 8 Step3/5 逐条核对 + Task 9 终验 ✅
- **Spec §8 风险**（过校正/horde 不够/地板扭曲/campaign 耗时）→ Task 8 Step3 迭代逻辑 + contingency + 后台跑 ✅
- **类型一致性**：`solo_spec` 返回键 `is_solo/is_floor/weapon_id` 在 Task1/Task2 一致；`FLOOR_PERK_HP_STACKS=5` 与集成测试 `+100.0` 一致（5×20）；契约 `_evo/_l3` 索引与各 `.tres` levels 长度一致（基础 3 级取末、进化 1 级取 0）✅
- **占位扫描**：无 TBD/TODO；所有数值、命令、代码块均具体 ✅
