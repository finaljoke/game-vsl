# 武器军械库重做 VFX-W1：视效底座（资产 + Vfx 工厂 + 打击感 API + 状态指示器）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立全武器/全状态共享的视效底座——把 Kenney FX 素材导入仓库、新增 `Vfx` 自动加载（粒子爆发 / 序列帧 / 状态指示器的工厂 + 预设注册表）、给 `GameFeel` 补可被武器调用的公开「打击感」API（按 light/medium/heavy 震屏 + 公开 hitstop），并把 W0 状态系统的「视觉」列（燃烧/减速/冻结/硬直指示器）落地到敌人身上。

**Architecture:** 沿用既有「`GameFeel` 管屏幕级反馈（震屏/闪屏/顿帧/音效/伤害数字），世界空间 FX 由调用方实例化」的格局，但把后者集中到新的 `Vfx` 自动加载，避免每把武器各写一套粒子代码。`Vfx` 持有**纯数据预设注册表**（`BURST_PRESETS` / `ANIM_PRESETS`）+ 三个工厂：`spawn_burst`（一次性 `CPUParticles2D`，复用 `GameFeel._spawn_particles` 的配方）、`spawn_anim`（从帧序列惰性构建并缓存 `SpriteFrames` 的 `AnimatedSprite2D`）、`make_status_indicator`（按状态 kind 返回**未入树**的配置好节点，由敌人挂为子节点并按状态生命周期增删）。`GameFeel` 增三个「武器手感」专用震屏发射器（与既有 player/levelup 发射器解耦）+ 公开 `shake(preset)` / `hitstop(duration)`。状态指示器的增删差分抽成**纯静态** `Enemy.diff_status_fx`，可无场景单测。

**Tech Stack:** Godot 4.6.3 · GDScript · gdUnit4 · Kenney 2D 素材（外部库 `D:\Workspace\GAME\Assets\Kenney`）· PhantomCamera v0.11（震屏，既有）· CanvasItemMaterial BLEND_MODE_ADD（加色发光，沿用 lightning 既有做法）。

## Global Constraints

逐条来自设计 spec（`docs/superpowers/specs/2026-06-17-weapon-arsenal-redesign-design.md`）§4.1、§6，以及仓库现状，每个任务都隐含遵守：

- **引擎 Godot 4.6.3**；测试经 gdUnit4 headless 运行，**必须** `--ignoreHeadlessMode`（否则 abort，退出码 103）。
- **不做原创美术**：视觉一律 Kenney 库素材 + 程序化粒子/着色器（spec §12 明确）。素材源真相是**外部** `D:\Workspace\GAME\Assets\Kenney\2D assets\`；用到的子集拷入仓库 `assets/sprites/kenney/…` 后**必须** headless `--import`（记忆 `feedback_godot_asset_import`：MCP reimport 不导入新拷入文件）。
- **视觉服从机制可读性**（spec §2.4）：FX 不能盖过敌人与可走位空间；状态指示器小、贴在敌人头顶或作半透 overlay。
- **状态视觉语义（spec §4.1 视觉列，不可偏离）**：`burn`=敌人贴图叠橙红 + 头顶小火粒子；`slow`=偏青 + 霜粒子；`freeze`=冰晶 overlay（=极端 slow）；`stun`=头顶星旋（`twirl_*`）。
- **打击感分级（spec §7 各武器「打击感」行）**：震屏分 light / medium / heavy 三档；重武器（碎/核爆/震地）命中可叠 hitstop。本计划只建底座 API，**逐武器接入留 VFX Wave 2**。
- **确定性与 headless 安全**：顿帧用 `Engine.time_scale`，在 bot/headless（`RunHarness.active`）下**必须跳过**（既有 `game_feel.gd:166-174` 已如此，公开化后保留该护栏）；恢复 timer 用 `ignore_time_scale=true`。
- **不破坏既有反馈**：`GameFeel` 既有信号链（enemy_hit/enemy_died/player_hit/...）与 `_emitter_hit/_emitter_player/_emitter_levelup`、boss 顿帧、死亡粒子、伤害数字**一律保留不动**；新增 API 是叠加项。
- **测试约定（仓库现状）**：测试 `extends GdUnitTestSuite`，用 `load("res://…")` / 全局自动加载名引用；纯函数走静态/纯实例，场景走 `load(...).instantiate()` + `add_child` + `await get_tree().process_frame`。
- **VFX 不可像素级断言**：headless 无法断言「画面好不好看」。本计划的自动化测试只验**结构/契约**（节点类型、emitting、父子关系、帧数、预设内容、护栏分支），**画面正确性**由任务 8 的人工/截图清单（godot-ai MCP）兜底，非阻塞。

**前置依赖（执行顺序）**：

- **必须先完成 W0**（`…-w0-foundation.md`）：本计划任务 7 依赖 `Enemy.apply_status(kind, magnitude, duration)`、`Enemy.has_status(kind) -> bool`（W0 产出）。其余任务（1–6）不依赖 W0。
- **与武器波次（W1/W2/W3a/W3b）正交**：本底座不碰任何武器脚本/`.tres`。**逐武器 FX 接入（光环粒子、近战斩光、投射拖尾、进化变色、各武器震屏/顿帧调用）留 VFX Wave 2**，那一波依赖「武器已存在」+「本底座已就绪」。

**headless 测试命令**（PowerShell；下文每个任务的 Run 步骤都用它，仅换 `-a` 的目标文件）：

```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<TEST_FILE>.gd
```

> **执行前置（不阻塞计划）**：在专用分支执行（建议 `feat/weapon-arsenal-vfx`，从已含 W0 的分支或 `main` 切出）。

---

## File Structure

**新建**

- `autoloads/vfx.gd` — `Vfx` 自动加载。唯一职责：世界空间 FX 的预设注册表 + 工厂（`spawn_burst` / `build_frames` + `spawn_anim` / `make_status_indicator` / `additive_material`）。不持有游戏状态。
- `tests/test_vfx_assets.gd` — 断言导入的 Kenney FX 贴图可 `load`（无场景）。
- `tests/test_vfx_presets.gd` — `Vfx.get_preset` 纯数据单测（无场景）。
- `tests/test_vfx_spawn.gd` — `spawn_burst` / `build_frames` / `spawn_anim` 结构契约（轻量场景：自建 host 节点）。
- `tests/test_vfx_status_indicator.gd` — `Vfx.make_status_indicator` 工厂返回的节点结构（无场景，节点不入树）。
- `tests/test_vfx_feel.gd` — `GameFeel.shake` 预设 + `hitstop` 护栏（无重场景）。
- `tests/test_enemy_status_fx.gd` — `Enemy.diff_status_fx` 纯静态 + 敌人状态指示器随状态增删（实例化 `enemy.tscn`，依赖 W0）。
- 资产目录（任务 1 拷入 + import）：`assets/sprites/kenney/particles/pack/`、`assets/sprites/kenney/explosions/`、`assets/sprites/kenney/smoke/`、`assets/sprites/kenney/runes/`、`assets/sprites/kenney/light_masks/`。

**修改**

- `project.godot` — `[autoload]` 段在 `GameFeel` 后新增 `Vfx="*res://autoloads/vfx.gd"`。
- `autoloads/game_feel.gd` — 新增 `SHAKE_PRESETS` 常量 + `_weapon_emitters` + 在 `_setup_shake_emitters` 里建三个武器手感发射器；新增公开 `shake(preset)`；把 `_trigger_hitstop` 改名为公开 `hitstop` 并更新调用点。
- `scenes/enemies/enemy.gd` — 新增 `_status_fx` 字典 + 纯静态 `diff_status_fx` + `_update_status_fx()`；在既有 `_process` 末尾调用 `_update_status_fx()`。

---

## Task 1: 导入 Kenney FX 素材

**Files:**
- Create (拷入 + import): `assets/sprites/kenney/particles/pack/*.png`、`assets/sprites/kenney/explosions/*.png`、`assets/sprites/kenney/smoke/*.png`、`assets/sprites/kenney/runes/*.png`、`assets/sprites/kenney/light_masks/*.png`
- Test: `tests/test_vfx_assets.gd`

**Interfaces:**
- Produces: 仓库内可 `load("res://assets/sprites/kenney/particles/pack/circle_03.png")` 等真实贴图路径，供后续任务的预设引用。

- [x] **Step 1: 写失败测试**

`tests/test_vfx_assets.gd`：

```gdscript
extends GdUnitTestSuite

# 代表性抽样：每个导入目录至少验一张，确认拷入 + import 成功。
func test_particle_pack_imported() -> void:
	assert_object(load("res://assets/sprites/kenney/particles/pack/circle_03.png")).is_not_null()
	assert_object(load("res://assets/sprites/kenney/particles/pack/twirl_01.png")).is_not_null()
	assert_object(load("res://assets/sprites/kenney/particles/pack/flame_01.png")).is_not_null()
	assert_object(load("res://assets/sprites/kenney/particles/pack/slash_01.png")).is_not_null()

func test_explosion_frames_imported() -> void:
	assert_object(load("res://assets/sprites/kenney/explosions/regularExplosion00.png")).is_not_null()
	assert_object(load("res://assets/sprites/kenney/explosions/sonicExplosion00.png")).is_not_null()
	assert_object(load("res://assets/sprites/kenney/explosions/groundExplosion00.png")).is_not_null()

func test_smoke_and_runes_imported() -> void:
	assert_object(load("res://assets/sprites/kenney/smoke/whitePuff00.png")).is_not_null()
	assert_object(load("res://assets/sprites/kenney/runes/runeBlue_tile_001.png")).is_not_null()
```

- [x] **Step 2: 跑测试确认失败**

Run: `…/Godot_v4.6.3-stable_win64_console.exe … -a res://tests/test_vfx_assets.gd`
Expected: FAIL — `load(...)` 返回 `null`（文件尚未拷入/未 import）。

- [x] **Step 3: 拷入素材**

PowerShell（源已实地核验存在，见 spec §6.2 与素材清单）：

```powershell
$src = "D:\Workspace\GAME\Assets\Kenney\2D assets"
$dst = "D:\Workspace\GAME\game_0_vsl\assets\sprites\kenney"
New-Item -ItemType Directory -Force "$dst\particles\pack" | Out-Null
New-Item -ItemType Directory -Force "$dst\explosions"     | Out-Null
New-Item -ItemType Directory -Force "$dst\smoke"          | Out-Null
New-Item -ItemType Directory -Force "$dst\runes"          | Out-Null
New-Item -ItemType Directory -Force "$dst\light_masks"    | Out-Null
Copy-Item "$src\Particle Pack\PNG (Transparent)\*.png"      "$dst\particles\pack\"
Copy-Item "$src\Explosion Pack\PNG\Regular explosion\*.png" "$dst\explosions\"
Copy-Item "$src\Explosion Pack\PNG\Sonic explosion\*.png"   "$dst\explosions\"
Copy-Item "$src\Explosion Pack\PNG\Ground explosion\*.png"  "$dst\explosions\"
Copy-Item "$src\Explosion Pack\PNG\Particles\*.png"         "$dst\explosions\"
Copy-Item "$src\Smoke Particles\PNG\White puff\*.png"       "$dst\smoke\"
Copy-Item "$src\Smoke Particles\PNG\Gas\*.png"              "$dst\smoke\"
Copy-Item "$src\Smoke Particles\PNG\Flash\*.png"            "$dst\smoke\"
Copy-Item "$src\Rune Pack\PNG\Blue\Tile\*.png"             "$dst\runes\"
Copy-Item "$src\Light Masks\Default\circle_a.png","$src\Light Masks\Default\cone_a.png","$src\Light Masks\Default\ring_a.png" "$dst\light_masks\"
```

> `Particle Pack\PNG (Transparent)\*.png` 只取顶层（不递归 `Rotated\` 子目录），符合预设所需。

- [x] **Step 4: headless 触发导入**

Run:

```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" --import
```

Expected: 进程为每个新 `.png` 生成 `.import` 旁文件 + `.godot/imported/` 缓存后退出（无 `ERROR`）。

- [x] **Step 5: 跑测试确认通过**

Run: `…/Godot_v4.6.3-stable_win64_console.exe … -a res://tests/test_vfx_assets.gd`
Expected: PASS（3 个测试方法全绿）。

- [x] **Step 6: 提交**

```powershell
git add tests/test_vfx_assets.gd "assets/sprites/kenney/particles/pack" "assets/sprites/kenney/explosions" "assets/sprites/kenney/smoke" "assets/sprites/kenney/runes" "assets/sprites/kenney/light_masks"
git commit -m @'
feat(vfx): 导入 Kenney FX 素材(Particle/Explosion/Smoke/Rune/LightMask)

VFX 底座第一步:粒子/序列帧/符文/光罩子集拷入 + headless import。
含 load() 断言确认导入成功。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 2: `Vfx` 自动加载 + 预设注册表（纯数据）

**Files:**
- Create: `autoloads/vfx.gd`
- Modify: `project.godot`（`[autoload]` 段）
- Test: `tests/test_vfx_presets.gd`

**Interfaces:**
- Produces:
  - 自动加载全局 `Vfx`。
  - `const BURST_PRESETS: Dictionary`（key=`StringName`，value=`{color,amount,lifetime,vmin,vmax,smin,smax,additive}`）。
  - `const ANIM_PRESETS: Dictionary`（key=`StringName`，value=`{dir,base,count,fps}`）。
  - `func get_preset(name: StringName) -> Dictionary`（命中 burst 或 anim 返回其配置，否则返回空 `{}`）。

- [x] **Step 1: 写失败测试**

`tests/test_vfx_presets.gd`：

```gdscript
extends GdUnitTestSuite

func test_burst_preset_has_expected_keys() -> void:
	var cfg := Vfx.get_preset(&"fire_burst")
	assert_bool(cfg.is_empty()).is_false()
	assert_bool(cfg.has("color")).is_true()
	assert_bool(cfg.has("amount")).is_true()
	assert_bool(cfg.has("lifetime")).is_true()

func test_anim_preset_has_expected_keys() -> void:
	var cfg := Vfx.get_preset(&"explosion_regular")
	assert_bool(cfg.is_empty()).is_false()
	assert_int(cfg["count"]).is_equal(9)
	assert_str(cfg["base"]).is_equal("regularExplosion")

func test_unknown_preset_is_empty() -> void:
	assert_bool(Vfx.get_preset(&"does_not_exist").is_empty()).is_true()

func test_core_presets_registered() -> void:
	# 底座必备最小集；逐武器扩充留 VFX Wave 2。
	for k in [&"fire_burst", &"frost_burst", &"hit_spark", &"magic_burst"]:
		assert_bool(Vfx.BURST_PRESETS.has(k)).is_true()
	for k in [&"explosion_regular", &"explosion_sonic", &"explosion_ground"]:
		assert_bool(Vfx.ANIM_PRESETS.has(k)).is_true()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_presets.gd`
Expected: FAIL — `Vfx` 未注册（标识符未知 / 解析错误）。

- [x] **Step 3: 新建 `autoloads/vfx.gd`（仅注册表 + getter；工厂方法后续任务补）**

```gdscript
extends Node
## Vfx — 全局视效工厂 + 预设注册表。
## 一处定义 FX 配方,武器/敌人/状态系统只调用,不各写一套粒子代码。
## 分工:GameFeel 管屏幕级反馈(震屏/闪屏/顿帧/音效/伤害数字);
##       Vfx 管世界空间的粒子/序列帧/状态指示器实例化。

const PACK := "res://assets/sprites/kenney/particles/pack/"
const EXPL := "res://assets/sprites/kenney/explosions/"

# 一次性粒子爆发预设(CPUParticles2D 配方)。additive=true 走加色发光材质。
const BURST_PRESETS := {
	&"fire_burst":  {"color": Color(1.0, 0.6, 0.1),   "amount": 10, "lifetime": 0.40, "vmin": 50.0, "vmax": 150.0, "smin": 3.0, "smax": 6.0, "additive": false},
	&"frost_burst": {"color": Color(0.55, 0.85, 1.0), "amount": 10, "lifetime": 0.40, "vmin": 40.0, "vmax": 120.0, "smin": 3.0, "smax": 5.0, "additive": false},
	&"hit_spark":   {"color": Color(1.0, 1.0, 0.85),  "amount": 6,  "lifetime": 0.25, "vmin": 60.0, "vmax": 180.0, "smin": 2.0, "smax": 4.0, "additive": true},
	&"magic_burst": {"color": Color(0.7, 0.5, 1.0),   "amount": 12, "lifetime": 0.45, "vmin": 30.0, "vmax": 110.0, "smin": 3.0, "smax": 6.0, "additive": true},
}

# 序列帧预设:目录 + 帧名前缀 + 帧数(00..count-1) + 帧率。
const ANIM_PRESETS := {
	&"explosion_regular": {"dir": "res://assets/sprites/kenney/explosions/", "base": "regularExplosion", "count": 9, "fps": 24.0},
	&"explosion_sonic":   {"dir": "res://assets/sprites/kenney/explosions/", "base": "sonicExplosion",   "count": 9, "fps": 24.0},
	&"explosion_ground":  {"dir": "res://assets/sprites/kenney/explosions/", "base": "groundExplosion",  "count": 9, "fps": 24.0},
}

func get_preset(name: StringName) -> Dictionary:
	if BURST_PRESETS.has(name):
		return BURST_PRESETS[name]
	if ANIM_PRESETS.has(name):
		return ANIM_PRESETS[name]
	return {}
```

- [x] **Step 4: 注册自动加载**

`project.godot` `[autoload]` 段，在 `GameFeel` 行后插入一行：

```
GameFeel="*res://autoloads/game_feel.gd"
Vfx="*res://autoloads/vfx.gd"
```

- [x] **Step 5: 跑测试确认通过**

Run: `… -a res://tests/test_vfx_presets.gd`
Expected: PASS（4 个测试方法全绿）。

- [x] **Step 6: 提交**

```powershell
git add autoloads/vfx.gd project.godot tests/test_vfx_presets.gd
git commit -m @'
feat(vfx): Vfx 自动加载 + 预设注册表(burst/anim)

纯数据预设 + get_preset getter;工厂方法在后续任务补。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 3: `Vfx.spawn_burst` — 一次性粒子爆发工厂

**Files:**
- Modify: `autoloads/vfx.gd`
- Test: `tests/test_vfx_spawn.gd`

**Interfaces:**
- Consumes: `BURST_PRESETS`（Task 2）。
- Produces:
  - `func spawn_burst(pos: Vector2, preset: StringName, parent: Node = null) -> CPUParticles2D` — 按预设建一次性粒子，挂到 `parent`（缺省 `get_tree().current_scene`），定位 `pos`，`lifetime+0.1s` 后 `queue_free`；预设未知或无宿主返回 `null`。
  - `static func additive_material() -> CanvasItemMaterial` — 缓存的 `BLEND_MODE_ADD` 材质（加色发光，沿用 lightning 既有做法）。
  - `static func _configure_burst(p: CPUParticles2D, cfg: Dictionary) -> void` — 把预设字典写到粒子节点（纯，便于单测无需入树）。

- [x] **Step 1: 写失败测试**

`tests/test_vfx_spawn.gd`：

```gdscript
extends GdUnitTestSuite

func test_spawn_burst_returns_configured_particles() -> void:
	var host := auto_free(Node2D.new())
	add_child(host)
	var p := Vfx.spawn_burst(Vector2(10, 20), &"fire_burst", host)
	assert_object(p).is_not_null()
	assert_bool(p is CPUParticles2D).is_true()
	assert_bool(p.emitting).is_true()
	assert_bool(p.one_shot).is_true()
	assert_int(p.amount).is_equal(10)
	assert_object(p.get_parent()).is_same(host)
	assert_vector(p.global_position).is_equal_approx(Vector2(10, 20), Vector2(0.5, 0.5))

func test_spawn_burst_additive_preset_uses_add_material() -> void:
	var host := auto_free(Node2D.new())
	add_child(host)
	var p := Vfx.spawn_burst(Vector2.ZERO, &"hit_spark", host)
	assert_object(p.material).is_not_null()
	assert_int((p.material as CanvasItemMaterial).blend_mode).is_equal(CanvasItemMaterial.BLEND_MODE_ADD)

func test_spawn_burst_unknown_preset_returns_null() -> void:
	var host := auto_free(Node2D.new())
	add_child(host)
	assert_object(Vfx.spawn_burst(Vector2.ZERO, &"nope", host)).is_null()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_spawn.gd`
Expected: FAIL — `spawn_burst` / `additive_material` 未定义。

- [x] **Step 3: 在 `autoloads/vfx.gd` 追加实现**

```gdscript
static var _add_mat: CanvasItemMaterial = null

static func additive_material() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat

static func _configure_burst(p: CPUParticles2D, cfg: Dictionary) -> void:
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = cfg["amount"]
	p.lifetime = cfg["lifetime"]
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.initial_velocity_min = cfg["vmin"]
	p.initial_velocity_max = cfg["vmax"]
	p.scale_amount_min = cfg["smin"]
	p.scale_amount_max = cfg["smax"]
	p.color = cfg["color"]
	if cfg.get("additive", false):
		p.material = additive_material()

func spawn_burst(pos: Vector2, preset: StringName, parent: Node = null) -> CPUParticles2D:
	var cfg: Dictionary = BURST_PRESETS.get(preset, {})
	if cfg.is_empty():
		return null
	var host: Node = parent if parent != null else get_tree().current_scene
	if host == null:
		return null
	var p := CPUParticles2D.new()
	_configure_burst(p, cfg)
	host.add_child(p)
	p.global_position = pos
	get_tree().create_timer(p.lifetime + 0.1).timeout.connect(
		func() -> void:
			if is_instance_valid(p): p.queue_free()
	)
	return p
```

- [x] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_vfx_spawn.gd`
Expected: PASS（3 个方法全绿）。

- [x] **Step 5: 提交**

```powershell
git add autoloads/vfx.gd tests/test_vfx_spawn.gd
git commit -m @'
feat(vfx): Vfx.spawn_burst 一次性粒子工厂 + 加色材质

按预设建 CPUParticles2D,挂宿主、定位、自动回收;additive 走 BLEND_MODE_ADD。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 4: `Vfx.build_frames` + `spawn_anim` — 序列帧工厂

**Files:**
- Modify: `autoloads/vfx.gd`
- Test: `tests/test_vfx_spawn.gd`（追加方法）

**Interfaces:**
- Consumes: `ANIM_PRESETS`（Task 2）+ 任务 1 导入的 explosion 帧。
- Produces:
  - `func build_frames(name: StringName) -> SpriteFrames` — 惰性从帧序列构建并**缓存** `SpriteFrames`（同名复用同一实例）；预设未知返回 `null`。
  - `func spawn_anim(pos: Vector2, name: StringName, parent: Node = null) -> AnimatedSprite2D` — 播一次 `default` 动画，挂 `parent`（缺省 `current_scene`），播完 `queue_free`；预设未知或无宿主返回 `null`。

- [x] **Step 1: 写失败测试（追加到 `tests/test_vfx_spawn.gd`）**

```gdscript
func test_build_frames_count() -> void:
	var sf := Vfx.build_frames(&"explosion_regular")
	assert_object(sf).is_not_null()
	assert_int(sf.get_frame_count(&"default")).is_equal(9)

func test_build_frames_cached() -> void:
	var a := Vfx.build_frames(&"explosion_regular")
	var b := Vfx.build_frames(&"explosion_regular")
	assert_object(a).is_same(b)

func test_build_frames_unknown_null() -> void:
	assert_object(Vfx.build_frames(&"nope")).is_null()

func test_spawn_anim_plays_and_parents() -> void:
	var host := auto_free(Node2D.new())
	add_child(host)
	var a := Vfx.spawn_anim(Vector2(5, 5), &"explosion_sonic", host)
	assert_object(a).is_not_null()
	assert_bool(a is AnimatedSprite2D).is_true()
	assert_bool(a.is_playing()).is_true()
	assert_object(a.get_parent()).is_same(host)
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_spawn.gd`
Expected: FAIL — `build_frames` / `spawn_anim` 未定义。

- [x] **Step 3: 在 `autoloads/vfx.gd` 追加实现**

```gdscript
var _frames_cache := {}  # StringName -> SpriteFrames

func build_frames(name: StringName) -> SpriteFrames:
	if _frames_cache.has(name):
		return _frames_cache[name]
	var cfg: Dictionary = ANIM_PRESETS.get(name, {})
	if cfg.is_empty():
		return null
	var sf := SpriteFrames.new()
	sf.set_animation_speed(&"default", cfg["fps"])
	sf.set_animation_loop(&"default", false)
	for i in range(cfg["count"]):
		var idx := str(i).pad_zeros(2)  # 0->"00", 8->"08"
		var tex := load(cfg["dir"] + cfg["base"] + idx + ".png") as Texture2D
		if tex != null:
			sf.add_frame(&"default", tex)
	_frames_cache[name] = sf
	return sf

func spawn_anim(pos: Vector2, name: StringName, parent: Node = null) -> AnimatedSprite2D:
	var sf := build_frames(name)
	if sf == null:
		return null
	var host: Node = parent if parent != null else get_tree().current_scene
	if host == null:
		return null
	var a := AnimatedSprite2D.new()
	a.sprite_frames = sf
	host.add_child(a)
	a.global_position = pos
	a.play(&"default")
	a.animation_finished.connect(
		func() -> void:
			if is_instance_valid(a): a.queue_free()
	)
	return a
```

- [x] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_vfx_spawn.gd`
Expected: PASS（含 Task 3 共 7 个方法全绿）。

- [x] **Step 5: 提交**

```powershell
git add autoloads/vfx.gd tests/test_vfx_spawn.gd
git commit -m @'
feat(vfx): Vfx.build_frames+spawn_anim 序列帧工厂

从帧序列惰性构建并缓存 SpriteFrames;spawn_anim 播一次后自回收。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 5: `GameFeel` 公开打击感 API — 震屏预设 + 公开 hitstop

**Files:**
- Modify: `autoloads/game_feel.gd`
- Test: `tests/test_vfx_feel.gd`

**Interfaces:**
- Produces:
  - `const SHAKE_PRESETS: Dictionary` — `{&"light":[amp,freq,dur,decay], &"medium":[...], &"heavy":[...]}`。
  - `var _weapon_emitters: Dictionary` — `StringName -> PhantomCameraNoiseEmitter2D`，在 `_setup_shake_emitters` 建好。
  - `func shake(preset: StringName) -> void` — 触发对应武器手感发射器；未知预设 no-op。
  - `func hitstop(duration: float) -> void` — 公开顿帧（原 `_trigger_hitstop` 改名）；`RunHarness.active` 时跳过。
- 既有 `_emitter_hit/_emitter_player/_emitter_levelup` 与全部信号处理**不变**。

- [x] **Step 1: 写失败测试**

`tests/test_vfx_feel.gd`：

```gdscript
extends GdUnitTestSuite

func test_shake_presets_defined() -> void:
	assert_bool(GameFeel.SHAKE_PRESETS.has(&"light")).is_true()
	assert_bool(GameFeel.SHAKE_PRESETS.has(&"medium")).is_true()
	assert_bool(GameFeel.SHAKE_PRESETS.has(&"heavy")).is_true()

func test_weapon_emitters_built() -> void:
	assert_object(GameFeel._weapon_emitters.get(&"light")).is_not_null()
	assert_object(GameFeel._weapon_emitters.get(&"medium")).is_not_null()
	assert_object(GameFeel._weapon_emitters.get(&"heavy")).is_not_null()

func test_shake_known_and_unknown_no_crash() -> void:
	# 已知预设触发、未知预设安全 no-op(headless 无法断言相机位移,只验不崩)。
	GameFeel.shake(&"light")
	GameFeel.shake(&"heavy")
	GameFeel.shake(&"does_not_exist")
	assert_bool(true).is_true()

func test_hitstop_guarded_when_harness_active() -> void:
	var prev_active: bool = RunHarness.active
	var prev_scale := Engine.time_scale
	RunHarness.active = true
	GameFeel.hitstop(0.05)
	assert_float(Engine.time_scale).is_equal(prev_scale)  # 护栏:harness 下不动 time_scale
	RunHarness.active = prev_active
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_feel.gd`
Expected: FAIL — `SHAKE_PRESETS` / `_weapon_emitters` / `shake` / `hitstop` 未定义。

- [x] **Step 3: 改 `autoloads/game_feel.gd`**

3a. 在 `# ── Shake emitters ──` 区块（约 32-35 行）追加预设常量与字典：

```gdscript
# ── Shake emitters ────────────────────────────────────────────────────────
var _emitter_hit: PhantomCameraNoiseEmitter2D
var _emitter_player: PhantomCameraNoiseEmitter2D
var _emitter_levelup: PhantomCameraNoiseEmitter2D

# 武器手感专用震屏分级(与 player/levelup 解耦,调武器手感不影响受击/升级反馈)。
# 各档:[amplitude, frequency, duration, decay]。
const SHAKE_PRESETS := {
	&"light":  [6.0,  9.0, 0.10, 0.06],
	&"medium": [12.0, 7.0, 0.16, 0.10],
	&"heavy":  [22.0, 5.0, 0.24, 0.14],
}
var _weapon_emitters := {}  # StringName -> PhantomCameraNoiseEmitter2D
```

3b. 在 `_setup_shake_emitters()`（约 70-73 行）末尾建武器手感发射器：

```gdscript
func _setup_shake_emitters() -> void:
	_emitter_hit     = _make_emitter(4.0,  8.0, 0.08, 0.05, false)
	_emitter_player  = _make_emitter(24.0, 5.0, 0.25, 0.15, false)
	_emitter_levelup = _make_emitter(10.0, 6.0, 0.15, 0.10, false)
	for key in SHAKE_PRESETS:
		var p: Array = SHAKE_PRESETS[key]
		_weapon_emitters[key] = _make_emitter(p[0], p[1], p[2], p[3], false)
```

3c. 新增公开 `shake`（放在 `_make_emitter` 之后）：

```gdscript
# 武器/系统按手感分级请求震屏。未知预设安全 no-op。
func shake(preset: StringName) -> void:
	var e: PhantomCameraNoiseEmitter2D = _weapon_emitters.get(preset)
	if e != null:
		e.emit()
```

3d. 把 `_trigger_hitstop` 改名为公开 `hitstop`（保留原注释与 `RunHarness` 护栏），并更新调用点：

原（约 159-174 行）：

```gdscript
		if enemy != null and is_instance_valid(enemy) and enemy.get("behavior") == "boss":
			_trigger_hitstop(0.05)
```
改为：
```gdscript
		if enemy != null and is_instance_valid(enemy) and enemy.get("behavior") == "boss":
			hitstop(0.05)
```

并把函数签名从 `func _trigger_hitstop(duration: float) -> void:` 改为 `func hitstop(duration: float) -> void:`（函数体不变）。

- [x] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_vfx_feel.gd`
Expected: PASS（4 个方法全绿）。

- [x] **Step 5: 回归既有 GameFeel 相关测试**（确认改名/新增未破坏既有反馈）

Run: `… -a res://tests/test_game_formulas.gd` 并按需跑任何引用 GameFeel 的现有测试。
Expected: PASS（无回归）。

- [x] **Step 6: 提交**

```powershell
git add autoloads/game_feel.gd tests/test_vfx_feel.gd
git commit -m @'
feat(vfx): GameFeel 公开打击感 API(shake 分级 + hitstop)

新增 light/medium/heavy 武器手感震屏发射器 + shake(preset);
_trigger_hitstop 改名公开 hitstop(保留 RunHarness 护栏)。供武器在 VFX Wave 2 调用。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 6: `Vfx.make_status_indicator` — 状态指示器工厂

**Files:**
- Modify: `autoloads/vfx.gd`
- Test: `tests/test_vfx_status_indicator.gd`

**Interfaces:**
- Consumes: 任务 1 导入的 `circle_*` / `twirl_*` 贴图。
- Produces: `func make_status_indicator(kind: StringName) -> Node2D` — 按状态 kind 返回**未入树**的配置好节点（`burn`/`slow`=头顶 `CPUParticles2D` 持续粒子；`freeze`/`stun`=半透 `Sprite2D` overlay）；未知 kind 返回 `null`。节点由敌人挂为子节点并管理生命周期（Task 7）。

- [x] **Step 1: 写失败测试**

`tests/test_vfx_status_indicator.gd`：

```gdscript
extends GdUnitTestSuite

func test_burn_indicator_is_emitting_particles() -> void:
	var n := Vfx.make_status_indicator(&"burn")
	assert_object(n).is_not_null()
	assert_bool(n is CPUParticles2D).is_true()
	assert_bool((n as CPUParticles2D).emitting).is_true()
	n.free()

func test_slow_indicator_is_particles() -> void:
	var n := Vfx.make_status_indicator(&"slow")
	assert_bool(n is CPUParticles2D).is_true()
	n.free()

func test_freeze_indicator_is_sprite_overlay() -> void:
	var n := Vfx.make_status_indicator(&"freeze")
	assert_bool(n is Sprite2D).is_true()
	assert_object((n as Sprite2D).texture).is_not_null()
	n.free()

func test_stun_indicator_is_sprite_overlay() -> void:
	var n := Vfx.make_status_indicator(&"stun")
	assert_bool(n is Sprite2D).is_true()
	n.free()

func test_unknown_kind_returns_null() -> void:
	assert_object(Vfx.make_status_indicator(&"nope")).is_null()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_status_indicator.gd`
Expected: FAIL — `make_status_indicator` 未定义。

- [x] **Step 3: 在 `autoloads/vfx.gd` 追加实现**

```gdscript
# 按状态 kind 造未入树的指示器节点;调用方负责挂为子节点并按状态生命周期增删。
func make_status_indicator(kind: StringName) -> Node2D:
	match kind:
		&"burn":   return _status_particles(Color(1.0, 0.45, 0.1))
		&"slow":   return _status_particles(Color(0.55, 0.85, 1.0))
		&"freeze": return _status_overlay(PACK + "circle_03.png", Color(0.6, 0.9, 1.0, 0.55), Vector2.ZERO, 0.45)
		&"stun":   return _status_overlay(PACK + "twirl_01.png", Color(1.0, 1.0, 0.5, 0.9), Vector2(0, -20), 0.35)
		_:         return null

# 头顶持续小粒子(燃烧=橙、减速=青)。
func _status_particles(color: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = Vector2(0, -16)
	p.emitting = true
	p.one_shot = false
	p.amount = 8
	p.lifetime = 0.5
	p.direction = Vector2.UP
	p.spread = 25.0
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 25.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	return p

# 半透贴图 overlay(冻结=冰青 circle、硬直=星旋 twirl)。
func _status_overlay(tex_path: String, color: Color, offset: Vector2, scale: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(tex_path) as Texture2D
	s.modulate = color
	s.position = offset
	s.scale = Vector2(scale, scale)
	return s
```

- [x] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_vfx_status_indicator.gd`
Expected: PASS（5 个方法全绿）。

- [x] **Step 5: 提交**

```powershell
git add autoloads/vfx.gd tests/test_vfx_status_indicator.gd
git commit -m @'
feat(vfx): Vfx.make_status_indicator 状态指示器工厂

burn/slow=头顶持续粒子,freeze/stun=半透贴图 overlay;返回未入树节点供敌人挂载。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 7: 敌人状态 FX 接入（纯差分 + 随状态增删指示器）

> **依赖 W0**：本任务用到 `Enemy.apply_status(kind, magnitude, duration)` 与 `Enemy.has_status(kind) -> bool`（W0 产出）。执行前确认 W0 已合并。

**Files:**
- Modify: `scenes/enemies/enemy.gd`
- Test: `tests/test_enemy_status_fx.gd`

**Interfaces:**
- Consumes: `Vfx.make_status_indicator`（Task 6）；`Enemy.has_status` / `apply_status`（W0）。
- Produces:
  - `static func diff_status_fx(active: Array, current: Array) -> Dictionary` — 返回 `{"add": Array[StringName], "remove": Array[StringName]}`（纯，无场景）。
  - `var _status_fx: Dictionary` — `StringName -> Node2D`，当前挂着的指示器。
  - `func _update_status_fx() -> void` — 按 `has_status` 算活跃状态，差分增删指示器子节点；从既有 `_process` 调用。

- [x] **Step 1: 写失败测试**

`tests/test_enemy_status_fx.gd`：

```gdscript
extends GdUnitTestSuite

const EnemyScript := preload("res://scenes/enemies/enemy.gd")

# ── 纯差分(无场景) ──────────────────────────────────────────────
func test_diff_adds_new_statuses() -> void:
	var d := EnemyScript.diff_status_fx([&"burn", &"slow"], [])
	assert_array(d["add"]).contains([&"burn", &"slow"])
	assert_array(d["remove"]).is_empty()

func test_diff_removes_gone_statuses() -> void:
	var d := EnemyScript.diff_status_fx([], [&"burn"])
	assert_array(d["remove"]).contains([&"burn"])
	assert_array(d["add"]).is_empty()

func test_diff_stable_when_unchanged() -> void:
	var d := EnemyScript.diff_status_fx([&"burn"], [&"burn"])
	assert_array(d["add"]).is_empty()
	assert_array(d["remove"]).is_empty()

# ── 场景集成(实例化 enemy.tscn,依赖 W0 状态系统) ─────────────────
func test_burn_status_spawns_indicator_child() -> void:
	var e := load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child(e)
	await get_tree().process_frame
	e.apply_status(&"burn", 5.0, 2.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(e._status_fx.has(&"burn")).is_true()
	assert_object(e._status_fx[&"burn"]).is_not_null()
	assert_object(e._status_fx[&"burn"].get_parent()).is_same(e)
	e.queue_free()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_enemy_status_fx.gd`
Expected: FAIL — `diff_status_fx` / `_status_fx` / `_update_status_fx` 未定义。

- [x] **Step 3: 改 `scenes/enemies/enemy.gd`**

3a. 在字段区（`_pulse_tween` 附近，约 23 行后）新增：

```gdscript
var _status_fx := {}  # StringName -> Node2D(当前挂着的状态指示器)

# 参与可视化的状态种类(顺序固定,便于差分稳定)。
const _STATUS_FX_KINDS: Array[StringName] = [&"burn", &"slow", &"freeze", &"stun"]
```

3b. 在既有 `_process`（约 44-46 行）末尾调用更新：

```gdscript
func _process(_delta: float) -> void:
	if absf(velocity.x) > 1.0:
		_sprite.flip_h = velocity.x < 0.0
	_update_status_fx()
```

3c. 新增纯差分 + 更新方法（放在 `_process` 之后）：

```gdscript
# 纯函数:对比活跃状态与当前指示器,算出要增/要删的 kind。无副作用,可无场景单测。
static func diff_status_fx(active: Array, current: Array) -> Dictionary:
	var to_add: Array[StringName] = []
	var to_remove: Array[StringName] = []
	for k in active:
		if not current.has(k):
			to_add.append(k)
	for k in current:
		if not active.has(k):
			to_remove.append(k)
	return {"add": to_add, "remove": to_remove}

# 每帧按状态系统当前状态,增删头顶/overlay 指示器。状态视觉与 GameFeel 受击闪白互不冲突
# (指示器是独立子节点,不动 _sprite.modulate)。
func _update_status_fx() -> void:
	var active: Array[StringName] = []
	for k in _STATUS_FX_KINDS:
		if has_status(k):
			active.append(k)
	var diff := diff_status_fx(active, _status_fx.keys())
	for k in diff["remove"]:
		var node: Node = _status_fx[k]
		if is_instance_valid(node):
			node.queue_free()
		_status_fx.erase(k)
	for k in diff["add"]:
		var node := Vfx.make_status_indicator(k)
		if node != null:
			add_child(node)
			_status_fx[k] = node
```

- [x] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_enemy_status_fx.gd`
Expected: PASS（3 纯差分 + 1 集成，共 4 个方法全绿）。

- [x] **Step 5: 回归敌人相关测试**

Run: `… -a res://tests/test_enemy_ai.gd`（确认 `_process` 改动未破坏敌人行为/移动测试）
Expected: PASS（无回归）。

- [x] **Step 6: 提交**

```powershell
git add scenes/enemies/enemy.gd tests/test_enemy_status_fx.gd
git commit -m @'
feat(vfx): 敌人状态指示器(burn/slow/freeze/stun)随状态增删

纯静态 diff_status_fx + _process 驱动 _update_status_fx;指示器走 Vfx 工厂,
落地 spec §4.1「视觉」列。依赖 W0 状态系统(has_status/apply_status)。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 8: 全量回归 + 视觉冒烟验证（非阻塞）

**Files:** 无新增；运行验证。

- [x] **Step 1: 跑全部测试套件**

Run（逐文件或目录批量；与项目既有跑法一致）：

```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

Expected: 全绿，含本波新增 6 个测试文件 + W0/既有测试无回归。

- [x] **Step 2: 视觉冒烟（人工/截图，自动化测不出画面）**

用 godot-ai MCP 跑一局并截图，逐条目视确认（headless 无法断言像素，这步是底座质量兜底）：

1. `project_run` 启动主场景，正常游玩到敌人受击/死亡：确认死亡粒子、伤害数字、受击闪白**一切如旧**（无回归）。
2. 触发一次带状态的命中（接入武器前可临时在调试里对某敌 `apply_status(&"burn", 5, 3)`）：确认敌人头顶出现橙色小火粒子；`slow` 出现青色粒子；`freeze` 出现冰青 overlay；`stun` 出现星旋 overlay；状态结束后指示器消失。
3. `editor_screenshot` 抓图复核 FX 不盖过敌人/走位空间（spec §2.4 可读性）。

> 这步**不阻塞**提交（无代码产物）。发现问题回到对应任务调预设数值。

- [x] **Step 3: 提交（若 Step 2 调了预设数值）**

```powershell
git add -A
git commit -m @'
chore(vfx): 视觉冒烟后微调状态指示器/爆发预设数值

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Self-Review

**1. Spec 覆盖（§6 视觉系统 + §4.1 视觉列）：**

| spec 要求 | 落地任务 |
|---|---|
| §6.2 Kenney FX 素材入库（Particle/Explosion/Smoke/Rune/LightMask） | Task 1（拷入 + import + load 断言） |
| §6.3 程序化配方约定（持续/投射/瞬时打击的节点惯例） | Task 2-4（`BURST_PRESETS`/`ANIM_PRESETS` + `spawn_burst`/`spawn_anim` 工厂统一惯例） |
| §6.3 着色器：加色混合（火/电发光） | Task 3（`additive_material` BLEND_MODE_ADD，沿用 lightning） |
| §4.1 视觉列：burn 橙红+头顶火粒子 / slow 青+霜粒子 / freeze 冰晶 overlay / stun 头顶星旋 twirl | Task 6（工厂）+ Task 7（随状态增删） |
| §7 打击感分级 light/medium/heavy 震屏 + 重武器 hitstop | Task 5（`shake(preset)` + 公开 `hitstop`；逐武器接入留 Wave 2） |

**有意推迟（非缺口，记入交接）：** 逐武器具体 FX（光环底纹+环绕粒子、近战 `slash_*`/`muzzle_*` 命中、投射 `trace_*` 拖尾、进化变色、各武器 `shake`/`hitstop` 调用）= **VFX Wave 2**（依赖武器存在）；专用着色器（火噪声扰动、冰白边折射、电 UV 抖动、召唤幽光描边、变幻径向扭曲）= **VFX Wave 3（打磨层，可选）**。本波只交付「所有这些都要用」的共享底座。

**2. Placeholder 扫描：** 无 TBD/TODO；每个改码步骤都附完整代码与确切命令、期望输出。

**3. 类型一致性核对：**
- `Vfx.get_preset/spawn_burst/build_frames/spawn_anim/make_status_indicator/additive_material` 签名在「定义任务」与「测试/被调任务」间一致。
- `GameFeel.SHAKE_PRESETS`（dict）、`_weapon_emitters`（dict）、`shake(StringName)`、`hitstop(float)` 命名一致；`_trigger_hitstop`→`hitstop` 改名连同唯一调用点（`_on_enemy_died`）同步更新。
- `Enemy.diff_status_fx(active, current) -> {"add","remove"}`、`_status_fx`（dict）、`_update_status_fx()`、`_STATUS_FX_KINDS` 命名在 enemy.gd 与测试间一致。
- 状态 kind 字面量 `&"burn"/&"slow"/&"freeze"/&"stun"` 与 W0 `apply_status` 的 kind、spec §4.1 一致。
- 资产路径常量 `PACK`/`EXPL` 与 Task 1 拷贝目标目录、`build_frames`/`make_status_indicator` 引用一致（`circle_03.png`/`twirl_01.png`/`regularExplosion00..08` 均在 Task 1 导入范围内）。

---

## Execution Handoff

**计划已存 `docs/superpowers/plans/2026-06-17-weapon-arsenal-vfx-foundation.md`，两种执行方式：**

**1. Subagent-Driven（推荐）** — 每任务派新 subagent，任务间两段式审查，迭代快。
**2. Inline Execution** — 本会话内按 executing-plans 批量执行，带检查点。

> **执行前置**：先确认 **W0 已合并**（Task 7 依赖状态系统）；在专用分支 `feat/weapon-arsenal-vfx` 执行。

**至此 VFX 通道的「底座（VFX-W1）」计划完成。** 后续可选：**VFX Wave 2**（逐武器 FX 接入：光环/近战斩光/投射拖尾/进化变色 + 各武器 `shake`/`hitstop` 调用，依赖武器波次 + 本底座）、**VFX Wave 3**（专用着色器打磨，可选）。
