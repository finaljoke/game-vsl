# Upgrade System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现基于 CardPool Autoload 的随机选卡升级系统，支持武器获取、Lv.2 强化、属性乘数三类卡片，LevelUpUI 退化为纯显示层。

**Architecture:** CardPool 单例持有全部卡片定义并负责过滤抽卡（pick）和应用效果（apply）；Player 新增 `owned_weapons`、`speed_mult`、`attack_speed_mult`、`xp_mult` 四个字段；LevelUpUI 从 CardPool 取卡后按 Layout C 风格渲染，选卡后调 CardPool.apply()。

**Tech Stack:** Godot 4.6 GDScript，GdUnit4 v6.1.3 单元测试。

---

## 文件改动清单

| 文件 | 操作 |
|---|---|
| `scenes/player/player.gd` | 修改：新增 4 个字段，`_physics_process` / `add_xp` 应用乘数 |
| `scenes/weapons/weapon_base.gd` | 修改：`_process()` 改为动态算 `effective_cd` |
| `scenes/weapons/orb/orb_shield.gd` | 修改：加 `class_name OrbShield`，供 CardPool.apply() 用 `is` 识别 |
| `autoloads/card_pool.gd` | 新建：CARDS 数组 + `pick()` + `apply()` + `register_weapon()` |
| `project.godot` | 修改：注册 CardPool Autoload |
| `scenes/main/main.gd` | 修改：初始登记飞刀到 `owned_weapons` |
| `scenes/ui/level_up_ui.gd` | 重写：调 CardPool，渲染 Layout C 卡片 |
| `tests/test_player.gd` | 修改：新增乘数字段测试 |
| `tests/test_card_pool.gd` | 新建：pick() 条件过滤 + apply() 属性效果测试 |

---

## GdUnit4 测试命令

```
"C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64.exe" --path "D:\Workspace\GAME\game_0_vsl" -s "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" --add "res://tests" --ignoreHeadlessMode
```

---

### Task 1: Player 新增乘数字段

**Files:**
- Modify: `tests/test_player.gd` (在第 108 行末尾追加)
- Modify: `scenes/player/player.gd`

- [ ] **Step 1: 在 test_player.gd 末尾追加 5 个失败测试**

```gdscript
# ── 乘数初始值 ────────────────────────────────────────────────────────────

func test_initial_speed_mult_is_1() -> void:
	assert_float(_player.speed_mult).is_equal(1.0)

func test_initial_attack_speed_mult_is_1() -> void:
	assert_float(_player.attack_speed_mult).is_equal(1.0)

func test_initial_xp_mult_is_1() -> void:
	assert_float(_player.xp_mult).is_equal(1.0)

func test_owned_weapons_starts_empty() -> void:
	assert_int(_player.owned_weapons.size()).is_equal(0)

func test_xp_mult_scales_xp_gain() -> void:
	_player.xp_mult = 1.25
	_player.add_xp(100.0)
	# 100 * 1.25 = 125 XP → 升级（消耗 100）→ xp 剩余 25
	assert_int(_player.level).is_equal(2)
	assert_float(_player.xp).is_equal_approx(25.0, 0.001)
```

- [ ] **Step 2: 运行测试，确认 5 个新测试失败**

```
"C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64.exe" --path "D:\Workspace\GAME\game_0_vsl" -s "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" --add "res://tests/test_player.gd" --ignoreHeadlessMode
```

Expected: 5 个测试 FAIL（字段不存在），原有 16 个仍 PASS

- [ ] **Step 3: 将 scenes/player/player.gd 替换为以下完整内容**

```gdscript
# scenes/player/player.gd
class_name Player
extends CharacterBody2D

signal leveled_up(new_level: int)
signal died

const SPEED: float = 200.0

var hp: float = 100.0
var max_hp: float = 100.0
var xp: float = 0.0
var xp_threshold: float = 100.0
var level: int = 1
var _dead: bool = false
var owned_weapons: Dictionary = {}
var speed_mult: float = 1.0
var attack_speed_mult: float = 1.0
var xp_mult: float = 1.0

@onready var hurt_box: Area2D = $HurtBox

func _physics_process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED * speed_mult
	move_and_slide()
	_check_contact_damage(delta)

func _check_contact_damage(delta: float) -> void:
	for body in hurt_box.get_overlapping_bodies():
		if body.is_in_group("enemies"):
			take_damage(body.CONTACT_DAMAGE * delta)
			break

func take_damage(amount: float) -> void:
	if _dead:
		return
	hp = max(0.0, hp - amount)
	GameFeel.player_hit.emit(amount)
	if hp <= 0.0:
		_dead = true
		GameFeel.player_died.emit()
		died.emit()

func add_xp(amount: float) -> void:
	xp += amount * xp_mult
	while xp >= xp_threshold:
		xp -= xp_threshold
		xp_threshold *= 1.2
		level += 1
		GameFeel.player_leveled_up.emit(level)
		leveled_up.emit(level)

func get_xp_percent() -> float:
	return xp / xp_threshold

func add_weapon(weapon_scene: PackedScene) -> void:
	var weapon := weapon_scene.instantiate()
	add_child(weapon)
```

- [ ] **Step 4: 运行测试，确认全部通过**

```
"C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64.exe" --path "D:\Workspace\GAME\game_0_vsl" -s "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" --add "res://tests/test_player.gd" --ignoreHeadlessMode
```

Expected: 21/21 PASS

- [ ] **Step 5: 提交**

```bash
git add tests/test_player.gd scenes/player/player.gd
git commit -m "feat: add owned_weapons and multiplier fields to Player"
```

---

### Task 2: WeaponBase 动态 effective_cd

**Files:**
- Modify: `scenes/weapons/weapon_base.gd`

无可独立运行的单元测试（WeaponBase 需要完整场景树）；通过 Task 7 后游戏内手动验证效果。

- [ ] **Step 1: 将 scenes/weapons/weapon_base.gd 替换为以下完整内容**

```gdscript
# scenes/weapons/weapon_base.gd
class_name WeaponBase
extends Node

var cooldown: float = 1.0
var _timer: float = 0.0

var _player: Node2D = null

func _ready() -> void:
	_player = get_parent() as Node2D

func _process(delta: float) -> void:
	_timer += delta
	var effective_cd := cooldown / (_player as Player).attack_speed_mult
	if _timer >= effective_cd:
		_timer = 0.0
		attack()

func attack() -> void:
	pass

func get_nearest_enemy() -> Node2D:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var nearest_dist := INF
	for e in enemies:
		var d := _player.global_position.distance_to((e as Node2D).global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e as Node2D
	return nearest

func get_ysort() -> Node:
	return get_tree().get_first_node_in_group("ysort")
```

- [ ] **Step 2: 提交**

```bash
git add scenes/weapons/weapon_base.gd
git commit -m "feat: WeaponBase uses stateless effective_cd from attack_speed_mult"
```

---

### Task 3: OrbShield class_name + CardPool 骨架 + Autoload 注册

**Files:**
- Modify: `scenes/weapons/orb/orb_shield.gd`
- Create: `autoloads/card_pool.gd`
- Modify: `project.godot`

必须在写 CardPool 测试之前完成（测试要引用 `CardPool` 单例）。

- [ ] **Step 1: 给 orb_shield.gd 第 1 行加 `class_name OrbShield`**

将 `scenes/weapons/orb/orb_shield.gd` 替换为：

```gdscript
# scenes/weapons/orb/orb_shield.gd
class_name OrbShield
extends Node2D

const DAMAGE: float = 8.0
const ORBIT_RADIUS: float = 60.0
const ORBIT_SPEED: float = 2.0
const HIT_COOLDOWN: float = 0.5
const ORB_RADIUS: float = 14.0

var orbit_index: int = 0
var total_orbs: int = 2
var _player: Node2D = null
var _hit_cooldowns: Dictionary = {}

func _ready() -> void:
	_player = get_parent()

func _process(delta: float) -> void:
	if _player == null:
		return
	var angle := (TAU / total_orbs) * orbit_index + Time.get_ticks_msec() * 0.001 * ORBIT_SPEED
	global_position = _player.global_position + Vector2(cos(angle), sin(angle)) * ORBIT_RADIUS
	_check_hits()
	_tick_cooldowns(delta)

func _check_hits() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy in _hit_cooldowns:
			continue
		if global_position.distance_to((enemy as Node2D).global_position) <= ORB_RADIUS:
			(enemy as Enemy).take_damage(DAMAGE)
			_hit_cooldowns[enemy] = HIT_COOLDOWN

func _tick_cooldowns(delta: float) -> void:
	for key in _hit_cooldowns.keys():
		_hit_cooldowns[key] -= delta
		if _hit_cooldowns[key] <= 0.0:
			_hit_cooldowns.erase(key)
```

- [ ] **Step 2: 新建 autoloads/card_pool.gd（骨架，方法留空）**

```gdscript
# autoloads/card_pool.gd
extends Node

const CARDS: Array[Dictionary] = [
	{ "id": "knife",       "name": "飞刀",      "desc": "朝最近敌人射出飞刀",    "type": "weapon",  "condition": "no:knife"      },
	{ "id": "orb",         "name": "护盾球",    "desc": "绕身旋转的能量球",      "type": "weapon",  "condition": "no:orb"        },
	{ "id": "explosion",   "name": "爆炸",      "desc": "随机位置触发范围爆炸",  "type": "weapon",  "condition": "no:explosion"  },
	{ "id": "knife_2",     "name": "飞刀 Lv.2",    "desc": "冷却 1.0s → 0.5s",         "type": "upgrade", "condition": "upgrade:knife"     },
	{ "id": "orb_2",       "name": "护盾球 Lv.2",  "desc": "护盾球数量 2 → 3",          "type": "upgrade", "condition": "upgrade:orb"       },
	{ "id": "explosion_2", "name": "爆炸 Lv.2",    "desc": "冷却 3.0s → 1.5s",         "type": "upgrade", "condition": "upgrade:explosion" },
	{ "id": "perk_speed",  "name": "移速提升",  "desc": "移动速度永久 +15%",     "type": "perk",    "condition": ""              },
	{ "id": "perk_hp",     "name": "生命上限",  "desc": "最大 HP +20，当场补满", "type": "perk",    "condition": ""              },
	{ "id": "perk_attack", "name": "攻速提升",  "desc": "攻击速度永久 +15%",     "type": "perk",    "condition": ""              },
	{ "id": "perk_xp",     "name": "XP 加成",   "desc": "XP 获取量永久 +25%",    "type": "perk",    "condition": ""              },
]

const KNIFE_SCENE := preload("res://scenes/weapons/knife/knife_weapon.tscn")
const ORB_SCENE := preload("res://scenes/weapons/orb/orb_weapon.tscn")
const ORB_SHIELD_SCENE := preload("res://scenes/weapons/orb/orb_shield.tscn")
const EXPLOSION_SCENE := preload("res://scenes/weapons/explosion/explosion_weapon.tscn")

func pick(_player: Player, _count: int = 3) -> Array[Dictionary]:
	return []

func apply(_card: Dictionary, _player: Player) -> void:
	pass

func register_weapon(player: Player, weapon_id: String) -> void:
	player.owned_weapons[weapon_id] = 1

func _check_condition(_condition: String, _player: Player) -> bool:
	return false
```

- [ ] **Step 3: 在 project.godot 的 [autoload] 段注册 CardPool**

找到 `[autoload]` 段，在 `GameFeel` 行之后插入一行：

```ini
CardPool="*res://autoloads/card_pool.gd"
```

改后 [autoload] 段如下：

```ini
[autoload]

_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"
GameManager="*res://autoloads/game_manager.gd"
GameFeel="*res://autoloads/game_feel.gd"
CardPool="*res://autoloads/card_pool.gd"
SoundManager="*uid://bg6usvpgisg7x"
PhantomCameraManager="*uid://duq6jhf6unyis"
```

- [ ] **Step 4: 提交**

```bash
git add scenes/weapons/orb/orb_shield.gd autoloads/card_pool.gd project.godot
git commit -m "feat: add OrbShield class_name, CardPool autoload skeleton"
```

---

### Task 4: CardPool pick() 逻辑 + 测试

**Files:**
- Create: `tests/test_card_pool.gd`
- Modify: `autoloads/card_pool.gd`

- [ ] **Step 1: 新建 tests/test_card_pool.gd**

```gdscript
# tests/test_card_pool.gd
extends GdUnitTestSuite

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

# ── pick() 条件过滤 ────────────────────────────────────────────────────────

func test_pick_returns_at_most_3_cards() -> void:
	var cards := CardPool.pick(_player, 3)
	assert_int(cards.size()).is_less_equal(3)

func test_pick_excludes_weapon_already_owned() -> void:
	_player.owned_weapons["knife"] = 1
	var cards := CardPool.pick(_player, 10)
	for card in cards:
		assert_str(card["id"]).is_not_equal("knife")

func test_pick_includes_upgrade_when_weapon_at_level1() -> void:
	_player.owned_weapons["knife"] = 1
	var cards := CardPool.pick(_player, 10)
	var found := false
	for card in cards:
		if card["id"] == "knife_2":
			found = true
	assert_bool(found).is_true()

func test_pick_excludes_upgrade_when_weapon_at_level2() -> void:
	_player.owned_weapons["knife"] = 2
	var cards := CardPool.pick(_player, 10)
	for card in cards:
		assert_str(card["id"]).is_not_equal("knife_2")

func test_pick_returns_all_available_when_pool_smaller_than_count() -> void:
	# 三种武器都升到 Lv.2 → 只剩 4 张属性牌
	_player.owned_weapons["knife"] = 2
	_player.owned_weapons["orb"] = 2
	_player.owned_weapons["explosion"] = 2
	var cards := CardPool.pick(_player, 10)
	assert_int(cards.size()).is_equal(4)

func test_pick_always_includes_perks() -> void:
	var cards := CardPool.pick(_player, 10)
	var perk_ids := ["perk_speed", "perk_hp", "perk_attack", "perk_xp"]
	for perk_id in perk_ids:
		var found := false
		for card in cards:
			if card["id"] == perk_id:
				found = true
		assert_bool(found).is_true()
```

- [ ] **Step 2: 运行测试，确认 6 个新测试失败**

```
"C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64.exe" --path "D:\Workspace\GAME\game_0_vsl" -s "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" --add "res://tests/test_card_pool.gd" --ignoreHeadlessMode
```

Expected: 6 个测试 FAIL（pick() 当前返回空数组）

- [ ] **Step 3: 在 autoloads/card_pool.gd 实现 pick() 和 _check_condition()**

将骨架中的 `pick()` 和 `_check_condition()` 替换为：

```gdscript
func pick(player: Player, count: int = 3) -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for card in CARDS:
		if _check_condition(card["condition"], player):
			available.append(card)
	available.shuffle()
	return available.slice(0, min(count, available.size()))

func _check_condition(condition: String, player: Player) -> bool:
	if condition == "":
		return true
	if condition.begins_with("no:"):
		var weapon_id := condition.substr(3)
		return not player.owned_weapons.has(weapon_id)
	if condition.begins_with("upgrade:"):
		var weapon_id := condition.substr(8)
		var lvl: int = player.owned_weapons.get(weapon_id, 0)
		return lvl >= 1 and lvl < 2
	return false
```

- [ ] **Step 4: 运行测试，确认通过**

```
"C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64.exe" --path "D:\Workspace\GAME\game_0_vsl" -s "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" --add "res://tests/test_card_pool.gd" --ignoreHeadlessMode
```

Expected: 6/6 PASS

- [ ] **Step 5: 提交**

```bash
git add tests/test_card_pool.gd autoloads/card_pool.gd
git commit -m "feat: implement CardPool.pick() with condition filtering"
```

---

### Task 5: CardPool apply() 逻辑 + 测试

**Files:**
- Modify: `tests/test_card_pool.gd`
- Modify: `autoloads/card_pool.gd`

- [ ] **Step 1: 在 test_card_pool.gd 末尾追加 7 个 apply() 测试**

```gdscript
# ── apply() 属性效果 ──────────────────────────────────────────────────────

func test_apply_perk_speed_multiplies_speed_mult() -> void:
	CardPool.apply({"id": "perk_speed"}, _player)
	assert_float(_player.speed_mult).is_equal_approx(1.15, 0.001)

func test_apply_perk_hp_increases_max_hp() -> void:
	CardPool.apply({"id": "perk_hp"}, _player)
	assert_float(_player.max_hp).is_equal(120.0)

func test_apply_perk_hp_heals_current_hp() -> void:
	_player.hp = 80.0
	CardPool.apply({"id": "perk_hp"}, _player)
	# min(80 + 20, 120) = 100
	assert_float(_player.hp).is_equal(100.0)

func test_apply_perk_attack_multiplies_attack_speed_mult() -> void:
	CardPool.apply({"id": "perk_attack"}, _player)
	assert_float(_player.attack_speed_mult).is_equal_approx(1.15, 0.001)

func test_apply_perk_xp_multiplies_xp_mult() -> void:
	CardPool.apply({"id": "perk_xp"}, _player)
	assert_float(_player.xp_mult).is_equal_approx(1.25, 0.001)

func test_apply_perk_speed_stacks_multiplicatively() -> void:
	CardPool.apply({"id": "perk_speed"}, _player)
	CardPool.apply({"id": "perk_speed"}, _player)
	assert_float(_player.speed_mult).is_equal_approx(1.15 * 1.15, 0.001)

func test_apply_weapon_registers_in_owned_weapons() -> void:
	CardPool.apply({"id": "knife"}, _player)
	assert_int(_player.owned_weapons.get("knife", 0)).is_equal(1)
```

- [ ] **Step 2: 运行测试，确认 7 个新测试失败**

```
"C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64.exe" --path "D:\Workspace\GAME\game_0_vsl" -s "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" --add "res://tests/test_card_pool.gd" --ignoreHeadlessMode
```

Expected: 7 个测试 FAIL（apply() 是空方法），之前 6 个仍 PASS

- [ ] **Step 3: 在 autoloads/card_pool.gd 实现 apply()**

将骨架中的 `apply()` 替换为：

```gdscript
func apply(card: Dictionary, player: Player) -> void:
	match card["id"]:
		"knife":
			player.add_weapon(KNIFE_SCENE)
			player.owned_weapons["knife"] = 1
		"orb":
			player.add_weapon(ORB_SCENE)
			player.owned_weapons["orb"] = 1
		"explosion":
			player.add_weapon(EXPLOSION_SCENE)
			player.owned_weapons["explosion"] = 1
		"knife_2":
			for child in player.get_children():
				if child is KnifeWeapon:
					child.cooldown = 0.5
			player.owned_weapons["knife"] = 2
		"orb_2":
			var new_orb := ORB_SHIELD_SCENE.instantiate() as OrbShield
			player.add_child(new_orb)
			new_orb.orbit_index = 2
			new_orb.total_orbs = 3
			for child in player.get_children():
				if child is OrbShield:
					child.total_orbs = 3
			player.owned_weapons["orb"] = 2
		"explosion_2":
			for child in player.get_children():
				if child is ExplosionWeapon:
					child.cooldown = 1.5
			player.owned_weapons["explosion"] = 2
		"perk_speed":
			player.speed_mult *= 1.15
		"perk_hp":
			player.max_hp += 20.0
			player.hp = min(player.hp + 20.0, player.max_hp)
		"perk_attack":
			player.attack_speed_mult *= 1.15
		"perk_xp":
			player.xp_mult *= 1.25
```

- [ ] **Step 4: 运行全部测试，确认通过**

```
"C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64.exe" --path "D:\Workspace\GAME\game_0_vsl" -s "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" --add "res://tests" --ignoreHeadlessMode
```

Expected: 54/54 PASS（20 formulas + 21 player + 13 card_pool）

- [ ] **Step 5: 提交**

```bash
git add tests/test_card_pool.gd autoloads/card_pool.gd
git commit -m "feat: implement CardPool.apply() for all 10 card effects"
```

---

### Task 6: main.gd 初始登记飞刀

**Files:**
- Modify: `scenes/main/main.gd`

- [ ] **Step 1: 将 scenes/main/main.gd 替换为以下内容**

```gdscript
# scenes/main/main.gd
extends Node

const KNIFE_SCENE = preload("res://scenes/weapons/knife/knife_weapon.tscn")

func _ready() -> void:
	var gm = get_node("/root/GameManager")
	var player := $YSort/Player as Player
	player.leveled_up.connect(func(_lvl: int): gm.trigger_level_up())
	player.died.connect(gm.game_over)
	player.add_weapon(KNIFE_SCENE)
	CardPool.register_weapon(player, "knife")
```

- [ ] **Step 2: 提交**

```bash
git add scenes/main/main.gd
git commit -m "feat: register initial knife in CardPool on game start"
```

---

### Task 7: LevelUpUI Layout C 重写

**Files:**
- Modify: `scenes/ui/level_up_ui.gd`

无单元测试。完成后运行游戏，手动验证选卡 UI。

- [ ] **Step 1: 将 scenes/ui/level_up_ui.gd 替换为以下完整内容**

```gdscript
# scenes/ui/level_up_ui.gd
extends CanvasLayer

@onready var card_container: HBoxContainer = $BG/Panel/CardContainer
@onready var _gm = get_node("/root/GameManager")

const COLORS := {
	"weapon": Color(0x4a9effff),
	"upgrade": Color(0xf5a623ff),
	"perk": Color(0x50fa7bff),
}
const TYPE_LABELS := {
	"weapon": "新武器",
	"upgrade": "★ 强化",
	"perk": "属性",
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_gm.level_up_triggered.connect(_on_level_up)

func _on_level_up() -> void:
	visible = true
	var player := get_tree().get_first_node_in_group("player") as Player
	_build_cards(CardPool.pick(player))

func _build_cards(cards: Array) -> void:
	for child in card_container.get_children():
		child.queue_free()
	for card in cards:
		card_container.add_child(_make_card(card))

func _make_card(card: Dictionary) -> Control:
	var color: Color = COLORS[card["type"]]

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(160, 180)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0x16213eff)
	style.set_border_width_all(1)
	style.border_color = color
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(0, 3)
	bar.color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bar)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 8)
	vbox.add_child(margin)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 4)
	margin.add_child(content)

	var type_lbl := Label.new()
	type_lbl.text = TYPE_LABELS[card["type"]]
	type_lbl.add_theme_color_override("font_color", color)
	type_lbl.add_theme_font_size_override("font_size", 10)
	type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(type_lbl)

	var name_lbl := Label.new()
	name_lbl.text = card["name"]
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = card["desc"]
	desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(desc_lbl)

	if card["type"] == "upgrade":
		panel.scale = Vector2(1.04, 1.04)

	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_on_card_picked(card)
	)

	return panel

func _on_card_picked(card: Dictionary) -> void:
	visible = false
	var player := get_tree().get_first_node_in_group("player") as Player
	CardPool.apply(card, player)
	GameFeel.item_selected.emit()
	_gm.resume_game()
```

- [ ] **Step 2: 运行游戏，手动验证选卡 UI**

启动游戏 → 收集 XP 升级 → 验证：
- 出现 3 张卡，每张有顶部色条（武器=蓝，强化=橙，属性=绿）
- 类型标签正确（"新武器" / "★ 强化" / "属性"）
- 强化牌（橙色）轻微放大（scale 1.04）
- 点击卡片后游戏继续，效果生效（拿到飞刀后下次升级不再出现飞刀，改出 Lv.2 选项）

- [ ] **Step 3: 提交**

```bash
git add scenes/ui/level_up_ui.gd
git commit -m "feat: redesign LevelUpUI with Layout C cards using CardPool"
```

---

## 验收清单

- [ ] 54 个测试全部 PASS（20 formulas + 21 player + 13 card_pool）
- [ ] 游戏内升级显示 Layout C 卡片（顶部色条，强化牌放大）
- [ ] 飞刀已拥有时不再显示"飞刀"选项，正确出现"飞刀 Lv.2"
- [ ] 选 perk_attack（攻速提升）后飞刀出刀频率明显加快
- [ ] 选 perk_speed（移速提升）后玩家移动速度明显变快
- [ ] 选 perk_hp（生命上限）后 HUD 显示最大 HP 增加
