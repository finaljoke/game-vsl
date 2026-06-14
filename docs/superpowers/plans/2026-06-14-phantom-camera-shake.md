# Phantom Camera Shake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken hand-written shake system in `game_feel.gd` with Phantom Camera's Perlin noise emitters, and add a `Camera2D` to the main scene (currently absent — all shake is a no-op).

**Architecture:** Two tasks. Task 1 adds the Phantom Camera infrastructure to `main.tscn` (Camera2D → PhantomCameraHost child, plus PhantomCamera2D sibling). Task 2 refactors `game_feel.gd`: removes hand-written `_process` shake, adds three `PhantomCameraNoiseEmitter2D` nodes created at runtime as children of the GameFeel Autoload, and replaces `_shake()` call-sites with `emitter.emit()`.

**Tech Stack:** Godot 4.6, GDScript, Phantom Camera v0.11 (`addons/phantom_camera/`), `PhantomCameraNoiseEmitter2D`, `PhantomCameraNoise2D`. `PhantomCameraManager` is already registered as Autoload in `project.godot`.

---

## File Structure

**Modified:**
- `scenes/main/main.tscn` — add 3 nodes: Camera2D, PhantomCameraHost (child of Camera2D), PhantomCamera2D
- `autoloads/game_feel.gd` — remove hand-written shake system, add emitter setup

**Unchanged:** all other files

---

### Task 1: Add Camera2D + Phantom Camera nodes to main.tscn

**Files:**
- Modify: `scenes/main/main.tscn`

Use godot-ai MCP tools. Load schemas with ToolSearch as needed (`select:mcp__godot-ai__scene_open`, etc.).

- [ ] **Step 1: Open main.tscn in the Godot editor**

```
mcp__godot-ai__scene_open
  path: "res://scenes/main/main.tscn"
```

- [ ] **Step 2: Add Camera2D to scene root**

```
mcp__godot-ai__node_create
  parent_path: "."            # root of Main scene
  node_type: "Camera2D"
  node_name: "Camera2D"
```

- [ ] **Step 3: Set Camera2D position to arena center**

The arena is 1280×720. Centering Camera2D here with anchor_mode DRAG_CENTER (=1) makes the viewport show exactly 0–1280 × 0–720.

```
mcp__godot-ai__node_set_property
  node_path: "Camera2D"
  property: "position"
  value: {"x": 640, "y": 360}
```

```
mcp__godot-ai__node_set_property
  node_path: "Camera2D"
  property: "anchor_mode"
  value: 1
```

- [ ] **Step 4: Add PhantomCameraHost as child of Camera2D**

PhantomCameraHost base type is `Node`. The plugin registers it as a custom type. Create with base type, then attach script.

```
mcp__godot-ai__node_create
  parent_path: "Camera2D"
  node_type: "Node"
  node_name: "PhantomCameraHost"
```

```
mcp__godot-ai__script_attach
  node_path: "Camera2D/PhantomCameraHost"
  script_path: "res://addons/phantom_camera/scripts/phantom_camera_host/phantom_camera_host.gd"
```

- [ ] **Step 5: Add PhantomCamera2D to scene root**

PhantomCamera2D base type is `Node2D`. No follow_mode property needed — `FollowMode.NONE = 0` is the default. The node auto-activates because it will be the only PhantomCamera2D in the scene (priority system picks it automatically).

```
mcp__godot-ai__node_create
  parent_path: "."
  node_type: "Node2D"
  node_name: "PhantomCamera2D"
```

```
mcp__godot-ai__script_attach
  node_path: "PhantomCamera2D"
  script_path: "res://addons/phantom_camera/scripts/phantom_camera/phantom_camera_2d.gd"
```

- [ ] **Step 6: Save the scene**

```
mcp__godot-ai__scene_save
  scene_path: "res://scenes/main/main.tscn"
```

- [ ] **Step 7: Run game and verify no errors**

```
mcp__godot-ai__project_run
```

Check Output panel. Expected: game launches normally, no errors from Phantom Camera. The shake won't work yet (game_feel.gd still calls old code), but Camera2D now exists so there should be no null-reference crash.

If you see `PhantomCameraManager not found`: the plugin Autoload must be registered — it already is in `project.godot` (confirmed: `PhantomCameraManager="*uid://duq6jhf6unyis"`). If the error still appears, reload the project.

- [ ] **Step 8: Commit**

```bash
git add scenes/main/main.tscn
git commit -m "feat: add Camera2D + PhantomCameraHost + PhantomCamera2D to main scene"
```

---

### Task 2: Replace shake system in game_feel.gd

**Files:**
- Modify: `autoloads/game_feel.gd`

All edits use the Edit tool with exact old_string → new_string replacements. Read the file first before editing.

- [ ] **Step 1: Remove shake state variables and _camera reference**

The three variables (`_shake_magnitude`, `_shake_decay`, `_camera`) are replaced by three emitter references.

```
old_string:
# ── Shake state ───────────────────────────────────────────────────────────
var _shake_magnitude: float = 0.0
var _shake_decay: float = 0.0

# ── Cached references ─────────────────────────────────────────────────────
var _camera: Camera2D = null
var _player_node: Node2D = null

new_string:
# ── Shake emitters ────────────────────────────────────────────────────────
var _emitter_hit: PhantomCameraNoiseEmitter2D
var _emitter_player: PhantomCameraNoiseEmitter2D
var _emitter_levelup: PhantomCameraNoiseEmitter2D

# ── Cached references ─────────────────────────────────────────────────────
var _player_node: Node2D = null
```

- [ ] **Step 2: Add _setup_shake_emitters() call to _ready()**

```
old_string:
func _ready() -> void:
	_setup_flash_rect()
	_setup_audio()
	enemy_hit.connect(_on_enemy_hit)

new_string:
func _ready() -> void:
	_setup_flash_rect()
	_setup_audio()
	_setup_shake_emitters()
	enemy_hit.connect(_on_enemy_hit)
```

- [ ] **Step 3: Add _setup_shake_emitters() and _make_emitter() helper**

Insert these two functions immediately before `_make_sfx_player`. The emitters are added as children of the GameFeel Autoload node (at `/root/GameFeel`), which is in the scene tree. Their `_enter_tree()` will find `/root/PhantomCameraManager` and subscribe to its noise signal. All three emitters use the default `noise_emitter_layer = 1`, which matches the PhantomCamera2D's default layer.

```
old_string:
func _make_sfx_player(path: String) -> AudioStreamPlayer:

new_string:
func _setup_shake_emitters() -> void:
	_emitter_hit     = _make_emitter(4.0,  8.0, 0.08, 0.05, false)
	_emitter_player  = _make_emitter(18.0, 5.0, 0.25, 0.15, true)
	_emitter_levelup = _make_emitter(10.0, 6.0, 0.15, 0.10, false)

func _make_emitter(amplitude: float, frequency: float, duration: float, decay: float, rotational: bool) -> PhantomCameraNoiseEmitter2D:
	var noise := PhantomCameraNoise2D.new()
	noise.amplitude = amplitude
	noise.frequency = frequency
	noise.positional_noise = true
	noise.rotational_noise = rotational
	noise.randomize_noise_seed = true
	var emitter := PhantomCameraNoiseEmitter2D.new()
	emitter.noise = noise
	emitter.duration = duration
	emitter.decay_time = decay
	emitter.continuous = false
	add_child(emitter)
	return emitter

func _make_sfx_player(path: String) -> AudioStreamPlayer:
```

- [ ] **Step 4: Remove _process() and _get_camera()**

```
old_string:
# ── Process: screen shake ─────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _shake_magnitude <= 0.0:
		return
	_shake_magnitude = max(0.0, _shake_magnitude - _shake_decay * delta)
	var cam := _get_camera()
	if cam == null:
		_shake_magnitude = 0.0
		return
	if _shake_magnitude < 0.1:
		cam.offset = Vector2.ZERO
		_shake_magnitude = 0.0
	else:
		cam.offset = Vector2(
			randf_range(-_shake_magnitude, _shake_magnitude),
			randf_range(-_shake_magnitude, _shake_magnitude)
		)

# ── Lazy lookups ──────────────────────────────────────────────────────────
func _get_camera() -> Camera2D:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_2d()
	return _camera

func _get_player() -> Node2D:

new_string:
# ── Lazy lookups ──────────────────────────────────────────────────────────
func _get_player() -> Node2D:
```

- [ ] **Step 5: Remove _shake() helper**

```
old_string:
func _shake(magnitude: float, duration: float) -> void:
	if magnitude > _shake_magnitude:
		_shake_magnitude = magnitude
		_shake_decay = magnitude / duration

func _flash_node

new_string:
func _flash_node
```

- [ ] **Step 6: Update _on_enemy_died — replace _shake with emitter**

```
old_string:
func _on_enemy_died(position: Vector2) -> void:
	_spawn_particles(position)
	_shake(3.0, 0.1)
	_play_sfx(_sfx_death)

new_string:
func _on_enemy_died(position: Vector2) -> void:
	_spawn_particles(position)
	_emitter_hit.emit()
	_play_sfx(_sfx_death)
```

- [ ] **Step 7: Update _on_player_hit — replace _shake with emitter**

```
old_string:
func _on_player_hit(_amount: float) -> void:
	_shake(8.0, 0.3)
	var p := _get_player()

new_string:
func _on_player_hit(_amount: float) -> void:
	_emitter_player.emit()
	var p := _get_player()
```

- [ ] **Step 8: Update _on_player_leveled_up — replace _shake with emitter**

```
old_string:
func _on_player_leveled_up(_level: int) -> void:
	_screen_flash(Color(1, 1, 1, 0.6), 0.15)
	_shake(5.0, 0.2)
	_play_sfx(_sfx_levelup)

new_string:
func _on_player_leveled_up(_level: int) -> void:
	_screen_flash(Color(1, 1, 1, 0.6), 0.15)
	_emitter_levelup.emit()
	_play_sfx(_sfx_levelup)
```

- [ ] **Step 9: Run game and verify all shake effects**

```
mcp__godot-ai__project_run
```

Test each action:

| 操作 | 预期效果 |
|---|---|
| 敌人死亡 | 轻微短促 Perlin 震动（比原随机偏移更流畅） |
| 玩家受伤 | 强烈震动 + 轻微相机倾斜 |
| 玩家升级 | 中等震动 + 全屏白闪 |
| 游戏输出面板 | 无报错 |

如果震动没有效果，检查 Output 面板。常见问题：
- `PhantomCameraManager not found`：重载项目，确保插件已启用
- `Invalid call. Nonexistent function 'emit' in base 'Nil'`：`_setup_shake_emitters()` 未在 `_ready()` 中调用，检查 Step 2

- [ ] **Step 10: Commit**

```bash
git add autoloads/game_feel.gd
git commit -m "feat: replace hand-written shake with PhantomCamera Perlin noise emitters"
```

---

## Self-review

**Spec coverage:**

| 设计文档要求 | 对应 Task/Step |
|---|---|
| Camera2D 添加到 main.tscn，position=(640,360) | Task 1 Steps 2–3 |
| anchor_mode = DRAG_CENTER | Task 1 Step 3 |
| PhantomCameraHost 作为 Camera2D 子节点 | Task 1 Step 4 |
| PhantomCamera2D，FollowMode.NONE（默认） | Task 1 Step 5 |
| 删除 _shake_magnitude, _shake_decay, _camera | Task 2 Step 1 |
| 删除 _process(), _get_camera(), _shake() | Task 2 Steps 4–5 |
| 新增 _emitter_hit, _emitter_player, _emitter_levelup 成员 | Task 2 Step 1 |
| _setup_shake_emitters() 在 _ready() 中调用 | Task 2 Steps 2–3 |
| emitter_hit: amplitude=4, freq=8, dur=0.08, decay=0.05, rot=false | Task 2 Step 3 |
| emitter_player: amplitude=18, freq=5, dur=0.25, decay=0.15, rot=true | Task 2 Step 3 |
| emitter_levelup: amplitude=10, freq=6, dur=0.15, decay=0.10, rot=false | Task 2 Step 3 |
| _on_enemy_died → _emitter_hit.emit() | Task 2 Step 6 |
| _on_player_hit → _emitter_player.emit() | Task 2 Step 7 |
| _on_player_leveled_up → _emitter_levelup.emit() | Task 2 Step 8 |

全部覆盖，无遗漏。
