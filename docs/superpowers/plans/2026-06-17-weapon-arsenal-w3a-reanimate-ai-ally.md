# 武器军械库重做 W3a：亡者召唤 + 漫游随从 AI 盟友 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **PREREQUISITE: W0 必须先合入**（消费 `Enemy.take_damage`，间接配合 W0 的敌人改动）。不依赖 W1/W2。

> **W3 拆成两份**：本计划是 **W3a = 召唤/AI 盟友子系统**（亡者召唤 Reanimate + RoamingMinion 自主实体 + 群尸 Horde 进化）——spec §7.10 标为「冲刺项·实现成本最高」，独立成卷以聚焦。**W3b = 其余 10 个进化质变**（Whirlwind/Earthshatter/Arrow Storm/Cyclone/Cataclysm/Inferno/Tempest/Blizzard/Bound Blades/Singularity），另起一卷。

**Goal:** 实现 spec §7.10 的**亡者召唤 Reanimate**——一把召唤**自主漫游骷髅随从**（独立索敌、追击、近战接触伤害）的武器，及其进化**群尸 Horde**（上限大增 + 随从死亡概率裂出小尸）。这是军械库唯一的「主动 AI 盟友」输出源。

**Architecture:** 新建轻量自主实体 `RoamingMinion`（`CharacterBody2D`，**不挂 LimboAI**，自带 `_physics_process` 索敌+移动+接触结算，避免给召唤物再上行为树）。`ReanimateWeapon`（`extends WeaponBase`）按 `cooldown` 节律维持最多 `max_minions` 个随从。随从入 `summons` 组、目标取 `enemies` 组；生命周期由 `lifetime` 控制。**分裂逻辑（Horde）以 `split_chance` 零默认门控**——基础 reanimate 不注入即不分裂，群尸 `.tres` 注入开启。

**Tech Stack:** Godot 4.6.3 · GDScript · gdUnit4 · 数据驱动（`WeaponData.levels` 反射 + `WeaponDB` 自动入库 + `CardPool` DSL；进化卡自动注入）。

## Global Constraints

- **新 id**：`reanimate`（基础）、`horde`（进化）。需在 `CardPool._register_weapon_effects` 加 `reanimate`（含 `_2/_3`），并加 `CARDS` 基础+升级条目。**进化卡 `evolve_reanimate` 由 `_register_evolution_cards` 自动注入**（无需手写），前提是 `reanimate.tres` 的 `evolution.evolved_id="horde"`。
- **随从不挂 LimboAI**：`RoamingMinion` 自带 `_physics_process` 索敌（遍历 `enemies` 组取最近）。**不用 `.tscn`**——脚本经 `preload(...).new()` 实例化，`_ready` 内程序化建碰撞形状 + 占位贴图（同 boomerang_projectile 的自建 sprite 套路）。
- **随从不被敌人攻击**：当前敌人 AI 不索敌 `summons` 组，故随从靠 `lifetime` 退场（非血量）。`minion_hp` 字段保留入 schema（存进 `RoamingMinion.max_hp`）但**本轮为预留**（注明）。
- **分裂防无限**：裂出的小尸 `split_chance=0`，不再二次分裂。
- **进化即质变（Horde）**：上限大增 + 死亡分裂——「自我延续的尸潮」即新机制规则（spec §11）。
- **`all_evolvable` 数量将变化**：reanimate 可进化后总数 7→8（W3b 再 +3 到 11）。把 `test_weapons_new` 的 `test_all_evolvable_count_is_seven` 改为**断言原 7 把仍可进化（集合成员）**，对后续新增鲁棒。
- **视觉占位**：随从用 dagger.png 占位贴图缩小；正式骷髅拼装（Monster Builder Pack）+ 召唤法阵留 VFX 通道。
- **测试约定**：`extends GdUnitTestSuite`；`const X := preload(...)`；敌人实例化 `enemy.tscn`（headless 加载 LimboAI）；调用 `weapon.attack()`（经 `get_ysort` 生成）前在测试里建一个 `"ysort"` 组桩节点，避免 `get_ysort()` 回退 null。

**headless 命令**（PowerShell）：

```powershell
# 单文件测试
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<TEST_FILE>.gd
# 刷新导入/类缓存
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" --import
```

---

## File Structure

**新建**
- `scenes/weapons/reanimate/roaming_minion.gd` — `RoamingMinion`（`CharacterBody2D`，自主索敌随从）。
- `scenes/weapons/reanimate/reanimate_weapon.gd` — `ReanimateWeapon`（维持随从数量）。
- `scenes/weapons/reanimate/reanimate_weapon.tscn` — 极简（单 `Node` 挂脚本）。
- `data/weapons/reanimate.tres` — 基础数据（W3a 末尾加 `evolution` 指向 horde）。
- `data/weapons/horde.tres` — 进化数据。
- `tests/test_reanimate.gd` — 随从行为 + 武器维持 + 进化质变。

**修改**
- `autoloads/card_pool.gd` — 注册 `reanimate`（id 列表 + 3 卡条目）。
- `tests/test_weapons_new.gd` — `test_all_evolvable_count_is_seven` 改为集合成员断言。

## Interfaces

```gdscript
# RoamingMinion（自主实体）
var damage: float; var speed: float; var lifetime: float; var max_hp: float; var split_chance: float
func _die() -> void          # 生命周期到/被清理时调用；split_chance>0 概率裂小尸
# 入 "summons" 组；目标取 "enemies" 组；contact 近战结算

# ReanimateWeapon（extends WeaponBase）
var summon_interval（=cooldown）, max_minions, damage, minion_hp, minion_speed, lifetime, split_chance
func attack() -> void        # 维持最多 max_minions 个随从
```

---

### Task 1: RoamingMinion 自主随从实体

**Files:**
- Create: `scenes/weapons/reanimate/roaming_minion.gd`
- Test: `tests/test_reanimate.gd`（新建）

**Interfaces:** Consumes: `Enemy.take_damage`（既有）。Produces: `RoamingMinion`（damage/speed/lifetime/max_hp/split_chance + `_die()`）。

- [x] **Step 1: 新建 `tests/test_reanimate.gd` 并写随从测试（先失败）**

```gdscript
extends GdUnitTestSuite
# 亡者召唤：随从自主索敌/接触/退场/分裂 + 武器维持上限 + 群尸进化。
# preload 引用脚本；敌人实例化 enemy.tscn(headless 加载 LimboAI)。

const RoamingMinionScript := preload("res://scenes/weapons/reanimate/roaming_minion.gd")
const EnemyScene := preload("res://scenes/enemies/enemy.tscn")

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

func _tough_enemy_at(pos: Vector2) -> Enemy:
	var e: Enemy = EnemyScene.instantiate()
	e.behavior = "chase"
	add_child(e)
	e.add_to_group("enemies")
	e.MAX_HP = 500.0
	e.hp = 500.0
	e.global_position = pos
	return auto_free(e)

# 召唤物经 get_ysort() 落位 → 测试建一个 "ysort" 桩，避免回退 null。
func _ysort_stub() -> Node2D:
	var ys := auto_free(Node2D.new())
	add_child(ys)
	ys.add_to_group("ysort")
	return ys

func test_minion_moves_toward_nearest_enemy() -> void:
	var m = auto_free(RoamingMinionScript.new())
	m.speed = 140.0
	m.lifetime = 99.0
	add_child(m)
	m.global_position = Vector2.ZERO
	_tough_enemy_at(Vector2(300, 0))
	var start_x := m.global_position.x
	for i in range(20):
		await get_tree().physics_frame
	assert_float(m.global_position.x).is_greater(start_x + 5.0)

func test_minion_damages_adjacent_enemy() -> void:
	var m = auto_free(RoamingMinionScript.new())
	m.damage = 12.0
	m.speed = 0.0          # 不移动，纯测接触
	m.lifetime = 99.0
	add_child(m)
	m.global_position = Vector2.ZERO
	var e := _tough_enemy_at(Vector2(8, 0))   # 接触半径内
	for i in range(3):
		await get_tree().physics_frame
	assert_float(e.hp).is_less(500.0)

func test_minion_expires_after_lifetime() -> void:
	var m = RoamingMinionScript.new()
	m.lifetime = 0.05
	add_child(m)
	for i in range(10):
		await get_tree().physics_frame
	assert_bool(is_instance_valid(m)).is_false()

func test_minion_splits_on_death_when_chance_full() -> void:
	var m = RoamingMinionScript.new()
	m.split_chance = 1.0   # 必裂
	add_child(m)
	m.global_position = Vector2(50, 50)
	m._die()
	await get_tree().process_frame
	var found := false
	for s in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(s) and s != m:
			found = true
	assert_bool(found).is_true()

func test_minion_no_split_when_chance_zero() -> void:
	var m = RoamingMinionScript.new()
	m.split_chance = 0.0
	add_child(m)
	m._die()
	await get_tree().process_frame
	var count := 0
	for s in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(s):
			count += 1
	assert_int(count).is_equal(0)
```

- [x] **Step 2: 运行，确认失败** — Run: `<TEST_FILE>` = `test_reanimate` → 红（`Could not preload .../roaming_minion.gd`）。

- [x] **Step 3: 创建 `scenes/weapons/reanimate/roaming_minion.gd`**

```gdscript
# scenes/weapons/reanimate/roaming_minion.gd
# 漫游随从：自主朝最近敌移动、接触近战；lifetime 到点退场。不挂 LimboAI(轻量自驱)。
# 经 ReanimateWeapon 程序化生成(无 .tscn)；_ready 自建碰撞形状 + 占位贴图。
class_name RoamingMinion
extends CharacterBody2D

const CONTACT_RADIUS: float = 18.0
const HIT_COOLDOWN: float = 0.5
const SPLIT_LIFETIME: float = 4.0   # 裂出小尸的寿命

var damage: float = 14.0
var speed: float = 120.0
var lifetime: float = 12.0
var max_hp: float = 30.0       # 预留(当前敌人 AI 不索敌 summons → 随从靠 lifetime 退场)
var split_chance: float = 0.0  # 群尸：死亡分裂概率(基础=0=不裂)
var _age: float = 0.0
var _hit_cd: float = 0.0

func _ready() -> void:
	add_to_group("summons")
	collision_layer = 0   # 纯运动学位移，不与玩家/敌人物理碰撞
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = CONTACT_RADIUS
	cs.shape = circ
	add_child(cs)
	var spr := Sprite2D.new()    # 占位视觉(VFX 通道换骷髅拼装)
	spr.texture = preload("res://assets/sprites/kenney/items/dagger.png")
	spr.scale = Vector2(0.4, 0.4)
	spr.modulate = Color(0.6, 0.9, 0.7)   # 幽绿，区分友军
	add_child(spr)

func _physics_process(delta: float) -> void:
	_age += delta
	_hit_cd = maxf(_hit_cd - delta, 0.0)
	var target := _nearest_enemy()
	if target != null:
		var to := target.global_position - global_position
		velocity = to.normalized() * speed
		move_and_slide()
		if _hit_cd <= 0.0 and global_position.distance_to(target.global_position) <= CONTACT_RADIUS + 8.0:
			target.take_damage(damage)
			_hit_cd = HIT_COOLDOWN
	if _age >= lifetime:
		_die()

func _nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to((e as Node2D).global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = e as Node2D
	return nearest

# 退场：群尸概率原地裂出一个不再分裂的短命小尸。
func _die() -> void:
	if split_chance > 0.0 and randf() < split_chance:
		var child = get_script().new()
		child.damage = damage
		child.speed = speed
		child.lifetime = SPLIT_LIFETIME
		child.max_hp = max_hp
		child.split_chance = 0.0
		var parent := get_parent()
		if parent != null:
			parent.add_child(child)
			child.global_position = global_position
	queue_free()
```

- [x] **Step 4: 运行，确认通过** — Run: `test_reanimate` → 5 个随从测试 PASS。

- [x] **Step 5: 提交**

```bash
git add scenes/weapons/reanimate/roaming_minion.gd tests/test_reanimate.gd
git commit -m "feat(summon): RoamingMinion 自主随从(索敌/接触/退场/分裂, 不挂 LimboAI)"
```

---

### Task 2: ReanimateWeapon 武器 + 数据 + 注册

**Files:**
- Create: `scenes/weapons/reanimate/reanimate_weapon.gd`、`reanimate_weapon.tscn`、`data/weapons/reanimate.tres`
- Modify: `autoloads/card_pool.gd`
- Test: `tests/test_reanimate.gd`

**Interfaces:** Consumes: `RoamingMinion`（Task 1）、`WeaponBase`（既有）。Produces: `reanimate` 武器（维持 `max_minions` 个随从）。

- [x] **Step 1: 向 `tests/test_reanimate.gd` 追加武器测试（先失败）**

```gdscript
# ── ReanimateWeapon ──
func _count_summons() -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(s):
			n += 1
	return n

func test_reanimate_reflects_level1_fields() -> void:
	CardPool.apply({"id": "reanimate"}, _player)
	var rw := _player.get_weapon_node("reanimate")
	assert_object(rw).is_not_null()
	assert_int(rw.get("max_minions")).is_equal(1)
	assert_float(rw.get("lifetime")).is_equal_approx(12.0, 0.001)

func test_reanimate_spawns_up_to_max_minions() -> void:
	_ysort_stub()
	CardPool.apply({"id": "reanimate"}, _player)
	var rw := _player.get_weapon_node("reanimate")
	rw.attack()
	rw.attack()   # Lv1 max=1 → 第二次不再生成
	await get_tree().process_frame
	assert_int(_count_summons()).is_equal(1)
```

- [x] **Step 2: 运行，确认失败** — Run: `test_reanimate` → 红（`reanimate missing in WeaponDB`）。

- [x] **Step 3: 创建 `scenes/weapons/reanimate/reanimate_weapon.gd`**

```gdscript
# scenes/weapons/reanimate/reanimate_weapon.gd
# 亡者召唤（召唤·进攻）：按 cooldown 节律维持最多 max_minions 个自主随从。
class_name ReanimateWeapon
extends WeaponBase

const MINION := preload("res://scenes/weapons/reanimate/roaming_minion.gd")

# 由 WeaponData.levels 反射注入(cooldown 即 summon_interval，走 WeaponBase 调度)
var max_minions: int = 1
var damage: float = 14.0
var minion_hp: float = 30.0
var minion_speed: float = 120.0
var lifetime: float = 12.0
var split_chance: float = 0.0   # 群尸进化注入；基础=0

func attack() -> void:
	if _count_minions() >= max_minions:
		return
	var m := MINION.new()
	m.damage = damage_for(damage)
	m.speed = minion_speed
	m.lifetime = lifetime
	m.max_hp = minion_hp
	m.split_chance = split_chance
	get_ysort().add_child(m)
	m.global_position = _player.global_position

func _count_minions() -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("summons"):
		if s is RoamingMinion and is_instance_valid(s):
			n += 1
	return n
```

- [x] **Step 4: 创建 `scenes/weapons/reanimate/reanimate_weapon.tscn`**

```
[gd_scene format=3]

[ext_resource type="Script" path="res://scenes/weapons/reanimate/reanimate_weapon.gd" id="1_re"]

[node name="ReanimateWeapon" type="Node"]
script = ExtResource("1_re")
```

- [x] **Step 5: 创建 `data/weapons/reanimate.tres`**（W3a 暂 `evolution={}`，Task 3 补）

```
[gd_resource type="Resource" script_class="WeaponData" load_steps=4 format=3]

[ext_resource type="Script" path="res://data/weapons/weapon_data.gd" id="1_data"]
[ext_resource type="PackedScene" path="res://scenes/weapons/reanimate/reanimate_weapon.tscn" id="2_scene"]
[ext_resource type="Texture2D" path="res://assets/sprites/kenney/items/dagger.png" id="3_icon"]

[resource]
script = ExtResource("1_data")
id = "reanimate"
display_name = "亡者召唤"
icon = ExtResource("3_icon")
base_scene = ExtResource("2_scene")
max_level = 3
levels = [{"cooldown": 3.0, "max_minions": 1, "damage": 14.0, "minion_hp": 30.0, "minion_speed": 120.0, "lifetime": 12.0}, {"cooldown": 3.0, "max_minions": 2, "damage": 14.0, "minion_hp": 30.0, "minion_speed": 120.0, "lifetime": 14.0}, {"cooldown": 3.0, "max_minions": 3, "damage": 16.0, "minion_hp": 35.0, "minion_speed": 130.0, "lifetime": 16.0}]
evolution = {}
```

- [x] **Step 6: 在 `autoloads/card_pool.gd` 注册 reanimate**

id 列表加 `"reanimate"`：

```gdscript
	for id in ["knife", "orb", "explosion", "lightning", "whip", "boomerang", "aura", "reanimate"]:
```
> 注：若 W2 已合入，列表里已含 maul/frostbite/gravity_well，则在其后再加 reanimate。

`CARDS` 加 3 条（新武器区）：

```gdscript
	{ "id": "reanimate",   "name": "亡者召唤",     "desc": "召唤自主骷髅随从，独立索敌近战",  "type": "weapon",  "condition": "no:reanimate"  },
	{ "id": "reanimate_2", "name": "亡者召唤 Lv.2", "desc": "随从上限 +1，存活↑",            "type": "upgrade", "condition": "upgrade:reanimate:1" },
	{ "id": "reanimate_3", "name": "亡者召唤 Lv.3", "desc": "随从上限 +1，伤害/存活↑",        "type": "upgrade", "condition": "upgrade:reanimate:2" },
```

- [x] **Step 7: 刷新导入/类缓存** — Run: `--import`。Expected: 无 `SCRIPT ERROR`/`Parse Error`；`reanimate.tres` 无未知字段告警。

- [x] **Step 8: 运行测试，确认通过** — Run: `test_reanimate` → 武器测试 PASS（随从测试不回归）。

- [x] **Step 9: 提交**

```bash
git add scenes/weapons/reanimate/reanimate_weapon.gd scenes/weapons/reanimate/reanimate_weapon.tscn data/weapons/reanimate.tres autoloads/card_pool.gd tests/test_reanimate.gd
git commit -m "feat(weapon): 亡者召唤 Reanimate 新增(维持 max_minions 个 RoamingMinion)"
```

---

### Task 3: 群尸 Horde 进化（质变：上限大增 + 死亡分裂）

**Files:**
- Modify: `data/weapons/reanimate.tres`（加 evolution）
- Create: `data/weapons/horde.tres`
- Modify: `tests/test_weapons_new.gd`（evolvable 数量断言改集合成员）
- Test: `tests/test_reanimate.gd`

**Interfaces:** Consumes: `RoamingMinion.split_chance`（Task 1 已实现分裂）、进化卡自动注入通路（`_register_evolution_cards`）。Produces: `horde` 进化形态。

**质变规则（spec §7.10）：** `max_minions` 大增 + `split_chance>0`（随从死亡概率原地裂出小尸）= 自我延续的尸潮。逻辑已在 `RoamingMinion._die()`（Task 1），本任务靠**数据开启**。

- [x] **Step 1: 更新 `tests/test_weapons_new.gd` 的 evolvable 断言 + 向 `test_reanimate.gd` 加进化测试（先失败）**

`tests/test_weapons_new.gd`：把 `test_all_evolvable_count_is_seven`（约第 80–82 行）替换为集合成员断言（对后续新增鲁棒）：

```gdscript
func test_original_seven_weapons_are_evolvable() -> void:
	# 原 7 把恒可进化；W3 起新增武器(reanimate 等)也会进入 all_evolvable，故只断言原 7 把在列。
	var ids: Array = []
	for w in WeaponDB.all_evolvable():
		ids.append(w.id)
	for id in ["knife", "orb", "explosion", "lightning", "whip", "boomerang", "aura"]:
		assert_bool(ids.has(id)).is_true()
```

`tests/test_reanimate.gd` 追加：

```gdscript
func test_evolve_reanimate_grants_horde() -> void:
	CardPool.apply({"id": "reanimate"}, _player)
	CardPool.apply({"id": "evolve_reanimate", "type": "evolution"}, _player)
	assert_bool(_player.has_weapon("horde")).is_true()
	assert_bool(_player.has_weapon("reanimate")).is_false()
	var hw := _player.get_weapon_node("horde")
	assert_int(hw.get("max_minions")).is_greater(3)        # 上限大增
	assert_float(hw.get("split_chance")).is_greater(0.0)   # 死亡分裂开启

func test_horde_minion_carries_split_chance() -> void:
	_ysort_stub()
	CardPool.apply({"id": "reanimate"}, _player)
	CardPool.apply({"id": "evolve_reanimate", "type": "evolution"}, _player)
	var hw := _player.get_weapon_node("horde")
	hw.attack()
	await get_tree().process_frame
	for s in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(s) and s is RoamingMinion:
			assert_float(s.split_chance).is_greater(0.0)
```

- [x] **Step 2: 运行，确认失败**

Run: `test_reanimate`（红：`horde missing in WeaponDB` / `evolve_reanimate` 无效果）；`test_weapons_new`（红：新断言里 all_evolvable 还没把…实际仍绿，但 reanimate 未进化前 evolve_reanimate 不存在 → test_reanimate 红即可）。

- [x] **Step 3: 给 `data/weapons/reanimate.tres` 加 evolution**

```
evolution = {"requires_perk": "perk_hp", "requires_perk_stacks": 3, "evolved_id": "horde"}
```

- [x] **Step 4: 创建 `data/weapons/horde.tres`**

```
[gd_resource type="Resource" script_class="WeaponData" load_steps=4 format=3]

[ext_resource type="Script" path="res://data/weapons/weapon_data.gd" id="1_data"]
[ext_resource type="PackedScene" path="res://scenes/weapons/reanimate/reanimate_weapon.tscn" id="2_scene"]
[ext_resource type="Texture2D" path="res://assets/sprites/kenney/items/dagger.png" id="3_icon"]

[resource]
script = ExtResource("1_data")
id = "horde"
display_name = "群尸"
icon = ExtResource("3_icon")
base_scene = ExtResource("2_scene")
max_level = 1
levels = [{"cooldown": 2.5, "max_minions": 6, "damage": 16.0, "minion_hp": 35.0, "minion_speed": 130.0, "lifetime": 18.0, "split_chance": 0.35}]
evolution = {}
```

- [x] **Step 5: 刷新导入/类缓存** — Run: `--import`。Expected: 无错误；`horde.tres`、`reanimate.tres` 无未知字段告警。

- [x] **Step 6: 运行测试，确认通过**

Run: `test_reanimate`（进化测试 PASS），再 `test_weapons_new`（`test_original_seven_weapons_are_evolvable` PASS）。
Expected: 均 PASS。`evolve_reanimate` 卡由 `_register_evolution_cards` 自动注入并生效。

- [x] **Step 7: 提交**

```bash
git add data/weapons/reanimate.tres data/weapons/horde.tres tests/test_weapons_new.gd tests/test_reanimate.gd
git commit -m "feat(weapon): 群尸 Horde 进化(上限大增 + 随从死亡分裂; evolvable 断言改集合成员)"
```

---

### Task 4: W3a 全量回归 + headless 烟雾

**Files:** 无新增（验证关）。

- [x] **Step 1: 跑全测试套件**

Run:
```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: 全绿。重点：`test_card_pool`（新 reanimate 武器卡不破坏槽满/计数用例——同 W2，槽满时被剔除）、`test_weapons_new`（evolvable 集合断言）、`test_reanimate` 全绿。

- [x] **Step 2: 资源导入 + 解析检查**

Run: `--import`
Expected: 无 `SCRIPT ERROR`/`Parse Error`；`reanimate.tres`/`horde.tres` 无未知字段告警；`reanimate_weapon.tscn` 入库。

- [x] **Step 3: 一局确定性烟雾**

Run:
```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --fixed-fps 60 --path "D:\Workspace\GAME\game_0_vsl" --quit-after 1800
```
Expected: 正常退出；无随从相关 `Invalid call`/`Nonexistent function`/物理告警（CollisionShape2D 已在 `_ready` 建好）。

- [x] **Step 4: 不提交（纯验证）。** 任一步红 → 回对应 Task 修复重跑。

---

## Self-Review（对照 spec 复核）

**1. Spec 覆盖（W3a = §7.10 + 召唤基类 §4.3 的 RoamingMinion 部分）**
- §7.10 亡者召唤（自主漫游骷髅、独立索敌追击近战、lifetime/max_minions）→ Task 1+2。✓
- §7.10 进化群尸 Horde（上限大增 + 死亡分裂自延续）→ Task 3。✓
- §4.3 RoamingMinion（CharacterBody2D、不挂 LimboAI、复用最近敌索敌、入 summons / 取 enemies 组）→ Task 1。✓
- §8 对接：CardPool 加 reanimate id + 卡；进化卡 evolve_reanimate 自动注入；WeaponDB 自动入库。✓

**范围外（已声明）**
- §4.3 的另一半 OrbitGuardian → W1（缚灵）。
- 视觉（骷髅拼装 / 召唤法阵 / 幽绿描边着色器）→ VFX 通道，本轮占位贴图。
- 其余 10 个进化质变 → **W3b**。

**2. 占位符扫描**：无 TODO/TBD；每步含完整代码 + 命令 + 预期。✓

**3. 类型/命名一致性**：`RoamingMinion`(damage/speed/lifetime/max_hp/split_chance/`_die`) 与 `ReanimateWeapon`(max_minions/minion_speed/minion_hp/lifetime/split_chance) 在脚本/`.tres`/测试间一致；`summons`/`enemies` 组名一致；进化卡走既有 `evolve_<id>` 自动通路。✓

**已知风险/注记**
- `RoamingMinion` 用 `CharacterBody2D` + `collision_layer/mask=0` 的纯运动学位移（不与玩家/敌人物理碰撞），靠距离判定接触伤害——`move_and_slide` 在有 CollisionShape2D 时无告警。
- `minion_hp` 当前为预留（敌人 AI 不索敌 summons，随从靠 lifetime 退场）；若日后敌人可攻击随从，再启用。
- 分裂用 `randf()`，测试用 `split_chance=1.0`/`0.0` 两个确定性极值，避免依赖 RNG 种子。
- 召唤经 `get_ysort()` 落位；测试用 `"ysort"` 桩节点保证不回退 null。

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-06-17-weapon-arsenal-w3a-reanimate-ai-ally.md`.**

路线图现状：**W0 / W1 / W2 / W3a** 四份计划已写。依赖链：W0 → {W1, W2, W3a}（W3a 仅依赖 W0；与 W1/W2 独立）。

接下来可选：
1. **写 W3b 计划**（其余 10 个进化质变：Whirlwind/Earthshatter/Arrow Storm/Cyclone/Cataclysm/Inferno/Tempest/Blizzard/Bound Blades/Singularity）——补完整个军械库设计。
2. **开始执行 W0**（其后 W1/W2/W3a 任意顺序）。
3. **写 VFX 通道计划**（所有推迟的视觉/状态可读性 FX + Kenney 素材导入）。
4. **先评审已写的计划**。

**告诉我选哪个。**
