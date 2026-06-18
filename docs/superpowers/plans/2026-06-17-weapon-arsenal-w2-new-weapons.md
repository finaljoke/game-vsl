# 武器军械库重做 W2：新增 3 把武器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **PREREQUISITE: W0 必须先合入。** 本计划消费 W0 的 `Enemy.apply_status`（slow/freeze/stun）、`Enemy.apply_impulse`（击退/拉拽）。见 `2026-06-17-weapon-arsenal-w0-foundation.md`。不依赖 W1。

**Goal:** 新增 3 把不与现有武器机制重叠的武器——**碎 Maul**（双手近战，强击退+硬直控场）、**霜噬 Frostbite**（冰系毁灭，减速→冻结控制循环）、**引力井 Gravity Well**（变幻系，拉拽聚怪的力量倍增器）——补全 spec §3 分类体系的双手/冰/变幻三个空位。

**Architecture:** 每把武器一个垂直切片：新建 weapon 脚本（`extends WeaponBase`）+ 极简 `.tscn`（单 `Node` 挂脚本）+ `.tres` 数据 + 在 `CardPool` 注册 id/卡条目 + 测试。Maul/Frostbite 是**瞬时 AoE**（沿用 aura/explosion 的「遍历 enemies 距离判定」式，无新实体）；Gravity Well 生成一个**持续场实体**（`GravityWell` 节点，类比 W1 的 `BurnField`，每物理帧对场内敌 `apply_impulse` 朝井心 + 周期轻伤）。全部经 W0 原语，零自写状态/位移逻辑。

**Tech Stack:** Godot 4.6.3 · GDScript · gdUnit4 · 数据驱动（`WeaponData.levels` 反射 + `WeaponDB` 自动入库 + `CardPool` DSL）。

## Global Constraints

- **新 id**：`maul` / `frostbite` / `gravity_well`（英文，沿用命名规范）。需在 `CardPool._register_weapon_effects` 的硬编码 id 列表**加入**这三者（及自动派生的 `_2/_3` 升级），并新增对应 `CARDS` 基础+升级条目。
- **W2 不做进化**：三把新武器 `.tres` 的 `evolution = {}`（暂不可进化）。其进化（震地 Earthshatter / 暴雪 Blizzard / 奇点 Singularity）是 **W3** 内容；W3 再补 `evolution` 字段 + 进化 `.tres`。→ `WeaponDB.all_evolvable()` 仍为 7，`test_all_evolvable_count_is_seven` 不回归。
- **不依赖新 AI 实体**：Maul/Frostbite 瞬时；Gravity Well 用轻量 `Node2D` 场实体（非 LimboAI、非 CharacterBody2D）。RoamingMinion 是 W3。
- **数值为草案基线**（spec §7.2/§7.8/§7.11 表照搬）；引力井拉力 `pull_strength` 经 `apply_impulse` 的衰减通道，**最终聚怪强度由 W4 telemetry 调**——本轮测试只验"朝井心施力"的机制方向，不锁定位移量级。
- **schema 字段必须在脚本声明**（否则 `apply_level` 反射静默忽略 + `push_warning`）。
- **图标为占位**：复用已入库的 Kenney 贴图（dagger/gem/orb_ring），VFX 通道再换正式图标/着色器。视觉同 W1 推迟到 VFX 通道。
- **新脚本/场景需刷新类缓存**：每把武器任务在跑测试前先 headless `--import`（更新 `global_script_class_cache` + uid），否则新 `class_name` / 新 `.tscn` 可能未被 headless 进程识别。测试一律 `preload` 引用脚本，不靠全局 class_name。
- **测试约定**：`extends GdUnitTestSuite`；`const X := preload(...)`；敌人测试实例化 `enemy.tscn`（headless 加载 LimboAI）。

**headless 命令**（PowerShell）：

```powershell
# 跑单个测试文件（替换 <TEST_FILE>）
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<TEST_FILE>.gd
# 刷新导入/类缓存
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" --import
```

---

## File Structure

**新建脚本/场景/数据（每把武器）**
- Maul：`scenes/weapons/maul/maul_weapon.gd` + `maul_weapon.tscn` + `data/weapons/maul.tres`
- Frostbite：`scenes/weapons/frostbite/frostbite_weapon.gd` + `frostbite_weapon.tscn` + `data/weapons/frostbite.tres`
- Gravity Well：`scenes/weapons/gravity_well/gravity_well_weapon.gd` + `gravity_well.gd`（场实体）+ `gravity_well_weapon.tscn` + `data/weapons/gravity_well.tres`

**修改**
- `autoloads/card_pool.gd`：`_register_weapon_effects` id 列表加 3 个；`CARDS` 加 9 条（3 基础 + 6 升级）。

**新建测试**
- `tests/test_weapons_w2.gd`：3 把武器的反射 + 机制集成（Maul 击退/硬直、Frostbite 减速→冻结、Gravity Well 拉拽/轻伤/过期）。

## Interfaces（W2 消费 W0）

```gdscript
# 碎 Maul：
Enemy.apply_impulse(dir, knockback)         # 径向远离玩家
Enemy.apply_status(&"stun", 0.0, stun_dur)

# 霜噬 Frostbite：
Enemy.has_status(&"slow") -> bool           # 判定"已减速则升级冻结"
Enemy.apply_status(&"slow", slow_factor, slow_dur)
Enemy.apply_status(&"freeze", 0.0, freeze_dur)

# 引力井 Gravity Well（GravityWell 场实体）：
Enemy.apply_impulse(dir_to_center, pull_strength * delta)   # 逐帧朝井心
Enemy.take_damage(tick_damage * TICK)                       # 周期轻伤

# 复用现有静态工具：
ExplosionWeapon.densest_center(positions, radius) -> Vector2   # 选最密集落点
```

---

### Task 1: 碎 Maul（双手近战，★ 新增）

**Files:**
- Create: `scenes/weapons/maul/maul_weapon.gd`、`scenes/weapons/maul/maul_weapon.tscn`、`data/weapons/maul.tres`
- Modify: `autoloads/card_pool.gd`
- Test: `tests/test_weapons_w2.gd`（新建）

**Interfaces:** Consumes: `apply_impulse`、`apply_status(&"stun")`（W0）。Produces: 无。

- [x] **Step 1: 新建 `tests/test_weapons_w2.gd` 并写 Maul 测试（先失败）**

```gdscript
extends GdUnitTestSuite
# W2 新增 3 把武器的反射 + 机制集成。preload 引用脚本；敌人实例化 enemy.tscn(headless 加载 LimboAI)。

const EnemyScene := preload("res://scenes/enemies/enemy.tscn")

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

# 在 pos 生成一只高血量敌人(避免被一击打死后断言失效)，入 "enemies" 组。
func _tough_enemy_at(pos: Vector2) -> Enemy:
	var e: Enemy = EnemyScene.instantiate()
	e.behavior = "chase"
	add_child(e)
	e.add_to_group("enemies")
	e.MAX_HP = 500.0
	e.hp = 500.0
	e.global_position = pos
	return auto_free(e)

# ── 碎 Maul ──
func test_maul_reflects_level1_fields() -> void:
	CardPool.apply({"id": "maul"}, _player)
	var node := _player.get_weapon_node("maul")
	assert_object(node).is_not_null()
	assert_float(node.get("radius")).is_equal_approx(130.0, 0.001)
	assert_float(node.get("knockback")).is_equal_approx(220.0, 0.001)
	assert_float(node.get("stun_dur")).is_equal_approx(0.4, 0.001)

func test_maul_damages_knocks_and_stuns_enemy_in_radius() -> void:
	CardPool.apply({"id": "maul"}, _player)
	var maul := _player.get_weapon_node("maul")
	var e := _tough_enemy_at(_player.global_position + Vector2(50, 0))   # 半径 130 内
	await get_tree().process_frame
	maul.attack()
	assert_float(e.hp).is_less(500.0)                       # 受伤
	assert_bool(e.is_stunned()).is_true()                   # 硬直
	assert_float(e.external_velocity.length()).is_greater(0.0)   # 击退冲量(朝 +x 远离玩家)
	assert_float(e.external_velocity.x).is_greater(0.0)

func test_maul_ignores_enemy_out_of_radius() -> void:
	CardPool.apply({"id": "maul"}, _player)
	var maul := _player.get_weapon_node("maul")
	var e := _tough_enemy_at(_player.global_position + Vector2(400, 0))  # 半径外
	await get_tree().process_frame
	maul.attack()
	assert_float(e.hp).is_equal(500.0)
	assert_bool(e.is_stunned()).is_false()
```

- [x] **Step 2: 运行，确认失败**

Run: `<TEST_FILE>` = `test_weapons_w2`
Expected: 红——`CardPool._grant_weapon: maul missing in WeaponDB`（数据/注册都还没有）。

- [x] **Step 3: 创建 `scenes/weapons/maul/maul_weapon.gd`**

```gdscript
# scenes/weapons/maul/maul_weapon.gd
# 碎 Maul（双手近战）：慢速大范围砸击，命中半径内全体 → 伤害 + 径向击退 + 硬直。低频高冲击控场。
class_name MaulWeapon
extends WeaponBase

# 由 WeaponData.levels 反射注入
var damage: float = 60.0
var radius: float = 130.0
var knockback: float = 220.0     # apply_impulse 强度(径向远离玩家)
var stun_dur: float = 0.4

func attack() -> void:
	var origin: Vector2 = _player.global_position
	var dmg: float = damage_for(damage)
	for e in enemies():
		if not is_instance_valid(e):
			continue
		var epos: Vector2 = (e as Node2D).global_position
		if origin.distance_to(epos) > radius:
			continue
		e.take_damage(dmg)
		if not is_instance_valid(e):
			continue   # 可能被打死
		if e.has_method("apply_impulse"):
			var dir := (epos - origin).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			e.apply_impulse(dir, knockback)
		if e.has_method("apply_status"):
			e.apply_status(&"stun", 0.0, stun_dur)
```

- [x] **Step 4: 创建 `scenes/weapons/maul/maul_weapon.tscn`**

```
[gd_scene format=3]

[ext_resource type="Script" path="res://scenes/weapons/maul/maul_weapon.gd" id="1_maul"]

[node name="MaulWeapon" type="Node"]
script = ExtResource("1_maul")
```

- [x] **Step 5: 创建 `data/weapons/maul.tres`**

```
[gd_resource type="Resource" script_class="WeaponData" load_steps=4 format=3]

[ext_resource type="Script" path="res://data/weapons/weapon_data.gd" id="1_data"]
[ext_resource type="PackedScene" path="res://scenes/weapons/maul/maul_weapon.tscn" id="2_scene"]
[ext_resource type="Texture2D" path="res://assets/sprites/kenney/items/dagger.png" id="3_icon"]

[resource]
script = ExtResource("1_data")
id = "maul"
display_name = "碎"
icon = ExtResource("3_icon")
base_scene = ExtResource("2_scene")
max_level = 3
levels = [{"cooldown": 2.2, "radius": 130.0, "damage": 60.0, "knockback": 220.0, "stun_dur": 0.4}, {"cooldown": 1.9, "radius": 150.0, "damage": 66.0, "knockback": 250.0, "stun_dur": 0.5}, {"cooldown": 1.6, "radius": 170.0, "damage": 72.0, "knockback": 280.0, "stun_dur": 0.6}]
evolution = {}
```

- [x] **Step 6: 在 `autoloads/card_pool.gd` 注册 maul**

`_register_weapon_effects` 的 id 列表加 `"maul"`：

```gdscript
	for id in ["knife", "orb", "explosion", "lightning", "whip", "boomerang", "aura", "maul"]:
```

`CARDS` 数组在新武器区（lightning/whip… 之后、synergy 之前）加 3 条：

```gdscript
	# W2 新增武器
	{ "id": "maul",        "name": "碎",           "desc": "慢速大范围砸击，强击退+硬直",   "type": "weapon",  "condition": "no:maul"       },
	{ "id": "maul_2",      "name": "碎 Lv.2",      "desc": "范围/击退/硬直↑，冷却↓",        "type": "upgrade", "condition": "upgrade:maul:1"     },
	{ "id": "maul_3",      "name": "碎 Lv.3",      "desc": "范围/击退/硬直↑，冷却↓",        "type": "upgrade", "condition": "upgrade:maul:2"     },
```

- [x] **Step 7: 刷新导入/类缓存**

Run: `--import` 命令。Expected: 无 `SCRIPT ERROR` / `Parse Error`；`maul.tres` 无未知字段告警。

- [x] **Step 8: 运行测试，确认通过** — Run: `<TEST_FILE>` = `test_weapons_w2` → Maul 4 个测试 PASS。

- [x] **Step 9: 提交**

```bash
git add scenes/weapons/maul/ data/weapons/maul.tres autoloads/card_pool.gd tests/test_weapons_w2.gd
git commit -m "feat(weapon): 碎 Maul 新增(双手近战, 击退+硬直, 接入 W0 apply_impulse/apply_status)"
```

---

### Task 2: 霜噬 Frostbite（冰系毁灭，★ 新增）

**Files:**
- Create: `scenes/weapons/frostbite/frostbite_weapon.gd`、`frostbite_weapon.tscn`、`data/weapons/frostbite.tres`
- Modify: `autoloads/card_pool.gd`
- Test: `tests/test_weapons_w2.gd`

**Interfaces:** Consumes: `has_status(&"slow")`、`apply_status(&"slow"/&"freeze")`（W0）；`ExplosionWeapon.densest_center`（复用）。Produces: 无。

**机制：** 在最密集处放冰爆 → `area` 内全体伤害 + 减速；对**已减速**的敌人命中则升级为**冻结**（spec §7.8 的控制循环）。

- [x] **Step 1: 向 `tests/test_weapons_w2.gd` 追加 Frostbite 测试（先失败）**

```gdscript
# ── 霜噬 Frostbite ──
func test_frostbite_reflects_level1_fields() -> void:
	CardPool.apply({"id": "frostbite"}, _player)
	var node := _player.get_weapon_node("frostbite")
	assert_object(node).is_not_null()
	assert_float(node.get("area")).is_equal_approx(90.0, 0.001)
	assert_float(node.get("slow_factor")).is_equal_approx(0.6, 0.001)

func test_frostbite_slows_then_freezes_on_second_hit() -> void:
	CardPool.apply({"id": "frostbite"}, _player)
	var fb := _player.get_weapon_node("frostbite")
	var e := _tough_enemy_at(_player.global_position + Vector2(20, 0))  # 唯一敌=最密集落点, 在 area 内
	await get_tree().process_frame
	fb.attack()
	assert_bool(e.has_status(&"slow")).is_true()    # 首次命中 → 减速
	assert_bool(e.has_status(&"freeze")).is_false()
	fb.attack()
	assert_bool(e.has_status(&"freeze")).is_true()  # 已减速 → 升级冻结

func test_frostbite_no_target_is_safe() -> void:
	CardPool.apply({"id": "frostbite"}, _player)
	var fb := _player.get_weapon_node("frostbite")
	fb.attack()   # 无敌人 → 不崩
	assert_bool(true).is_true()
```

- [x] **Step 2: 运行，确认失败** — Run: `test_weapons_w2` → 红（`frostbite missing in WeaponDB`）。

- [x] **Step 3: 创建 `scenes/weapons/frostbite/frostbite_weapon.gd`**

```gdscript
# scenes/weapons/frostbite/frostbite_weapon.gd
# 霜噬 Frostbite（冰系毁灭）：朝最密集处放冰爆 → area 内伤害 + 减速；命中已减速者则升级为冻结。
class_name FrostbiteWeapon
extends WeaponBase

const ExplosionWeaponScript := preload("res://scenes/weapons/explosion/explosion_weapon.gd")  # 复用 densest_center

# 由 WeaponData.levels 反射注入
var damage: float = 16.0
var area: float = 90.0
var slow_factor: float = 0.6     # 速度乘子(越小越慢)
var slow_dur: float = 1.5
var freeze_dur: float = 0.6

func attack() -> void:
	var targets := enemies()
	if targets.is_empty():
		return
	var positions: Array = []
	for e in targets:
		positions.append((e as Node2D).global_position)
	var center: Vector2 = ExplosionWeaponScript.densest_center(positions, area)
	var dmg: float = damage_for(damage)
	for e in targets:
		if not is_instance_valid(e):
			continue
		if center.distance_to((e as Node2D).global_position) > area:
			continue
		e.take_damage(dmg)
		if not is_instance_valid(e):
			continue
		if e.has_method("apply_status") and e.has_method("has_status"):
			if e.has_status(&"slow"):
				e.apply_status(&"freeze", 0.0, freeze_dur)   # 二次命中 → 冻结
			else:
				e.apply_status(&"slow", slow_factor, slow_dur)
```

- [x] **Step 4: 创建 `scenes/weapons/frostbite/frostbite_weapon.tscn`**

```
[gd_scene format=3]

[ext_resource type="Script" path="res://scenes/weapons/frostbite/frostbite_weapon.gd" id="1_fb"]

[node name="FrostbiteWeapon" type="Node"]
script = ExtResource("1_fb")
```

- [x] **Step 5: 创建 `data/weapons/frostbite.tres`**

```
[gd_resource type="Resource" script_class="WeaponData" load_steps=4 format=3]

[ext_resource type="Script" path="res://data/weapons/weapon_data.gd" id="1_data"]
[ext_resource type="PackedScene" path="res://scenes/weapons/frostbite/frostbite_weapon.tscn" id="2_scene"]
[ext_resource type="Texture2D" path="res://assets/sprites/kenney/items/gem.png" id="3_icon"]

[resource]
script = ExtResource("1_data")
id = "frostbite"
display_name = "霜噬"
icon = ExtResource("3_icon")
base_scene = ExtResource("2_scene")
max_level = 3
levels = [{"cooldown": 1.4, "damage": 16.0, "area": 90.0, "slow_factor": 0.6, "slow_dur": 1.5, "freeze_dur": 0.6}, {"cooldown": 1.1, "damage": 18.0, "area": 100.0, "slow_factor": 0.5, "slow_dur": 1.8, "freeze_dur": 0.8}, {"cooldown": 0.9, "damage": 20.0, "area": 110.0, "slow_factor": 0.45, "slow_dur": 2.0, "freeze_dur": 1.0}]
evolution = {}
```

- [x] **Step 6: 在 `autoloads/card_pool.gd` 注册 frostbite**

id 列表加 `"frostbite"`：

```gdscript
	for id in ["knife", "orb", "explosion", "lightning", "whip", "boomerang", "aura", "maul", "frostbite"]:
```

`CARDS` 的 W2 区追加：

```gdscript
	{ "id": "frostbite",   "name": "霜噬",         "desc": "冰爆减速，再命中则冻结",       "type": "weapon",  "condition": "no:frostbite"  },
	{ "id": "frostbite_2", "name": "霜噬 Lv.2",    "desc": "范围/减速/冻结↑，冷却↓",        "type": "upgrade", "condition": "upgrade:frostbite:1" },
	{ "id": "frostbite_3", "name": "霜噬 Lv.3",    "desc": "范围/减速/冻结↑，冷却↓",        "type": "upgrade", "condition": "upgrade:frostbite:2" },
```

- [x] **Step 7: 刷新导入/类缓存** — Run: `--import`。Expected: 无错误/无未知字段告警。

- [x] **Step 8: 运行测试，确认通过** — Run: `test_weapons_w2` → Frostbite 测试 PASS（Maul 不回归）。

- [x] **Step 9: 提交**

```bash
git add scenes/weapons/frostbite/ data/weapons/frostbite.tres autoloads/card_pool.gd tests/test_weapons_w2.gd
git commit -m "feat(weapon): 霜噬 Frostbite 新增(冰系毁灭, 减速→冻结控制循环)"
```

---

### Task 3: 引力井 Gravity Well（变幻系，★ 新增）

**Files:**
- Create: `scenes/weapons/gravity_well/gravity_well_weapon.gd`、`gravity_well.gd`、`gravity_well_weapon.tscn`、`data/weapons/gravity_well.tres`
- Modify: `autoloads/card_pool.gd`
- Test: `tests/test_weapons_w2.gd`

**Interfaces:** Consumes: `apply_impulse`、`take_damage`（W0/既有）；`ExplosionWeapon.densest_center`。Produces: `GravityWell` 场实体（radius/pull_strength/field_dur/tick_damage）。

**机制：** 在最密集处生成持续 `field_dur` 的引力井；井内敌人每物理帧被朝井心 `apply_impulse` + 周期轻伤。价值在"聚怪"（与直伤武器正交），为 AoE 做铺垫。

- [x] **Step 1: 向 `tests/test_weapons_w2.gd` 追加引力井测试（先失败）**

```gdscript
# ── 引力井 Gravity Well ──
const GravityWellScript := preload("res://scenes/weapons/gravity_well/gravity_well.gd")

func test_gravity_well_reflects_level1_fields() -> void:
	CardPool.apply({"id": "gravity_well"}, _player)
	var node := _player.get_weapon_node("gravity_well")
	assert_object(node).is_not_null()
	assert_float(node.get("radius")).is_equal_approx(140.0, 0.001)
	assert_float(node.get("pull_strength")).is_equal_approx(120.0, 0.001)

func test_gravity_well_pulls_enemy_toward_center() -> void:
	var well = auto_free(GravityWellScript.new())
	well.radius = 140.0
	well.pull_strength = 120.0
	well.field_dur = 5.0
	well.tick_damage = 0.0   # 隔离：只测拉力
	add_child(well)
	well.global_position = Vector2.ZERO
	var e := _tough_enemy_at(Vector2(100, 0))   # 半径内, 在 +x
	await get_tree().process_frame
	well._physics_process(0.1)                   # 手动跑一帧井逻辑
	# 井心在 -x 方向 → 敌人应受朝 -x 的冲量
	assert_float(e.external_velocity.x).is_less(0.0)

func test_gravity_well_ticks_damage() -> void:
	var well = auto_free(GravityWellScript.new())
	well.radius = 140.0
	well.pull_strength = 0.0
	well.field_dur = 5.0
	well.tick_damage = 8.0
	add_child(well)
	well.global_position = Vector2.ZERO
	var e := _tough_enemy_at(Vector2(50, 0))
	await get_tree().process_frame
	well._physics_process(0.3)   # > TICK(0.25) → 结算一拍
	assert_float(e.hp).is_less(500.0)

func test_gravity_well_expires_after_field_dur() -> void:
	var well = auto_free(GravityWellScript.new())
	well.field_dur = 0.2
	add_child(well)
	well._physics_process(0.3)   # _age 0.3 > 0.2 → queue_free
	await get_tree().process_frame
	assert_bool(is_instance_valid(well)).is_false()
```

- [x] **Step 2: 运行，确认失败** — Run: `test_weapons_w2` → 红（`Could not preload .../gravity_well.gd`）。

- [x] **Step 3: 创建场实体 `scenes/weapons/gravity_well/gravity_well.gd`**

```gdscript
# scenes/weapons/gravity_well/gravity_well.gd
# 引力井场实体：存活 field_dur 秒，每物理帧把半径内敌人朝井心 apply_impulse + 周期轻伤。
# 位移/伤害都走 W0/既有通道，本实体只负责"持续施力 + 计时"。
class_name GravityWell
extends Node2D

const TICK: float = 0.25

var radius: float = 140.0
var pull_strength: float = 120.0   # 朝井心的拉力(经 apply_impulse*delta；最终强度 W4 调)
var field_dur: float = 2.0
var tick_damage: float = 3.0       # 每秒轻伤(每拍结算 *TICK)
var _age: float = 0.0
var _tick_accum: float = 0.0

func _physics_process(delta: float) -> void:
	_age += delta
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var to_center: Vector2 = global_position - (e as Node2D).global_position
		if to_center.length() <= radius and e.has_method("apply_impulse"):
			e.apply_impulse(to_center.normalized(), pull_strength * delta)
	_tick_accum += delta
	while _tick_accum >= TICK:
		_tick_accum -= TICK
		_apply_tick_damage()
	if _age >= field_dur:
		queue_free()

func _apply_tick_damage() -> void:
	if tick_damage <= 0.0:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if global_position.distance_to((e as Node2D).global_position) <= radius:
			e.take_damage(tick_damage * TICK)
```

- [x] **Step 4: 运行 `test_weapons_w2` 的引力井实体测试，确认通过**

Run: `test_weapons_w2`
Expected: `test_gravity_well_pulls/ticks/expires` PASS；`test_gravity_well_reflects_level1_fields` 仍红（武器脚本/数据未建）。

- [x] **Step 5: 创建武器脚本 `scenes/weapons/gravity_well/gravity_well_weapon.gd`**

```gdscript
# scenes/weapons/gravity_well/gravity_well_weapon.gd
# 引力井 Gravity Well（变幻系）：在最密集处生成持续引力井，拉拽聚怪 + 轻伤。力量倍增器(与直伤正交)。
class_name GravityWellWeapon
extends WeaponBase

const GRAVITY_WELL := preload("res://scenes/weapons/gravity_well/gravity_well.gd")
const ExplosionWeaponScript := preload("res://scenes/weapons/explosion/explosion_weapon.gd")

# 由 WeaponData.levels 反射注入
var field_dur: float = 2.0
var radius: float = 140.0
var pull_strength: float = 120.0
var tick_damage: float = 3.0

func attack() -> void:
	var targets := enemies()
	if targets.is_empty():
		return
	var positions: Array = []
	for e in targets:
		positions.append((e as Node2D).global_position)
	var center: Vector2 = ExplosionWeaponScript.densest_center(positions, radius)
	var well := GRAVITY_WELL.new()
	well.radius = radius
	well.pull_strength = pull_strength
	well.field_dur = field_dur
	well.tick_damage = damage_for(tick_damage)   # 轻伤吃玩家伤害加成
	get_ysort().add_child(well)
	well.global_position = center
```

- [x] **Step 6: 创建 `scenes/weapons/gravity_well/gravity_well_weapon.tscn`**

```
[gd_scene format=3]

[ext_resource type="Script" path="res://scenes/weapons/gravity_well/gravity_well_weapon.gd" id="1_gw"]

[node name="GravityWellWeapon" type="Node"]
script = ExtResource("1_gw")
```

- [x] **Step 7: 创建 `data/weapons/gravity_well.tres`**

```
[gd_resource type="Resource" script_class="WeaponData" load_steps=4 format=3]

[ext_resource type="Script" path="res://data/weapons/weapon_data.gd" id="1_data"]
[ext_resource type="PackedScene" path="res://scenes/weapons/gravity_well/gravity_well_weapon.tscn" id="2_scene"]
[ext_resource type="Texture2D" path="res://assets/sprites/kenney/particles/orb_ring.png" id="3_icon"]

[resource]
script = ExtResource("1_data")
id = "gravity_well"
display_name = "引力井"
icon = ExtResource("3_icon")
base_scene = ExtResource("2_scene")
max_level = 3
levels = [{"cooldown": 4.0, "field_dur": 2.0, "radius": 140.0, "pull_strength": 120.0, "tick_damage": 3.0}, {"cooldown": 3.4, "field_dur": 2.5, "radius": 160.0, "pull_strength": 140.0, "tick_damage": 4.0}, {"cooldown": 3.0, "field_dur": 3.0, "radius": 180.0, "pull_strength": 160.0, "tick_damage": 5.0}]
evolution = {}
```

- [x] **Step 8: 在 `autoloads/card_pool.gd` 注册 gravity_well**

id 列表加 `"gravity_well"`：

```gdscript
	for id in ["knife", "orb", "explosion", "lightning", "whip", "boomerang", "aura", "maul", "frostbite", "gravity_well"]:
```

`CARDS` 的 W2 区追加：

```gdscript
	{ "id": "gravity_well",   "name": "引力井",     "desc": "漩涡拉拽聚怪 + 轻伤，放大 AoE", "type": "weapon",  "condition": "no:gravity_well"  },
	{ "id": "gravity_well_2", "name": "引力井 Lv.2", "desc": "范围/拉力/轻伤↑，冷却↓",       "type": "upgrade", "condition": "upgrade:gravity_well:1" },
	{ "id": "gravity_well_3", "name": "引力井 Lv.3", "desc": "范围/拉力/轻伤↑，冷却↓",       "type": "upgrade", "condition": "upgrade:gravity_well:2" },
```

- [x] **Step 9: 刷新导入/类缓存** — Run: `--import`。Expected: 无错误/无未知字段告警。

- [x] **Step 10: 运行测试，确认通过** — Run: `test_weapons_w2` → 全部 PASS（Maul/Frostbite 不回归）。

- [x] **Step 11: 提交**

```bash
git add scenes/weapons/gravity_well/ data/weapons/gravity_well.tres autoloads/card_pool.gd tests/test_weapons_w2.gd
git commit -m "feat(weapon): 引力井 Gravity Well 新增(变幻系, 拉拽聚怪场实体, 接入 W0 apply_impulse)"
```

---

### Task 4: W2 全量回归 + headless 烟雾

**Files:** 无新增（验证关）。

- [x] **Step 1: 跑全测试套件**

Run:
```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: 全绿。重点确认 `test_card_pool` 不回归——尤其：
- `test_pick_returns_all_available_when_pool_smaller_than_count`（=11）：6 槽满 → 含新武器在内的 weapon 卡都被槽满剔除 → 仍 11。
- `test_all_evolvable_count_is_seven`：W2 武器 `evolution={}` → 仍 7。
- `test_weapon_cards_are_uncommon` / `test_all_runtime_cards_have_rarity`：新武器卡自动获 uncommon。

- [x] **Step 2: 资源导入 + 解析检查**

Run: `--import`
Expected: 无 `SCRIPT ERROR` / `Parse Error`；3 个新 `.tres` 无未知字段告警；3 个新 `.tscn` 正确入库。

- [x] **Step 3: 一局确定性烟雾**

Run:
```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --fixed-fps 60 --path "D:\Workspace\GAME\game_0_vsl" --quit-after 1800
```
Expected: 正常退出；无新武器相关 `Invalid call`/`Nonexistent function`。

- [x] **Step 4: 不提交（纯验证）。** 任一步红 → 回对应 Task 修复重跑。

---

## Self-Review（对照 spec 复核）

**1. Spec 覆盖（W2 = §7 的 3 把 ★ 新增）**
- §7.2 碎 Maul（双手近战，半径重击 + 击退 + 硬直）→ Task 1。✓
- §7.8 霜噬 Frostbite（冰爆，减速→冻结控制循环）→ Task 2。✓
- §7.11 引力井 Gravity Well（持续引力场拉拽聚怪 + 轻伤）→ Task 3。✓
- §3 分类补位：双手近战 / 毁灭·冰 / 变幻 三个空位填满，机制签名与现有武器互不重叠（碎=慢大击退硬直 ≠ 斩=高频小范围；霜噬=减速冻结控制独占冰位；引力井=拉拽控场无直伤主体）。✓
- §8 对接面：`CardPool._register_weapon_effects` 加 3 id + `CARDS` 加 9 条；`WeaponDB` 自动入库（零改）；进化卡因 `evolution={}` 暂不注入。✓

**范围外（已声明）**
- 视觉/状态 FX（冰晶 overlay / 旋涡粒子 / 法阵底 / 着色器）→ VFX 通道；图标用占位。
- 三把的进化（震地/暴雪/奇点）+ `evolution` 字段 → W3。
- synergy 新条目：W2 未加（新武器非投射，不入现有 synergy_pierce/multishot 门控）；如需 AoE/控制类 synergy，W3/平衡期再议。

**2. 占位符扫描**：无 TODO/TBD；每步含完整代码（脚本/`.tscn`/`.tres`/注册）+ 确切命令 + 预期。✓

**3. 类型/命名一致性**：字段 `radius/knockback/stun_dur`（maul）、`area/slow_factor/slow_dur/freeze_dur`（frostbite）、`field_dur/radius/pull_strength/tick_damage`（gravity_well/GravityWell）在脚本声明、`.tres` levels、反射测试间一致；状态 kind 用 W0 的 `&"slow"/&"freeze"/&"stun"`。✓

**已知风险/注记**
- 引力井拉力经 `apply_impulse`（W0 外力随帧 ×0.85 衰减）→ 持续场的等效拉速偏温和；测试只验"朝井心施力方向"，**聚怪量级留 W4 telemetry 调**（可能需要把 `pull_strength` 调高或后续给场实体一个非衰减的拉拽通道）。
- Maul 60+ 伤害可能一击秒杀低血敌 → `apply_impulse/apply_status` 前已 `is_instance_valid` 复检，避免对已 `queue_free` 的节点操作。
- 集成测试实例化 `enemy.tscn`（LimboAI headless 前提，同 W0/W1）。引力井实体测试用手动 `_physics_process`，不依赖帧序与玩家。

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-06-17-weapon-arsenal-w2-new-weapons.md`.**

现已就绪：**W0（底座）/ W1（重构 7 把）/ W2（新增 3 把）** 三份计划。执行依赖链：W0 → {W1, W2}（W1、W2 都只依赖 W0，彼此独立，可并行或任意先后）。

接下来可选：
1. **开始执行 W0**（其后 W1/W2 任意顺序）。
2. **继续写 W3 计划**（亡者召唤 RoamingMinion AI 随从 + 全部 11 个进化质变）。
3. **先评审 W0–W2 三份计划**（视觉并入策略 / 引力井拉力机制 / 分支策略）。

**告诉我选哪个。**
