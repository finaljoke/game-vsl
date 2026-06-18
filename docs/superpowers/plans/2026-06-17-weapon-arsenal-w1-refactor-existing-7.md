# 武器军械库重做 W1：重构现有 7 把基础武器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **PREREQUISITE: W0 必须先合入。** 本计划消费 W0 的 `Enemy.apply_status / is_stunned`、`WeaponBase.damage_for(base, can_crit, crit_bonus)`。见 `docs/superpowers/plans/2026-06-17-weapon-arsenal-w0-foundation.md`。

**Goal:** 把现有 7 把基础武器（whip/knife/boomerang/explosion/aura/lightning/orb）按设计 spec §7 重塑为 TES 身份（斩/长弓/回旋斧/火球/烈焰护体/连锁闪电/缚灵），重调数值 schema 并接入 W0 的状态/暴击原语——**id 保持英文不变**，存量卡条件与 effect_registry 零破坏。

**Architecture:** 每把武器一个垂直切片：改 `.tres`（display_name + levels 新 schema + 进化 perk 门槛）→ 改 weapon 脚本（声明新字段供反射 + 调 W0 原语）→ 改 `CardPool.CARDS` 的展示文案 → 测试。**所有新机制走「零默认即关闭」**：新增字段默认 0/中性，基础武器经 levels 注入开启，**未改写的进化 `.tres`（bloody_whip/thousand_edge/cyclone/thunderstorm/inferno_aura/nuke/mega_orb）因不注入这些键而保持原行为**——进化质变留给 W3。

**Tech Stack:** Godot 4.6.3 · GDScript · gdUnit4 · 数据驱动（`WeaponData.levels` 反射注入 + `WeaponDB` 自动入库 + `CardPool` 卡条件 DSL）。

## Global Constraints

逐条来自 spec §2、§5、§7、§8、§9，每个任务隐含遵守：

- **id 保留英文不变**（`whip/knife/boomerang/explosion/aura/lightning/orb`），仅改 `WeaponData.display_name` 与 `CARDS` 文案。`CardPool._register_weapon_effects` 的硬编码 id 列表、卡条件 DSL（`no:`/`upgrade:`/`evolve_ready:`/`has_any:`）**零改动**。
- **进化即质变留给 W3**：W1 **不改写任何进化 `.tres`**，也不实现 360°/地火/天雷等质变。W1 只调整基础武器的 `evolution.requires_perk`（perk 门槛路由，见各任务），不碰进化形态本身。
- **零默认即关闭**：每个新增的机制字段（`burn_dps/shock_dur/field_dur/crit_bonus` 等）默认值 = 关闭（0），脚本仅在该值 > 0 时触发新行为。这是进化 `.tres` 不回归的保证。
- **schema 字段必须在脚本声明**：`.tres` 的 `levels` 字典键若脚本未声明为同名 `var`，`WeaponBase.apply_level` 会 `push_warning` 并忽略（静默失效防线）。每任务新增字段都先在脚本声明。
- **`range` 是 GDScript 内置函数**：spec §7.1 schema 写 `range`，实现沿用现有字段名 `swing_range` 避免遮蔽内置 `range()`。
- **数值为草案基线**：最终由 bot/telemetry A/B 回填（确定性 `--fixed-fps 60`）；W1 按 spec §7 表照搬。
- **视觉/状态 FX 不在 W1**（见下「范围说明」）。
- **测试约定**：`extends GdUnitTestSuite`；`const X := preload("res://…")` 引用脚本；场景测试 `load(...).instantiate()` + `add_child` + `await get_tree().process_frame`；敌人测试实例化 `enemy.tscn`（headless 加载 LimboAI）。

**headless 测试命令**（PowerShell；各任务 Run 步骤替换 `<TEST_FILE>`）：

```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<TEST_FILE>.gd
```

---

## 范围说明：视觉/状态 FX 推迟到独立 VFX 通道

spec §10.2 把「逐把验证视觉框架与手感」放进 W1，但**本计划只做机制/数值/原语接入/卡文案（可 TDD 的垂直切片）**，把**新视觉**（程序化粒子、着色器、状态可读性指示 = 燃烧橙红脉冲/冻结冰晶/感电星旋、新 Kenney FX 素材导入）整体推迟到 W1 之后的 **VFX 通道**。理由：

- 视觉无法单测，验收靠跑游戏/截图——与机制的 TDD 节律不同；混在一起会拖垮可评审性。
- 现有占位视觉（whip slash / lightning bolt / explosion sprite / aura ring / orb 等）**继续可用**，重构后武器仍「看得过去」。
- 燃烧 DoT 经 `take_damage` 已复用 GameFeel 命中闪白，提供基本反馈。

> 想把视觉并入 W1 就说，会按 spec §6.2 资源映射 + §7 逐条视觉配方补一个 VFX 任务组（含 Kenney 素材 headless `--import`）。

---

## File Structure

**修改 `.tres`（7 个基础武器数据，重写 display_name/levels，whip 另改 requires_perk）**
- `data/weapons/whip.tres`、`knife.tres`、`boomerang.tres`、`explosion.tres`、`aura.tres`、`lightning.tres`、`orb.tres`

**修改脚本（声明新字段 + 接 W0 原语；保留进化用的既有字段）**
- `scenes/weapons/knife/knife_weapon.gd` + `knife_projectile.gd`（暴击 + 弹速）
- `scenes/weapons/explosion/explosion_weapon.gd` + `explosion.gd`（blast_radius 数据驱动 + 生成燃烧地火）
- `scenes/weapons/aura/aura_weapon.gd`（命中附 burn）
- `scenes/weapons/lightning/lightning_weapon.gd`（链尾附 stun + link_range 数据驱动）
- `scenes/weapons/orb/orb_weapon.gd` + `orb_shield.gd`（orbit_radius/hit_cooldown 数据驱动）
- `scenes/weapons/whip/whip_weapon.gd`、`boomerang/boomerang_weapon.gd`：**脚本无需改**（机制已就位，纯数据/文案）

**新建**
- `scenes/weapons/explosion/burn_field.gd`（`BurnField`：火球落点的持续燃烧地火实体）
- `tests/test_weapons_w1.gd`（W1 新机制：长弓暴击口径纯函数 + 烈焰/闪电状态附着 + 缚灵数据驱动反射）
- `tests/test_burn_field.gd`（地火实体集成）

**修改测试（既有断言因数值/schema 变更需更新）**
- `tests/test_weapons_new.gd`（whip Lv1 arc 120 → 100）
- `tests/test_card_pool.gd`（knife Lv3 cooldown 0.3 → 0.5）
- `autoloads/card_pool.gd`（`CARDS` 的 7 把武器卡 name/desc 文案改名）

## Interfaces（W1 消费 W0 / 产出供 W3）

```gdscript
# 消费 W0：
Enemy.apply_status(&"burn"|&"stun", magnitude, duration)   # 火球/烈焰=burn, 闪电=stun
Enemy.is_stunned()                                         # （间接，经 W0 BT atom）
WeaponBase.damage_for(base, can_crit := true, crit_bonus)  # 长弓距离/满血暴击

# W1 产出（纯函数，可单测；W3 进化沿用同字段）：
KnifeWeapon.longbow_crit_bonus(dist, crit_range, full_hp, crit_bonus) -> float   # static
BurnField（radius/burn_dps/field_dur；每 0.25s 对半径内敌 apply_status(&"burn")）
```

---

### Task 1: 斩 Cleave（⟳ whip，纯数据 + 改名）

**Files:**
- Modify: `data/weapons/whip.tres`
- Modify: `autoloads/card_pool.gd`（CARDS 文案）
- Test: `tests/test_weapons_new.gd`（更新 arc 断言）

**Interfaces:** Consumes: 无（whip 脚本的 facing 弧劈机制已就位）。Produces: 无新接口。

**机制说明：** 现有 `WhipWeapon` 已实现「跟随 `_facing` 的扇形 `in_cone` 命中」——正是 Cleave 的签名。本任务只重调数值（高频小范围）、改名、并把进化门槛改到 `perk_attack`（spec §7.1）。

- [x] **Step 1: 更新 `tests/test_weapons_new.gd` 的 whip 断言（先失败）**

把 `test_grant_whip_reflects_level1_arc`（约第 95–98 行）的期望由 120 改为 100：

```gdscript
func test_grant_whip_reflects_level1_arc() -> void:
	CardPool.apply({"id": "whip"}, _player)
	var node := _player.get_weapon_node("whip")
	assert_float(node.get("arc_deg")).is_equal_approx(100.0, 0.001)   # 斩 Lv1 = 100（原 120）
```

- [x] **Step 2: 运行，确认失败**

Run: `<TEST_FILE>` = `test_weapons_new`
Expected: 红——`test_grant_whip_reflects_level1_arc` 期望 100 实得 120（.tres 仍旧值）。

- [x] **Step 3: 重写 `data/weapons/whip.tres`**

替换 `display_name` / `levels` / `evolution` 三行（其余 ext_resource 不动）：

```
display_name = "斩"
...
levels = [{"cooldown": 0.7, "arc_deg": 100.0, "swing_range": 110.0, "damage": 22.0}, {"cooldown": 0.6, "arc_deg": 110.0, "swing_range": 120.0, "damage": 24.0}, {"cooldown": 0.5, "arc_deg": 120.0, "swing_range": 130.0, "damage": 26.0}]
evolution = {"requires_perk": "perk_attack", "requires_perk_stacks": 3, "evolved_id": "bloody_whip"}
```

- [x] **Step 4: 改 `autoloads/card_pool.gd` 的 whip 卡文案**

```gdscript
	{ "id": "whip",        "name": "斩",           "desc": "朝移动方向快速弧劈，高频近身",  "type": "weapon",  "condition": "no:whip"       },
```
并把 `whip_2` / `whip_3` 的 name 前缀改为「斩」：

```gdscript
	{ "id": "whip_2",      "name": "斩 Lv.2",      "desc": "弧更宽，冷却↓",             "type": "upgrade", "condition": "upgrade:whip:1"      },
	{ "id": "whip_3",      "name": "斩 Lv.3",      "desc": "弧更宽，冷却↓",             "type": "upgrade", "condition": "upgrade:whip:2"      },
```

- [x] **Step 5: 运行，确认通过**

Run: `<TEST_FILE>` = `test_weapons_new`
Expected: PASS。

- [x] **Step 6: 提交**

```bash
git add data/weapons/whip.tres autoloads/card_pool.gd tests/test_weapons_new.gd
git commit -m "feat(weapon): 斩 Cleave 重塑 whip(高频小范围弧劈数值 + 进化门槛 perk_attack)"
```

---

### Task 2: 回旋斧 Throwing Axe（⟳ boomerang，纯数据 + 改名）

**Files:**
- Modify: `data/weapons/boomerang.tres`
- Modify: `autoloads/card_pool.gd`
- Test: `tests/test_weapons_w1.gd`（新建，加反射断言）

**Interfaces:** Consumes: 无（折返双段机制保留）。Produces: 无。

- [x] **Step 1: 新建 `tests/test_weapons_w1.gd` 并写回旋斧反射断言（先失败）**

```gdscript
extends GdUnitTestSuite
# W1 新机制单测：纯函数 + 数据驱动反射 + 状态附着。preload 引用脚本。

const KnifeScript := preload("res://scenes/weapons/knife/knife_weapon.gd")
const EnemyScene := preload("res://scenes/enemies/enemy.tscn")

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

# 在玩家附近 dist 处生成一只敌人(入 "enemies" 组)，返回之。
func _spawn_enemy_near(dist: float) -> Enemy:
	var e: Enemy = EnemyScene.instantiate()
	e.behavior = "chase"
	add_child(e)
	e.add_to_group("enemies")
	e.global_position = _player.global_position + Vector2(dist, 0)
	return auto_free(e)

# ── 回旋斧(boomerang) Lv1 冷却数据 ──
func test_throwing_axe_lv1_cooldown() -> void:
	CardPool.apply({"id": "boomerang"}, _player)
	assert_float(_player.get_weapon_node("boomerang").cooldown).is_equal_approx(1.5, 0.001)
```

- [x] **Step 2: 运行，确认失败**

Run: `<TEST_FILE>` = `test_weapons_w1`
Expected: 红——boomerang Lv1 cooldown 实得 1.6（.tres 旧值）。

- [x] **Step 3: 重写 `data/weapons/boomerang.tres`**

```
display_name = "回旋斧"
...
levels = [{"cooldown": 1.5, "pierce": 3, "throw_range": 220.0, "damage": 20.0}, {"cooldown": 1.2, "pierce": 4, "throw_range": 250.0, "damage": 20.0}, {"cooldown": 1.0, "pierce": 5, "throw_range": 280.0, "damage": 20.0}]
evolution = {"requires_perk": "perk_speed", "requires_perk_stacks": 3, "evolved_id": "cyclone"}
```

- [x] **Step 4: 改 `card_pool.gd` 的 boomerang 卡文案**

```gdscript
	{ "id": "boomerang",   "name": "回旋斧",       "desc": "抛出后折返，去回各结算穿透",  "type": "weapon",  "condition": "no:boomerang"  },
	{ "id": "boomerang_2", "name": "回旋斧 Lv.2",  "desc": "穿透 +1，射程↑",            "type": "upgrade", "condition": "upgrade:boomerang:1" },
	{ "id": "boomerang_3", "name": "回旋斧 Lv.3",  "desc": "穿透 +1，射程↑",            "type": "upgrade", "condition": "upgrade:boomerang:2" },
```

- [x] **Step 5: 运行，确认通过** — Run: `test_weapons_w1` → PASS。

- [x] **Step 6: 提交**

```bash
git add data/weapons/boomerang.tres autoloads/card_pool.gd tests/test_weapons_w1.gd
git commit -m "feat(weapon): 回旋斧 Throwing Axe 重塑 boomerang(数值 + 改名)"
```

---

### Task 3: 缚灵 Spectral Wisps（⟳ orb，orbit_radius/hit_cooldown 数据驱动）

**Files:**
- Modify: `scenes/weapons/orb/orb_weapon.gd`、`scenes/weapons/orb/orb_shield.gd`
- Modify: `data/weapons/orb.tres`
- Modify: `autoloads/card_pool.gd`
- Test: `tests/test_weapons_w1.gd`

**Interfaces:** Consumes: 无。Produces: `OrbShield.orbit_radius/hit_cooldown` 成为实例可注入字段（W3 缚刃脱轨沿用）。

**说明：** 把 `OrbShield` 的 `ORBIT_RADIUS`/`HIT_COOLDOWN` 常量改为可注入 `var`（默认值 = 原常量，保证 mega_orb 等不注入者行为不变），由 `OrbWeapon` 按 levels 注入。

- [x] **Step 1: 向 `tests/test_weapons_w1.gd` 追加反射断言（先失败）**

```gdscript
func test_spectral_wisps_data_drives_orbit_radius() -> void:
	CardPool.apply({"id": "orb"}, _player)
	for c in _player.get_children():
		if c is OrbShield:
			assert_float(c.orbit_radius).is_equal_approx(60.0, 0.001)  # 缚灵 Lv1=60
```

- [x] **Step 2: 运行，确认失败**

Run: `<TEST_FILE>` = `test_weapons_w1`
Expected: 红——`OrbShield` 无 `orbit_radius` 字段（仍是 const）。

- [x] **Step 3: 改 `scenes/weapons/orb/orb_shield.gd`（常量→可注入 var）**

把第 5–7 行的 `ORBIT_RADIUS`/`HIT_COOLDOWN` 常量保留为默认来源，新增同义 `var`，并在 `_process`/`_check_hits` 改用 var：

```gdscript
const DEFAULT_ORBIT_RADIUS: float = 60.0
const ORBIT_SPEED: float = 2.0
const DEFAULT_HIT_COOLDOWN: float = 0.5
const ORB_RADIUS: float = 14.0

var orbit_index: int = 0
var total_orbs: int = 2
var orbit_radius: float = DEFAULT_ORBIT_RADIUS   # 由 OrbWeapon 注入(缚灵数据驱动)
var hit_cooldown: float = DEFAULT_HIT_COOLDOWN   # 由 OrbWeapon 注入
var damage: float = 8.0
var _player: Node2D = null
var _hit_cooldowns: Dictionary = {}
```

`_process` 内 `ORBIT_RADIUS` → `orbit_radius`：

```gdscript
	var angle := (TAU / total_orbs) * orbit_index + Time.get_ticks_msec() * 0.001 * ORBIT_SPEED
	global_position = _player.global_position + Vector2(cos(angle), sin(angle)) * orbit_radius
```

`_check_hits` 内 `HIT_COOLDOWN` → `hit_cooldown`：

```gdscript
	var cd := hit_cooldown / maxf(player.attack_speed_mult, 0.01)
```

- [x] **Step 4: 改 `scenes/weapons/orb/orb_weapon.gd`（声明字段 + 注入到护盾球）**

声明新字段（供反射）：

```gdscript
var total_orbs: int = 0  # 由 WeaponData.levels 注入
var damage: float = 8.0
var orbit_radius: float = 60.0      # 缚灵数据驱动(注入给每个 OrbShield)
var hit_cooldown: float = 0.5
```

`_sync_shields` 分发处补两行：

```gdscript
	for i in range(existing.size()):
		existing[i].total_orbs = total_orbs
		existing[i].orbit_index = i
		existing[i].damage = damage
		existing[i].orbit_radius = orbit_radius
		existing[i].hit_cooldown = hit_cooldown
```

- [x] **Step 5: 重写 `data/weapons/orb.tres`**

```
display_name = "缚灵"
...
levels = [{"total_orbs": 2, "damage": 8.0, "orbit_radius": 60.0}, {"total_orbs": 3, "damage": 8.0, "orbit_radius": 64.0}, {"total_orbs": 4, "damage": 9.0, "orbit_radius": 68.0}]
evolution = {"requires_perk": "perk_hp", "requires_perk_stacks": 3, "evolved_id": "mega_orb"}
```

- [x] **Step 6: 改 `card_pool.gd` 的 orb 卡文案**

```gdscript
	{ "id": "orb",         "name": "缚灵",      "desc": "环绕自身的守卫灵，接触伤害",   "type": "weapon",  "condition": "no:orb"        },
	{ "id": "orb_2",       "name": "缚灵 Lv.2",  "desc": "灵体数量 2 → 3",            "type": "upgrade", "condition": "upgrade:orb:1"       },
	{ "id": "orb_3",       "name": "缚灵 Lv.3",  "desc": "灵体数量 3 → 4",            "type": "upgrade", "condition": "upgrade:orb:2"       },
```

- [x] **Step 7: 运行，确认通过**

Run: `<TEST_FILE>` = `test_weapons_w1`，再 `test_card_pool`（确认 `test_apply_orb_3` total_orbs=4 不回归）
Expected: 均 PASS。

- [x] **Step 8: 提交**

```bash
git add scenes/weapons/orb/orb_weapon.gd scenes/weapons/orb/orb_shield.gd data/weapons/orb.tres autoloads/card_pool.gd tests/test_weapons_w1.gd
git commit -m "feat(weapon): 缚灵 Spectral Wisps 重塑 orb(orbit_radius/hit_cooldown 数据驱动 + 改名)"
```

---

### Task 4: 烈焰护体 Flame Cloak（⟳ aura，命中附 burn）

**Files:**
- Modify: `scenes/weapons/aura/aura_weapon.gd`
- Modify: `data/weapons/aura.tres`
- Modify: `autoloads/card_pool.gd`
- Test: `tests/test_weapons_w1.gd`

**Interfaces:** Consumes: `Enemy.apply_status(&"burn", burn_dps, dur)`（W0）。Produces: 无。

- [x] **Step 1: 向 `tests/test_weapons_w1.gd` 追加 burn 附着断言（先失败）**

```gdscript
func test_flame_cloak_applies_burn_to_enemy_in_radius() -> void:
	CardPool.apply({"id": "aura"}, _player)
	var aura := _player.get_weapon_node("aura")
	var e := _spawn_enemy_near(30.0)   # 在 Lv1 radius=90 内
	await get_tree().process_frame
	aura.attack()
	assert_bool(e.has_status(&"burn")).is_true()

func test_flame_cloak_no_burn_when_dps_zero() -> void:
	# 进化 inferno_aura 不注入 burn_dps → 默认 0 → 不附 burn（W1 不改进化行为）
	CardPool.apply({"id": "aura"}, _player)
	var aura := _player.get_weapon_node("aura")
	aura.burn_dps = 0.0
	var e := _spawn_enemy_near(30.0)
	await get_tree().process_frame
	aura.attack()
	assert_bool(e.has_status(&"burn")).is_false()
```

- [x] **Step 2: 运行，确认失败**

Run: `<TEST_FILE>` = `test_weapons_w1`
Expected: 红——`AuraWeapon` 无 `burn_dps` 字段。

- [x] **Step 3: 改 `scenes/weapons/aura/aura_weapon.gd`**

声明字段（第 8–10 行附近）+ 常量：

```gdscript
const BURN_REFRESH: float = 0.5   # burn 状态刷新时长(高频脉冲持续覆盖)

# 由 WeaponData.levels 反射注入
var damage: float = 12.0
var radius: float = 90.0
var burn_dps: float = 0.0           # >0 时命中附燃烧 DoT(基础注入；进化不注入→0→不附)
var lifesteal_on_hit: float = 0.0   # 进化形态(炼狱)：每命中一敌回血
```

`attack()` 命中处补 burn（仅 `burn_dps > 0`）：

```gdscript
func attack() -> void:
	var dmg: float = damage_for(damage)
	var origin: Vector2 = _player.global_position
	for e in enemies():
		if not is_instance_valid(e):
			continue
		if origin.distance_to((e as Node2D).global_position) <= radius:
			e.take_damage(dmg)
			if burn_dps > 0.0 and e.has_method("apply_status"):
				e.apply_status(&"burn", burn_dps, BURN_REFRESH)
			if lifesteal_on_hit > 0.0 and _player.has_method("heal"):
				_player.heal(lifesteal_on_hit)
```

- [x] **Step 4: 重写 `data/weapons/aura.tres`**

```
display_name = "烈焰护体"
...
levels = [{"cooldown": 0.8, "radius": 90.0, "damage": 12.0, "burn_dps": 4.0}, {"cooldown": 0.65, "radius": 110.0, "damage": 13.0, "burn_dps": 5.0}, {"cooldown": 0.5, "radius": 130.0, "damage": 14.0, "burn_dps": 6.0}]
evolution = {"requires_perk": "perk_hp", "requires_perk_stacks": 3, "evolved_id": "inferno_aura"}
```

- [x] **Step 5: 改 `card_pool.gd` 的 aura 卡文案**

```gdscript
	{ "id": "aura",        "name": "烈焰护体",     "desc": "贴身燃烧光环，持续灼烧",      "type": "weapon",  "condition": "no:aura"       },
	{ "id": "aura_2",      "name": "烈焰护体 Lv.2", "desc": "范围 +20，灼烧↑",          "type": "upgrade", "condition": "upgrade:aura:1"      },
	{ "id": "aura_3",      "name": "烈焰护体 Lv.3", "desc": "范围 +20，灼烧↑",          "type": "upgrade", "condition": "upgrade:aura:2"      },
```

- [x] **Step 6: 运行，确认通过**

Run: `<TEST_FILE>` = `test_weapons_w1`，再 `test_weapons_new`（确认 `test_grant_aura_reflects_level1_radius`=90 不回归）
Expected: 均 PASS。

- [x] **Step 7: 提交**

```bash
git add scenes/weapons/aura/aura_weapon.gd data/weapons/aura.tres autoloads/card_pool.gd tests/test_weapons_w1.gd
git commit -m "feat(weapon): 烈焰护体 Flame Cloak 重塑 aura(命中附 burn + 改名)"
```

---

### Task 5: 连锁闪电 Chain Lightning（⟳ lightning，链尾附 stun + link_range 数据驱动）

**Files:**
- Modify: `scenes/weapons/lightning/lightning_weapon.gd`
- Modify: `data/weapons/lightning.tres`
- Modify: `autoloads/card_pool.gd`
- Test: `tests/test_weapons_w1.gd`

**Interfaces:** Consumes: `Enemy.apply_status(&"stun", 0, shock_dur)`（W0）。Produces: 无。

**说明：** `LINK_RANGE` 常量改为可注入 `var link_range`（默认 160 = 原常量，thunderstorm 不注入即不变）；命中路径后对**链尾**敌人附 stun（仅 `shock_dur > 0`）。

- [x] **Step 1: 向 `tests/test_weapons_w1.gd` 追加 stun 断言（先失败）**

```gdscript
func test_chain_lightning_stuns_tail_enemy() -> void:
	CardPool.apply({"id": "lightning"}, _player)
	var lw := _player.get_weapon_node("lightning")
	var e := _spawn_enemy_near(50.0)   # 唯一敌 → 既是链首也是链尾
	await get_tree().process_frame
	lw.attack()
	assert_bool(e.is_stunned()).is_true()

func test_chain_lightning_no_stun_when_dur_zero() -> void:
	CardPool.apply({"id": "lightning"}, _player)
	var lw := _player.get_weapon_node("lightning")
	lw.shock_dur = 0.0   # 进化 thunderstorm 不注入 → 不附 stun
	var e := _spawn_enemy_near(50.0)
	await get_tree().process_frame
	lw.attack()
	assert_bool(e.is_stunned()).is_false()
```

- [x] **Step 2: 运行，确认失败**

Run: `<TEST_FILE>` = `test_weapons_w1`
Expected: 红——`LightningWeapon` 无 `shock_dur` 字段。

- [x] **Step 3: 改 `scenes/weapons/lightning/lightning_weapon.gd`**

把 `const LINK_RANGE` 改为默认常量 + 可注入 var，新增 `shock_dur`：

```gdscript
const DEFAULT_LINK_RANGE: float = 160.0   # 连锁跳跃最大间距(默认)
```
字段区（第 12–15 行附近）：

```gdscript
# 由 WeaponData.levels 反射注入
var damage: float = 22.0
var chains: int = 3
var shock_dur: float = 0.0                       # >0 时链尾附感电硬直(基础注入；进化不注入→0)
var link_range: float = DEFAULT_LINK_RANGE       # 数据驱动连锁间距
var bolt_tint: Color = Color(0.62, 0.86, 1.0)
```

`attack()`：`LINK_RANGE` → `link_range`，并在命中后对链尾附 stun：

```gdscript
func attack() -> void:
	var targets := enemies()
	if targets.is_empty():
		return
	var positions: Array = []
	for e in targets:
		positions.append((e as Node2D).global_position)
	var idx: Array = chain_targets(_player.global_position, positions, chains, link_range)
	if idx.is_empty():
		return
	var dmg: float = damage_for(damage)
	var path: Array = [_player.global_position]
	for i in idx:
		var enemy := targets[i]
		if is_instance_valid(enemy):
			path.append((enemy as Node2D).global_position)
			enemy.take_damage(dmg)
	# 链尾感电硬直(spec §7.7)：仅 shock_dur>0 时触发，对链上最后一个仍存活的敌人
	if shock_dur > 0.0:
		var tail := targets[idx[idx.size() - 1]]
		if is_instance_valid(tail) and tail.has_method("apply_status"):
			tail.apply_status(&"stun", 0.0, shock_dur)
	_spawn_bolt(path)
```

- [x] **Step 4: 重写 `data/weapons/lightning.tres`**

```
display_name = "连锁闪电"
...
levels = [{"cooldown": 1.2, "chains": 3, "damage": 22.0, "shock_dur": 0.2}, {"cooldown": 0.9, "chains": 4, "damage": 22.0, "shock_dur": 0.25}, {"cooldown": 0.7, "chains": 5, "damage": 22.0, "shock_dur": 0.3}]
evolution = {"requires_perk": "perk_attack", "requires_perk_stacks": 3, "evolved_id": "thunderstorm"}
```

- [x] **Step 5: 改 `card_pool.gd` 的 lightning 卡文案**

```gdscript
	{ "id": "lightning",   "name": "连锁闪电",     "desc": "向最近敌劈雷并连锁，附感电硬直", "type": "weapon",  "condition": "no:lightning"  },
	{ "id": "lightning_2", "name": "连锁闪电 Lv.2", "desc": "连锁数 3 → 4，冷却↓",       "type": "upgrade", "condition": "upgrade:lightning:1" },
	{ "id": "lightning_3", "name": "连锁闪电 Lv.3", "desc": "连锁数 4 → 5，冷却↓",       "type": "upgrade", "condition": "upgrade:lightning:2" },
```

- [x] **Step 6: 运行，确认通过**

Run: `<TEST_FILE>` = `test_weapons_w1`，再 `test_weapons_new`（确认 `test_grant_lightning_reflects_level1_chains`=3、`test_evolve_lightning`=8 不回归）
Expected: 均 PASS。

- [x] **Step 7: 提交**

```bash
git add scenes/weapons/lightning/lightning_weapon.gd data/weapons/lightning.tres autoloads/card_pool.gd tests/test_weapons_w1.gd
git commit -m "feat(weapon): 连锁闪电 Chain Lightning 重塑 lightning(链尾附 stun + link_range 数据驱动)"
```

---

### Task 6: 长弓 Longbow（⟳ knife，距离/满血暴击 + 弹速）

**Files:**
- Modify: `scenes/weapons/knife/knife_weapon.gd`、`scenes/weapons/knife/knife_projectile.gd`
- Modify: `data/weapons/knife.tres`
- Modify: `autoloads/card_pool.gd`
- Test: `tests/test_weapons_w1.gd`、`tests/test_card_pool.gd`（更新 Lv3 冷却断言）

**Interfaces:** Consumes: `WeaponBase.damage_for(base, true, crit_bonus)`（W0 暴击）。Produces: `KnifeWeapon.longbow_crit_bonus(dist, crit_range, full_hp, crit_bonus) -> float`（static, 纯函数）。

**说明：** 新增 `crit_range/crit_bonus/proj_speed` 字段（默认 `crit_bonus=0`→不暴击，保证 thousand_edge 不回归）。`attack()` 按主目标的距离/满血计算 `crit_bonus`，经 `damage_for(.., true, bonus)` 烘焙暴击进弹体伤害。弹速由 `proj_speed` 注入（projectile 的 `SPEED` 常量改为默认值）。

- [x] **Step 1: 向 `tests/test_weapons_w1.gd` 追加暴击纯函数 + 反射断言（先失败）**

```gdscript
# ── 长弓距离/满血暴击口径(纯函数)──
func test_longbow_crit_bonus_far_target() -> void:
	# dist 300 > crit_range 260 → 给 bonus
	assert_float(KnifeScript.longbow_crit_bonus(300.0, 260.0, false, 0.25)).is_equal_approx(0.25, 0.001)

func test_longbow_crit_bonus_full_hp_target() -> void:
	# 近距但满血 → 给 bonus
	assert_float(KnifeScript.longbow_crit_bonus(100.0, 260.0, true, 0.25)).is_equal_approx(0.25, 0.001)

func test_longbow_crit_bonus_near_and_hurt_no_bonus() -> void:
	# 近距且非满血 → 不给
	assert_float(KnifeScript.longbow_crit_bonus(100.0, 260.0, false, 0.25)).is_equal(0.0)

func test_longbow_zero_bonus_field_never_crits() -> void:
	# 进化 thousand_edge crit_bonus 默认 0 → 任何情况返回 0
	assert_float(KnifeScript.longbow_crit_bonus(999.0, 260.0, true, 0.0)).is_equal(0.0)

func test_longbow_reflects_crit_fields() -> void:
	CardPool.apply({"id": "knife"}, _player)
	var node := _player.get_weapon_node("knife")
	assert_float(node.get("crit_range")).is_equal_approx(260.0, 0.001)
	assert_float(node.get("crit_bonus")).is_equal_approx(0.25, 0.001)
	assert_float(node.get("proj_speed")).is_greater(400.0)
```

- [x] **Step 2: 运行，确认失败**

Run: `<TEST_FILE>` = `test_weapons_w1`
Expected: 红——`longbow_crit_bonus` 静态方法不存在 / `crit_range` 字段不存在。

- [x] **Step 3: 改 `scenes/weapons/knife/knife_weapon.gd`**

字段区（第 8–12 行）声明新字段（保留进化用的 proj_scale/proj_tint）：

```gdscript
# 基础伤害：由 WeaponData.levels[].damage 反射注入
var damage: float = 18.0
var pierce: int = 2
var crit_range: float = 99999.0   # 目标距离 > 此值触发暴击加成(默认极大=不触发)
var crit_bonus: float = 0.0       # >0 时附距离/满血暴击率加成(基础注入；进化不注入→0→不暴)
var proj_speed: float = 400.0     # 弹速(长弓更快；默认=原 SPEED)
# 进化视觉(反射注入)：基础不指定 → 默认无变化
var proj_scale: float = 1.0
var proj_tint: Color = Color.WHITE
```

`attack()` 计算暴击加成并烘焙进弹体伤害 + 注入弹速：

```gdscript
func attack() -> void:
	var target := get_nearest_enemy()
	if target == null:
		return
	var base_dir := _player.global_position.direction_to(target.global_position)
	# 距离/满血暴击：按主目标判定，应用到本次齐射所有弹
	var dist := _player.global_position.distance_to(target.global_position)
	var full_hp: bool = ("hp" in target) and ("MAX_HP" in target) and target.hp >= target.MAX_HP
	var applied_bonus := longbow_crit_bonus(dist, crit_range, full_hp, crit_bonus)
	# E3 质变：global_pierce 加穿透；extra_projectiles 多发小角度扇形
	var eff_pierce: int = pierce + mod_int("global_pierce")
	var n: int = 1 + mod_int("extra_projectiles")
	var spread := deg_to_rad(12.0)
	for i in range(n):
		var dir := base_dir
		if n > 1:
			dir = base_dir.rotated((float(i) - float(n - 1) * 0.5) * spread)
		var projectile := PROJECTILE_SCENE.instantiate()
		projectile.damage = damage_for(damage, true, applied_bonus)
		projectile.pierce = eff_pierce
		projectile.speed = proj_speed
		get_ysort().add_child(projectile)
		projectile.global_position = _player.global_position
		projectile.rotation = dir.angle() + PI / 2
		projectile.scale *= proj_scale
		projectile.modulate = proj_tint
		projectile.direction = dir

# 纯函数(便于单测)：目标距离 > crit_range 或满血 → 返回 crit_bonus，否则 0。
# crit_bonus 为 0(进化默认)时恒返回 0 → 配合 player.crit_chance=0 永不暴击。
static func longbow_crit_bonus(dist: float, crit_range: float, full_hp: bool, crit_bonus: float) -> float:
	if dist > crit_range or full_hp:
		return crit_bonus
	return 0.0
```

> 注：原代码先设 `direction` 再设 `rotation`；此处把 `direction` 移到末尾不影响（projectile 在 `_physics_process` 才读 direction）。

- [x] **Step 4: 改 `scenes/weapons/knife/knife_projectile.gd`（弹速可注入）**

```gdscript
const SPEED: float = 400.0   # 默认弹速
const LIFETIME: float = 3.0

var damage: float = 0.0
var direction: Vector2 = Vector2.RIGHT
var pierce: int = 1
var speed: float = SPEED      # 由 KnifeWeapon 注入(长弓更快)
```

`_physics_process` 用 `speed`：

```gdscript
	global_position += direction * speed * delta
```

- [x] **Step 5: 重写 `data/weapons/knife.tres`**

```
display_name = "长弓"
...
levels = [{"cooldown": 0.9, "pierce": 2, "damage": 18.0, "crit_range": 260.0, "crit_bonus": 0.25, "proj_speed": 520.0}, {"cooldown": 0.7, "pierce": 3, "damage": 18.0, "crit_range": 260.0, "crit_bonus": 0.30, "proj_speed": 520.0}, {"cooldown": 0.5, "pierce": 4, "damage": 18.0, "crit_range": 240.0, "crit_bonus": 0.35, "proj_speed": 560.0}]
evolution = {"requires_perk": "perk_attack", "requires_perk_stacks": 3, "evolved_id": "thousand_edge"}
```

- [x] **Step 6: 更新 `tests/test_card_pool.gd` 的 knife Lv3 冷却断言**

`test_apply_knife_3_sets_level_cooldown_and_pierce`（约第 199–207 行）把 cooldown 期望 0.3 → 0.5（pierce 4 不变）：

```gdscript
func test_apply_knife_3_sets_level_cooldown_and_pierce() -> void:
	CardPool.apply({"id": "knife"}, _player)
	CardPool.apply({"id": "knife_2"}, _player)
	CardPool.apply({"id": "knife_3"}, _player)
	assert_int(_player.get_weapon_level("knife")).is_equal(3)
	for child in _player.get_children():
		if child is KnifeWeapon:
			assert_float(child.cooldown).is_equal_approx(0.5, 0.001)   # 长弓 Lv3=0.5(原 0.3)
			assert_int(child.pierce).is_equal(4)
```

- [x] **Step 7: 改 `card_pool.gd` 的 knife 卡文案**

```gdscript
	{ "id": "knife",       "name": "长弓",      "desc": "瞄准最近敌射出穿透箭，远距暴击", "type": "weapon",  "condition": "no:knife"      },
	{ "id": "knife_2",     "name": "长弓 Lv.2",    "desc": "冷却 0.9s → 0.7s，穿透↑",   "type": "upgrade", "condition": "upgrade:knife:1"     },
	{ "id": "knife_3",     "name": "长弓 Lv.3",    "desc": "冷却 0.7s → 0.5s，穿透 +1",  "type": "upgrade", "condition": "upgrade:knife:2"     },
```

- [x] **Step 8: 运行，确认通过**

Run: `<TEST_FILE>` = `test_weapons_w1`，再 `test_card_pool`（含 `test_apply_knife_sets_default_pierce`=2、evolve thousand_edge cooldown 0.15/pierce 8 不回归）
Expected: 均 PASS。

- [x] **Step 9: 提交**

```bash
git add scenes/weapons/knife/knife_weapon.gd scenes/weapons/knife/knife_projectile.gd data/weapons/knife.tres autoloads/card_pool.gd tests/test_weapons_w1.gd tests/test_card_pool.gd
git commit -m "feat(weapon): 长弓 Longbow 重塑 knife(距离/满血暴击 + 弹速数据驱动)"
```

---

### Task 7: 火球 Fireball（⟳ explosion，blast_radius 数据驱动 + 燃烧地火）

**Files:**
- Modify: `scenes/weapons/explosion/explosion_weapon.gd`、`scenes/weapons/explosion/explosion.gd`
- Create: `scenes/weapons/explosion/burn_field.gd`
- Modify: `data/weapons/explosion.tres`
- Modify: `autoloads/card_pool.gd`
- Test: `tests/test_burn_field.gd`（新建）、`tests/test_weapons_w1.gd`

**Interfaces:** Consumes: `Enemy.apply_status(&"burn", burn_dps, dur)`（W0）。Produces: `BurnField`（radius/burn_dps/field_dur）。

**说明：** `Explosion.RADIUS` 常量→可注入 `blast_radius`（默认 80 = 原值，nuke 不注入即不变）。爆炸后，若 `burn_dps>0 且 field_dur>0`，在落点生成 `BurnField` 持续地火（每 0.25s 对半径内敌附 burn）。nuke 不注入 burn_dps/field_dur → 默认 0 → 不生成地火（W1 不改进化）。

- [x] **Step 1: 新建 `tests/test_burn_field.gd`（先失败）**

```gdscript
extends GdUnitTestSuite
# 燃烧地火实体集成验证(实例化 enemy.tscn → 依赖 LimboAI headless 加载)。

const BurnFieldScript := preload("res://scenes/weapons/explosion/burn_field.gd")
const EnemyScene := preload("res://scenes/enemies/enemy.tscn")

func _enemy_at(pos: Vector2) -> Enemy:
	var e: Enemy = EnemyScene.instantiate()
	e.behavior = "chase"
	add_child(e)
	e.add_to_group("enemies")
	e.global_position = pos
	return auto_free(e)

func _field(radius: float, dps: float, dur: float) -> Node2D:
	var f = BurnFieldScript.new()
	f.radius = radius
	f.burn_dps = dps
	f.field_dur = dur
	add_child(f)
	f.global_position = Vector2.ZERO
	return auto_free(f)

func test_burn_field_applies_burn_to_enemy_in_radius() -> void:
	var f := _field(80.0, 8.0, 2.0)
	var e := _enemy_at(Vector2(40, 0))   # 半径内
	for i in range(20):
		await get_tree().physics_frame
	assert_bool(e.has_status(&"burn")).is_true()

func test_burn_field_ignores_enemy_out_of_radius() -> void:
	var f := _field(80.0, 8.0, 2.0)
	var e := _enemy_at(Vector2(300, 0))  # 半径外
	for i in range(20):
		await get_tree().physics_frame
	assert_bool(e.has_status(&"burn")).is_false()

func test_burn_field_expires_after_field_dur() -> void:
	var f := _field(80.0, 8.0, 0.2)
	for i in range(30):                  # ~0.5s > 0.2s
		await get_tree().physics_frame
	assert_bool(is_instance_valid(f)).is_false()
```

- [x] **Step 2: 运行，确认失败**

Run: `<TEST_FILE>` = `test_burn_field`
Expected: 红——`Could not preload resource "res://scenes/weapons/explosion/burn_field.gd"`。

- [x] **Step 3: 创建 `scenes/weapons/explosion/burn_field.gd`**

```gdscript
# scenes/weapons/explosion/burn_field.gd
# 火球落点的持续燃烧地火：存活 field_dur 秒，每 TICK 对半径内敌人刷新 burn 状态。
# 实际 DoT 伤害由 Enemy 的 StatusComponent(W0)结算；本实体只负责"持续附着"。
class_name BurnField
extends Node2D

const TICK: float = 0.25

var radius: float = 80.0
var burn_dps: float = 6.0
var field_dur: float = 2.0
var _age: float = 0.0
var _tick_accum: float = 0.0

func _physics_process(delta: float) -> void:
	_age += delta
	_tick_accum += delta
	while _tick_accum >= TICK:
		_tick_accum -= TICK
		_apply_burn()
	if _age >= field_dur:
		queue_free()

func _apply_burn() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if global_position.distance_to((e as Node2D).global_position) <= radius \
				and e.has_method("apply_status"):
			# 刷新时长 = TICK*2，覆盖到下一拍；敌人离场后 burn 自然过期
			e.apply_status(&"burn", burn_dps, TICK * 2.0)
```

- [x] **Step 4: 运行 `test_burn_field`，确认通过** — Run: `test_burn_field` → PASS。

- [x] **Step 5: 改 `scenes/weapons/explosion/explosion.gd`（blast_radius 可注入）**

```gdscript
class_name Explosion
extends Node2D

const DEFAULT_RADIUS: float = 80.0   # 默认命中半径(nuke 等不注入者沿用)
const LIFETIME: float = 0.35

var damage: float = 0.0
var blast_radius: float = DEFAULT_RADIUS   # 由 ExplosionWeapon 注入(火球数据驱动)
var base_scale: float = 1.0
var _age: float = 0.0
```

`detonate()` 用 `blast_radius`：

```gdscript
func detonate() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to((enemy as Node2D).global_position) <= blast_radius:
			enemy.take_damage(damage)
```

- [x] **Step 6: 改 `scenes/weapons/explosion/explosion_weapon.gd`（声明字段 + 注入半径 + 生成地火）**

字段区（第 8–11 行）声明新字段（保留进化用的 blast_scale/blast_tint）：

```gdscript
const BURN_FIELD = preload("res://scenes/weapons/explosion/burn_field.gd")

var damage: float = 40.0
var blast_radius: float = 80.0   # 命中半径(数据驱动；默认=Explosion.DEFAULT_RADIUS)
var burn_dps: float = 0.0        # >0 且 field_dur>0 时落点留地火(基础注入；进化不注入→0)
var field_dur: float = 0.0
# 进化视觉(反射注入)
var blast_scale: float = 1.0
var blast_tint: Color = Color.WHITE
```

`attack()`：用 `blast_radius` 选点/注入，并生成地火：

```gdscript
func attack() -> void:
	var targets := enemies()
	if targets.is_empty():
		return
	var positions: Array[Vector2] = []
	for e in targets:
		positions.append((e as Node2D).global_position)
	var center := densest_center(positions, blast_radius)
	var explosion := EXPLOSION_SCENE.instantiate()
	explosion.damage = damage_for(damage)
	explosion.blast_radius = blast_radius
	explosion.base_scale = blast_scale
	explosion.modulate = blast_tint
	get_ysort().add_child(explosion)
	explosion.global_position = center
	explosion.detonate()
	# 火球地火(spec §7.5)：仅基础注入 burn_dps/field_dur 时生成；nuke 不注入→跳过
	if burn_dps > 0.0 and field_dur > 0.0:
		var field := BURN_FIELD.new()
		field.radius = blast_radius
		field.burn_dps = burn_dps
		field.field_dur = field_dur
		get_ysort().add_child(field)
		field.global_position = center
```

> 注：删去了对 `EXPLOSION_SCRIPT.RADIUS` 的引用（改用数据字段 `blast_radius`）。`EXPLOSION_SCRIPT` const 可保留也可删；保留无害。

- [x] **Step 7: 重写 `data/weapons/explosion.tres`**

```
display_name = "火球"
...
levels = [{"cooldown": 2.6, "damage": 40.0, "blast_radius": 80.0, "burn_dps": 6.0, "field_dur": 2.0}, {"cooldown": 1.6, "damage": 42.0, "blast_radius": 90.0, "burn_dps": 8.0, "field_dur": 2.5}, {"cooldown": 1.0, "damage": 44.0, "blast_radius": 100.0, "burn_dps": 10.0, "field_dur": 3.0}]
evolution = {"requires_perk": "perk_damage", "requires_perk_stacks": 3, "evolved_id": "nuke"}
```

- [x] **Step 8: 向 `tests/test_weapons_w1.gd` 追加火球反射断言**

```gdscript
func test_fireball_reflects_burn_field_data() -> void:
	CardPool.apply({"id": "explosion"}, _player)
	var node := _player.get_weapon_node("explosion")
	assert_float(node.get("blast_radius")).is_equal_approx(80.0, 0.001)
	assert_float(node.get("burn_dps")).is_equal_approx(6.0, 0.001)
	assert_float(node.get("field_dur")).is_equal_approx(2.0, 0.001)
```

- [x] **Step 9: 改 `card_pool.gd` 的 explosion 卡文案**

```gdscript
	{ "id": "explosion",   "name": "火球",      "desc": "投向最密集敌群的范围爆炸 + 地火",  "type": "weapon",  "condition": "no:explosion"  },
	{ "id": "explosion_2", "name": "火球 Lv.2",    "desc": "冷却 2.6s → 1.6s，地火↑",  "type": "upgrade", "condition": "upgrade:explosion:1" },
	{ "id": "explosion_3", "name": "火球 Lv.3",    "desc": "冷却 1.6s → 1.0s，地火↑",  "type": "upgrade", "condition": "upgrade:explosion:2" },
```

- [x] **Step 10: 运行，确认通过**

Run: `<TEST_FILE>` = `test_weapons_w1`、`test_burn_field`，再 `test_card_pool`（确认 `test_apply_explosion_3` cooldown=1.0、`test_evolve_explosion`→nuke cooldown 0.5/blast_scale>1 不回归）
Expected: 均 PASS。

- [x] **Step 11: 提交**

```bash
git add scenes/weapons/explosion/explosion_weapon.gd scenes/weapons/explosion/explosion.gd scenes/weapons/explosion/burn_field.gd data/weapons/explosion.tres autoloads/card_pool.gd tests/test_weapons_w1.gd tests/test_burn_field.gd
git commit -m "feat(weapon): 火球 Fireball 重塑 explosion(blast_radius 数据驱动 + 燃烧地火 BurnField)"
```

---

### Task 8: W1 全量回归 + headless 烟雾

**Files:** 无新增（验证关）。

- [x] **Step 1: 跑全测试套件**

Run:
```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: 全绿。重点确认无回归：`test_weapons_new`（7 把入库/反射/进化辨识度）、`test_card_pool`（升级/进化/槽位/synergy）、W0 套件。

- [x] **Step 2: 资源导入 + 解析检查**

Run:
```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" --import
```
Expected: 无 `SCRIPT ERROR` / `Parse Error`；7 个改写的 `.tres` 无「未知字段」`push_warning`（说明 levels 键都已在脚本声明）。

- [x] **Step 3: 一局确定性烟雾**

Run:
```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --fixed-fps 60 --path "D:\Workspace\GAME\game_0_vsl" --quit-after 1800
```
Expected: 正常退出；日志无武器相关 `Invalid call` / `Nonexistent function`（apply_status/damage_for 调用正确）。

- [x] **Step 4: 不提交（纯验证）。** 任一步红 → 回对应 Task 修复重跑。

---

## Self-Review（对照 spec 复核）

**1. Spec 覆盖（W1 = §7 的 7 把 ⟳ 重构）**
- §7.1 斩 Cleave（whip，facing 弧劈、高频小范围）→ Task 1。✓
- §7.3 长弓 Longbow（knife，穿透 + 距离/满血暴击）→ Task 6。✓
- §7.4 回旋斧 Throwing Axe（boomerang，折返双段保留）→ Task 2。✓
- §7.5 火球 Fireball（explosion，AoE + 地面燃烧）→ Task 7。✓
- §7.6 烈焰护体 Flame Cloak（aura，命中附 burn）→ Task 4。✓
- §7.7 连锁闪电 Chain Lightning（lightning，链 + 感电硬直）→ Task 5。✓
- §7.9 缚灵 Spectral Wisps（orb，环绕守卫数据驱动）→ Task 3。✓
- §8.1 id 保留英文、仅改 display_name；effect_registry/卡条件零破坏 → 全任务遵守（CARDS 仅改文案，`_register_weapon_effects` 不动）。✓
- §8 共享原语接入面（weapon_base.damage_for / enemy.apply_status）→ Task 4/5/6/7。✓

**范围外（已在顶部声明）**
- 视觉/状态可读性 FX → 推迟到 VFX 通道。⚠
- §7.2 碎 Maul、§7.8 霜噬 Frostbite、§7.11 引力井（★ 新增）→ W2。
- 全部进化质变（Whirlwind/Cataclysm/Tempest/Inferno/Cyclone/Bound Blades/Arrow Storm 等）→ W3。本轮进化 `.tres` 不改，靠「零默认即关闭」保持原行为。

**2. 占位符扫描**：无 TODO/TBD；每步含完整代码 + 确切命令 + 预期。✓

**3. 类型/命名一致性**：新字段 `burn_dps/shock_dur/link_range/blast_radius/field_dur/crit_range/crit_bonus/proj_speed/orbit_radius/hit_cooldown` 在脚本声明、`.tres` levels、反射测试间一致；状态 kind 用 W0 的 `&"burn"/&"stun"`；`BurnField` 字段 radius/burn_dps/field_dur 在脚本与测试一致。✓

**4. 进化不回归核验**（关键设计）：
- bloody_whip（whip 进化）：字段 arc_deg/swing_range/double_sided/damage 仍在 WhipWeapon → 不变。✓
- thousand_edge（knife）：不注入 crit_bonus → 默认 0 → `longbow_crit_bonus` 恒 0 → 配合 `player.crit_chance=0` 永不暴；proj_speed 默认 400。✓
- nuke（explosion）：不注入 burn_dps/field_dur → 0 → 不生成地火；blast_radius 默认 80 = 原 RADIUS。✓
- inferno_aura（aura）：不注入 burn_dps → 0 → 不附 burn（沿用原伤害 + lifesteal）。✓
- thunderstorm（lightning）：不注入 shock_dur → 0 → 不附 stun；bolt_tint 仍注入；link_range 默认 160。✓
- mega_orb（orb）：不注入 orbit_radius/hit_cooldown → 默认 60/0.5 = 原常量。✓
- cyclone（boomerang）：纯数据，字段不变。✓

**已知风险/注记**
- 全部敌人/地火集成测试依赖 LimboAI headless 加载（同 W0 前提）。长弓暴击口径已由纯函数 `longbow_crit_bonus` + W0 `damage_for` 双重覆盖，不依赖场景。
- 烈焰/连锁/地火的状态附着测试用「先 apply 后立即断言」，避免跨帧过期带来的脆性。

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-06-17-weapon-arsenal-w1-refactor-existing-7.md`.**

W0 与 W1 计划均已就绪。建议执行顺序：**先实现 W0（底座）→ 再 W1（7 把重构）**，因 W1 消费 W0 的 `apply_status`/`damage_for` 暴击重载。

接下来可选：
1. **开始执行 W0**（Subagent-Driven 推荐 / Inline）。
2. **继续写 W2 计划**（新增 3 把：碎 Maul / 霜噬 Frostbite / 引力井 Gravity Well）。
3. **继续写 W3 计划**（亡者召唤 RoamingMinion + 全部进化质变）。
4. **先评审 W0/W1 两份计划**（如视觉是否并入 W1、§4.3 是否回 W0）。

**告诉我选哪个。**
