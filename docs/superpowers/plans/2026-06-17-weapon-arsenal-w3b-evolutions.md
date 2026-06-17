# 武器军械库重做 W3b：10 个进化质变 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **PREREQUISITE: W0 + W1 + W2 必须先合入。** 本计划在 W1/W2 重构后的武器脚本上**追加质变字段/逻辑**，并写进化 `.tres`。Reanimate/Horde 见 W3a（独立）。

**Goal:** 把军械库 10 个进化从「数值堆叠」变为**机制质变**——每个引入一条新机制规则（spec §11）：回旋斩 360°+流血+回血 / 震地冲击波+地裂 / 箭雨齐射+满血必暴 / 旋风斧环绕旋刃 / 核爆二次引爆+炼狱地火 / 炼狱回血+扩张 / 雷暴天雷 / 暴雪持续雪域 / 缚刃脱轨扑击 / 奇点坍缩引爆。

**Architecture:** 沿用「**零默认即关闭**」——质变机制做成基础武器脚本上**默认关闭的门控字段**，进化 `.tres` 注入开启；基础形态不注入即行为不变（与 W1 同理）。进化形态复用基础 `base_scene`（同一脚本，靠数据分化）。两个新增持续场实体（`SnowField`、复用 W2 的 `GravityWell` 扩展）走 `BurnField` 同款 `_physics_process` 计时套路。

**Tech Stack:** Godot 4.6.3 · GDScript · gdUnit4 · 数据驱动 + 进化卡自动注入。

## Global Constraints

- **保留既有断言字段**：现有测试锁定的进化字段必须**原样保留**，只 ADD 质变字段——thousand_edge(`cooldown 0.15`/`pierce 8`/`proj_scale 1.7`)、nuke(`cooldown 0.5`/`blast_scale 1.6`)、mega_orb(`total_orbs 8`)、thunderstorm(`chains 8`/`bolt_tint R≈0.85`)、inferno_aura(`radius 170`)、cyclone(`count 3`/`pierce 8`)、bloody_whip。
- **零默认即关闭**：新增门控字段默认 0/false；基础武器 `.tres` 不注入。
- **3 把 W2 武器获得进化**：maul→earthshatter(perk_hp)、frostbite→blizzard(perk_attack)、gravity_well→singularity(perk_speed)。给其基础 `.tres` 补 `evolution` 字典 + 建进化 `.tres`。进化卡 `evolve_<id>` 由 `_register_evolution_cards` **自动注入**（无需手写 CARDS）。
- **evolvable 数量**：W3b 后新增 earthshatter/blizzard/singularity（+ W3a 的 horde）→ 不再是 7。把 `test_weapons_new.test_all_evolvable_count_is_seven` 改为**断言原 7 把在 all_evolvable**（集合成员，对新增鲁棒）。若 W3a 已改则跳过（幂等）。
- **流血复用 burn**：回旋斩「流血 DoT」复用 W0 的 `&"burn"` kind（spec §7.1 原文「burn 式流血」）。
- **视觉占位**：质变视觉（血红刃光/地裂/天雷/雪域/幽蓝剑/坍缩内爆）留 VFX 通道；进化沿用基础占位视觉 + 既有 tint/scale 数据。
- **测试约定**：`extends GdUnitTestSuite`；`const X := preload(...)`；敌人实例化 `enemy.tscn`；调 `attack()`（经 `get_ysort` 生成）前建 `"ysort"` 组桩；分裂/随机用确定性极值或直接调方法，不依赖 RNG 种子。

**headless 命令**（PowerShell；替换 `<TEST_FILE>`）：

```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<TEST_FILE>.gd
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" --import
```

---

## File Structure

**修改脚本（追加门控质变字段/逻辑）**
- `scenes/weapons/whip/whip_weapon.gd`（Whirlwind：360°+流血+回血）
- `scenes/weapons/knife/knife_weapon.gd`（Arrow Storm：volley 齐射）
- `scenes/weapons/boomerang/boomerang_weapon.gd` + `boomerang_projectile.gd`（Cyclone：环绕旋刃）
- `scenes/weapons/explosion/explosion_weapon.gd`（Cataclysm：二次引爆）
- `scenes/weapons/lightning/lightning_weapon.gd`（Tempest：天雷）
- `scenes/weapons/orb/orb_shield.gd` + `orb_weapon.gd`（Bound Blades：脱轨扑击）
- `scenes/weapons/maul/maul_weapon.gd`（Earthshatter：冲击波+地裂）
- `scenes/weapons/frostbite/frostbite_weapon.gd`（Blizzard：召唤雪域）
- `scenes/weapons/gravity_well/gravity_well.gd`（Singularity：坍缩引爆）
- `scenes/weapons/gravity_well/gravity_well_weapon.gd`（传 collapse_damage）

**新建**
- `scenes/weapons/frostbite/snow_field.gd`（`SnowField` 持续雪域实体）
- `data/weapons/earthshatter.tres`、`blizzard.tres`、`singularity.tres`（新进化数据）
- `tests/test_weapons_w3b.gd`（10 个质变的反射 + 机制）

**修改数据**
- `data/weapons/bloody_whip.tres`、`thousand_edge.tres`、`cyclone.tres`、`nuke.tres`、`inferno_aura.tres`、`thunderstorm.tres`、`mega_orb.tres`（注入质变字段）
- `data/weapons/maul.tres`、`frostbite.tres`、`gravity_well.tres`（补 `evolution`）
- `tests/test_weapons_new.gd`（evolvable 集合成员断言，若 W3a 未改）

---

### Task 1: 回旋斩 Whirlwind（whip→bloody_whip：360° + 流血 + 回血）

**Files:** Modify `scenes/weapons/whip/whip_weapon.gd`、`data/weapons/bloody_whip.tres`；Test `tests/test_weapons_w3b.gd`（新建）。

**质变规则：** `full_circle` 全向劈（忽略锥形）+ 命中附流血(`bleed_dps`，复用 burn) + 命中回血(`lifesteal_on_hit`)。

- [ ] **Step 1: 新建 `tests/test_weapons_w3b.gd` 并写 Whirlwind 测试（先失败）**

```gdscript
extends GdUnitTestSuite
# W3b 进化质变：反射 + 机制。preload 引用脚本；敌人实例化 enemy.tscn(headless 加载 LimboAI)。

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

func _ysort_stub() -> void:
	var ys := auto_free(Node2D.new())
	add_child(ys)
	ys.add_to_group("ysort")

# 拉满基础武器并进化(apply 跳过条件，直接走效果)
func _evolve(base_id: String, evolved_id: String) -> WeaponBase:
	_ysort_stub()
	CardPool.apply({"id": base_id}, _player)
	CardPool.apply({"id": "evolve_%s" % base_id, "type": "evolution"}, _player)
	return _player.get_weapon_node(evolved_id)

# ── 回旋斩 Whirlwind ──
func test_whirlwind_reflects_quale_fields() -> void:
	var w := _evolve("whip", "bloody_whip")
	assert_object(w).is_not_null()
	assert_bool(w.get("full_circle")).is_true()
	assert_float(w.get("bleed_dps")).is_greater(0.0)
	assert_float(w.get("lifesteal_on_hit")).is_greater(0.0)

func test_whirlwind_hits_enemy_behind_player() -> void:
	var w := _evolve("whip", "bloody_whip")
	_player.global_position = Vector2.ZERO
	w._facing = Vector2.RIGHT
	var e := _tough_enemy_at(Vector2(-60, 0))   # 在身后(锥形外)，但 360° 内
	await get_tree().process_frame
	w.attack()
	assert_float(e.hp).is_less(500.0)            # 全向命中
	assert_bool(e.has_status(&"burn")).is_true() # 流血(复用 burn)
```

- [ ] **Step 2: 运行，确认失败** — Run: `<TEST_FILE>` = `test_weapons_w3b` → 红（`full_circle` 字段不存在）。

- [ ] **Step 3: 改 `scenes/weapons/whip/whip_weapon.gd`**

字段区（`double_sided` 行后）追加：

```gdscript
	var full_circle: bool = false        # 进化(回旋斩)：360° 全向劈，忽略锥形
	var bleed_dps: float = 0.0           # >0 命中附流血(复用 burn DoT)
	var lifesteal_on_hit: float = 0.0    # >0 命中回血
```

`attack()` 替换为（支持 full_circle 与流血/回血）：

```gdscript
func attack() -> void:
	var targets := enemies()
	if targets.is_empty():
		return
	var dmg: float = damage_for(damage)
	var origin: Vector2 = _player.global_position
	for e in targets:
		var pos: Vector2 = (e as Node2D).global_position
		var hit: bool
		if full_circle:
			hit = origin.distance_to(pos) <= swing_range
		else:
			hit = in_cone(pos, origin, _facing, arc_deg, swing_range)
			if not hit and double_sided:
				hit = in_cone(pos, origin, -_facing, arc_deg, swing_range)
		if hit and is_instance_valid(e):
			e.take_damage(dmg)
			if bleed_dps > 0.0 and e.has_method("apply_status"):
				e.apply_status(&"burn", bleed_dps, 2.0)
			if lifesteal_on_hit > 0.0 and _player.has_method("heal"):
				_player.heal(lifesteal_on_hit)
	_spawn_swipe(origin)
```

- [ ] **Step 4: 重写 `data/weapons/bloody_whip.tres` 的 levels**

```
levels = [{"cooldown": 0.6, "arc_deg": 170.0, "swing_range": 200.0, "full_circle": true, "bleed_dps": 8.0, "lifesteal_on_hit": 0.5, "damage": 30.0}]
```

- [ ] **Step 5: 刷新缓存 + 运行测试** — Run: `--import`，再 `test_weapons_w3b` → Whirlwind PASS。

- [ ] **Step 6: 提交**

```bash
git add scenes/weapons/whip/whip_weapon.gd data/weapons/bloody_whip.tres tests/test_weapons_w3b.gd
git commit -m "feat(evolve): 回旋斩 Whirlwind 质变(360°+流血+命中回血)"
```

---

### Task 2: 箭雨 Arrow Storm（knife→thousand_edge：齐射 + 满血必暴）

**Files:** Modify `scenes/weapons/knife/knife_weapon.gd`、`data/weapons/thousand_edge.tres`；Test `test_weapons_w3b.gd`。

**质变规则：** `volley` 发齐射（极短 CD 已有 0.15）+ 对满血目标 `crit_bonus=1.0`（必暴），`crit_range` 设极大使距离不触发、只满血触发。

- [ ] **Step 1: 追加测试（先失败）**

```gdscript
# ── 箭雨 Arrow Storm ──
func test_arrow_storm_reflects_volley() -> void:
	var w := _evolve("knife", "thousand_edge")
	assert_int(w.get("volley")).is_greater(1)
	assert_float(w.get("crit_bonus")).is_equal_approx(1.0, 0.001)

func test_arrow_storm_fires_volley_projectiles() -> void:
	var ys := auto_free(Node2D.new()); add_child(ys); ys.add_to_group("ysort")
	CardPool.apply({"id": "knife"}, _player)
	CardPool.apply({"id": "evolve_knife", "type": "evolution"}, _player)
	var w := _player.get_weapon_node("thousand_edge")
	_tough_enemy_at(_player.global_position + Vector2(100, 0))
	await get_tree().process_frame
	w.attack()
	# 齐射 5 发 → ysort 下至少 5 个投射体
	assert_int(ys.get_child_count()).is_greater_equal(5)
```

- [ ] **Step 2: 运行，确认失败** — `test_weapons_w3b` 红（`volley` 字段不存在）。

- [ ] **Step 3: 改 `scenes/weapons/knife/knife_weapon.gd`**

字段区追加：

```gdscript
	var volley: int = 0   # >0：每次齐射 volley 发(箭雨)，替代默认单发
```

`attack()` 内把 `var n: int = 1 + mod_int("extra_projectiles")` 改为：

```gdscript
	var base_count: int = volley if volley > 0 else 1
	var n: int = base_count + mod_int("extra_projectiles")
```

- [ ] **Step 4: 重写 `data/weapons/thousand_edge.tres` 的 levels**（保留 cooldown 0.15/pierce 8/proj_scale 1.7/proj_tint）

```
levels = [{"cooldown": 0.15, "pierce": 8, "proj_scale": 1.7, "proj_tint": Color(1, 0.85, 0.2, 1), "damage": 15.0, "volley": 5, "crit_bonus": 1.0, "crit_range": 99999.0, "proj_speed": 600.0}]
```

- [ ] **Step 5: 刷新缓存 + 测试** — `--import`，`test_weapons_w3b` → PASS；并跑 `test_card_pool`（`test_apply_evolve_knife` cooldown 0.15/pierce 8 不回归）。

- [ ] **Step 6: 提交**

```bash
git add scenes/weapons/knife/knife_weapon.gd data/weapons/thousand_edge.tres tests/test_weapons_w3b.gd
git commit -m "feat(evolve): 箭雨 Arrow Storm 质变(volley 齐射 + 满血必暴)"
```

---

### Task 3: 旋风斧 Cyclone（boomerang→cyclone：环绕旋刃）

**Files:** Modify `scenes/weapons/boomerang/boomerang_weapon.gd`、`boomerang_projectile.gd`、`data/weapons/cyclone.tres`；Test `test_weapons_w3b.gd`。

**质变规则：** 折返路径改为**环绕玩家旋转**（`orbit_return`），形成短时旋刃领域（不再直线归位）。

- [ ] **Step 1: 追加测试（先失败）**

```gdscript
# ── 旋风斧 Cyclone ──
const BoomerangProjScript := preload("res://scenes/weapons/boomerang/boomerang_projectile.gd")

func test_cyclone_reflects_orbit_return() -> void:
	var w := _evolve("boomerang", "cyclone")
	assert_bool(w.get("orbit_return")).is_true()
	assert_int(w.get("count")).is_equal(3)

func test_cyclone_projectile_orbits_not_homes() -> void:
	var p = auto_free(BoomerangProjScript.new())
	p.max_range = 200.0
	p.orbit_return = true
	add_child(p)
	await get_tree().process_frame   # _ready 抓 player(=本测试的 _player)
	p.global_position = _player.global_position + Vector2(80, 0)
	p._returning = true              # 进入折返(环绕)阶段
	for i in range(15):
		await get_tree().physics_frame
	# 环绕态不应归位到玩家(距离仍 > 折返阈值)
	assert_float(p.global_position.distance_to(_player.global_position)).is_greater(20.0)
```

- [ ] **Step 2: 运行，确认失败** — 红（`orbit_return` 不存在）。

- [ ] **Step 3: 改 `scenes/weapons/boomerang/boomerang_projectile.gd`**

字段区追加：

```gdscript
var orbit_return: bool = false      # 进化(旋风)：折返改环绕玩家旋转
const ORBIT_DURATION: float = 1.5
const ORBIT_ANG_SPEED: float = 6.0
var _orbit_t: float = 0.0
var _orbit_angle: float = 0.0
```

`_physics_process` 的 `else`(折返)分支替换为：

```gdscript
	else:
		if _player == null or not is_instance_valid(_player):
			queue_free()
			return
		if orbit_return:
			_orbit_t += delta
			_orbit_angle += ORBIT_ANG_SPEED * delta
			var r: float = max_range * 0.4
			global_position = _player.global_position + Vector2(cos(_orbit_angle), sin(_orbit_angle)) * r
			if _orbit_t >= ORBIT_DURATION:
				queue_free()
				return
		else:
			var to: Vector2 = _player.global_position - global_position
			if to.length() <= RETURN_THRESHOLD:
				queue_free()
				return
			global_position += to.normalized() * SPEED * delta
```

- [ ] **Step 4: 改 `scenes/weapons/boomerang/boomerang_weapon.gd`**

字段区加 `var orbit_return: bool = false`；`attack()` 内 `proj.max_range = throw_range` 之后加 `proj.orbit_return = orbit_return`。

- [ ] **Step 5: 重写 `data/weapons/cyclone.tres` 的 levels**（保留 count 3/pierce 8/throw_range 300）

```
levels = [{"cooldown": 0.7, "pierce": 8, "throw_range": 300.0, "count": 3, "orbit_return": true, "damage": 20.0}]
```

- [ ] **Step 6: 刷新缓存 + 测试** — `--import`，`test_weapons_w3b` → Cyclone PASS。

- [ ] **Step 7: 提交**

```bash
git add scenes/weapons/boomerang/boomerang_weapon.gd scenes/weapons/boomerang/boomerang_projectile.gd data/weapons/cyclone.tres tests/test_weapons_w3b.gd
git commit -m "feat(evolve): 旋风斧 Cyclone 质变(折返改环绕玩家旋刃领域)"
```

---

### Task 4: 核爆 Cataclysm（explosion→nuke：二次引爆 + 炼狱地火）

**Files:** Modify `scenes/weapons/explosion/explosion_weapon.gd`、`data/weapons/nuke.tres`；Test `test_weapons_w3b.gd`。

**质变规则：** 爆炸范围放大（`blast_radius` ×1.6）+ 更大更久炼狱地火（高 `burn_dps`/`field_dur`，复用 W1 BurnField）+ 中心**二次延迟引爆**（`secondary_count`/`secondary_delay`）。

- [ ] **Step 1: 追加测试（先失败）**

```gdscript
# ── 核爆 Cataclysm ──
func test_cataclysm_reflects_quale_fields() -> void:
	var w := _evolve("explosion", "nuke")
	assert_float(w.get("blast_radius")).is_greater(80.0)   # ×1.6
	assert_float(w.get("burn_dps")).is_greater(0.0)        # 炼狱地火
	assert_int(w.get("secondary_count")).is_greater(0)     # 二次引爆
```

- [ ] **Step 2: 运行，确认失败** — 红（`secondary_count` 不存在）。

- [ ] **Step 3: 改 `scenes/weapons/explosion/explosion_weapon.gd`**

> 前提：W1 已把 `blast_radius/burn_dps/field_dur` 加到此脚本并把生成爆炸/地火写进 `attack()`。本任务把「生成一次爆炸」抽成 helper 并加二次引爆。

字段区追加：

```gdscript
	var secondary_count: int = 0     # >0：中心追加 N 次延迟引爆(核爆)
	var secondary_delay: float = 0.3
```

把 `attack()` 里生成爆炸的那段抽成 `_spawn_explosion(center)` 并在 `attack()` 末尾追加二次引爆调度：

```gdscript
func _spawn_explosion(center: Vector2) -> void:
	var explosion := EXPLOSION_SCENE.instantiate()
	explosion.damage = damage_for(damage)
	explosion.blast_radius = blast_radius
	explosion.base_scale = blast_scale
	explosion.modulate = blast_tint
	get_ysort().add_child(explosion)
	explosion.global_position = center
	explosion.detonate()
	if burn_dps > 0.0 and field_dur > 0.0:
		var field := BURN_FIELD.new()
		field.radius = blast_radius
		field.burn_dps = burn_dps
		field.field_dur = field_dur
		get_ysort().add_child(field)
		field.global_position = center
```

`attack()` 改为（选点后调 helper + 二次引爆）：

```gdscript
func attack() -> void:
	var targets := enemies()
	if targets.is_empty():
		return
	var positions: Array[Vector2] = []
	for e in targets:
		positions.append((e as Node2D).global_position)
	var center := densest_center(positions, blast_radius)
	_spawn_explosion(center)
	for i in range(secondary_count):
		var c := center
		get_tree().create_timer(secondary_delay * float(i + 1)).timeout.connect(func() -> void: _spawn_explosion(c))
```

- [ ] **Step 4: 重写 `data/weapons/nuke.tres` 的 levels**（保留 cooldown 0.5/blast_scale 1.6/blast_tint）

```
levels = [{"cooldown": 0.5, "blast_scale": 1.6, "blast_tint": Color(1, 0.55, 0.15, 1), "damage": 40.0, "blast_radius": 128.0, "burn_dps": 14.0, "field_dur": 4.0, "secondary_count": 1, "secondary_delay": 0.3}]
```

- [ ] **Step 5: 刷新缓存 + 测试** — `--import`，`test_weapons_w3b` → PASS；`test_card_pool`（nuke cooldown 0.5/blast_scale>1 不回归）。

- [ ] **Step 6: 提交**

```bash
git add scenes/weapons/explosion/explosion_weapon.gd data/weapons/nuke.tres tests/test_weapons_w3b.gd
git commit -m "feat(evolve): 核爆 Cataclysm 质变(范围×1.6 + 炼狱地火 + 二次延迟引爆)"
```

---

### Task 5: 炼狱 Inferno（aura→inferno_aura：回血 + 扩张 + 强 burn，数据 only）

**Files:** Modify `data/weapons/inferno_aura.tres`；Test `test_weapons_w3b.gd`。

**质变规则：** 半径扩张（170 已有）+ 命中回血（`lifesteal_on_hit 0.3` 已有，基础烈焰护体无）+ 更强 burn（`burn_dps` 注入）。**W1 已给 aura 脚本加好 gated burn_dps/lifesteal_on_hit → 本任务纯数据。**

- [ ] **Step 1: 追加测试（先失败）**

```gdscript
# ── 炼狱 Inferno ──
func test_inferno_reflects_burn_and_lifesteal() -> void:
	var w := _evolve("aura", "inferno_aura")
	assert_float(w.get("burn_dps")).is_greater(0.0)
	assert_float(w.get("lifesteal_on_hit")).is_greater(0.0)
	assert_float(w.get("radius")).is_equal_approx(170.0, 0.001)
```

- [ ] **Step 2: 运行，确认失败** — 红（inferno_aura `burn_dps` 反射为默认 0）。

- [ ] **Step 3: 重写 `data/weapons/inferno_aura.tres` 的 levels**（加 burn_dps，保留 radius 170/lifesteal 0.3/cooldown 0.4）

```
levels = [{"cooldown": 0.4, "radius": 170.0, "lifesteal_on_hit": 0.3, "burn_dps": 10.0, "damage": 12.0}]
```

- [ ] **Step 4: 刷新缓存 + 测试** — `--import`，`test_weapons_w3b` → PASS；`test_weapons_new`（`test_evolve_aura` radius 170 不回归）。

- [ ] **Step 5: 提交**

```bash
git add data/weapons/inferno_aura.tres tests/test_weapons_w3b.gd
git commit -m "feat(evolve): 炼狱 Inferno 质变(强 burn + 回血; 复用 W1 aura gated 字段, 纯数据)"
```

---

### Task 6: 雷暴 Tempest（lightning→thunderstorm：天雷）

**Files:** Modify `scenes/weapons/lightning/lightning_weapon.gd`、`data/weapons/thunderstorm.tres`；Test `test_weapons_w3b.gd`。

**质变规则：** 链数大增（8 已有）+ 每次攻击额外在随机敌头顶**召唤天雷**（独立 AoE 落雷，`sky_strikes`）。

- [ ] **Step 1: 追加测试（先失败）**

```gdscript
# ── 雷暴 Tempest ──
func test_tempest_reflects_sky_strikes() -> void:
	var w := _evolve("lightning", "thunderstorm")
	assert_int(w.get("sky_strikes")).is_greater(0)
	assert_int(w.get("chains")).is_equal(8)

func test_tempest_sky_strike_damages_enemies() -> void:
	var w := _evolve("lightning", "thunderstorm")
	var e := _tough_enemy_at(Vector2(300, 300))
	await get_tree().process_frame
	w._sky_strike([e])   # 直接打这一目标头顶落雷
	assert_float(e.hp).is_less(500.0)
```

- [ ] **Step 2: 运行，确认失败** — 红（`sky_strikes` / `_sky_strike` 不存在）。

- [ ] **Step 3: 改 `scenes/weapons/lightning/lightning_weapon.gd`**

字段区追加（W1 已加 shock_dur/link_range）：

```gdscript
	var sky_strikes: int = 0      # >0：每次攻击额外召唤 N 道随机天雷
	var sky_radius: float = 70.0
	var sky_damage: float = 0.0
```

`attack()` 末尾（`_spawn_bolt(path)` 之前/之后）追加：

```gdscript
	if sky_strikes > 0 and sky_damage > 0.0:
		_sky_strike(targets)
```

新增方法：

```gdscript
# 在随机敌人头顶落 sky_strikes 道独立 AoE 落雷。
func _sky_strike(targets: Array) -> void:
	var dmg: float = damage_for(sky_damage)
	var pool: Array = targets.duplicate()
	var strikes: int = mini(sky_strikes, pool.size())
	for _i in range(strikes):
		if pool.is_empty():
			break
		var pick: int = randi() % pool.size()
		var center: Vector2 = (pool[pick] as Node2D).global_position
		pool.remove_at(pick)
		for e in enemies():
			if is_instance_valid(e) and center.distance_to((e as Node2D).global_position) <= sky_radius:
				e.take_damage(dmg)
```

- [ ] **Step 4: 重写 `data/weapons/thunderstorm.tres` 的 levels**（保留 chains 8/bolt_tint/cooldown 0.45）

```
levels = [{"cooldown": 0.45, "chains": 8, "bolt_tint": Color(0.85, 0.75, 1.0, 1.0), "damage": 22.0, "sky_strikes": 3, "sky_radius": 70.0, "sky_damage": 22.0}]
```

- [ ] **Step 5: 刷新缓存 + 测试** — `--import`，`test_weapons_w3b` → PASS；`test_weapons_new`（`test_evolve_lightning` chains 8 / `test_thunderstorm_bolt_tint` 不回归）。

- [ ] **Step 6: 提交**

```bash
git add scenes/weapons/lightning/lightning_weapon.gd data/weapons/thunderstorm.tres tests/test_weapons_w3b.gd
git commit -m "feat(evolve): 雷暴 Tempest 质变(随机敌头顶召唤独立天雷 AoE)"
```

---

### Task 7: 缚刃 Bound Blades（orb→mega_orb：脱轨扑击）

**Files:** Modify `scenes/weapons/orb/orb_shield.gd`、`orb_weapon.gd`、`data/weapons/mega_orb.tres`；Test `test_weapons_w3b.gd`。

**质变规则：** 灵体周期性**脱轨扑向最近敌**（短暂索敌冲刺后归位），从被动守卫变半主动攻击。

- [ ] **Step 1: 追加测试（先失败）**

```gdscript
# ── 缚刃 Bound Blades ──
const OrbShieldScript := preload("res://scenes/weapons/orb/orb_shield.gd")

func test_bound_blades_orbs_have_dash_enabled() -> void:
	_evolve("orb", "mega_orb")
	var found := false
	for c in _player.get_children():
		if c is OrbShield:
			found = true
			assert_bool(c.dash_enabled).is_true()
	assert_bool(found).is_true()

func test_orb_dashes_toward_enemy_when_due() -> void:
	var orb = auto_free(OrbShieldScript.new())
	orb.total_orbs = 1
	orb.dash_enabled = true
	orb.dash_interval = 0.0    # 立即可冲
	_player.add_child(orb)
	await get_tree().process_frame
	var e := _tough_enemy_at(_player.global_position + Vector2(200, 0))
	var d0 := orb.global_position.distance_to(e.global_position)
	for i in range(10):
		await get_tree().process_frame
	assert_float(orb.global_position.distance_to(e.global_position)).is_less(d0)
```

- [ ] **Step 2: 运行，确认失败** — 红（`dash_enabled` 不存在）。

- [ ] **Step 3: 改 `scenes/weapons/orb/orb_shield.gd`**

字段区追加：

```gdscript
var dash_enabled: bool = false      # 进化(缚刃)：周期脱轨扑击
var dash_interval: float = 3.0
const DASH_SPEED: float = 600.0
var _dash_t: float = 0.0
var _dashing: bool = false
var _dash_target: Node2D = null
```

`_process` 替换为（dash 状态机优先，否则默认轨道）：

```gdscript
func _process(delta: float) -> void:
	if _player == null:
		return
	if dash_enabled and _update_dash(delta):
		_check_hits()
		_tick_cooldowns(delta)
		return
	var angle := (TAU / total_orbs) * orbit_index + Time.get_ticks_msec() * 0.001 * ORBIT_SPEED
	global_position = _player.global_position + Vector2(cos(angle), sin(angle)) * orbit_radius
	_check_hits()
	_tick_cooldowns(delta)

# 返回 true 表示本帧处于脱轨冲刺(已自行定位)，false 表示走默认轨道。
func _update_dash(delta: float) -> bool:
	if not _dashing:
		_dash_t += delta
		if _dash_t < dash_interval:
			return false
		_dash_target = _nearest_enemy()
		if _dash_target == null:
			_dash_t = 0.0
			return false
		_dashing = true
	if _dash_target == null or not is_instance_valid(_dash_target):
		_dashing = false
		_dash_t = 0.0
		return false
	global_position = global_position.move_toward(_dash_target.global_position, DASH_SPEED * delta)
	if global_position.distance_to(_dash_target.global_position) <= ORB_RADIUS:
		_dashing = false
		_dash_t = 0.0
	return true

func _nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nd := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to((e as Node2D).global_position)
		if d < nd:
			nd = d
			nearest = e as Node2D
	return nearest
```

- [ ] **Step 4: 改 `scenes/weapons/orb/orb_weapon.gd`**

字段区加 `var dash_enabled: bool = false` 与 `var dash_interval: float = 3.0`；`_sync_shields` 分发循环里补：

```gdscript
		existing[i].dash_enabled = dash_enabled
		existing[i].dash_interval = dash_interval
```

- [ ] **Step 5: 重写 `data/weapons/mega_orb.tres` 的 levels**（保留 total_orbs 8）

```
levels = [{"total_orbs": 8, "damage": 8.0, "dash_enabled": true, "dash_interval": 3.0}]
```

- [ ] **Step 6: 刷新缓存 + 测试** — `--import`，`test_weapons_w3b` → PASS；`test_card_pool`（`test_apply_evolve_orb` total_orbs 8 不回归）。

- [ ] **Step 7: 提交**

```bash
git add scenes/weapons/orb/orb_shield.gd scenes/weapons/orb/orb_weapon.gd data/weapons/mega_orb.tres tests/test_weapons_w3b.gd
git commit -m "feat(evolve): 缚刃 Bound Blades 质变(灵体周期脱轨扑击)"
```

---

### Task 8: 震地 Earthshatter（maul→earthshatter，新进化）

**Files:** Modify `scenes/weapons/maul/maul_weapon.gd`、`data/weapons/maul.tres`；Create `data/weapons/earthshatter.tres`；Modify `tests/test_weapons_new.gd`（evolvable 断言，若 W3a 未改）；Test `test_weapons_w3b.gd`。

**质变规则：** 砸击后向外发射**扩张冲击波**（延迟二次命中更远一圈敌人）+ 命中处留短暂 `slow` 地裂。

- [ ] **Step 1: （若 W3a 未做）把 `tests/test_weapons_new.gd` 的 `test_all_evolvable_count_is_seven` 改为集合成员断言**

```gdscript
func test_original_seven_weapons_are_evolvable() -> void:
	var ids: Array = []
	for w in WeaponDB.all_evolvable():
		ids.append(w.id)
	for id in ["knife", "orb", "explosion", "lightning", "whip", "boomerang", "aura"]:
		assert_bool(ids.has(id)).is_true()
```
（若 W3a 已替换则跳过本步。）

- [ ] **Step 2: 向 `test_weapons_w3b.gd` 追加 Earthshatter 测试（先失败）**

```gdscript
# ── 震地 Earthshatter ──
func test_evolve_maul_grants_earthshatter() -> void:
	var w := _evolve("maul", "earthshatter")
	assert_bool(_player.has_weapon("earthshatter")).is_true()
	assert_float(w.get("shockwave_radius")).is_greater(0.0)

func test_earthshatter_shockwave_hits_far_ring_and_slows() -> void:
	var w := _evolve("maul", "earthshatter")
	_player.global_position = Vector2.ZERO
	# 落在初始 radius(170) 外、shockwave_radius(280) 内
	var e := _tough_enemy_at(Vector2(240, 0))
	await get_tree().process_frame
	w._apply_shockwave(Vector2.ZERO)
	assert_float(e.hp).is_less(500.0)
	assert_bool(e.has_status(&"slow")).is_true()
```

- [ ] **Step 3: 运行，确认失败** — 红（`earthshatter missing` / `_apply_shockwave` 不存在）。

- [ ] **Step 4: 改 `scenes/weapons/maul/maul_weapon.gd`**

字段区追加：

```gdscript
	var shockwave_radius: float = 0.0     # >0：延迟扩张冲击波到此半径
	var shockwave_damage: float = 0.0
	var shockwave_slow: float = 0.0       # 地裂减速乘子(0=不减速)
	var shockwave_slow_dur: float = 0.0
	const SHOCKWAVE_DELAY: float = 0.25
```

`attack()` 末尾（`for` 之后）追加调度：

```gdscript
	if shockwave_radius > 0.0:
		var c := origin
		get_tree().create_timer(SHOCKWAVE_DELAY).timeout.connect(func() -> void: _apply_shockwave(c))
```

新增方法：

```gdscript
# 冲击波：命中初始 radius 之外、shockwave_radius 之内的一圈敌人 + 地裂减速。
func _apply_shockwave(origin: Vector2) -> void:
	var dmg: float = damage_for(shockwave_damage)
	for e in enemies():
		if not is_instance_valid(e):
			continue
		var d: float = origin.distance_to((e as Node2D).global_position)
		if d > radius and d <= shockwave_radius:
			e.take_damage(dmg)
			if shockwave_slow > 0.0 and e.has_method("apply_status"):
				e.apply_status(&"slow", shockwave_slow, shockwave_slow_dur)
```

- [ ] **Step 5: 给 `data/weapons/maul.tres` 加 evolution**

```
evolution = {"requires_perk": "perk_hp", "requires_perk_stacks": 3, "evolved_id": "earthshatter"}
```

- [ ] **Step 6: 创建 `data/weapons/earthshatter.tres`**

```
[gd_resource type="Resource" script_class="WeaponData" load_steps=4 format=3]

[ext_resource type="Script" path="res://data/weapons/weapon_data.gd" id="1_data"]
[ext_resource type="PackedScene" path="res://scenes/weapons/maul/maul_weapon.tscn" id="2_scene"]
[ext_resource type="Texture2D" path="res://assets/sprites/kenney/items/dagger.png" id="3_icon"]

[resource]
script = ExtResource("1_data")
id = "earthshatter"
display_name = "震地"
icon = ExtResource("3_icon")
base_scene = ExtResource("2_scene")
max_level = 1
levels = [{"cooldown": 1.6, "radius": 170.0, "damage": 72.0, "knockback": 300.0, "stun_dur": 0.6, "shockwave_radius": 280.0, "shockwave_damage": 40.0, "shockwave_slow": 0.5, "shockwave_slow_dur": 1.5}]
evolution = {}
```

- [ ] **Step 7: 刷新缓存 + 测试** — `--import`，`test_weapons_w3b` → PASS；`test_weapons_new`（集合成员断言 PASS）。

- [ ] **Step 8: 提交**

```bash
git add scenes/weapons/maul/maul_weapon.gd data/weapons/maul.tres data/weapons/earthshatter.tres tests/test_weapons_new.gd tests/test_weapons_w3b.gd
git commit -m "feat(evolve): 震地 Earthshatter 新进化(扩张冲击波 + 地裂减速)"
```

---

### Task 9: 暴雪 Blizzard（frostbite→blizzard，新进化 + 雪域实体）

**Files:** Modify `scenes/weapons/frostbite/frostbite_weapon.gd`、`data/weapons/frostbite.tres`；Create `scenes/weapons/frostbite/snow_field.gd`、`data/weapons/blizzard.tres`；Test `test_weapons_w3b.gd`。

**质变规则：** 改为区域内**持续降雪领域**（`field_dur` 内反复 slow + 周期冻结），脱离单次施放。

- [ ] **Step 1: 追加测试（先失败）**

```gdscript
# ── 暴雪 Blizzard ──
const SnowFieldScript := preload("res://scenes/weapons/frostbite/snow_field.gd")

func test_evolve_frostbite_grants_blizzard() -> void:
	var w := _evolve("frostbite", "blizzard")
	assert_bool(_player.has_weapon("blizzard")).is_true()
	assert_float(w.get("field_dur")).is_greater(0.0)

func test_snow_field_slows_enemy_in_radius() -> void:
	var f = auto_free(SnowFieldScript.new())
	f.radius = 110.0
	f.slow_factor = 0.5
	f.field_dur = 5.0
	f.freeze_dur = 0.6
	add_child(f)
	f.global_position = Vector2.ZERO
	var e := _tough_enemy_at(Vector2(40, 0))
	for i in range(20):
		await get_tree().physics_frame
	assert_bool(e.has_status(&"slow") or e.has_status(&"freeze")).is_true()
```

- [ ] **Step 2: 运行，确认失败** — 红（`Could not preload .../snow_field.gd`）。

- [ ] **Step 3: 创建 `scenes/weapons/frostbite/snow_field.gd`**

```gdscript
# scenes/weapons/frostbite/snow_field.gd
# 暴雪雪域：存活 field_dur，每 TICK 刷新 slow、每秒一次 freeze。DoT/控制经 W0 StatusComponent 结算。
class_name SnowField
extends Node2D

const TICK: float = 0.25
const FREEZE_TICK: float = 1.0

var radius: float = 110.0
var slow_factor: float = 0.5
var freeze_dur: float = 0.6
var field_dur: float = 3.0
var _age: float = 0.0
var _slow_accum: float = 0.0
var _freeze_accum: float = 0.0

func _physics_process(delta: float) -> void:
	_age += delta
	_slow_accum += delta
	_freeze_accum += delta
	if _slow_accum >= TICK:
		_slow_accum -= TICK
		_apply(false)
	if _freeze_accum >= FREEZE_TICK:
		_freeze_accum -= FREEZE_TICK
		_apply(true)
	if _age >= field_dur:
		queue_free()

func _apply(freeze: bool) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if global_position.distance_to((e as Node2D).global_position) > radius or not e.has_method("apply_status"):
			continue
		if freeze:
			e.apply_status(&"freeze", 0.0, freeze_dur)
		else:
			e.apply_status(&"slow", slow_factor, TICK * 2.0)
```

- [ ] **Step 4: 改 `scenes/weapons/frostbite/frostbite_weapon.gd`**

顶部加 preload，字段区加 `field_dur`：

```gdscript
const SNOW_FIELD := preload("res://scenes/weapons/frostbite/snow_field.gd")
```
```gdscript
	var field_dur: float = 0.0   # >0：进化(暴雪)生成持续雪域
```

`attack()` 末尾（`for` 之后、`center` 已算出）追加：

```gdscript
	if field_dur > 0.0:
		var field := SNOW_FIELD.new()
		field.radius = area
		field.slow_factor = slow_factor
		field.freeze_dur = freeze_dur
		field.field_dur = field_dur
		get_ysort().add_child(field)
		field.global_position = center
```

- [ ] **Step 5: 给 `data/weapons/frostbite.tres` 加 evolution**

```
evolution = {"requires_perk": "perk_attack", "requires_perk_stacks": 3, "evolved_id": "blizzard"}
```

- [ ] **Step 6: 创建 `data/weapons/blizzard.tres`**

```
[gd_resource type="Resource" script_class="WeaponData" load_steps=4 format=3]

[ext_resource type="Script" path="res://data/weapons/weapon_data.gd" id="1_data"]
[ext_resource type="PackedScene" path="res://scenes/weapons/frostbite/frostbite_weapon.tscn" id="2_scene"]
[ext_resource type="Texture2D" path="res://assets/sprites/kenney/items/gem.png" id="3_icon"]

[resource]
script = ExtResource("1_data")
id = "blizzard"
display_name = "暴雪"
icon = ExtResource("3_icon")
base_scene = ExtResource("2_scene")
max_level = 1
levels = [{"cooldown": 2.0, "damage": 20.0, "area": 130.0, "slow_factor": 0.45, "slow_dur": 2.0, "freeze_dur": 1.0, "field_dur": 3.0}]
evolution = {}
```

- [ ] **Step 7: 刷新缓存 + 测试** — `--import`，`test_weapons_w3b` → PASS。

- [ ] **Step 8: 提交**

```bash
git add scenes/weapons/frostbite/frostbite_weapon.gd scenes/weapons/frostbite/snow_field.gd data/weapons/frostbite.tres data/weapons/blizzard.tres tests/test_weapons_w3b.gd
git commit -m "feat(evolve): 暴雪 Blizzard 新进化(持续雪域 SnowField, 反复减速 + 周期冻结)"
```

---

### Task 10: 奇点 Singularity（gravity_well→singularity，新进化）

**Files:** Modify `scenes/weapons/gravity_well/gravity_well.gd`、`gravity_well_weapon.gd`、`data/weapons/gravity_well.tres`；Create `data/weapons/singularity.tres`；Test `test_weapons_w3b.gd`。

**质变规则：** 拉拽更强 + `field_dur` 结束时**坍缩引爆**（聚拢的敌群被一次高伤 AoE 收割）。

- [ ] **Step 1: 追加测试（先失败）**

```gdscript
# ── 奇点 Singularity ──
const GravityWellScript2 := preload("res://scenes/weapons/gravity_well/gravity_well.gd")

func test_evolve_gravity_well_grants_singularity() -> void:
	var w := _evolve("gravity_well", "singularity")
	assert_bool(_player.has_weapon("singularity")).is_true()
	assert_float(w.get("collapse_damage")).is_greater(0.0)

func test_singularity_collapse_damages_clustered_enemies() -> void:
	var well = auto_free(GravityWellScript2.new())
	well.radius = 140.0
	well.field_dur = 0.05
	well.pull_strength = 0.0
	well.tick_damage = 0.0
	well.collapse_damage = 60.0
	add_child(well)
	well.global_position = Vector2.ZERO
	var e := _tough_enemy_at(Vector2(50, 0))
	for i in range(10):
		await get_tree().physics_frame   # _age 超过 field_dur → 坍缩并 queue_free
	assert_float(e.hp).is_less(500.0)
```

- [ ] **Step 2: 运行，确认失败** — 红（`singularity missing` / `collapse_damage` 不存在）。

- [ ] **Step 3: 改 `scenes/weapons/gravity_well/gravity_well.gd`**

字段区加 `var collapse_damage: float = 0.0`。`_physics_process` 的过期分支替换：

```gdscript
	if _age >= field_dur:
		_collapse()
		queue_free()
```

新增方法：

```gdscript
# 坍缩引爆：场到期时对半径内敌人一次高伤(奇点)。
func _collapse() -> void:
	if collapse_damage <= 0.0:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and global_position.distance_to((e as Node2D).global_position) <= radius:
			e.take_damage(collapse_damage)
```

- [ ] **Step 4: 改 `scenes/weapons/gravity_well/gravity_well_weapon.gd`**

字段区加 `var collapse_damage: float = 0.0`；`attack()` 内创建 well 后加 `well.collapse_damage = damage_for(collapse_damage)`。

- [ ] **Step 5: 给 `data/weapons/gravity_well.tres` 加 evolution**

```
evolution = {"requires_perk": "perk_speed", "requires_perk_stacks": 3, "evolved_id": "singularity"}
```

- [ ] **Step 6: 创建 `data/weapons/singularity.tres`**

```
[gd_resource type="Resource" script_class="WeaponData" load_steps=4 format=3]

[ext_resource type="Script" path="res://data/weapons/weapon_data.gd" id="1_data"]
[ext_resource type="PackedScene" path="res://scenes/weapons/gravity_well/gravity_well_weapon.tscn" id="2_scene"]
[ext_resource type="Texture2D" path="res://assets/sprites/kenney/particles/orb_ring.png" id="3_icon"]

[resource]
script = ExtResource("1_data")
id = "singularity"
display_name = "奇点"
icon = ExtResource("3_icon")
base_scene = ExtResource("2_scene")
max_level = 1
levels = [{"cooldown": 3.0, "field_dur": 3.0, "radius": 180.0, "pull_strength": 240.0, "tick_damage": 5.0, "collapse_damage": 60.0}]
evolution = {}
```

- [ ] **Step 7: 刷新缓存 + 测试** — `--import`，`test_weapons_w3b` → PASS。

- [ ] **Step 8: 提交**

```bash
git add scenes/weapons/gravity_well/gravity_well.gd scenes/weapons/gravity_well/gravity_well_weapon.gd data/weapons/gravity_well.tres data/weapons/singularity.tres tests/test_weapons_w3b.gd
git commit -m "feat(evolve): 奇点 Singularity 新进化(强拉拽 + 到期坍缩引爆 AoE)"
```

---

### Task 11: W3b 全量回归 + headless 烟雾

**Files:** 无新增（验证关）。

- [ ] **Step 1: 跑全测试套件**

Run:
```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: 全绿。重点不回归：`test_card_pool`（thousand_edge 0.15/8、nuke 0.5、mega_orb 8、进化辨识度视觉）、`test_weapons_new`（thunderstorm chains 8 / bolt_tint、inferno radius 170、集合成员 evolvable）。

- [ ] **Step 2: 资源导入 + 解析检查**

Run: `--import`
Expected: 无 `SCRIPT ERROR`/`Parse Error`；3 个新进化 `.tres` + 7 个改写进化 `.tres` 无未知字段告警。

- [ ] **Step 3: 一局确定性烟雾**

Run:
```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --fixed-fps 60 --path "D:\Workspace\GAME\game_0_vsl" --quit-after 1800
```
Expected: 正常退出；无进化相关 `Invalid call`/`Nonexistent function`/计时器或场实体报错。

- [ ] **Step 4: 不提交（纯验证）。** 任一步红 → 回对应 Task 修复重跑。

---

## Self-Review（对照 spec 复核）

**1. Spec 覆盖（W3b = §7 的 10 个进化质变；Horde 在 W3a）**
- §7.1 回旋斩(360°+流血+回血)→ T1 ✓；§7.3 箭雨(齐射+满血必暴)→ T2 ✓；§7.4 旋风斧(环绕旋刃)→ T3 ✓；§7.5 核爆(二爆+地火)→ T4 ✓；§7.6 炼狱(回血+扩张+强 burn)→ T5 ✓；§7.7 雷暴(天雷)→ T6 ✓；§7.9 缚刃(脱轨扑击)→ T7 ✓；§7.2 震地(冲击波+地裂)→ T8 ✓；§7.8 暴雪(雪域)→ T9 ✓；§7.11 奇点(坍缩引爆)→ T10 ✓。
- §11「进化均为质变」：10 条新机制规则全部落实（每条对应一个 Task 的门控逻辑）。✓
- §8 对接：3 把 W2 武器补 evolution → 进化卡自动注入；evolvable 集合断言鲁棒化。✓

**范围外**：质变视觉（血红刃/地裂/天雷/雪域/幽蓝剑/坍缩内爆）→ VFX 通道。W3a 的 Reanimate/Horde 独立。

**2. 占位符扫描**：无 TODO/TBD；每步完整代码 + 命令 + 预期。✓

**3. 进化不回归核验**：所有任务**只 ADD 质变字段、保留既有被断言字段**（thousand_edge cd0.15/pierce8/proj_scale1.7、nuke cd0.5/blast_scale1.6、mega_orb total_orbs8、thunderstorm chains8/bolt_tint、inferno radius170、cyclone count3/pierce8）。✓

**4. 零默认即关闭核验**：full_circle/bleed_dps/lifesteal_on_hit/volley/orbit_return/secondary_count/sky_strikes/dash_enabled/shockwave_radius/field_dur(frostbite)/collapse_damage 默认 0/false → 基础武器不注入即原行为不变。✓

**已知风险/注记**
- Earthshatter/Cataclysm 用 `get_tree().create_timer` 做延迟；质变伤害逻辑抽成可直接调用的方法(`_apply_shockwave`/`_spawn_explosion`)供单测，绕开计时器异步。
- 缚刃脱轨用 `_process`(渲染帧)——与 OrbShield 现状一致(轨道也在 `_process`)；如需确定性可后续迁 `_physics_process`。
- 雪域/坍缩等场实体测试用手动帧推进或直接调方法，不依赖玩家/帧序。
- 进化形态复用基础脚本 + 数据分化；新进化 `.tres` 的 `base_scene` 指向对应基础武器 `.tscn`。

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-06-17-weapon-arsenal-w3b-evolutions.md`.**

**整套军械库设计计划已完成**：W0(底座) · W1(重构 7) · W2(新增 3) · W3a(Reanimate AI 盟友) · W3b(10 进化质变)。依赖链：**W0 → W1 → {W3b}**，**W0 → W2 → {W3b}**，**W0 → W3a**（W3b 依赖 W1+W2 的重构脚本；W3a 仅依赖 W0）。

接下来可选：
1. **开始执行**（推荐从 W0 起，Subagent-Driven 每任务新 subagent + 审查）。
2. **写 VFX 通道计划**（所有推迟的视觉/状态可读性 FX + Kenney 素材导入）。
3. **写 W4 平衡计划**（bot/telemetry A/B 跑数值回填，`--fixed-fps 60`）。
4. **先评审整套计划**。

**告诉我选哪个。**
