# 武器军械库重做 VFX-W2：逐武器视效接入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 VFX 底座（VFX-W1 的 `Vfx` 工厂 + `GameFeel` 打击感 API）逐把接到每件武器的开火/命中/AoE 时刻——按 spec §7 的「视觉」与「打击感」配方为每把武器补粒子爆发 / 序列帧 / 拖尾 / 分级震屏 / 重武器 hitstop，落实「一眼读出这是什么武器、命中了谁」。

**Architecture:** 纯**叠加**式接入——不改任何武器的机制/伤害逻辑，只在已有的命中/施放点追加对 `Vfx.*` 与 `GameFeel.shake/hitstop` 的调用。进化形态的**变色**已由 W1/W3b 经 `proj_tint`/`blast_tint`/`bolt_tint`/`double_sided`/`lifesteal_on_hit` 等数据字段完成，本波只补「粒子/序列帧/震屏/顿帧」。新增的逐武器粒子配方集中进 `Vfx.BURST_PRESETS` + 一个 `Vfx.make_trail` 工厂，武器侧只调用不自写粒子参数。

**Tech Stack:** Godot 4.6.3 · GDScript · gdUnit4 · VFX-W1 底座（`Vfx` 自动加载 + `GameFeel.shake/hitstop`）· Kenney FX 素材（VFX-W1 已导入）。

## Global Constraints

逐条来自 spec §6、§7 各武器「视觉/打击感」行、以及仓库现状，每个任务都隐含遵守：

- **引擎 Godot 4.6.3**；测试经 gdUnit4 headless，**必须** `--ignoreHeadlessMode`。
- **只叠加、不改机制**：本波不动任何 `take_damage` 调用、命中判定、伤害口径、`.tres` 数值。FX 调用是已有逻辑之后的追加行。
- **打击感分级（spec §7 各武器「打击感」行，逐字落地）**：
  - 斩/回旋斧/长弓普通命中 = `GameFeel.shake(&"light")`；长弓暴击、火球、连锁、震地冲击波 = `&"medium")`；核爆/碎/震地砸地 = `&"heavy")` + `GameFeel.hitstop(0.06)`。
  - 持续光环类（烈焰护体/炼狱、缚灵/缚刃、引力井）**不震屏**（避免抖动疲劳，spec §7 炼狱行明示），仅命中闪光/粒子。
- **视觉可读性（spec §2.4）**：FX 不盖过敌人与走位空间；拖尾/光环半透，爆发短命。
- **headless 安全**：`GameFeel.hitstop` 内已对 `RunHarness.active` 跳过（VFX-W1 保留）；本波直接调用即可，无需自处理。
- **复用底座，不自写粒子**：所有粒子走 `Vfx.spawn_burst`/`make_trail`，序列帧走 `Vfx.spawn_anim`，震屏/顿帧走 `GameFeel`。新粒子配方加进 `Vfx.BURST_PRESETS`，不在武器脚本内 new `CPUParticles2D`。
- **VFX 不可像素级断言**：逐武器测试以**结构/集成冒烟**为主（攻击后 FX 节点出现、伤害不回归），画面正确性由任务 11 的截图清单（godot-ai MCP）兜底，非阻塞。同 VFX-W1 的诚实口径。
- **测试约定**：`extends GdUnitTestSuite`；武器实例化需挂在一个 `Player`（`get_parent() as Player`）下才能 `_ready`；用 `load(...).instantiate()` + `add_child` + `await get_tree().process_frame`。

**前置依赖（执行顺序）：**

- **必须先完成 VFX-W1**（`…-vfx-foundation.md`）：本波全程调用 `Vfx.spawn_burst/spawn_anim/make_trail` 与 `GameFeel.shake/hitstop`。
- **必须先完成对应武器波次**：斩/长弓/回旋斧/火球/烈焰/连锁/缚灵 FX 依赖 **W1**；碎/霜噬/引力井 FX 依赖 **W2**；Reanimate 随从 FX 依赖 **W3a**；进化专属 FX（回旋斩血雾、雷暴天雷、奇点坍缩等）依赖 **W3b**。
- 各任务的代码插入点以**当前武器脚本**（本计划已逐字核对）为锚；若 W1/W2/W3 重构挪动了命中点，接到等价的「`take_damage` 之后」位置即可。

**headless 测试命令**（PowerShell；下文每任务 Run 步骤都用它，仅换 `-a` 目标）：

```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<TEST_FILE>.gd
```

---

## File Structure

**修改**

- `autoloads/vfx.gd` — 追加逐武器 `BURST_PRESETS` 条目 + `make_trail` 工厂（Task 1）。
- `scenes/weapons/whip/whip_weapon.gd` — 命中 `shake(light)` + 回旋斩血雾（Task 2）。
- `scenes/weapons/knife/knife_weapon.gd` + `knife_projectile.gd` — 枪口闪 + 命中火花 + 暴击金花/`shake`（Task 3）。
- `scenes/weapons/boomerang/boomerang_projectile.gd` — `trace_*` 拖尾（Task 4）。
- `scenes/weapons/explosion/explosion.gd` + `explosion_weapon.gd` — 序列帧爆炸 + `shake`/`hitstop`（Task 5）。
- `scenes/weapons/lightning/lightning_weapon.gd` — 命中火花/星 + `shake(medium)` + 短 `hitstop`（Task 6）。
- `scenes/weapons/aura/aura_weapon.gd` — 环绕火/霜粒子（Task 7）。
- `scenes/weapons/orb/orb_shield.gd` — 灵体辉光 + 拖尾（Task 8）。
- 新武器脚本（W2 产出）：`maul`/`frostbite`/`gravity_well` — 砸地/冰爆/旋涡 FX（Task 9）。
- 随从脚本（W3a 产出）：`reanimate`/`roaming_minion` — 召唤法阵 + 随从辉光（Task 10）。

**新建（测试）**

- `tests/test_vfx_weapon_presets.gd`、`tests/test_vfx_weapon_fx.gd`（逐武器集成冒烟，按任务追加方法）。

---

## Task 1: `Vfx` 追加逐武器粒子配方 + 拖尾工厂

**Files:**
- Modify: `autoloads/vfx.gd`（`BURST_PRESETS` 追加 + 新 `make_trail`）
- Test: `tests/test_vfx_weapon_presets.gd`

**Interfaces:**
- Produces:
  - `BURST_PRESETS` 新增 `&"blood_burst"`、`&"crit_spark"`、`&"ice_shard"`、`&"shock_spark"`。
  - `func make_trail(color: Color, additive: bool = false) -> CPUParticles2D` — 返回**未入树**、持续发射的拖尾粒子，供投射物挂为子节点。

- [x] **Step 1: 写失败测试**

`tests/test_vfx_weapon_presets.gd`：

```gdscript
extends GdUnitTestSuite

func test_weapon_burst_presets_registered() -> void:
	for k in [&"blood_burst", &"crit_spark", &"ice_shard", &"shock_spark"]:
		assert_bool(Vfx.BURST_PRESETS.has(k)).is_true()

func test_make_trail_returns_emitting_particles() -> void:
	var t := Vfx.make_trail(Color(1, 0, 0))
	assert_bool(t is CPUParticles2D).is_true()
	assert_bool(t.emitting).is_true()
	assert_bool(t.one_shot).is_false()
	t.free()

func test_make_trail_additive_uses_add_material() -> void:
	var t := Vfx.make_trail(Color(1, 1, 1), true)
	assert_int((t.material as CanvasItemMaterial).blend_mode).is_equal(CanvasItemMaterial.BLEND_MODE_ADD)
	t.free()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_weapon_presets.gd`
Expected: FAIL — 新预设/`make_trail` 不存在。

- [x] **Step 3: 改 `autoloads/vfx.gd`**

3a. 在 `BURST_PRESETS` 字典里追加 4 条（放在 `magic_burst` 后）：

```gdscript
	&"magic_burst": {"color": Color(0.7, 0.5, 1.0),   "amount": 12, "lifetime": 0.45, "vmin": 30.0, "vmax": 110.0, "smin": 3.0, "smax": 6.0, "additive": true},
	&"blood_burst": {"color": Color(0.7, 0.05, 0.08), "amount": 8,  "lifetime": 0.35, "vmin": 30.0, "vmax": 90.0,  "smin": 2.0, "smax": 4.0, "additive": false},
	&"crit_spark":  {"color": Color(1.0, 0.85, 0.3),  "amount": 14, "lifetime": 0.30, "vmin": 80.0, "vmax": 220.0, "smin": 2.0, "smax": 5.0, "additive": true},
	&"ice_shard":   {"color": Color(0.7, 0.92, 1.0),  "amount": 10, "lifetime": 0.35, "vmin": 50.0, "vmax": 140.0, "smin": 2.0, "smax": 4.0, "additive": false},
	&"shock_spark": {"color": Color(0.7, 0.9, 1.0),   "amount": 10, "lifetime": 0.25, "vmin": 70.0, "vmax": 200.0, "smin": 2.0, "smax": 4.0, "additive": true},
```

3b. 追加拖尾工厂（放在 `make_status_indicator` 附近）：

```gdscript
# 投射物拖尾:挂为投射物子节点的持续粒子,随运动留尾。additive 走加色发光。
func make_trail(color: Color, additive: bool = false) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = true
	p.one_shot = false
	p.amount = 16
	p.lifetime = 0.3
	p.explosiveness = 0.0
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 10.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	if additive:
		p.material = additive_material()
	return p
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_weapon_presets.gd` → PASS。

```powershell
git add autoloads/vfx.gd tests/test_vfx_weapon_presets.gd
git commit -m @'
feat(vfx): Vfx 追加逐武器粒子配方(blood/crit/ice/shock) + make_trail 拖尾工厂

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 2: 斩 / 回旋斩 Whirlwind（whip）FX

**Files:**
- Modify: `scenes/weapons/whip/whip_weapon.gd`
- Test: `tests/test_vfx_weapon_fx.gd`

**Interfaces:**
- Consumes: `GameFeel.shake`、`Vfx.spawn_burst(&"blood_burst")`。
- 现状锚点：`attack()` 在命中循环里 `e.take_damage(dmg)`，循环后 `_spawn_swipe(origin)`（已有斩光贴图，不动）。

- [x] **Step 1: 写失败测试（`tests/test_vfx_weapon_fx.gd`，含 helper）**

```gdscript
extends GdUnitTestSuite

const WhipScript := preload("res://scenes/weapons/whip/whip_weapon.gd")

# 造一个挂着武器的最小玩家 + ysort，便于攻击产出 FX。
func _make_player() -> Player:
	var p := load("res://scenes/player/player.tscn").instantiate()
	add_child(p)
	return p

func _make_enemy_at(pos: Vector2) -> Node2D:
	var e := load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child(e)
	e.global_position = pos
	e.add_to_group("enemies")
	return e

func _ysort_child_count() -> int:
	var ys := get_tree().get_first_node_in_group("ysort")
	return ys.get_child_count() if ys != null else get_tree().current_scene.get_child_count()

func test_whirlwind_hit_spawns_blood_burst() -> void:
	var player := _make_player()
	var whip := WhipScript.new()
	whip.data = null
	player.add_child(whip)
	await get_tree().process_frame
	whip.double_sided = true   # 回旋斩形态
	whip.swing_range = 200.0
	var enemy := _make_enemy_at(player.global_position + Vector2(40, 0))
	await get_tree().process_frame
	var before := _ysort_child_count()
	whip.attack()
	await get_tree().process_frame
	# 命中后应在场上多出血雾粒子(斩光本就有,这里验"比仅斩光更多")
	assert_int(_ysort_child_count()).is_greater(before)
	player.queue_free(); enemy.queue_free()
```

> 若测试环境没有 `ysort` 组节点，`get_ysort()` 回退到 `current_scene`，helper 已对齐该回退。

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_weapon_fx.gd`
Expected: FAIL — 攻击只产斩光，无血雾，计数断言不满足（或 double_sided 命中未接 FX）。

- [x] **Step 3: 改 `whip_weapon.gd` 的 `attack()`**

把命中循环与收尾改为（追加 `any_hit` 与血雾/震屏）：

```gdscript
func attack() -> void:
	var targets := enemies()
	if targets.is_empty():
		return
	var dmg: float = damage_for(damage)
	var origin: Vector2 = _player.global_position
	var any_hit := false
	for e in targets:
		var pos: Vector2 = (e as Node2D).global_position
		var hit := in_cone(pos, origin, _facing, arc_deg, swing_range)
		if not hit and double_sided:
			hit = in_cone(pos, origin, -_facing, arc_deg, swing_range)
		if hit and is_instance_valid(e):
			e.take_damage(dmg)
			any_hit = true
			if double_sided:  # 回旋斩:命中溅血雾(配合 W3b 的流血 DoT 质变)
				Vfx.spawn_burst(pos, &"blood_burst")
	_spawn_swipe(origin)
	if any_hit:
		GameFeel.shake(&"light")
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → PASS。

```powershell
git add scenes/weapons/whip/whip_weapon.gd tests/test_vfx_weapon_fx.gd
git commit -m @'
feat(vfx): 斩/回旋斩命中接 light 震屏 + 回旋斩溅血雾

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 3: 长弓 / 箭雨 Arrow Storm（knife）FX

**Files:**
- Modify: `scenes/weapons/knife/knife_weapon.gd`、`scenes/weapons/knife/knife_projectile.gd`
- Test: `tests/test_vfx_weapon_fx.gd`（追加方法）

**Interfaces:**
- Consumes: `Vfx.spawn_burst(&"hit_spark" / &"crit_spark")`、`GameFeel.shake`。
- 现状锚点：`knife_weapon.attack()` 每发实例化 projectile；`knife_projectile._physics_process` 命中处 `body.take_damage(damage)`。
- W1「长弓」给 projectile 注入 `is_crit: bool`（暴击），W1 已加该字段；本波据其选 `crit_spark` + `medium` 震屏。若 W1 字段名不同，按其暴击标志接。

- [x] **Step 1: 写失败测试（追加到 `tests/test_vfx_weapon_fx.gd`）**

```gdscript
const KnifeProjScript := preload("res://scenes/weapons/knife/knife_projectile.gd")

func test_knife_hit_spawns_spark() -> void:
	var player := _make_player()
	await get_tree().process_frame
	var proj := KnifeProjScript.new()
	proj.damage = 5.0
	proj.pierce = 1
	add_child(proj)
	proj.global_position = player.global_position
	var enemy := _make_enemy_at(player.global_position)  # 重合 → 必命中
	await get_tree().process_frame
	var before := _ysort_child_count()
	await get_tree().physics_frame
	await get_tree().process_frame
	# 命中应产出火花粒子
	assert_int(_ysort_child_count()).is_greater_equal(before)  # 命中点 spark
	player.queue_free()
	if is_instance_valid(enemy): enemy.queue_free()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_weapon_fx.gd`
Expected: FAIL — 命中无火花。

- [x] **Step 3a: 改 `knife_projectile.gd` 命中处**

在 `body.take_damage(damage)` 后追加命中火花（暴击金花，普通白花）：

```gdscript
			_hit_ids[id] = true
			body.take_damage(damage)
			var preset: StringName = &"crit_spark" if is_crit else &"hit_spark"
			Vfx.spawn_burst(global_position, preset)
			pierce -= 1
```

并在字段区补 `is_crit`（若 W1 已加则跳过；这里给默认值兜底）：

```gdscript
var is_crit: bool = false  # 由 KnifeWeapon 注入(长弓暴击);决定命中火花颜色/震屏
```

- [x] **Step 3b: 改 `knife_weapon.gd` 的 `attack()`**

在每发 projectile 配置块里把暴击标志透传，并在暴击时 `medium` 震屏。W1「长弓」已算出暴击（`longbow_crit_bonus` 静态 + `damage_for(base, can_crit, crit_bonus)`）；本波只读结果。最小接法——在 `attack()` 循环里：

```gdscript
		var projectile := PROJECTILE_SCENE.instantiate()
		var crit := WeaponBase.crit_multiplier(_player.crit_chance + longbow_crit_bonus, _player.crit_mult) > 1.0
		projectile.damage = damage_for(damage, true, longbow_crit_bonus)
		projectile.is_crit = crit
		projectile.pierce = eff_pierce
		...
		if crit:
			GameFeel.shake(&"medium")
```

> `longbow_crit_bonus`、`damage_for(base, can_crit, crit_bonus)`、`crit_multiplier` 均为 W0/W1 产出；若长弓在基础飞刀上不暴击（基础 knife 无暴击），`can_crit` 传 `false`、`is_crit=false`，仅普通火花。按 W1 实际接线。

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → PASS。

```powershell
git add scenes/weapons/knife/knife_weapon.gd scenes/weapons/knife/knife_projectile.gd tests/test_vfx_weapon_fx.gd
git commit -m @'
feat(vfx): 飞刀/长弓命中火花,暴击金花 + medium 震屏

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 4: 回旋斧 / 旋风斧 Cyclone（boomerang）FX — 拖尾

**Files:**
- Modify: `scenes/weapons/boomerang/boomerang_projectile.gd`
- Test: `tests/test_vfx_weapon_fx.gd`（追加方法）

**Interfaces:**
- Consumes: `Vfx.make_trail`。
- 现状锚点：`boomerang_projectile._ready()` 建 `_sprite` 后即可挂拖尾子节点。

- [x] **Step 1: 写失败测试（追加）**

```gdscript
const BoomerangProjScript := preload("res://scenes/weapons/boomerang/boomerang_projectile.gd")

func test_boomerang_has_trail_child() -> void:
	var player := _make_player()
	await get_tree().process_frame
	var proj := BoomerangProjScript.new()
	add_child(proj)
	await get_tree().process_frame
	var has_trail := false
	for c in proj.get_children():
		if c is CPUParticles2D:
			has_trail = true
	assert_bool(has_trail).is_true()
	player.queue_free(); proj.queue_free()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → FAIL（无拖尾子节点）。

- [x] **Step 3: 改 `boomerang_projectile.gd` 的 `_ready()`**

在 `add_child(_sprite)` 后追加拖尾：

```gdscript
func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_sprite = Sprite2D.new()
	_sprite.texture = SPRITE_TEX
	_sprite.scale = Vector2(0.8, 0.8)
	add_child(_sprite)
	# 旋斧残影拖尾(冷钢青白)
	add_child(Vfx.make_trail(Color(0.8, 0.9, 1.0, 0.7)))
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → PASS。

```powershell
git add scenes/weapons/boomerang/boomerang_projectile.gd tests/test_vfx_weapon_fx.gd
git commit -m @'
feat(vfx): 回旋斧拖尾残影(trace 风格粒子)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 5: 火球 / 核爆 Cataclysm（explosion）FX — 序列帧 + 震屏/顿帧

**Files:**
- Modify: `scenes/weapons/explosion/explosion.gd`、`scenes/weapons/explosion/explosion_weapon.gd`
- Test: `tests/test_vfx_weapon_fx.gd`（追加方法）

**Interfaces:**
- Consumes: `Vfx.spawn_anim(&"explosion_regular" / &"explosion_ground")`、`GameFeel.shake`、`GameFeel.hitstop`。
- 现状锚点：`ExplosionWeapon.attack()` 实例化 explosion 并 `detonate()`；`Explosion._process` 用单张贴图缩放淡出。
- 核爆判定：W3b「核爆」经 `blast_scale` 注入放大（现有字段）；本波据 `base_scale > 1.0` 选地裂序列 + heavy。

- [x] **Step 1: 写失败测试（追加）**

```gdscript
const ExplosionScript := preload("res://scenes/weapons/explosion/explosion.gd")

func test_explosion_spawns_anim_sprite() -> void:
	# Explosion.detonate 附带序列帧爆炸 FX。
	var enemy := _make_enemy_at(Vector2(500, 500))
	var expl := ExplosionScript.new()
	add_child(expl)
	expl.damage = 1.0
	expl.global_position = Vector2(500, 500)
	await get_tree().process_frame
	var scene_before := get_tree().current_scene.get_child_count() if get_tree().current_scene else 0
	expl.detonate()
	await get_tree().process_frame
	# 应有一个 AnimatedSprite2D 出现(序列帧爆炸)
	var found := false
	for n in get_tree().get_nodes_in_group("ysort"):
		pass
	# 直接查 expl 的兄弟/当前场景里的 AnimatedSprite2D
	assert_bool(_scene_has_animated_sprite()).is_true()
	if is_instance_valid(enemy): enemy.queue_free()
	if is_instance_valid(expl): expl.queue_free()

func _scene_has_animated_sprite() -> bool:
	var roots: Array = [get_tree().current_scene]
	var ys := get_tree().get_first_node_in_group("ysort")
	if ys != null: roots.append(ys)
	for r in roots:
		if r == null: continue
		for c in r.get_children():
			if c is AnimatedSprite2D:
				return true
	return false
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → FAIL（无 AnimatedSprite2D）。

- [x] **Step 3a: 改 `explosion.gd` 的 `detonate()`**

在伤害循环后追加序列帧 FX + 震屏/顿帧（按 `base_scale` 区分核爆）：

```gdscript
func detonate() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to((enemy as Node2D).global_position) <= RADIUS:
			enemy.take_damage(damage)
	# 序列帧爆炸 FX:核爆(放大)用地裂序列 + heavy 震屏 + 顿帧;普通火球用常规爆炸 + medium。
	var is_nuke := base_scale > 1.0
	var anim: StringName = &"explosion_ground" if is_nuke else &"explosion_regular"
	var fx := Vfx.spawn_anim(global_position, anim)
	if fx != null:
		fx.scale = Vector2.ONE * base_scale
	if is_nuke:
		GameFeel.shake(&"heavy")
		GameFeel.hitstop(0.06)
	else:
		GameFeel.shake(&"medium")
```

- [x] **Step 3b（可选清理）：** 既有单张贴图 `_process` 缩放淡出可保留作底层闪光，或在确认序列帧观感后由视觉冒烟决定是否弱化其 alpha。本步不强制改 `_process`。

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → PASS。

```powershell
git add scenes/weapons/explosion/explosion.gd scenes/weapons/explosion/explosion_weapon.gd tests/test_vfx_weapon_fx.gd
git commit -m @'
feat(vfx): 火球序列帧爆炸+medium,核爆地裂序列+heavy 震屏+hitstop

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 6: 连锁闪电 / 雷暴 Tempest（lightning）FX — 命中火花 + 震屏/顿帧

**Files:**
- Modify: `scenes/weapons/lightning/lightning_weapon.gd`
- Test: `tests/test_vfx_weapon_fx.gd`（追加方法）

**Interfaces:**
- Consumes: `Vfx.spawn_burst(&"shock_spark")`、`GameFeel.shake(&"medium")`、`GameFeel.hitstop(0.04)`。
- 现状锚点：`attack()` 命中后 `_spawn_bolt(path)`（已有电弧/辉光，不动）；`_spawn_impact(ys, pos)` 是每个命中点。

- [x] **Step 1: 写失败测试（追加）**

```gdscript
const LightningScript := preload("res://scenes/weapons/lightning/lightning_weapon.gd")

func test_lightning_attack_sparks_and_no_crash() -> void:
	var player := _make_player()
	var lit := LightningScript.new()
	lit.data = null
	player.add_child(lit)
	await get_tree().process_frame
	var enemy := _make_enemy_at(player.global_position + Vector2(60, 0))
	await get_tree().process_frame
	var before := _ysort_child_count()
	lit.attack()
	await get_tree().process_frame
	assert_int(_ysort_child_count()).is_greater(before)  # 电弧+辉光+火花
	player.queue_free()
	if is_instance_valid(enemy): enemy.queue_free()
```

- [x] **Step 2: 跑测试确认失败 / 确认基线**

Run: `… -a res://tests/test_vfx_weapon_fx.gd`
（基础 lightning 已产电弧；此测验「攻击命中后不崩 + 节点增多」，作为接 FX 的回归锚。）

- [x] **Step 3: 改 `lightning_weapon.gd`**

3a. `attack()` 命中后追加震屏/顿帧（在 `_spawn_bolt(path)` 后）：

```gdscript
	_spawn_bolt(path)
	GameFeel.shake(&"medium")
	GameFeel.hitstop(0.04)  # 噼啪顿挫;headless 自动跳过
```

3b. `_spawn_impact` 末尾追加电火花爆发（叠在辉光上）：

```gdscript
	tw.finished.connect(func() -> void: if is_instance_valid(g): g.queue_free())
	Vfx.spawn_burst(pos, &"shock_spark")
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → PASS。

```powershell
git add scenes/weapons/lightning/lightning_weapon.gd tests/test_vfx_weapon_fx.gd
git commit -m @'
feat(vfx): 连锁闪电命中电火花 + medium 震屏 + 短 hitstop

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 7: 烈焰护体 / 炼狱 Inferno（aura）FX — 环绕火/霜粒子

**Files:**
- Modify: `scenes/weapons/aura/aura_weapon.gd`
- Test: `tests/test_vfx_weapon_fx.gd`（追加方法）

**Interfaces:**
- Consumes: `Vfx.make_trail`（复用作环绕持续粒子）。
- 现状锚点：`_setup_ring()` 建 `_ring` 挂在玩家下；`_update_ring()` 据 `lifesteal_on_hit` 变色。**不震屏**（spec）。

- [x] **Step 1: 写失败测试（追加）**

```gdscript
const AuraScript := preload("res://scenes/weapons/aura/aura_weapon.gd")

func test_aura_has_orbit_particles() -> void:
	var player := _make_player()
	var aura := AuraScript.new()
	aura.data = null
	player.add_child(aura)
	await get_tree().process_frame
	# 光环视觉挂在玩家下;应含一个持续粒子节点(火/霜)
	var has_particles := false
	for c in player.get_children():
		if c is CPUParticles2D:
			has_particles = true
	assert_bool(has_particles).is_true()
	player.queue_free()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → FAIL（仅有 ring sprite，无粒子）。

- [x] **Step 3: 改 `aura_weapon.gd` 的 `_setup_ring()`**

在 `(_player as Node2D).add_child(_ring)` 后追加环绕粒子（炼狱橙、基础青）：

```gdscript
func _setup_ring() -> void:
	_ring = Sprite2D.new()
	_ring.texture = RING_TEX
	(_player as Node2D).add_child(_ring)
	# 环绕火/霜粒子:炼狱(lifesteal)橙红,基础冷青。半透不挡视线。
	var col := Color(1.0, 0.5, 0.15, 0.5) if lifesteal_on_hit > 0.0 else Color(0.6, 0.9, 1.0, 0.4)
	var p := Vfx.make_trail(col)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	(_player as Node2D).add_child(p)
	_update_ring()
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → PASS。

```powershell
git add scenes/weapons/aura/aura_weapon.gd tests/test_vfx_weapon_fx.gd
git commit -m @'
feat(vfx): 烈焰护体/炼狱环绕火霜粒子(半径内球形发射,不震屏)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 8: 缚灵 / 缚刃 Bound Blades（orb）FX — 灵体辉光 + 拖尾

**Files:**
- Modify: `scenes/weapons/orb/orb_shield.gd`
- Test: `tests/test_vfx_weapon_fx.gd`（追加方法）

**Interfaces:**
- Consumes: `Vfx.make_trail(…, true)`（加色幽蓝辉光拖尾）。
- 现状锚点：`OrbShield._ready()` 拿 `_player`；护盾球自身是 Node2D（贴图在 `.tscn` 的 Sprite2D 子节点）。**不震屏**。

- [x] **Step 1: 写失败测试（追加）**

```gdscript
const OrbShieldScene := "res://scenes/weapons/orb/orb_shield.tscn"

func test_orb_shield_has_glow_trail() -> void:
	var player := _make_player()
	await get_tree().process_frame
	var orb := load(OrbShieldScene).instantiate()
	player.add_child(orb)
	await get_tree().process_frame
	var has_trail := false
	for c in orb.get_children():
		if c is CPUParticles2D:
			has_trail = true
	assert_bool(has_trail).is_true()
	player.queue_free()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → FAIL。

- [x] **Step 3: 改 `orb_shield.gd` 的 `_ready()`**

```gdscript
func _ready() -> void:
	_player = get_parent()
	# 灵体幽蓝辉光拖尾(加色发光)
	add_child(Vfx.make_trail(Color(0.5, 0.6, 1.0, 0.8), true))
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → PASS。

```powershell
git add scenes/weapons/orb/orb_shield.gd tests/test_vfx_weapon_fx.gd
git commit -m @'
feat(vfx): 缚灵护盾球幽蓝辉光拖尾

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 9: 新武器 FX — 碎 Maul / 霜噬 Frostbite / 引力井 Gravity Well

> **依赖 W2**：脚本 `scenes/weapons/maul/…`、`scenes/weapons/frostbite/…`、`scenes/weapons/gravity_well/…` 由武器波次 W2 产出。本任务在其命中/施放点接 FX。

**Files:**
- Modify: W2 产出的三把武器脚本
- Test: `tests/test_vfx_weapon_fx.gd`（追加方法，按 W2 实际类名）

**Interfaces:**
- 碎 Maul（双手近战，砸击 + stun + 击退）：命中 `Vfx.spawn_anim(&"explosion_ground")`（小尺度）+ `GameFeel.shake(&"heavy")` + `GameFeel.hitstop(0.06)`。
- 霜噬 Frostbite（冰，命中附 slow/freeze）：命中 `Vfx.spawn_burst(&"ice_shard")` + `GameFeel.shake(&"light")`。
- 引力井 Gravity Well（变幻，区域拉拽）：生成时 `Vfx.spawn_burst(&"magic_burst")` 于井心 + 旋涡（见下）；**不震屏**（持续场），奇点坍缩（W3b）时 `shake(&"medium")`。

- [x] **Step 1: 写失败测试（追加，示例：Maul）**

```gdscript
# 类名以 W2 实际为准(此处假设 MaulWeapon)。
func test_maul_hit_heavy_feedback() -> void:
	var player := _make_player()
	var maul = load("res://scenes/weapons/maul/maul_weapon.tscn").instantiate()
	player.add_child(maul)
	await get_tree().process_frame
	var enemy := _make_enemy_at(player.global_position + Vector2(30, 0))
	await get_tree().process_frame
	maul.attack()
	await get_tree().process_frame
	assert_bool(_scene_has_animated_sprite()).is_true()  # 砸地序列帧
	player.queue_free()
	if is_instance_valid(enemy): enemy.queue_free()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → FAIL。

- [x] **Step 3: 在三把武器命中/施放点追加 FX**

碎 Maul `attack()` 命中后：

```gdscript
	# 砸地:地裂序列帧 + heavy 震屏 + 顿帧(强调"沉重")
	var fx := Vfx.spawn_anim(_player.global_position, &"explosion_ground")
	if fx != null:
		fx.scale = Vector2(0.7, 0.7)
	GameFeel.shake(&"heavy")
	GameFeel.hitstop(0.06)
```

霜噬 Frostbite 命中循环里每命中一敌：

```gdscript
		e.take_damage(dmg)
		Vfx.spawn_burst((e as Node2D).global_position, &"ice_shard")
	# 循环后:
	if any_hit:
		GameFeel.shake(&"light")
```

引力井 Gravity Well 生成井时（`_ready` 或施放点）：

```gdscript
	Vfx.spawn_burst(global_position, &"magic_burst")
	# 旋涡:挂一个向心拖尾(twirl 风格);坍缩(W3b)时另接 shake(&"medium")
	add_child(Vfx.make_trail(Color(0.7, 0.5, 1.0, 0.6), true))
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → PASS。

```powershell
git add scenes/weapons/maul scenes/weapons/frostbite scenes/weapons/gravity_well tests/test_vfx_weapon_fx.gd
git commit -m @'
feat(vfx): 碎砸地heavy+顿帧 / 霜噬冰爆light / 引力井旋涡magic

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 10: 亡者召唤 Reanimate / 群尸 Horde（W3a）FX — 召唤法阵 + 随从辉光

> **依赖 W3a**：`scenes/weapons/reanimate/reanimate_weapon.gd` + `roaming_minion.gd` 由 W3a 产出。

**Files:**
- Modify: `reanimate_weapon.gd`（召唤瞬间）、`roaming_minion.gd`（随从外观）
- Test: `tests/test_vfx_weapon_fx.gd`（追加方法）

**Interfaces:**
- 召唤瞬间：井心/随从生成点 `Vfx.spawn_burst(&"magic_burst")` + 地面亮符文（`Sprite2D` 用 `res://assets/sprites/kenney/runes/runeBlue_tile_001.png`，短淡出）+ `GameFeel.shake(&"light")`。
- 随从（RoamingMinion）：`_ready` 挂幽蓝辉光拖尾 `Vfx.make_trail(Color(0.5,0.6,1.0,0.8), true)`。

- [x] **Step 1: 写失败测试（追加）**

```gdscript
func test_minion_has_glow_trail() -> void:
	var player := _make_player()
	await get_tree().process_frame
	var minion = load("res://scenes/weapons/reanimate/roaming_minion.tscn").instantiate()
	add_child(minion)
	await get_tree().process_frame
	var has_trail := false
	for c in minion.get_children():
		if c is CPUParticles2D:
			has_trail = true
	assert_bool(has_trail).is_true()
	player.queue_free()
	if is_instance_valid(minion): minion.queue_free()
```

> RoamingMinion 在 W3a 是代码自建碰撞/精灵的 CharacterBody2D；若它无 `.tscn` 而是脚本 `.new()`，改用 `load(".../roaming_minion.gd").new()`。

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → FAIL。

- [x] **Step 3: 接 FX**

`roaming_minion.gd` 的 `_ready()`（在自建精灵后）：

```gdscript
	add_child(Vfx.make_trail(Color(0.5, 0.6, 1.0, 0.8), true))
```

`reanimate_weapon.gd` 召唤随从处（每召唤一只）：

```gdscript
	Vfx.spawn_burst(spawn_pos, &"magic_burst")
	_spawn_rune_flash(spawn_pos)
	GameFeel.shake(&"light")
```

并在 `reanimate_weapon.gd` 加法阵闪一下的小工具：

```gdscript
const _RUNE_TEX := preload("res://assets/sprites/kenney/runes/runeBlue_tile_001.png")

func _spawn_rune_flash(pos: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = _RUNE_TEX
	s.modulate = Color(0.5, 0.7, 1.0, 0.9)
	s.scale = Vector2(0.5, 0.5)
	get_ysort().add_child(s)
	s.global_position = pos
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 0.4)
	tw.finished.connect(func() -> void: if is_instance_valid(s): s.queue_free())
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_weapon_fx.gd` → PASS。

```powershell
git add scenes/weapons/reanimate tests/test_vfx_weapon_fx.gd
git commit -m @'
feat(vfx): 召唤法阵闪光+magic 涌出+light 震屏,随从幽蓝辉光拖尾

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 11: 全量回归 + 视觉冒烟

- [x] **Step 1: 跑全部测试套件**

Run: `… -a res://tests`
Expected: 全绿（VFX-W1/W2 测试 + W0–W3b 武器测试无回归；本波只叠加 FX，未动伤害/机制，既有数值断言不变）。

- [x] **Step 2: 视觉冒烟（godot-ai MCP，逐武器目视，非阻塞）**

`project_run` 主场景，逐把武器升级并触发，`editor_screenshot` 对照 spec §7 配方逐条确认：
- 斩=金弧扫动 / 回旋斩=红弧+血雾；长弓命中白花、暴击金花 + 顿一下；回旋斧带残影拖尾；火球=爆炸序列帧+medium 抖、核爆=地裂+heavy 抖+顿帧；连锁=电弧+电火花+medium；烈焰护体=橙环粒子、炼狱更盛；缚灵=幽蓝辉光球；碎=砸地重击；霜噬=冰爆；引力井=旋涡；召唤=法阵闪光。
- 复核 FX 不盖过敌人/走位空间（spec §2.4）；持续光环类确认**无**抖动疲劳。
- 发现问题回对应任务调预设/震屏档位。

- [x] **Step 3: 提交（若调了数值）**

```powershell
git add -A
git commit -m @'
chore(vfx): 逐武器视觉冒烟后微调震屏档/粒子预设

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Self-Review

**1. Spec 覆盖（§7 各武器「视觉/打击感」行）：**

| 武器（基础/进化） | 视觉 FX | 打击感 | 任务 |
|---|---|---|---|
| 斩 / 回旋斩 | 斩光弧（已有）+ 回旋斩血雾 | light 震屏 | 2 |
| 长弓 / 箭雨 | 命中火花、暴击金花 | 暴击 medium | 3 |
| 回旋斧 / 旋风斧 | trace 残影拖尾 | (去/回 light，留 W4 可加) | 4 |
| 火球 / 核爆 | 爆炸序列帧 / 地裂序列 | medium / heavy + hitstop | 5 |
| 连锁闪电 / 雷暴 | 电弧（已有）+ 电火花 | medium + 短 hitstop | 6 |
| 烈焰护体 / 炼狱 | 环绕火/霜粒子 | 不震屏 | 7 |
| 缚灵 / 缚刃 | 幽蓝辉光拖尾 | 不震屏 | 8 |
| 碎 / 霜噬 / 引力井 | 砸地序列 / 冰爆 / 旋涡 | heavy+顿帧 / light / 不震屏 | 9 |
| 亡者召唤 / 群尸 | 召唤法阵 + 随从辉光 | light | 10 |

**有意推迟（记入交接）：** 专用**着色器**（火噪声扰动加色、冰白边折射、电 UV 抖动、召唤幽光描边、变幻径向扭曲）= **VFX Wave 3（打磨层）**；本波用粒子/序列帧/加色材质达成大部分观感，着色器是锦上添花。进化专属的天雷/坍缩/冲击波等**独立 AoE 实体**的视觉随其机制（W3b）落地，本波只接其触发点的震屏。

**2. Placeholder 扫描：** 无 TBD；每个改码步骤给完整插入代码 + 命令。Task 9/10 标注「类名/路径以 W2/W3a 实际产出为准」是**显式依赖说明**，非占位——接线位置（命中后/`_ready`）与调用代码均完整给出。

**3. 类型一致性核对：**
- `Vfx.spawn_burst(pos, StringName)` / `spawn_anim(pos, StringName)` / `make_trail(Color, bool)` 签名与 VFX-W1 定义一致。
- `GameFeel.shake(StringName)` / `hitstop(float)` 与 VFX-W1 一致；档位字面量 `&"light"/&"medium"/&"heavy"` 与 `SHAKE_PRESETS` 键一致。
- 新预设键 `&"blood_burst"/&"crit_spark"/&"ice_shard"/&"shock_spark"` 在 Task 1 注册、在 Task 2/3/6/9 引用，拼写一致。
- 接线锚点（`whip.attack` 命中循环、`knife_projectile` 命中处、`boomerang_projectile._ready`、`Explosion.detonate`、`lightning._spawn_impact`、`aura._setup_ring`、`orb_shield._ready`）均与本计划逐字核对过的当前脚本一致。

---

## Execution Handoff

**计划已存 `docs/superpowers/plans/2026-06-17-weapon-arsenal-vfx-w2-per-weapon.md`，两种执行方式：Subagent-Driven（推荐）/ Inline。**

> **执行前置**：先确认 **VFX-W1** 及**对应武器波次**（W1/W2/W3a/W3b）已合并；在专用分支执行。

后续可选：**VFX Wave 3**（专用着色器打磨，可选）、**W4 平衡（telemetry A/B）**。
