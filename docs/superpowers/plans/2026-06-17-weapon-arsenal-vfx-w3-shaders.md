# 武器军械库重做 VFX-W3：着色器打磨层 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地 spec §6.3 点名的 5 个着色器配方——火（噪声扰动+暖色）、冰（白边）、电（UV 抖动）、召唤（幽光描边）、变幻（径向扭曲）——并经 `Vfx` 材质工厂接到对应 FX/状态节点上，把 VFX-W1/W2 的「粒子+序列帧+加色」观感升到「有材质质感」。

**Architecture:** 5 个 `canvas_item` 着色器放 `res://shaders/`；`Vfx` 增 `SHADERS` 注册表 + `make_shader_material(name, unique)` 工厂（共享实例缓存，`unique=true` 时 `duplicate` 出独立参数副本）。接线是**替换/追加** material 赋值，不改任何机制：电→闪电电弧贴图，召唤→护盾球/随从精灵描边，冰→冻结 overlay，火→爆炸序列帧热扰，变幻→引力井屏读扭曲。

**Tech Stack:** Godot 4.6.3 · GDScript + Godot Shading Language（`canvas_item`）· gdUnit4 · VFX-W1/W2 底座（`Vfx`）。

## Global Constraints

逐条来自 spec §6.3、§6.4、仓库现状，每个任务都隐含遵守：

- **引擎 Godot 4.6.3**；测试经 gdUnit4 headless，**必须** `--ignoreHeadlessMode`。
- **着色器是打磨层，非阻塞主线**：本波不改机制/数值/粒子配方；只加 `.gdshader` + material 赋值。即使本波全不做，游戏与 VFX-W1/W2 仍完整可玩。
- **可读性优先（spec §2.4/§6.4）**：描边/白边/扭曲都克制（窄描边、低 strength），不得糊敌人轮廓或晕走位空间。
- **加色质感沿用既有约定**：电/火走加色或暖色乘法，与 lightning 既有 `BLEND_MODE_ADD` 风格一致。
- **着色器编译不可被单测断言为「视觉正确」**：headless 测试只验 `.gdshader` 可加载 + 暴露预期 uniform + 工厂返回 `ShaderMaterial` + 目标节点 material 已被赋值。**编译错误**靠每个 Run 步骤检查输出**无 `SHADER ERROR` / `ERROR`**；**画面正确性**靠任务 8 截图清单（godot-ai MCP）。诚实口径同 VFX-W1/W2。
- **复用工厂**：所有 `ShaderMaterial` 经 `Vfx.make_shader_material` 取，不在各处 `new ShaderMaterial()`；需独立 uniform 的场合传 `unique=true`。
- **测试约定**：`extends GdUnitTestSuite`；着色器用 `load("res://shaders/x.gdshader") as Shader`；`Shader.get_shader_uniform_list()` 取 uniform 名。

**前置依赖：**

- **必须先完成 VFX-W1**（`Vfx` 自动加载 + `make_status_indicator`）与 **VFX-W2**（逐武器 FX 接入，提供电弧/护盾/爆炸/引力井等接线点）。
- 召唤描边接随从依赖 **W3a**；变幻扭曲接引力井依赖 **W2**；这些任务标注了对应依赖。

**headless 测试命令**（PowerShell；下文每任务 Run 步骤都用它，仅换 `-a` 目标）：

```powershell
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/<TEST_FILE>.gd
```

---

## File Structure

**新建**

- `shaders/fire_distort.gdshader` — 火：噪声扰动 UV + 暖色乘法（热浪）。
- `shaders/ice_edge.gdshader` — 冰：径向白边（冰晶轮廓）。
- `shaders/electric_jitter.gdshader` — 电：逐行 UV 抖动 + 加色（噼啪）。
- `shaders/summon_glow.gdshader` — 召唤：alpha 膨胀描边（幽光轮廓）。
- `shaders/radial_distort.gdshader` — 变幻：屏读径向扭曲（向心吸入）。
- `tests/test_vfx_shaders.gd` — 着色器加载 + uniform + 工厂结构。
- `tests/test_vfx_shader_wiring.gd` — 接线集成（节点 material 是 ShaderMaterial）。

**修改**

- `autoloads/vfx.gd` — `SHADERS` 注册表 + `make_shader_material`。
- `scenes/weapons/lightning/lightning_weapon.gd` — 电弧/辉光 material 换电着色器。
- `scenes/weapons/orb/orb_shield.gd` — 护盾球精灵描边。
- `autoloads/vfx.gd`（`make_status_indicator` 冻结分支）— 冰白边。
- `scenes/weapons/explosion/explosion.gd` — 爆炸序列帧热扰。
- 引力井脚本（W2 产出）— 屏读扭曲。
- 随从脚本（W3a 产出）— 召唤描边。

---

## Task 1: 着色器库（5 个 .gdshader）

**Files:**
- Create: `shaders/fire_distort.gdshader`、`shaders/ice_edge.gdshader`、`shaders/electric_jitter.gdshader`、`shaders/summon_glow.gdshader`、`shaders/radial_distort.gdshader`
- Test: `tests/test_vfx_shaders.gd`

**Interfaces:**
- Produces: 5 个可加载的 `Shader` 资源，uniform 名固定（`fire`:speed/strength/tint；`ice`:edge_color/rim；`electric`:jitter/speed；`summon`:glow_color/width；`distort`:strength）。

- [x] **Step 1: 写失败测试**

`tests/test_vfx_shaders.gd`：

```gdscript
extends GdUnitTestSuite

func _uniform_names(path: String) -> Array:
	var sh := load(path) as Shader
	if sh == null:
		return []
	var names: Array = []
	for u in sh.get_shader_uniform_list():
		names.append(u["name"])
	return names

func test_fire_shader_loads_with_uniforms() -> void:
	assert_object(load("res://shaders/fire_distort.gdshader")).is_not_null()
	assert_array(_uniform_names("res://shaders/fire_distort.gdshader")).contains(["speed", "tint"])

func test_ice_shader_loads_with_uniforms() -> void:
	assert_array(_uniform_names("res://shaders/ice_edge.gdshader")).contains(["edge_color", "rim"])

func test_electric_shader_loads_with_uniforms() -> void:
	assert_array(_uniform_names("res://shaders/electric_jitter.gdshader")).contains(["jitter", "speed"])

func test_summon_shader_loads_with_uniforms() -> void:
	assert_array(_uniform_names("res://shaders/summon_glow.gdshader")).contains(["glow_color", "width"])

func test_distort_shader_loads_with_uniforms() -> void:
	assert_array(_uniform_names("res://shaders/radial_distort.gdshader")).contains(["strength"])
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_shaders.gd`
Expected: FAIL — 着色器文件不存在，`load` 返回 null，uniform 列表为空。

- [x] **Step 3: 写 5 个着色器**

`shaders/fire_distort.gdshader`：

```glsl
shader_type canvas_item;
// 火:UV 噪声扰动制造热浪 + 暖色乘法。安全用于序列帧(不强制加色,不过曝)。
uniform float speed = 1.0;
uniform float strength = 0.04;
uniform vec4 tint : source_color = vec4(1.0, 0.6, 0.2, 1.0);

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	uv.y += sin(uv.x * 12.0 + t * 6.0) * strength;
	uv.x += cos(uv.y * 10.0 + t * 5.0) * strength;
	vec4 tex = texture(TEXTURE, uv);
	COLOR = tex * tint * COLOR;
}
```

`shaders/ice_edge.gdshader`：

```glsl
shader_type canvas_item;
// 冰:从中心向外的白边(冰晶轮廓),保留原 alpha。
uniform vec4 edge_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float rim = 1.5;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float d = clamp(distance(UV, vec2(0.5)) * 2.0, 0.0, 1.0);
	float e = pow(d, rim);
	vec3 col = mix(tex.rgb, edge_color.rgb, e);
	COLOR = vec4(col, tex.a);
}
```

`shaders/electric_jitter.gdshader`：

```glsl
shader_type canvas_item;
render_mode blend_add;
// 电:逐行随机水平抖动 + 加色发光(噼啪)。
uniform float jitter = 0.03;
uniform float speed = 30.0;

float rand(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float row = floor(UV.y * 20.0);
	uv.x += (rand(row + floor(TIME * speed)) - 0.5) * jitter;
	COLOR = texture(TEXTURE, uv) * COLOR;
}
```

`shaders/summon_glow.gdshader`：

```glsl
shader_type canvas_item;
// 召唤:对 alpha 做十字膨胀,差值染成幽光描边。窄 width 保轮廓可读。
uniform vec4 glow_color : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform float width = 2.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * width;
	float a = tex.a;
	a = max(a, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	a = max(a, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	float outline = clamp(a - tex.a, 0.0, 1.0);
	COLOR = tex + glow_color * outline;
}
```

`shaders/radial_distort.gdshader`：

```glsl
shader_type canvas_item;
// 变幻:屏读径向扭曲,把背景向中心吸入(引力井)。
uniform float strength = 0.1;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 dir = UV - vec2(0.5);
	float d = length(dir);
	vec2 offset = normalize(dir + vec2(0.0001)) * strength * clamp(0.5 - d, 0.0, 0.5);
	vec4 col = texture(screen_tex, SCREEN_UV + offset);
	COLOR = vec4(col.rgb, texture(TEXTURE, UV).a);
}
```

- [x] **Step 4: 跑测试确认通过 + 检查无编译错误**

Run: `… -a res://tests/test_vfx_shaders.gd`
Expected: PASS（5 个方法全绿）；输出**无** `SHADER ERROR`。

- [x] **Step 5: 提交**

```powershell
git add shaders tests/test_vfx_shaders.gd
git commit -m @'
feat(vfx): 着色器库(火扰动/冰白边/电抖动/召唤描边/变幻扭曲)

spec §6.3 五配方,canvas_item 着色器;含加载+uniform 断言。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 2: `Vfx.make_shader_material` 工厂

**Files:**
- Modify: `autoloads/vfx.gd`
- Test: `tests/test_vfx_shaders.gd`（追加方法）

**Interfaces:**
- Produces:
  - `const SHADERS: Dictionary` — `{&"fire","ice","electric","summon","distort"} -> 路径`。
  - `func make_shader_material(name: StringName, unique: bool = false) -> ShaderMaterial` — `unique=false` 返回缓存共享实例；`unique=true` 返回 `duplicate()` 的独立副本；未知 name 返回 `null`。

- [x] **Step 1: 写失败测试（追加）**

```gdscript
func test_make_shader_material_returns_shader_material() -> void:
	var m := Vfx.make_shader_material(&"fire")
	assert_bool(m is ShaderMaterial).is_true()
	assert_object(m.shader).is_not_null()

func test_shared_material_is_cached() -> void:
	assert_object(Vfx.make_shader_material(&"ice")).is_same(Vfx.make_shader_material(&"ice"))

func test_unique_material_is_distinct() -> void:
	assert_object(Vfx.make_shader_material(&"ice", true)).is_not_same(Vfx.make_shader_material(&"ice", true))

func test_unknown_shader_returns_null() -> void:
	assert_object(Vfx.make_shader_material(&"nope")).is_null()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_shaders.gd` → FAIL（`SHADERS`/`make_shader_material` 未定义）。

- [x] **Step 3: 改 `autoloads/vfx.gd`**

```gdscript
const SHADERS := {
	&"fire":     "res://shaders/fire_distort.gdshader",
	&"ice":      "res://shaders/ice_edge.gdshader",
	&"electric": "res://shaders/electric_jitter.gdshader",
	&"summon":   "res://shaders/summon_glow.gdshader",
	&"distort":  "res://shaders/radial_distort.gdshader",
}
var _shader_mat_cache := {}  # StringName -> ShaderMaterial(共享)

func make_shader_material(name: StringName, unique: bool = false) -> ShaderMaterial:
	var path: String = SHADERS.get(name, "")
	if path == "":
		return null
	if not _shader_mat_cache.has(name):
		var sh := load(path) as Shader
		if sh == null:
			return null
		var base := ShaderMaterial.new()
		base.shader = sh
		_shader_mat_cache[name] = base
	var shared: ShaderMaterial = _shader_mat_cache[name]
	return shared.duplicate() as ShaderMaterial if unique else shared
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_shaders.gd` → PASS。

```powershell
git add autoloads/vfx.gd tests/test_vfx_shaders.gd
git commit -m @'
feat(vfx): Vfx.make_shader_material 工厂(共享缓存 + unique 副本)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 3: 电着色器 → 连锁闪电电弧

**Files:**
- Modify: `scenes/weapons/lightning/lightning_weapon.gd`
- Test: `tests/test_vfx_shader_wiring.gd`

**Interfaces:**
- Consumes: `Vfx.make_shader_material(&"electric")`。
- 现状锚点：`_spawn_segment`/`_spawn_impact` 用 `s.material = _additive()`。

- [x] **Step 1: 写失败测试**

`tests/test_vfx_shader_wiring.gd`：

```gdscript
extends GdUnitTestSuite

const LightningScript := preload("res://scenes/weapons/lightning/lightning_weapon.gd")

func _make_player() -> Node2D:
	var p := load("res://scenes/player/player.tscn").instantiate()
	add_child(p)
	return p

func _make_enemy_at(pos: Vector2) -> Node2D:
	var e := load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child(e); e.global_position = pos; e.add_to_group("enemies")
	return e

func _ysort() -> Node:
	var ys := get_tree().get_first_node_in_group("ysort")
	return ys if ys != null else get_tree().current_scene

func test_lightning_bolt_uses_electric_shader() -> void:
	var player := _make_player()
	var lit := LightningScript.new()
	lit.data = null
	player.add_child(lit)
	await get_tree().process_frame
	var enemy := _make_enemy_at(player.global_position + Vector2(60, 0))
	await get_tree().process_frame
	lit.attack()
	await get_tree().process_frame
	var found := false
	for c in _ysort().get_children():
		if c is Sprite2D and (c as Sprite2D).material is ShaderMaterial:
			found = true
	assert_bool(found).is_true()
	player.queue_free()
	if is_instance_valid(enemy): enemy.queue_free()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_shader_wiring.gd` → FAIL（电弧用的是 CanvasItemMaterial 非 ShaderMaterial）。

- [x] **Step 3: 改 `lightning_weapon.gd`**

把 `_spawn_segment` 与 `_spawn_impact` 里的 `s.material = _additive()` / `g.material = _additive()` 改为：

```gdscript
	s.material = Vfx.make_shader_material(&"electric")
```
```gdscript
	g.material = Vfx.make_shader_material(&"electric")
```

（`_additive()` 静态保留无妨，或一并删除——但删除前确认无其他引用。最小改动：仅替换两处赋值。）

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_shader_wiring.gd` → PASS；输出无 `SHADER ERROR`。

```powershell
git add scenes/weapons/lightning/lightning_weapon.gd tests/test_vfx_shader_wiring.gd
git commit -m @'
feat(vfx): 闪电电弧/辉光改用电 UV 抖动着色器

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 4: 召唤描边 → 护盾球精灵

**Files:**
- Modify: `scenes/weapons/orb/orb_shield.gd`
- Test: `tests/test_vfx_shader_wiring.gd`（追加方法）

**Interfaces:**
- Consumes: `Vfx.make_shader_material(&"summon")`。
- 现状锚点：`OrbShield._ready()`；精灵为 `.tscn` 里的 `Sprite2D` 子节点。

- [x] **Step 1: 写失败测试（追加）**

```gdscript
func test_orb_shield_sprite_has_summon_shader() -> void:
	var player := _make_player()
	await get_tree().process_frame
	var orb := load("res://scenes/weapons/orb/orb_shield.tscn").instantiate()
	player.add_child(orb)
	await get_tree().process_frame
	var spr := orb.get_node_or_null("Sprite2D")
	assert_object(spr).is_not_null()
	assert_bool(spr.material is ShaderMaterial).is_true()
	player.queue_free()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_shader_wiring.gd` → FAIL。

- [x] **Step 3: 改 `orb_shield.gd` 的 `_ready()`**

```gdscript
func _ready() -> void:
	_player = get_parent()
	var spr := get_node_or_null("Sprite2D")
	if spr != null:
		spr.material = Vfx.make_shader_material(&"summon")
	# (VFX-W2 已在此挂幽蓝拖尾;两行并存)
	add_child(Vfx.make_trail(Color(0.5, 0.6, 1.0, 0.8), true))
```

> 若 VFX-W2 已加 `add_child(Vfx.make_trail(...))`，保留它，仅新增描边两行；勿重复添加拖尾。

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_shader_wiring.gd` → PASS。

```powershell
git add scenes/weapons/orb/orb_shield.gd tests/test_vfx_shader_wiring.gd
git commit -m @'
feat(vfx): 缚灵护盾球精灵加召唤幽光描边

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 5: 冰白边 → 冻结状态 overlay

**Files:**
- Modify: `autoloads/vfx.gd`（`make_status_indicator` 冻结分支）
- Test: `tests/test_vfx_shaders.gd`（追加方法）

**Interfaces:**
- Consumes: `Vfx.make_shader_material(&"ice")`。
- 现状锚点：VFX-W1 的 `make_status_indicator(&"freeze")` 返回一个 `Sprite2D` overlay。

- [x] **Step 1: 写失败测试（追加，纯——无场景）**

```gdscript
func test_freeze_indicator_uses_ice_shader() -> void:
	var n := Vfx.make_status_indicator(&"freeze")
	assert_bool(n is Sprite2D).is_true()
	assert_bool((n as Sprite2D).material is ShaderMaterial).is_true()
	n.free()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_shaders.gd` → FAIL（freeze overlay 无 material）。

- [x] **Step 3: 改 `autoloads/vfx.gd` 的 `_status_overlay`/freeze 分支**

让冻结 overlay 带冰着色器。改 `make_status_indicator` 的 freeze 分支或 `_status_overlay`，最小做法——在 freeze 分支构造后赋 material：

```gdscript
	match kind:
		&"burn":   return _status_particles(Color(1.0, 0.45, 0.1))
		&"slow":   return _status_particles(Color(0.55, 0.85, 1.0))
		&"freeze":
			var s := _status_overlay(PACK + "circle_03.png", Color(0.6, 0.9, 1.0, 0.55), Vector2.ZERO, 0.45)
			s.material = make_shader_material(&"ice")
			return s
		&"stun":   return _status_overlay(PACK + "twirl_01.png", Color(1.0, 1.0, 0.5, 0.9), Vector2(0, -20), 0.35)
		_:         return null
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_shaders.gd` → PASS。

```powershell
git add autoloads/vfx.gd tests/test_vfx_shaders.gd
git commit -m @'
feat(vfx): 冻结 overlay 加冰白边着色器

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 6: 火热扰 → 爆炸序列帧

**Files:**
- Modify: `scenes/weapons/explosion/explosion.gd`
- Test: `tests/test_vfx_shader_wiring.gd`（追加方法）

**Interfaces:**
- Consumes: `Vfx.make_shader_material(&"fire")`。
- 现状锚点：VFX-W2 的 `Explosion.detonate()` 里 `var fx := Vfx.spawn_anim(...)`。

- [x] **Step 1: 写失败测试（追加）**

```gdscript
const ExplosionScript := preload("res://scenes/weapons/explosion/explosion.gd")

func test_explosion_anim_has_fire_shader() -> void:
	var expl := ExplosionScript.new()
	add_child(expl)
	expl.damage = 1.0
	expl.global_position = Vector2(400, 400)
	await get_tree().process_frame
	expl.detonate()
	await get_tree().process_frame
	var found := false
	for c in _ysort().get_children():
		if c is AnimatedSprite2D and (c as AnimatedSprite2D).material is ShaderMaterial:
			found = true
	# spawn_anim 缺省挂 current_scene;两处都查
	for c in get_tree().current_scene.get_children():
		if c is AnimatedSprite2D and (c as AnimatedSprite2D).material is ShaderMaterial:
			found = true
	assert_bool(found).is_true()
	if is_instance_valid(expl): expl.queue_free()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_shader_wiring.gd` → FAIL（anim 无 material）。

- [x] **Step 3: 改 `explosion.gd` 的 `detonate()`**

在 `var fx := Vfx.spawn_anim(...)` 赋 scale 处追加 material：

```gdscript
	var fx := Vfx.spawn_anim(global_position, anim)
	if fx != null:
		fx.scale = Vector2.ONE * base_scale
		fx.material = Vfx.make_shader_material(&"fire")
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_shader_wiring.gd` → PASS；无 `SHADER ERROR`。

```powershell
git add scenes/weapons/explosion/explosion.gd tests/test_vfx_shader_wiring.gd
git commit -m @'
feat(vfx): 爆炸序列帧加火热扰着色器

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 7: 变幻扭曲 → 引力井（依赖 W2）+ 召唤描边 → 随从（依赖 W3a）

> **依赖 W2 / W3a**：引力井、随从脚本由对应武器波次产出。接线点以其实际视觉节点为准。

**Files:**
- Modify: 引力井脚本（W2）、随从脚本（W3a）
- Test: `tests/test_vfx_shader_wiring.gd`（追加方法）

**Interfaces:**
- Consumes: `Vfx.make_shader_material(&"distort", true)`（井各自独立 strength）、`Vfx.make_shader_material(&"summon")`。

- [x] **Step 1: 写失败测试（追加，路径以 W2/W3a 实际为准）**

```gdscript
func test_gravity_well_visual_has_distort_shader() -> void:
	var well := load("res://scenes/weapons/gravity_well/gravity_well.tscn").instantiate()
	add_child(well)
	await get_tree().process_frame
	# 井的视觉节点(Sprite2D/Node2D 下的 Sprite2D)应带扭曲材质
	var ok := false
	for c in well.get_children():
		if c is CanvasItem and (c as CanvasItem).material is ShaderMaterial:
			ok = true
	# 或井自身是 CanvasItem
	if well is CanvasItem and (well as CanvasItem).material is ShaderMaterial:
		ok = true
	assert_bool(ok).is_true()
	well.queue_free()
```

- [x] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_vfx_shader_wiring.gd` → FAIL。

- [x] **Step 3: 接线**

引力井视觉节点（W2 产出的井心 Sprite2D，或 `_ready` 里自建的视觉）：

```gdscript
	# 屏读径向扭曲:背景向井心吸入。各井独立 strength,故 unique。
	var mat := Vfx.make_shader_material(&"distort", true)
	mat.set_shader_parameter("strength", 0.12)
	$Visual.material = mat   # 节点名以 W2 实际为准($Sprite2D/$Visual)
```

随从（W3a 的 `roaming_minion`）精灵（VFX-W2 已加拖尾，这里加描边）：

```gdscript
	if _sprite != null:  # _sprite 为 W3a 自建的随从精灵
		_sprite.material = Vfx.make_shader_material(&"summon")
```

- [x] **Step 4: 跑测试确认通过 → 提交**

Run: `… -a res://tests/test_vfx_shader_wiring.gd` → PASS。

```powershell
git add scenes/weapons/gravity_well scenes/weapons/reanimate tests/test_vfx_shader_wiring.gd
git commit -m @'
feat(vfx): 引力井屏读径向扭曲 + 随从召唤描边

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 8: 全量回归 + 视觉冒烟

- [x] **Step 1: 跑全部测试套件**

Run: `… -a res://tests`
Expected: 全绿；**输出无 `SHADER ERROR` / `ERROR`**（着色器编译干净）。

- [x] **Step 2: 视觉冒烟（godot-ai MCP，非阻塞）**

`project_run` 主场景，`editor_screenshot` 逐项确认：
- 闪电电弧有抖动噼啪感、火球/核爆有热浪、冻结敌人有冰晶白边、护盾球/随从有幽蓝描边、引力井把背景向心吸入扭曲。
- **可读性复核（spec §2.4/§6.4）**：描边窄、白边不糊轮廓、扭曲 strength 不晕走位空间、电抖动不致癫痫感。超标则调对应 uniform（`width`/`rim`/`strength`/`jitter`）。
- 低端机性能：屏读 `distort` 是唯一较贵项；若引力井同屏多个掉帧，限制同时启用的扭曲井数或降 strength。

- [x] **Step 3: 提交（若调了 uniform）**

```powershell
git add -A
git commit -m @'
chore(vfx): 视觉冒烟后微调着色器 uniform(描边宽/白边/扭曲强度)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Self-Review

**1. Spec 覆盖（§6.3 着色器配方）：**

| spec 配方 | 着色器 | 接到哪 | 任务 |
|---|---|---|---|
| 火=噪声扰动+加色混合 | `fire_distort` | 爆炸序列帧（火球/核爆/炼狱） | 1,2,6 |
| 冰=折射/白边 | `ice_edge` | 冻结状态 overlay（霜噬/暴雪） | 1,2,5 |
| 电=UV 抖动 | `electric_jitter` | 闪电电弧/辉光 | 1,2,3 |
| 召唤=幽光描边 | `summon_glow` | 缚灵护盾球 + 亡者随从 | 1,2,4,7 |
| 变幻=径向扭曲 | `radial_distort` | 引力井（屏读吸入） | 1,2,7 |

**2. Placeholder 扫描：** 无 TBD；5 个着色器与工厂均给完整代码。Task 7 标「节点名/路径以 W2/W3a 实际为准」是**显式依赖**，接线代码与赋值完整。

**3. 类型一致性核对：**
- `Vfx.make_shader_material(StringName, bool) -> ShaderMaterial`、`SHADERS` 键 `&"fire"/"ice"/"electric"/"summon"/"distort"` 在 Task 2 定义、Task 3-7 引用，一致。
- uniform 名（`speed`/`strength`/`tint`/`edge_color`/`rim`/`jitter`/`glow_color`/`width`）在着色器声明与 Task 1 测试断言一致；Task 7 `set_shader_parameter("strength", …)` 与 `radial_distort` 的 uniform 名一致。
- 接线锚点（`lightning._spawn_segment/_spawn_impact`、`orb_shield._ready` 的 `Sprite2D`、`make_status_indicator` freeze 分支、`Explosion.detonate` 的 `fx`）与 VFX-W1/W2 及当前脚本一致。

**4. 诚实性：** 着色器「编译成功 ≠ 视觉正确」已在 Global Constraints 与 Task 8 明示；自动化只验加载/uniform/材质赋值，画面与性能靠截图清单兜底。

---

## Execution Handoff

**计划已存 `docs/superpowers/plans/2026-06-17-weapon-arsenal-vfx-w3-shaders.md`，两种执行方式：Subagent-Driven（推荐）/ Inline。**

> **执行前置**：先确认 **VFX-W1/W2** 已合并（Task 7 还需 W2 引力井 / W3a 随从）。本波是打磨层，可在主线 VFX 稳定后再做。

至此**整套 VFX 通道计划完成**：VFX-W1（底座）· VFX-W2（逐武器接入）· VFX-W3（着色器打磨）。剩余可写：**W4 平衡（telemetry A/B）**。
