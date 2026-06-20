# P3b 进化复衡 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 据 P3 已验证的 backlog 主轴判据 + 混编 A/B 边际终判，复衡 5 个进化（削 nuke/thunderstorm/earthshatter 清场、削 thousand_edge 满血恒暴击上限、质变重做 mega_orb 为宽轨+扑击 AoE），守 C4 质变守恒、数据闭环迭代到带。

**Architecture:** 四类改动——① **数值** `.tres`（5 个进化的清场/暴击/护盾杠杆）；② **一处武器行为** `orb_shield.gd` 的 dash 到点 AoE（mega_orb 质变核心，真 TDD red-green）；③ **守卫测试**：扩 `test_evolution_contracts.gd` 锁 5 进化质变守恒，把既有硬编码反射/行为测试转**动态 WeaponDB 引用**（支持数据闭环迭代不改测试）；④ **campaign 验证**：复用 P3 工具（solo `run_p2a_campaign.ps1` + `analyze_dominance.gd`；混编 `run_p3_mix_campaign.ps1` + `analyze_mix_ab.gd`）迭代到带。

**Tech Stack:** Godot 4.7 GDScript；gdUnit4（headless）；PowerShell campaign 脚本；遥测 tick CSV / events JSONL / summary JSON。

## Global Constraints

- **引擎 Godot 4.7**；CLI 一律用 `C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe`（GUI 版 headless 抓不到 stdout）。
- **跑任何 headless（测试/campaign）前先关 Godot 编辑器**（LimboAI 双实例 DLL 冲突陷阱）。
- **确定性靠 `--fixed-fps 60`**（不是 `--fast`）；campaign 配方 `--bot=kite --fast=8 --maxtime=600`，种子 `7 42 101 1 2 3 4 5`（同 P2a/P2b/P3）。
- **C6 截断陷阱**：新测试**排套件末尾**；GREEN 态**核对发现用例数 == 预期**，别只看全绿，风险测试排最后。
- **数值复衡数据闭环**：`.tres` 首轮值是**假设非终值**；每轮改后重跑相关 campaign 看落带，迭代到达标（spec §2）。
- **守 C4 质变守恒**：复衡后每进化在设计意图轴严格 ≥ base 武器满级 L3（契约测试永久锁，spec §6）。
- **gdUnit 全量**：`& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`（**必须 `--ignoreHeadlessMode`** 否则退出码 103）。
- 单文件套件：把 `-a res://tests` 换成 `-a res://tests/test_evolution_contracts.gd`（或对应文件）。
- 上位 spec：[docs/superpowers/specs/2026-06-21-p3b-evolution-rebalance-design.md](../specs/2026-06-21-p3b-evolution-rebalance-design.md)。
- **绝不 `git add -A`**（仓库 ~2500 未追踪 + 一批预存 M 的 .tscn/.import/project.godot 非本轮改动）；每任务只 `git add` 该任务碰的文件。

---

### Task 0: 分支确认 + 基线用例数

分支 `feat/p3b-evolution-rebalance` 已建（spec 提交所在）。本任务确认起点 + 锚定基线测试数（C6 核对依据）。

- [ ] **Step 1: 确认分支与干净起点**

Run: `git branch --show-current && git log --oneline -2`
Expected: 分支 = `feat/p3b-evolution-rebalance`；HEAD 两条为 spec 提交 + spec 纠错提交。

- [ ] **Step 2: 关编辑器，跑全量测试锚定基线**

Run: `& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path D:\Workspace\GAME\game_0_vsl -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: 全绿 0 error；**记录 GdUnit 末尾打印的发现/执行用例总数 N0**（spec 预期 543，以实测为准）。本 plan 完成时预期 = **N0 + 6**（+5 契约 + 1 dash AoE 行为）。

---

### Task 1: 工作流 A · nuke 削清场（solo 验证组，数值 + 契约）

**Files:**
- Modify: `data/weapons/nuke.tres`（`levels[0]`：field_dur/cooldown/blast_radius）
- Modify: `tests/test_card_pool.gd`（`test_apply_evolve_explosion_grants_nuke` 的 cooldown 断言转动态）
- Modify: `tests/test_evolution_contracts.gd`（末尾加 nuke 守恒契约）

**Interfaces:**
- Consumes: `WeaponDB.get_data("nuke"/"explosion").levels`；既有 `_evo()`/`_l3()` 私有助手（test_evolution_contracts.gd）。
- Produces: nuke.tres 新值 field_dur=3.0 / cooldown=0.7 / blast_radius=112.0；契约 `test_nuke_clearing_ge_base_l3`。

- [ ] **Step 1: 加 nuke 守恒契约**（追加到 `tests/test_evolution_contracts.gd` 末尾）

```gdscript
# ── nuke ≥ explosion L3(全屏覆盖/地火/二连爆身份) ──────────────────────────
func test_nuke_clearing_ge_base_l3() -> void:
	var nuke := _evo("nuke")
	var l3 := _l3("explosion")
	assert_float(float(nuke["blast_radius"])).is_greater_equal(float(l3["blast_radius"]))  # 覆盖 ≥ base
	assert_float(float(nuke["burn_dps"])).is_greater_equal(float(l3["burn_dps"]))          # 地火 ≥ base
	assert_float(float(nuke["field_dur"])).is_greater_equal(float(l3["field_dur"]))        # 地火时长 ≥ base
	assert_float(float(nuke["cooldown"])).is_less_equal(float(l3["cooldown"]))             # 引爆不慢于 base
	assert_int(int(nuke.get("secondary_count", 0))).is_greater(0)                          # 二连爆=质变身份(base 无)
```

- [ ] **Step 2: 把 test_card_pool 的 nuke cooldown 断言转动态**（避免每轮迭代改测试）

在 `tests/test_card_pool.gd` `test_apply_evolve_explosion_grants_nuke`，把：
```gdscript
			assert_float(child.cooldown).is_equal_approx(0.5, 0.001)
```
替换为：
```gdscript
			assert_float(child.cooldown).is_equal_approx(float(WeaponDB.get_data("nuke").levels[0]["cooldown"]), 0.001)
```

- [ ] **Step 3: 跑测试确认当前绿（契约在旧值下也成立=守卫，非 red 驱动）**

Run: `& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_evolution_contracts.gd`
（`$Godot` = `C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe`，下同）
Expected: 全绿（旧 nuke field_dur=4.0≥3.0、blast_radius=128≥100、cooldown=0.5≤1.3 均成立）。

- [ ] **Step 4: 改 nuke.tres 数值**

把 `data/weapons/nuke.tres` `levels[0]` 三个字段改为：
```
"blast_radius": 112.0,
...
"cooldown": 0.7,
...
"field_dur": 3.0,
```
（其余 blast_scale/blast_tint/burn_dps/damage/secondary_count/secondary_delay 不动。）

- [ ] **Step 5: 跑相关套件确认仍绿**

Run: `... -a res://tests/test_evolution_contracts.gd` 然后 `... -a res://tests/test_card_pool.gd`
Expected: 两套件全绿（契约：blast_radius112≥100、field_dur3≥3、cooldown0.7≤1.3；card_pool：cooldown 动态匹配 0.7）。

- [ ] **Step 6: 提交**

```bash
git add data/weapons/nuke.tres tests/test_evolution_contracts.gd tests/test_card_pool.gd
git commit -m "feat(p3b): nuke 削清场(field_dur4->3/cd0.5->0.7/blast128->112)+质变守恒契约"
```

---

### Task 2: 工作流 A · thunderstorm 削清场（数值 + 契约）

**Files:**
- Modify: `data/weapons/thunderstorm.tres`（`levels[0]`：sky_strikes/cooldown/chains）
- Modify: `tests/test_weapons_new.gd`（`test_evolve_lightning_grants_thunderstorm` chains 断言转动态）
- Modify: `tests/test_weapons_w3b.gd`（`test_tempest_reflects_sky_strikes` chains 断言转动态）
- Modify: `tests/test_evolution_contracts.gd`（末尾加 thunderstorm 守恒契约）

**Interfaces:**
- Produces: thunderstorm.tres 新值 sky_strikes=2 / cooldown=0.6 / chains=6；契约 `test_thunderstorm_clearing_ge_base_l3`。

- [ ] **Step 1: 加 thunderstorm 守恒契约**（追加 `tests/test_evolution_contracts.gd` 末尾）

```gdscript
# ── thunderstorm ≥ lightning L3(连锁 + 天雷身份) ──────────────────────────
func test_thunderstorm_clearing_ge_base_l3() -> void:
	var ts := _evo("thunderstorm")
	var l3 := _l3("lightning")
	assert_int(int(ts["chains"])).is_greater_equal(int(l3["chains"]))          # 连锁 ≥ base
	assert_float(float(ts["cooldown"])).is_less_equal(float(l3["cooldown"]))   # 不慢于 base
	assert_int(int(ts.get("sky_strikes", 0))).is_greater(0)                    # 天雷=质变身份(base 无)
```

- [ ] **Step 2: 两处 chains 硬编码断言转动态**

`tests/test_weapons_new.gd` `test_evolve_lightning_grants_thunderstorm`，把：
```gdscript
	assert_int(_player.get_weapon_node("thunderstorm").get("chains")).is_equal(8)
```
替换为：
```gdscript
	assert_int(_player.get_weapon_node("thunderstorm").get("chains")).is_equal(int(WeaponDB.get_data("thunderstorm").levels[0]["chains"]))
```

`tests/test_weapons_w3b.gd` `test_tempest_reflects_sky_strikes`，把：
```gdscript
	assert_int(w.get("chains")).is_equal(8)
```
替换为：
```gdscript
	assert_int(w.get("chains")).is_greater(int(WeaponDB.get_data("lightning").levels[2]["chains"]))  # 进化连锁 > base lightning L3(5)
```

- [ ] **Step 3: 改 thunderstorm.tres 数值**

`data/weapons/thunderstorm.tres` `levels[0]`：
```
"chains": 6,
"cooldown": 0.6,
...
"sky_strikes": 2
```
（bolt_tint/damage/shock_dur/sky_damage/sky_radius 不动。）

- [ ] **Step 4: 跑相关套件确认绿**

Run: `... -a res://tests/test_evolution_contracts.gd`、`... -a res://tests/test_weapons_new.gd`、`... -a res://tests/test_weapons_w3b.gd`
Expected: 全绿（契约 chains6≥5、cd0.6≤0.7、sky_strikes2>0；new：chains 动态匹配 6；w3b：6>5）。

- [ ] **Step 5: 提交**

```bash
git add data/weapons/thunderstorm.tres tests/test_evolution_contracts.gd tests/test_weapons_new.gd tests/test_weapons_w3b.gd
git commit -m "feat(p3b): thunderstorm 削清场(sky_strikes3->2/cd0.45->0.6/chains8->6)+契约"
```

---

### Task 3: 工作流 A · earthshatter 削清场（数值 + 契约）

**Files:**
- Modify: `data/weapons/earthshatter.tres`（`levels[0]`：shockwave_radius/shockwave_damage）
- Modify: `tests/test_weapons_w3b.gd`（`test_earthshatter_shockwave_hits_far_ring_and_slows` 敌位转动态、稳健落环内）
- Modify: `tests/test_evolution_contracts.gd`（末尾加 earthshatter 守恒契约）

**Interfaces:**
- Produces: earthshatter.tres 新值 shockwave_radius=240.0 / shockwave_damage=32.0；契约 `test_earthshatter_shockwave_ge_base_l3`。

- [ ] **Step 1: 加 earthshatter 守恒契约**（追加 `tests/test_evolution_contracts.gd` 末尾）

```gdscript
# ── earthshatter ≥ maul L3(命中身份)+ 冲击波质变 ──────────────────────────
func test_earthshatter_shockwave_ge_base_l3() -> void:
	var es := _evo("earthshatter")
	var l3 := _l3("maul")
	assert_float(float(es["damage"])).is_greater_equal(float(l3["damage"]))      # 命中伤 ≥ base
	assert_float(float(es["radius"])).is_greater_equal(float(l3["radius"]))       # 命中半径 ≥ base
	assert_float(float(es.get("shockwave_radius", 0.0))).is_greater(0.0)          # 冲击波=质变身份(base 无)
	assert_float(float(es["shockwave_radius"])).is_greater(float(es["radius"]))   # 环带必须超出命中半径才有意义
```

- [ ] **Step 2: earthshatter 行为测试敌位转稳健（落新环带内，不踩边界）**

`tests/test_weapons_w3b.gd` `test_earthshatter_shockwave_hits_far_ring_and_slows`，把：
```gdscript
	# 落在初始 radius(170) 外、shockwave_radius(280) 内
	var e := _tough_enemy_at(Vector2(240, 0))
```
替换为：
```gdscript
	# 落在初始 radius 外、shockwave_radius 内(取环带中点,随复衡仍稳健)
	var sw: float = float(WeaponDB.get_data("earthshatter").levels[0]["shockwave_radius"])
	var rad: float = float(WeaponDB.get_data("earthshatter").levels[0]["radius"])
	var e := _tough_enemy_at(Vector2((rad + sw) * 0.5, 0))
```

- [ ] **Step 3: 改 earthshatter.tres 数值**

`data/weapons/earthshatter.tres` `levels[0]`：
```
"shockwave_damage": 32.0,
"shockwave_radius": 240.0,
```
（cooldown/damage/knockback/radius/shockwave_slow/shockwave_slow_dur/stun_dur 不动。）

- [ ] **Step 4: 跑相关套件确认绿**

Run: `... -a res://tests/test_evolution_contracts.gd`、`... -a res://tests/test_weapons_w3b.gd`
Expected: 全绿（契约 damage72≥72、radius170≥170、shockwave_radius240>0 且 >170；w3b：敌落 205 处在 170~240 环带内被命中 + slow）。

- [ ] **Step 5: 提交**

```bash
git add data/weapons/earthshatter.tres tests/test_evolution_contracts.gd tests/test_weapons_w3b.gd
git commit -m "feat(p3b): earthshatter 削清场(shockwave r280->240/dmg40->32)+契约"
```

---

### Task 4: 工作流 B · thousand_edge 削满血恒暴击上限（数值 + 契约）

**Files:**
- Modify: `data/weapons/thousand_edge.tres`（`levels[0]`：crit_bonus/volley/cooldown）
- Modify: `tests/test_card_pool.gd`（`test_apply_evolve_knife_grants_thousand_edge` cooldown 断言转动态）
- Modify: `tests/test_weapons_w3b.gd`（`test_arrow_storm_reflects_volley` crit_bonus 转动态、`test_arrow_storm_fires_volley_projectiles` 弹数转动态）
- Modify: `tests/test_evolution_contracts.gd`（末尾加 thousand_edge 守恒契约）

**Interfaces:**
- Consumes: `knife_weapon.gd` 的 `longbow_crit_bonus`（暴击门控：`dist>crit_range OR full_hp → crit_bonus`）。
- Produces: thousand_edge.tres 新值 crit_bonus=0.6 / volley=3 / cooldown=0.22（crit_range/pierce/damage 不动）；契约 `test_thousand_edge_ceiling_ge_base_l3`。

> ⚠ **不降 crit_range**：`longbow_crit_bonus` 是 `dist>crit_range` 才给暴击；crit_range99999 使暴击纯由满血门控，降它会让远敌也暴=反向 buff。削法=降 crit_bonus（恒暴击→概率暴击）。详见 spec §4。

- [ ] **Step 1: 加 thousand_edge 守恒契约**（追加 `tests/test_evolution_contracts.gd` 末尾）

```gdscript
# ── thousand_edge ≥ knife L3(多发/穿透/射速/暴击轴,不锁单发 damage) ─────────
func test_thousand_edge_ceiling_ge_base_l3() -> void:
	var te := _evo("thousand_edge")
	var l3 := _l3("knife")
	assert_int(int(te.get("volley", 0))).is_greater_equal(2)                       # 多发身份(base knife 无 volley=单发)
	assert_int(int(te["pierce"])).is_greater_equal(int(l3["pierce"]))              # 穿透 ≥ base
	assert_float(float(te["cooldown"])).is_less_equal(float(l3["cooldown"]))       # 不慢于 base
	assert_float(float(te["crit_bonus"])).is_greater_equal(float(l3["crit_bonus"]))# 暴击加成 ≥ base(防过砍暴击轴退化)
```

- [ ] **Step 2: 三处硬编码断言转动态**

`tests/test_card_pool.gd` `test_apply_evolve_knife_grants_thousand_edge`，把：
```gdscript
			assert_float(child.cooldown).is_equal_approx(0.15, 0.001)
			assert_int(child.pierce).is_equal(8)
```
替换为：
```gdscript
			assert_float(child.cooldown).is_equal_approx(float(WeaponDB.get_data("thousand_edge").levels[0]["cooldown"]), 0.001)
			assert_int(child.pierce).is_equal(int(WeaponDB.get_data("thousand_edge").levels[0]["pierce"]))
```

`tests/test_weapons_w3b.gd` `test_arrow_storm_reflects_volley`，把：
```gdscript
	assert_float(w.get("crit_bonus")).is_equal_approx(1.0, 0.001)
```
替换为：
```gdscript
	assert_float(w.get("crit_bonus")).is_equal_approx(float(WeaponDB.get_data("thousand_edge").levels[0]["crit_bonus"]), 0.001)
```

`tests/test_weapons_w3b.gd` `test_arrow_storm_fires_volley_projectiles`，把：
```gdscript
	# 齐射 5 发 → ysort 下至少 5 个投射体
	assert_int(ys.get_child_count()).is_greater_equal(5)
```
替换为：
```gdscript
	# 齐射 volley 发 → ysort 下至少 volley 个投射体(动态,随复衡仍稳健)
	assert_int(ys.get_child_count()).is_greater_equal(int(WeaponDB.get_data("thousand_edge").levels[0]["volley"]))
```

- [ ] **Step 3: 改 thousand_edge.tres 数值**

`data/weapons/thousand_edge.tres` `levels[0]`：
```
"cooldown": 0.22,
"crit_bonus": 0.6,
...
"volley": 3
```
（crit_range/damage/pierce/proj_scale/proj_speed/proj_tint 不动。）

- [ ] **Step 4: 跑相关套件确认绿**

Run: `... -a res://tests/test_evolution_contracts.gd`、`... -a res://tests/test_card_pool.gd`、`... -a res://tests/test_weapons_w3b.gd`
Expected: 全绿（契约 volley3≥2、pierce8≥4、cd0.22≤0.5、crit_bonus0.6≥0.35；card_pool cooldown 动态匹配 0.22、pierce8；w3b crit_bonus 动态 0.6、弹数 ≥3）。

- [ ] **Step 5: 提交**

```bash
git add data/weapons/thousand_edge.tres tests/test_evolution_contracts.gd tests/test_card_pool.gd tests/test_weapons_w3b.gd
git commit -m "feat(p3b): thousand_edge 削绕冷却上限(crit_bonus1.0->0.6 恒暴击转概率/volley5->3/cd0.15->0.22)+契约"
```

---

### Task 5: 工作流 C · mega_orb dash 到点 AoE 行为（真 TDD red-green）

**Files:**
- Modify: `scenes/weapons/orb/orb_shield.gd`（新增 `dash_aoe_radius`/`dash_aoe_damage` + `_apply_dash_aoe()`，dash 到点调用）
- Modify: `scenes/weapons/orb/orb_weapon.gd`（新增同名 var + `_sync_shields()` 注入）
- Modify: `tests/test_weapons_w3b.gd`（末尾加 dash AoE 行为测试）

**Interfaces:**
- Consumes: `OrbShield._player`（Player，`_ready` 抓 get_parent）、`Enemy.take_damage`、`enemies` group；`OrbWeapon._sync_shields()`（既有，逐球注入字段）。
- Produces: `OrbShield._apply_dash_aoe(center: Vector2) -> void`（对 dash_aoe_radius 内全体造 dash_aoe_damage×damage_mult；radius/damage ≤0 时 no-op）；`OrbShield.dash_aoe_radius`/`dash_aoe_damage`（float，默认 0）；`OrbWeapon.dash_aoe_radius`/`dash_aoe_damage`（反射注入 + 逐球传递）。

- [ ] **Step 1: 写失败行为测试**（追加 `tests/test_weapons_w3b.gd` 末尾；OrbShieldScript 常量已在该文件 L131 定义）

```gdscript
# ── 缚刃 dash 到点 AoE(P3b 质变:扑击从单体接触→群伤爆裂) ────────────────────
func test_mega_orb_dash_aoe_damages_cluster() -> void:
	var orb = auto_free(OrbShieldScript.new())
	orb.dash_aoe_radius = 90.0
	orb.dash_aoe_damage = 24.0
	_player.add_child(orb)
	await get_tree().process_frame   # _ready 抓 _player
	var center := _player.global_position + Vector2(300, 0)
	var inside := _tough_enemy_at(center + Vector2(40, 0))    # 距 center 40 < 90 → 受群伤
	var outside := _tough_enemy_at(center + Vector2(200, 0))  # 距 center 200 > 90 → 不受
	orb._apply_dash_aoe(center)
	assert_float(inside.hp).is_less(500.0)
	assert_float(outside.hp).is_equal(500.0)

func test_orb_dash_aoe_noop_when_unset() -> void:
	# base orb(dash_aoe_radius/damage 默认 0)→ 扑击不造成 AoE(零影响守恒)
	var orb = auto_free(OrbShieldScript.new())
	_player.add_child(orb)
	await get_tree().process_frame
	var center := _player.global_position + Vector2(300, 0)
	var e := _tough_enemy_at(center)
	orb._apply_dash_aoe(center)
	assert_float(e.hp).is_equal(500.0)   # radius/damage=0 → no-op
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/test_weapons_w3b.gd`
Expected: `test_mega_orb_dash_aoe_damages_cluster` FAIL（`_apply_dash_aoe` 不存在 / inside 未受伤）；`test_orb_dash_aoe_noop_when_unset` 可能 error（方法缺失）。

- [ ] **Step 3: 实现 orb_shield.gd**

在 `scenes/weapons/orb/orb_shield.gd` dash 字段区（`var _dash_target` 附近）加两个字段：
```gdscript
var dash_aoe_radius: float = 0.0    # 进化(缚刃)：dash 到点群伤范围(0=不触发,base orb 无扑击)
var dash_aoe_damage: float = 0.0
```

在 `_update_dash()` 到点分支（`if global_position.distance_to(_dash_target.global_position) <= ORB_RADIUS:`）内、`_dashing = false` 之前插入 AoE 调用：
```gdscript
		if global_position.distance_to(_dash_target.global_position) <= ORB_RADIUS:
			_apply_dash_aoe(global_position)   # 质变:到点群伤爆裂
			_dashing = false
			_dash_t = 0.0
```

在文件末尾（`_tick_cooldowns` 之后）加方法：
```gdscript
# 扑击到点群伤(质变):对 dash_aoe_radius 内全体造 dash_aoe_damage(含玩家增伤)。
# radius/damage ≤0(base orb 默认)→ no-op,零影响。
func _apply_dash_aoe(center: Vector2) -> void:
	if dash_aoe_radius <= 0.0 or dash_aoe_damage <= 0.0:
		return
	var player := _player as Player
	var dmg := dash_aoe_damage * (player.damage_mult if player != null else 1.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if center.distance_to((enemy as Node2D).global_position) <= dash_aoe_radius:
			(enemy as Enemy).take_damage(dmg)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/test_weapons_w3b.gd`
Expected: 两个新测试绿；既有 orb 测试（dash_enabled/dashes_toward/per_orb_not_weaker）仍绿。

- [ ] **Step 5: 实现 orb_weapon.gd 注入**

在 `scenes/weapons/orb/orb_weapon.gd` 字段区（`var dash_interval` 之后）加：
```gdscript
var dash_aoe_radius: float = 0.0   # 进化(缚刃)注入:扑击到点群伤,逐球传递
var dash_aoe_damage: float = 0.0
```

在 `_sync_shields()` 的逐球注入循环末尾（`existing[i].dash_interval = dash_interval` 之后）加：
```gdscript
		existing[i].dash_aoe_radius = dash_aoe_radius
		existing[i].dash_aoe_damage = dash_aoe_damage
```

- [ ] **Step 6: 跑测试确认仍绿**

Run: `... -a res://tests/test_weapons_w3b.gd`、`... -a res://tests/test_card_pool.gd`
Expected: 全绿（注入字段不破坏既有；mega_orb.tres 尚未加 dash_aoe_* → OrbWeapon 反射注入跳过缺失键，保持默认 0，行为不变）。

- [ ] **Step 7: 提交**

```bash
git add scenes/weapons/orb/orb_shield.gd scenes/weapons/orb/orb_weapon.gd tests/test_weapons_w3b.gd
git commit -m "feat(p3b): orb_shield dash 到点 AoE 行为(mega_orb 质变核心)+orb_weapon 注入"
```

---

### Task 6: 工作流 C · mega_orb 宽轨 + AoE 数值 + 契约（启用质变）

**Files:**
- Modify: `data/weapons/mega_orb.tres`（`levels[0]`：orbit_radius/dash_interval/damage + 新键 dash_aoe_radius/dash_aoe_damage）
- Modify: `tests/test_evolution_contracts.gd`（末尾加 mega_orb 守恒契约）

**Interfaces:**
- Consumes: Task 5 的 `OrbWeapon.dash_aoe_radius`/`dash_aoe_damage` 注入路径。
- Produces: mega_orb.tres 新值 orbit_radius=120 / dash_interval=2.0 / damage=18 / dash_aoe_radius=90 / dash_aoe_damage=24；契约 `test_mega_orb_quale_redo`。

- [ ] **Step 1: 加 mega_orb 守恒契约**（追加 `tests/test_evolution_contracts.gd` 末尾）

```gdscript
# ── mega_orb 质变重做(宽轨 + 扑击 AoE) ≥ orb L3 + 新机制 ───────────────────
func test_mega_orb_quale_redo() -> void:
	var mo := _evo("mega_orb")
	var l3 := _l3("orb")
	assert_int(int(mo["total_orbs"])).is_greater(int(l3["total_orbs"]))         # 球数 > base
	assert_float(float(mo["orbit_radius"])).is_greater_equal(float(l3["orbit_radius"]))  # 轨半径 ≥ base(宽轨)
	assert_float(float(mo["damage"])).is_greater_equal(float(l3["damage"]))     # 环绕伤 ≥ base
	assert_float(float(mo.get("dash_aoe_radius", 0.0))).is_greater(0.0)         # 扑击 AoE=质变身份(base 无)
	assert_float(float(mo.get("dash_aoe_damage", 0.0))).is_greater(0.0)
```

- [ ] **Step 2: 跑契约确认当前失败**（mega_orb.tres 尚无 dash_aoe_* → red）

Run: `... -a res://tests/test_evolution_contracts.gd`
Expected: `test_mega_orb_quale_redo` FAIL（`dash_aoe_radius`/`dash_aoe_damage` 键不存在 → get 默认 0.0 → 断言 >0 失败）。其余契约绿。

- [ ] **Step 3: 改 mega_orb.tres 数值（加新键、改宽轨）**

把 `data/weapons/mega_orb.tres` `levels[0]` 整体改为：
```
levels = [{
"damage": 18.0,
"dash_aoe_damage": 24.0,
"dash_aoe_radius": 90.0,
"dash_enabled": true,
"dash_interval": 2.0,
"hit_cooldown": 0.3,
"orbit_radius": 120.0,
"total_orbs": 8
}]
```

- [ ] **Step 4: 跑契约 + card_pool + w3b 确认绿**

Run: `... -a res://tests/test_evolution_contracts.gd`、`... -a res://tests/test_card_pool.gd`、`... -a res://tests/test_weapons_w3b.gd`
Expected: 全绿。契约：total_orbs8>4、orbit_radius120≥68、damage18≥14、dash_aoe_radius/damage>0。w3b `test_mega_orb_per_orb_not_weaker_than_maxed_orb`（动态 vs orb 满级）：damage18≥14、hit_cooldown0.3≤0.3、orbit_radius120≥68、total_orbs8>4 ✓。card_pool `test_apply_evolve_orb_grants_mega_orb`：total_orbs==8 ✓（不动）。

- [ ] **Step 5: 提交**

```bash
git add data/weapons/mega_orb.tres tests/test_evolution_contracts.gd
git commit -m "feat(p3b): mega_orb 质变重做(orbit68->120 宽轨/dash_aoe r90 dmg24/dmg14->18/dash_interval3->2)+契约"
```

---

### Task 7: 全量回归 + C6 核数

**Files:** 无改动（纯验证）。

- [ ] **Step 1: 关编辑器，跑全量 gdUnit**

Run: `& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: 全绿 0 error；**发现/执行用例总数 == N0 + 6**（Task 0 锚定的 N0 加：契约 +5〔nuke/thunderstorm/earthshatter/thousand_edge/mega_orb〕、dash AoE 行为 +2〔damages_cluster/noop_when_unset〕= +7）。

> 修正：本 plan 新增 **+7** 个用例（不是设计 spec 估的 +6——dash AoE 行为拆成 2 个用例更严谨）。预期总数 = **N0 + 7**。若数字不符 → C6 截断陷阱，排查（风险测试已在各套件末尾）。

- [ ] **Step 2: 若数字不符则排查截断**

逐套件单跑 `test_evolution_contracts.gd` / `test_weapons_w3b.gd`，核对各自用例数（contracts 原 8 + 5 = 13；w3b 原数 + 3）。定位静默吞测试的解析/断言错误，修复后重跑。

---

### Task 8: 工作流 A 验证 · solo campaign 重跑 + 落带（数据闭环）

**Files:**
- 可能 Modify: `data/weapons/nuke.tres` / `thunderstorm.tres` / `earthshatter.tres`（仅当首轮未落带需补刀）
- Create: `docs/reviews/2026-06-21-evolution-rebalance-p3b-report.md`（骨架 + §A nuke 类落带结果）

**这是测量/迭代任务，不是 TDD。** 退出判据 spec §8#1。

- [ ] **Step 1: 关编辑器，跑全量 solo campaign（11×8，重算跨进化中位）**

Run: `pwsh tools/run_p2a_campaign.ps1`（若脚本 out 默认非 p3b，传 `-OutDir telemetry/p3b_solo`；先 `Get-Content tools/run_p2a_campaign.ps1 -TotalCount 30` 确认参数名）
Expected: 88 run（11 武器 × 8 种子）全跑完，各打印终局行。耗时约 1.5–2h（--fast=8）。

- [ ] **Step 2: 重算支配判据**

Run: `& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://tools/analyze_dominance.gd -- --dir=telemetry/p3b_solo --report=telemetry/p3b_solo/dominance_report.json`
Expected: 打印 11 行 verdict 表（含 `verdict_new`、backlog、clear_eff、hp_min）。

- [ ] **Step 3: 核退出判据 §8#1**

- nuke/thunderstorm/earthshatter 的 `verdict_new` 应从 **OP → ok**（backlog 升入带、clear_eff 落带上沿、**不掉底**=不翻 weak）。
- 用新跨进化中位复查未动进化（cyclone/inferno_aura/frostbite/gravity_well/boomerang/reanimate）**无新 OP**（被动破带）。
- **若 ≥1 个仍 OP**：按 spec §2「砍带顶看数据补刀」补刀该进化的次级杠杆（nuke→blast_radius 再降/secondary 去；thunderstorm→sky_radius/sky_damage 降；earthshatter→shockwave_radius 再降），守契约下沿，重跑 Step 1–2。
- **若有进化掉底翻 weak**（过校正）：回调该字段（首轮砍轻原则），重跑。
- **若未动进化被动破带**：纳入本轮微调（spec §1 非目标的例外条款），或报告披露。

- [ ] **Step 4: 落带结果入报告 §A + 提交**

新建 `docs/reviews/2026-06-21-evolution-rebalance-p3b-report.md`，写：标题/定位（承 P3 §4b + spec）、§0 一句话、§A 工作流 A（前后 verdict 对照表 + 中位漂移复查 + 不掉底核）、§B/§C 占位。
```bash
# 若 Step 3 触发补刀:
git add data/weapons/*.tres docs/reviews/2026-06-21-evolution-rebalance-p3b-report.md
git commit -m "chore(p3b): nuke 类落带(verdict OP->ok)+报告 §A"
# 若首轮即达标(无补刀):
git add docs/reviews/2026-06-21-evolution-rebalance-p3b-report.md
git commit -m "docs(p3b): 工作流 A solo 验证落带报告 §A"
```

> ⚠ 跑前关编辑器（LimboAI 双实例）。补刀改 .tres 后契约测试须仍绿（守恒下沿未破）——补刀提交前快跑 `... -a res://tests/test_evolution_contracts.gd`。

---

### Task 9: 工作流 B/C 验证 · 混编 A/B 重跑 + 终判（数据闭环）

**Files:**
- 可能 Modify: `data/weapons/thousand_edge.tres`（边际仍 > 控制组则补刀 pierce/volley）
- 可能 Modify: `data/weapons/mega_orb.tres` / `scenes/weapons/orb/orb_shield.gd`（边际仍偏弱则补强 / 过冲则回收）
- Modify: `docs/reviews/2026-06-21-evolution-rebalance-p3b-report.md`（§B/§C 终判）

**这是测量/迭代任务。** 退出判据 spec §8#2/#3。

- [ ] **Step 1: 关编辑器，跑混编 A/B campaign**

Run: `pwsh tools/run_p3_mix_campaign.ps1 -OutDir telemetry/p3b_mix`（默认 Targets=knife,orb,explosion；先 `Get-Content tools/run_p3_mix_campaign.ps1 -TotalCount 20` 确认参数）
Expected: mixbase + mix_{knife,orb,explosion} × 8 种子 = 32 run。脚本末尾自动调 analyze_mix_ab。

- [ ] **Step 2: A/B 边际归因**

Run（若 Step 1 未自动出表）: `& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://tools/analyze_mix_ab.gd -- --dir=telemetry/p3b_mix`
Expected: 打印每目标 reached / backlog_mix / backlog_base / **marginal** / clear_eff / hp_min。

- [ ] **Step 3: 核退出判据 §8#2/#3**

- **thousand_edge**（§8#2）：marginal 应 **≤ 控制组 explosion** 的 marginal（消「强清场+安全」OP 签名；P3 基线 knife +16 vs explosion +25，复衡后 explosion 也降，要求 knife ≤ explosion）。
  - 仍 > 控制组 → 补刀：pierce 8→6（或 volley 3→2），重跑。守契约（pierce≥4、volley≥2）。
- **mega_orb**（§8#3）：marginal 应**显著 >+3**（P3 基线）、hp_min **显著 >0.18**、未翻 OP（不应 ≈ 控制组 nuke 或更高）。
  - 仍偏弱（marginal 未升 / hp 未改善）→ 补强：dash_aoe_damage 24→32 或 orbit_radius 120→140 或 dash_interval 2→1.5，重跑。
  - 过冲翻 OP（marginal ≈ 控制组）→ 回收：dash_aoe_damage 降 / orbit_radius 降，重跑。
- reached 应仍 8/8（底盘未动）。

- [ ] **Step 4: 终判入报告 §B/§C + 提交**

把 A/B 终判表 + thousand_edge/mega_orb 前后对照写入报告 §B/§C。
```bash
git add data/weapons/thousand_edge.tres data/weapons/mega_orb.tres scenes/weapons/orb/orb_shield.gd docs/reviews/2026-06-21-evolution-rebalance-p3b-report.md
git commit -m "chore(p3b): thousand_edge/mega_orb 混编 A/B 落带终判 + 报告 §B/§C"
# (仅 add 实际改了的文件)
```

> ⚠ 每次补刀改 .tres/.gd 后,提交前快跑契约 + w3b 套件确认绿(守恒未破、行为未坏)。

---

### Task 10: 收尾 · 全量回归 + C5 确定性 + 报告定稿

**Files:**
- Modify: `docs/reviews/2026-06-21-evolution-rebalance-p3b-report.md`（§退出判据核对 + §残留/下一步）

- [ ] **Step 1: 关编辑器，全量 gdUnit 终验**

Run: `& $Godot --headless --path D:\Workspace\GAME\game_0_vsl -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
Expected: 全绿 0 error；用例数 == N0 + 7（C6）。

- [ ] **Step 2: C5 确定性抽查（改动相关档同种子两跑）**

Run（mix_orb seed 7 两跑，比对 summary 关键字段）:
```
& $Godot --headless --fixed-fps 60 --path D:\Workspace\GAME\game_0_vsl -- --bot=kite --cards=mix_orb --seed=7 --fast=8 --maxtime=600 --out=telemetry/p3b_c5/mix_orb_s7_a
& $Godot --headless --fixed-fps 60 --path D:\Workspace\GAME\game_0_vsl -- --bot=kite --cards=mix_orb --seed=7 --fast=8 --maxtime=600 --out=telemetry/p3b_c5/mix_orb_s7_b
```
Expected: 两跑 summary 的 outcome/level/kills/survived 聚合稳定（dash AoE 无新 RNG，最近敌 + group 遍历确定性；后期有界不确定按 P2b 用户裁决不要求逐字节）。

- [ ] **Step 3: 报告定稿（退出判据逐条核对）**

在 `docs/reviews/2026-06-21-evolution-rebalance-p3b-report.md` 写 §退出判据核对表（逐条对照 spec §8）+ §残留局限/下一步（如二轮补刀记录、未纳入的 inferno_aura 手感 / base 可达性指向内容广度阶段）。

- [ ] **Step 4: 提交**

```bash
git add docs/reviews/2026-06-21-evolution-rebalance-p3b-report.md
git commit -m "docs(p3b): 退出判据核对 + C5 确定性 + 残留/下一步(P3b 复衡完成)"
```

---

## Self-Review（plan vs spec 覆盖核对）

- **spec §3a nuke** → Task 1 ✓；**§3b thunderstorm** → Task 2 ✓；**§3c earthshatter** → Task 3 ✓（含 §3d solo 验证 → Task 8）。
- **spec §4 thousand_edge** → Task 4 ✓（crit_bonus 非 crit_range，机制纠错已并入）；混编验证 → Task 9。
- **spec §5a mega_orb 行为** → Task 5 ✓；**§5b 数值** → Task 6 ✓；**§5c 混编验证** → Task 9。
- **spec §6 契约（5 条）** → Task 1/2/3/4/6 各加一条 ✓；mega_orb dash AoE 行为测试 → Task 5 ✓。
- **spec §8 退出判据** → Task 7（全绿+C6）/ Task 8（§8#1）/ Task 9（§8#2/#3）/ Task 10（§8#4-6）✓。
- **spec §7 文件结构** → 全部文件在对应 task 的 Files 块 ✓；复用工具不改 ✓。
- **类型一致性**：`_apply_dash_aoe(center: Vector2)` 在 Task 5 定义、Task 5 测试调用，签名一致 ✓；`dash_aoe_radius`/`dash_aoe_damage` 在 orb_shield.gd（Task5）/orb_weapon.gd（Task5）/mega_orb.tres（Task6）/契约（Task6）命名一致 ✓。
- **无占位符**：所有代码步含完整代码 + 精确命令 + 预期 ✓。
- **用例数修正**：Task 7/10 用 N0+7（dash AoE 拆 2 用例），spec §8#5 估算的 543+6 以此为准（实测 N0 锚定）。
