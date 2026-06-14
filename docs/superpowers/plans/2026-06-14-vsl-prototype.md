# VSL 原型 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现可玩的 Vampire Survivors 核心循环：WASD 移动、3 种自动武器、敌人涌入、XP 收集、升级选武器、死亡重开。

**Architecture:** 扁平场景层级（方案 A）——所有实体为自包含 Godot 场景，无额外抽象层。GameManager Autoload 管理全局状态机（playing / level_up / dead）。场景间通过 groups + signals 解耦。

**Tech Stack:** Godot 4.6 · GDScript 2.0 · godot-ai MCP（场景/属性操作）· CharacterBody2D（玩家/敌人）· Area2D（武器/XP宝石）

> **重要：** 任务 1–13 创建所有脚本和场景，任务 14 组装主场景。**在任务 14 完成前不要运行游戏。**

---

## 文件清单

```
autoloads/
  game_manager.gd
scenes/
  main/
    main.tscn
    main.gd
  arena/
    arena.tscn
  player/
    player.tscn
    player.gd
  enemies/
    enemy.tscn
    enemy.gd
    enemy_spawner.gd
  collectibles/
    xp_gem.tscn
    xp_gem.gd
  weapons/
    weapon_base.gd
    knife/
      knife_weapon.tscn   knife_weapon.gd
      knife_projectile.tscn   knife_projectile.gd
    orb/
      orb_weapon.tscn   orb_weapon.gd
      orb_shield.tscn   orb_shield.gd
    explosion/
      explosion_weapon.tscn   explosion_weapon.gd
      explosion.tscn   explosion.gd
  ui/
    hud.tscn   hud.gd
    level_up_ui.tscn   level_up_ui.gd
    death_screen.tscn   death_screen.gd
```

---

## Task 1: Project Configuration

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Configure window, collision layers, and WASD input**

  Use godot-ai MCP `project_manage` with `op=settings_set` to apply:

  ```
  display/window/size/viewport_width = 1280
  display/window/size/viewport_height = 720
  display/window/size/resizable = false

  layer_names/2d_physics/layer_1 = "world"
  layer_names/2d_physics/layer_2 = "player"
  layer_names/2d_physics/layer_3 = "enemy"
  layer_names/2d_physics/layer_4 = "projectile"
  layer_names/2d_physics/layer_5 = "xp_gem"

  input/move_left = {"deadzone": 0.5, "events": [InputEventKey with keycode=KEY_A, InputEventKey with keycode=KEY_LEFT]}
  input/move_right = {"deadzone": 0.5, "events": [InputEventKey with keycode=KEY_D, InputEventKey with keycode=KEY_RIGHT]}
  input/move_up = {"deadzone": 0.5, "events": [InputEventKey with keycode=KEY_W, InputEventKey with keycode=KEY_UP]}
  input/move_down = {"deadzone": 0.5, "events": [InputEventKey with keycode=KEY_S, InputEventKey with keycode=KEY_DOWN]}
  ```

  **Simpler alternative** — directly edit `project.godot` by appending these sections (keep existing content):

  ```ini
  [display]

  window/size/viewport_width=1280
  window/size/viewport_height=720
  window/size/resizable=false

  [layer_names]

  2d_physics/layer_1="world"
  2d_physics/layer_2="player"
  2d_physics/layer_3="enemy"
  2d_physics/layer_4="projectile"
  2d_physics/layer_5="xp_gem"

  [input]

  move_left={
  "deadzone": 0.5,
  "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":65,"physical_keycode":0,"key_label":0,"unicode":97,"location":0,"echo":false,"script":null)
  ]
  }
  move_right={
  "deadzone": 0.5,
  "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":68,"physical_keycode":0,"key_label":0,"unicode":100,"location":0,"echo":false,"script":null)
  ]
  }
  move_up={
  "deadzone": 0.5,
  "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":87,"physical_keycode":0,"key_label":0,"unicode":119,"location":0,"echo":false,"script":null)
  ]
  }
  move_down={
  "deadzone": 0.5,
  "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":83,"physical_keycode":0,"key_label":0,"unicode":115,"location":0,"echo":false,"script":null)
  ]
  }
  ```

- [ ] **Step 2: Register GameManager autoload in project.godot**

  Add to the `[autoload]` section (after the existing `_mcp_game_helper` line):

  ```ini
  GameManager="*res://autoloads/game_manager.gd"
  ```

- [ ] **Step 3: Verify**

  Open Godot editor. Check:
  - Project Settings → Display → Window: 1280×720
  - Project Settings → Layer Names → 2D Physics: layer 1=world, 2=player, 3=enemy, 4=projectile, 5=xp_gem
  - Project Settings → Input Map: move_left/right/up/down exist with WASD keys
  - Project Settings → Autoload: GameManager listed

---

## Task 2: GameManager Autoload

**Files:**
- Create: `autoloads/game_manager.gd`

- [ ] **Step 1: Create directory and write script**

  ```gdscript
  # autoloads/game_manager.gd
  extends Node

  enum State { PLAYING, LEVEL_UP, DEAD }

  signal level_up_triggered
  signal game_over_triggered

  var current_state: State = State.PLAYING
  var elapsed_time: float = 0.0

  func _ready() -> void:
      process_mode = Node.PROCESS_MODE_ALWAYS

  func _process(delta: float) -> void:
      if current_state == State.PLAYING:
          elapsed_time += delta

  func trigger_level_up() -> void:
      if current_state != State.PLAYING:
          return
      current_state = State.LEVEL_UP
      get_tree().paused = true
      level_up_triggered.emit()

  func resume_game() -> void:
      current_state = State.PLAYING
      get_tree().paused = false

  func game_over() -> void:
      if current_state == State.DEAD:
          return
      current_state = State.DEAD
      game_over_triggered.emit()

  func restart() -> void:
      elapsed_time = 0.0
      current_state = State.PLAYING
      get_tree().paused = false
      get_tree().reload_current_scene()
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add autoloads/game_manager.gd project.godot
  git commit -m "feat: project config + GameManager autoload"
  ```

---

## Task 3: Arena Scene

**Files:**
- Create: `scenes/arena/arena.tscn`

- [ ] **Step 1: Create arena scene via godot-ai MCP**

  Use `scene_manage` with `op=create_scene`:
  - Root type: `Node2D`
  - Name: `Arena`
  - Path: `res://scenes/arena/arena.tscn`

- [ ] **Step 2: Add background ColorRect**

  Use `node_create` to add `ColorRect` as child of Arena:
  - Name: `Background`
  - Properties:
    - `color`: `Color(0.12, 0.12, 0.15, 1)` (dark blue-grey)
    - `size`: `Vector2(1280, 720)`
    - `position`: `Vector2(0, 0)`

- [ ] **Step 3: Add 4 boundary walls (StaticBody2D)**

  Create each wall as `StaticBody2D` child of Arena, then add `CollisionShape2D` child to each:

  **WallTop** (StaticBody2D):
  - `collision_layer = 1` (world), `collision_mask = 0`
  - `position = Vector2(640, -5)`
  - Child CollisionShape2D: `RectangleShape2D` size `Vector2(1280, 10)`

  **WallBottom** (StaticBody2D):
  - `collision_layer = 1`, `collision_mask = 0`
  - `position = Vector2(640, 725)`
  - Child CollisionShape2D: `RectangleShape2D` size `Vector2(1280, 10)`

  **WallLeft** (StaticBody2D):
  - `collision_layer = 1`, `collision_mask = 0`
  - `position = Vector2(-5, 360)`
  - Child CollisionShape2D: `RectangleShape2D` size `Vector2(10, 720)`

  **WallRight** (StaticBody2D):
  - `collision_layer = 1`, `collision_mask = 0`
  - `position = Vector2(1285, 360)`
  - Child CollisionShape2D: `RectangleShape2D` size `Vector2(10, 720)`

- [ ] **Step 4: Save scene**

  Use `scene_save` to save `res://scenes/arena/arena.tscn`.

- [ ] **Step 5: Commit**

  ```bash
  git add scenes/arena/arena.tscn
  git commit -m "feat: arena scene with boundary walls"
  ```

---

## Task 4: Player Script & Scene

**Files:**
- Create: `scenes/player/player.gd`
- Create: `scenes/player/player.tscn`

- [ ] **Step 1: Write player script**

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

  @onready var hurt_box: Area2D = $HurtBox

  func _physics_process(delta: float) -> void:
      var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
      velocity = dir * SPEED
      move_and_slide()
      _check_contact_damage(delta)

  func _check_contact_damage(delta: float) -> void:
      for body in hurt_box.get_overlapping_bodies():
          if body.is_in_group("enemies"):
              take_damage((body as Enemy).CONTACT_DAMAGE * delta)
              break

  func take_damage(amount: float) -> void:
      if _dead:
          return
      hp = max(0.0, hp - amount)
      if hp <= 0.0:
          _dead = true
          died.emit()

  func add_xp(amount: float) -> void:
      xp += amount
      if xp >= xp_threshold:
          xp -= xp_threshold
          xp_threshold *= 1.2
          level += 1
          leveled_up.emit(level)

  func get_xp_percent() -> float:
      return xp / xp_threshold

  func add_weapon(weapon_scene: PackedScene) -> void:
      var weapon := weapon_scene.instantiate()
      add_child(weapon)
  ```

- [ ] **Step 2: Create player scene via godot-ai MCP**

  Root: `CharacterBody2D`, name `Player`, path `res://scenes/player/player.tscn`

  Node structure:
  ```
  Player (CharacterBody2D)
  ├── Sprite2D           # placeholder: modulate=Color(0.2,0.6,1), use a simple colored rect
  ├── CollisionShape2D   # CapsuleShape2D radius=12, height=24
  └── HurtBox (Area2D)
      └── CollisionShape2D  # CapsuleShape2D radius=12, height=24
  ```

  Properties to set on `Player`:
  - `collision_layer = 2` (player)
  - `collision_mask = 1` (world — so player is blocked by walls)
  - `script = res://scenes/player/player.gd`
  - Add to group `"player"`

  Properties to set on `HurtBox` (Area2D):
  - `collision_layer = 2` (player)
  - `collision_mask = 4` (enemy layer = bit 2 = value 4)
  - `monitoring = true`
  - `monitorable = false`

  For `Sprite2D` placeholder: set `texture = preload("res://icon.svg")` and `modulate = Color(0.2, 0.6, 1.0)`, `scale = Vector2(0.3, 0.3)` to keep it small. All Sprite2D placeholders in this plan use the same approach (modulate for color, icon.svg for texture).

- [ ] **Step 3: Save and verify**

  Save `res://scenes/player/player.tscn`. Open in Godot editor and run the scene alone (F6). Press WASD — player should move and be blocked by nothing (no walls in this scene). No errors in console.

- [ ] **Step 4: Commit**

  ```bash
  git add scenes/player/player.gd scenes/player/player.tscn
  git commit -m "feat: player movement, HP, XP, weapon slots"
  ```

---

## Task 5: Enemy Script & Scene

**Files:**
- Create: `scenes/enemies/enemy.gd`
- Create: `scenes/enemies/enemy.tscn`

- [ ] **Step 1: Write enemy script**

  ```gdscript
  # scenes/enemies/enemy.gd
  class_name Enemy
  extends CharacterBody2D

  signal died(position: Vector2)

  const SPEED: float = 80.0
  const MAX_HP: float = 20.0
  const CONTACT_DAMAGE: float = 8.0

  var hp: float = MAX_HP
  var _player: Node2D = null

  func _ready() -> void:
      _player = get_tree().get_first_node_in_group("player")

  func _physics_process(_delta: float) -> void:
      if _player == null:
          return
      var dir := (_player.global_position - global_position).normalized()
      velocity = dir * SPEED
      move_and_slide()

  func take_damage(amount: float) -> void:
      hp -= amount
      if hp <= 0.0:
          died.emit(global_position)
          queue_free()
  ```

- [ ] **Step 2: Create enemy scene via godot-ai MCP**

  Root: `CharacterBody2D`, name `Enemy`, path `res://scenes/enemies/enemy.tscn`

  Node structure:
  ```
  Enemy (CharacterBody2D)
  ├── Sprite2D           # modulate=Color(1, 0.2, 0.2) — red placeholder
  └── CollisionShape2D   # CapsuleShape2D radius=10, height=20
  ```

  Properties on `Enemy`:
  - `collision_layer = 4` (enemy, use bit 3 → value 4)
  - `collision_mask = 3` (world=1 + player=2 → value 3)
  - `script = res://scenes/enemies/enemy.gd`
  - Add to group `"enemies"`

  > **Note on collision layers:** Godot uses bitmasks. Layer 1 = bit 0 = value 1. Layer 2 = bit 1 = value 2. Layer 3 = bit 2 = value 4. Layer 4 = bit 3 = value 8. Layer 5 = bit 4 = value 16.
  >
  > So: player layer=2 mask=1, enemy layer=4 mask=3 (world+player), projectile layer=8 mask=4 (enemy), xp_gem layer=16 mask=2 (player).
  >
  > **Use these bit values throughout all tasks.**

- [ ] **Step 3: Commit**

  ```bash
  git add scenes/enemies/enemy.gd scenes/enemies/enemy.tscn
  git commit -m "feat: enemy movement and take_damage"
  ```

---

## Task 6: EnemySpawner Script

**Files:**
- Create: `scenes/enemies/enemy_spawner.gd`

- [ ] **Step 1: Write spawner script**

  ```gdscript
  # scenes/enemies/enemy_spawner.gd
  extends Node

  const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")
  const XP_GEM_SCENE = preload("res://scenes/collectibles/xp_gem.tscn")

  const INITIAL_INTERVAL: float = 1.5
  const SCALE_INTERVAL: float = 20.0
  const SCALE_FACTOR: float = 0.85
  const MIN_INTERVAL: float = 0.3
  const MAX_ENEMIES: int = 200
  const ARENA_W: float = 1280.0
  const ARENA_H: float = 720.0
  const SPAWN_MARGIN: float = 20.0

  var _spawn_timer: float = 0.0
  var _scale_timer: float = 0.0
  var _spawn_interval: float = INITIAL_INTERVAL
  var _ysort: Node = null

  func _ready() -> void:
      _ysort = get_tree().get_first_node_in_group("ysort")

  func _process(delta: float) -> void:
      if GameManager.current_state != GameManager.State.PLAYING:
          return
      _spawn_timer += delta
      _scale_timer += delta
      if _scale_timer >= SCALE_INTERVAL:
          _scale_timer = 0.0
          _spawn_interval = max(_spawn_interval * SCALE_FACTOR, MIN_INTERVAL)
      if _spawn_timer >= _spawn_interval:
          _spawn_timer = 0.0
          _try_spawn()

  func _try_spawn() -> void:
      if get_tree().get_nodes_in_group("enemies").size() >= MAX_ENEMIES:
          return
      var enemy := ENEMY_SCENE.instantiate()
      _ysort.add_child(enemy)
      enemy.global_position = _random_edge_pos()
      enemy.died.connect(_on_enemy_died)

  func _on_enemy_died(pos: Vector2) -> void:
      var gem := XP_GEM_SCENE.instantiate()
      _ysort.add_child(gem)
      gem.global_position = pos

  func _random_edge_pos() -> Vector2:
      match randi() % 4:
          0: return Vector2(randf_range(0.0, ARENA_W), -SPAWN_MARGIN)
          1: return Vector2(randf_range(0.0, ARENA_W), ARENA_H + SPAWN_MARGIN)
          2: return Vector2(-SPAWN_MARGIN, randf_range(0.0, ARENA_H))
          _: return Vector2(ARENA_W + SPAWN_MARGIN, randf_range(0.0, ARENA_H))
  ```

  > **Note:** This script `preload`s both `enemy.tscn` and `xp_gem.tscn`. Complete Task 7 (XPGem) before running.

- [ ] **Step 2: Commit**

  ```bash
  git add scenes/enemies/enemy_spawner.gd
  git commit -m "feat: enemy spawner with difficulty scaling"
  ```

---

## Task 7: XPGem Script & Scene

**Files:**
- Create: `scenes/collectibles/xp_gem.gd`
- Create: `scenes/collectibles/xp_gem.tscn`

- [ ] **Step 1: Write XPGem script**

  ```gdscript
  # scenes/collectibles/xp_gem.gd
  extends Node2D

  const XP_VALUE: float = 10.0
  const MAGNET_RADIUS: float = 80.0
  const MAGNET_SPEED: float = 300.0
  const COLLECT_DIST: float = 8.0

  var _player: Node2D = null
  var _magnetized: bool = false

  func _ready() -> void:
      _player = get_tree().get_first_node_in_group("player")

  func _process(delta: float) -> void:
      if _player == null:
          return
      var dist := global_position.distance_to(_player.global_position)
      if dist <= MAGNET_RADIUS:
          _magnetized = true
      if _magnetized:
          var dir := (_player.global_position - global_position).normalized()
          global_position += dir * MAGNET_SPEED * delta
          if global_position.distance_to(_player.global_position) <= COLLECT_DIST:
              _player.add_xp(XP_VALUE)
              queue_free()
  ```

- [ ] **Step 2: Create XPGem scene via godot-ai MCP**

  Root: `Node2D`, name `XPGem`, path `res://scenes/collectibles/xp_gem.tscn`

  Node structure:
  ```
  XPGem (Node2D)
  └── Sprite2D   # modulate=Color(0.2, 1.0, 0.4) — green placeholder, small scale
  ```

  Properties on `XPGem`:
  - `script = res://scenes/collectibles/xp_gem.gd`

- [ ] **Step 3: Commit**

  ```bash
  git add scenes/collectibles/xp_gem.gd scenes/collectibles/xp_gem.tscn
  git commit -m "feat: xp gem with magnetic collection"
  ```

---

## Task 8: WeaponBase + KnifeWeapon

**Files:**
- Create: `scenes/weapons/weapon_base.gd`
- Create: `scenes/weapons/knife/knife_projectile.gd`
- Create: `scenes/weapons/knife/knife_projectile.tscn`
- Create: `scenes/weapons/knife/knife_weapon.gd`
- Create: `scenes/weapons/knife/knife_weapon.tscn`

- [ ] **Step 1: Write WeaponBase**

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
      if _timer >= cooldown:
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

- [ ] **Step 2: Write KnifeProjectile script**

  ```gdscript
  # scenes/weapons/knife/knife_projectile.gd
  extends Area2D

  const SPEED: float = 400.0
  const DAMAGE: float = 15.0
  const LIFETIME: float = 3.0

  var direction: Vector2 = Vector2.RIGHT
  var _age: float = 0.0

  func _ready() -> void:
      body_entered.connect(_on_body_entered)

  func _process(delta: float) -> void:
      global_position += direction * SPEED * delta
      _age += delta
      if _age >= LIFETIME:
          queue_free()

  func _on_body_entered(body: Node) -> void:
      if body.is_in_group("enemies"):
          (body as Enemy).take_damage(DAMAGE)
          queue_free()
  ```

- [ ] **Step 3: Create KnifeProjectile scene via godot-ai MCP**

  Root: `Area2D`, name `KnifeProjectile`, path `res://scenes/weapons/knife/knife_projectile.tscn`

  ```
  KnifeProjectile (Area2D)
  ├── Sprite2D            # modulate=Color(1,1,0.2) — yellow, small
  └── CollisionShape2D    # RectangleShape2D size=Vector2(12, 4)
  ```

  Properties on `KnifeProjectile`:
  - `collision_layer = 8` (projectile bit 4 = 8)
  - `collision_mask = 4` (enemy bit 3 = 4)
  - `monitoring = true`
  - `script = res://scenes/weapons/knife/knife_projectile.gd`

- [ ] **Step 4: Write KnifeWeapon script**

  ```gdscript
  # scenes/weapons/knife/knife_weapon.gd
  class_name KnifeWeapon
  extends WeaponBase

  const PROJECTILE_SCENE = preload("res://scenes/weapons/knife/knife_projectile.tscn")

  func _ready() -> void:
      cooldown = 1.0

  func attack() -> void:
      var target := get_nearest_enemy()
      if target == null:
          return
      var projectile := PROJECTILE_SCENE.instantiate() as Area2D
      get_ysort().add_child(projectile)
      projectile.global_position = _player.global_position
      projectile.direction = (_player.global_position.direction_to(target.global_position))
  ```

- [ ] **Step 5: Create KnifeWeapon scene via godot-ai MCP**

  Root: `Node`, name `KnifeWeapon`, path `res://scenes/weapons/knife/knife_weapon.tscn`
  - `script = res://scenes/weapons/knife/knife_weapon.gd`

- [ ] **Step 6: Commit**

  ```bash
  git add scenes/weapons/weapon_base.gd scenes/weapons/knife/
  git commit -m "feat: weapon base + knife weapon"
  ```

---

## Task 9: OrbWeapon

**Files:**
- Create: `scenes/weapons/orb/orb_shield.gd`
- Create: `scenes/weapons/orb/orb_shield.tscn`
- Create: `scenes/weapons/orb/orb_weapon.gd`
- Create: `scenes/weapons/orb/orb_weapon.tscn`

- [ ] **Step 1: Write OrbShield script**

  ```gdscript
  # scenes/weapons/orb/orb_shield.gd
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

- [ ] **Step 2: Create OrbShield scene via godot-ai MCP**

  Root: `Node2D`, name `OrbShield`, path `res://scenes/weapons/orb/orb_shield.tscn`

  ```
  OrbShield (Node2D)
  └── Sprite2D   # modulate=Color(0.6, 0.2, 1.0) — purple, small circle placeholder
  ```

  - `script = res://scenes/weapons/orb/orb_shield.gd`

- [ ] **Step 3: Write OrbWeapon script**

  ```gdscript
  # scenes/weapons/orb/orb_weapon.gd
  class_name OrbWeapon
  extends WeaponBase

  const ORB_SCENE = preload("res://scenes/weapons/orb/orb_shield.tscn")
  const NUM_ORBS: int = 2

  func _ready() -> void:
      cooldown = 9999.0  # timer never fires; orbs are permanent
      for i in range(NUM_ORBS):
          var orb := ORB_SCENE.instantiate()
          get_parent().add_child(orb)
          orb.orbit_index = i
          orb.total_orbs = NUM_ORBS

  func attack() -> void:
      pass  # orbs handle themselves
  ```

- [ ] **Step 4: Create OrbWeapon scene via godot-ai MCP**

  Root: `Node`, name `OrbWeapon`, path `res://scenes/weapons/orb/orb_weapon.tscn`
  - `script = res://scenes/weapons/orb/orb_weapon.gd`

- [ ] **Step 5: Commit**

  ```bash
  git add scenes/weapons/orb/
  git commit -m "feat: orb weapon with hit cooldown"
  ```

---

## Task 10: ExplosionWeapon

**Files:**
- Create: `scenes/weapons/explosion/explosion.gd`
- Create: `scenes/weapons/explosion/explosion.tscn`
- Create: `scenes/weapons/explosion/explosion_weapon.gd`
- Create: `scenes/weapons/explosion/explosion_weapon.tscn`

- [ ] **Step 1: Write Explosion script**

  ```gdscript
  # scenes/weapons/explosion/explosion.gd
  extends Node2D

  const DAMAGE: float = 40.0
  const RADIUS: float = 80.0
  const LIFETIME: float = 0.35

  var _age: float = 0.0

  func _ready() -> void:
      _apply_damage()

  func _process(delta: float) -> void:
      _age += delta
      scale = Vector2.ONE * (1.0 + _age / LIFETIME * 0.5)
      modulate.a = 1.0 - (_age / LIFETIME)
      if _age >= LIFETIME:
          queue_free()

  func _apply_damage() -> void:
      for enemy in get_tree().get_nodes_in_group("enemies"):
          if global_position.distance_to((enemy as Node2D).global_position) <= RADIUS:
              (enemy as Enemy).take_damage(DAMAGE)
  ```

- [ ] **Step 2: Create Explosion scene via godot-ai MCP**

  Root: `Node2D`, name `Explosion`, path `res://scenes/weapons/explosion/explosion.tscn`

  ```
  Explosion (Node2D)
  └── Sprite2D   # modulate=Color(1, 0.5, 0.1) — orange, larger scale (e.g. scale=Vector2(4,4))
  ```

  - `script = res://scenes/weapons/explosion/explosion.gd`

- [ ] **Step 3: Write ExplosionWeapon script**

  ```gdscript
  # scenes/weapons/explosion/explosion_weapon.gd
  class_name ExplosionWeapon
  extends WeaponBase

  const EXPLOSION_SCENE = preload("res://scenes/weapons/explosion/explosion.tscn")

  func _ready() -> void:
      cooldown = 3.0

  func attack() -> void:
      var target := get_nearest_enemy()
      if target == null:
          return
      var explosion := EXPLOSION_SCENE.instantiate()
      get_ysort().add_child(explosion)
      explosion.global_position = target.global_position
  ```

- [ ] **Step 4: Create ExplosionWeapon scene via godot-ai MCP**

  Root: `Node`, name `ExplosionWeapon`, path `res://scenes/weapons/explosion/explosion_weapon.tscn`
  - `script = res://scenes/weapons/explosion/explosion_weapon.gd`

- [ ] **Step 5: Commit**

  ```bash
  git add scenes/weapons/explosion/
  git commit -m "feat: explosion weapon with AOE damage"
  ```

---

## Task 11: HUD

**Files:**
- Create: `scenes/ui/hud.gd`
- Create: `scenes/ui/hud.tscn`

- [ ] **Step 1: Write HUD script**

  ```gdscript
  # scenes/ui/hud.gd
  extends CanvasLayer

  @onready var hp_bar: ProgressBar = $HPBar
  @onready var xp_bar: ProgressBar = $XPBar
  @onready var timer_label: Label = $TimerLabel
  @onready var level_label: Label = $LevelLabel

  var _player: Player = null

  func _ready() -> void:
      add_to_group("hud")
      _player = get_tree().get_first_node_in_group("player") as Player

  func _process(_delta: float) -> void:
      if _player == null:
          return
      hp_bar.value = (_player.hp / _player.max_hp) * 100.0
      xp_bar.value = _player.get_xp_percent() * 100.0
      level_label.text = "Lv.%d" % _player.level
      var t := int(GameManager.elapsed_time)
      timer_label.text = "%02d:%02d" % [t / 60, t % 60]
  ```

- [ ] **Step 2: Create HUD scene via godot-ai MCP**

  Root: `CanvasLayer`, name `HUD`, path `res://scenes/ui/hud.tscn`
  - `script = res://scenes/ui/hud.gd`
  - `layer = 1`

  Node structure:
  ```
  HUD (CanvasLayer)
  ├── HPBar (ProgressBar)
  │     anchors: left=0, top=0 | offset: left=10, top=10, right=200, bottom=28
  │     min_value=0, max_value=100, value=100
  ├── TimerLabel (Label)
  │     anchors: left=0.5, top=0 | offset: left=-40, top=8, right=40, bottom=30
  │     text="00:00", horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
  ├── LevelLabel (Label)
  │     anchors: right=1, top=0 | offset: left=-70, top=8, right=-10, bottom=30
  │     text="Lv.1", horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
  └── XPBar (ProgressBar)
        anchors: left=0, right=1, bottom=1 | offset: left=0, top=-20, right=0, bottom=0
        min_value=0, max_value=100, value=0
  ```

  > For anchors in Godot 4: set `anchor_left`, `anchor_top`, `anchor_right`, `anchor_bottom` and offset properties via `node_set_property`.

- [ ] **Step 3: Commit**

  ```bash
  git add scenes/ui/hud.gd scenes/ui/hud.tscn
  git commit -m "feat: HUD with HP/XP bars, timer, level"
  ```

---

## Task 12: LevelUpUI

**Files:**
- Create: `scenes/ui/level_up_ui.gd`
- Create: `scenes/ui/level_up_ui.tscn`

- [ ] **Step 1: Write LevelUpUI script**

  ```gdscript
  # scenes/ui/level_up_ui.gd
  extends CanvasLayer

  const WEAPON_REGISTRY: Array[Dictionary] = [
      {
          "id": "knife",
          "name": "飞刀",
          "desc": "朝最近敌人射出飞刀",
          "scene": "res://scenes/weapons/knife/knife_weapon.tscn"
      },
      {
          "id": "orb",
          "name": "护盾球",
          "desc": "绕身旋转的能量球",
          "scene": "res://scenes/weapons/orb/orb_weapon.tscn"
      },
      {
          "id": "explosion",
          "name": "爆炸",
          "desc": "随机位置触发范围爆炸",
          "scene": "res://scenes/weapons/explosion/explosion_weapon.tscn"
      }
  ]

  @onready var card_container: HBoxContainer = $BG/Panel/CardContainer

  func _ready() -> void:
      process_mode = Node.PROCESS_MODE_ALWAYS
      visible = false
      GameManager.level_up_triggered.connect(_on_level_up)

  func _on_level_up() -> void:
      visible = true
      _build_cards()

  func _build_cards() -> void:
      for child in card_container.get_children():
          child.queue_free()
      for data in WEAPON_REGISTRY:
          var btn := Button.new()
          btn.text = "%s\n%s" % [data["name"], data["desc"]]
          btn.custom_minimum_size = Vector2(160, 100)
          btn.pressed.connect(_on_weapon_picked.bind(data["scene"]))
          card_container.add_child(btn)

  func _on_weapon_picked(scene_path: String) -> void:
      visible = false
      var player := get_tree().get_first_node_in_group("player") as Player
      player.add_weapon(load(scene_path))
      GameManager.resume_game()
  ```

- [ ] **Step 2: Create LevelUpUI scene via godot-ai MCP**

  Root: `CanvasLayer`, name `LevelUpUI`, path `res://scenes/ui/level_up_ui.tscn`
  - `script = res://scenes/ui/level_up_ui.gd`
  - `layer = 10`

  Node structure:
  ```
  LevelUpUI (CanvasLayer)
  └── BG (ColorRect)
        anchors: fill entire screen (0,0,1,1)
        color: Color(0, 0, 0, 0.6)
      └── Panel (VBoxContainer)
            anchors: centered, size≈520×180
            alignment: center
          ├── TitleLabel (Label)  text="升级！选择武器"  horizontal_alignment=center
          └── CardContainer (HBoxContainer)  alignment=center  separation=12
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add scenes/ui/level_up_ui.gd scenes/ui/level_up_ui.tscn
  git commit -m "feat: level-up weapon selection UI"
  ```

---

## Task 13: DeathScreen

**Files:**
- Create: `scenes/ui/death_screen.gd`
- Create: `scenes/ui/death_screen.tscn`

- [ ] **Step 1: Write DeathScreen script**

  ```gdscript
  # scenes/ui/death_screen.gd
  extends CanvasLayer

  @onready var time_label: Label = $BG/Panel/TimeLabel
  @onready var level_label: Label = $BG/Panel/LevelLabel
  @onready var restart_btn: Button = $BG/Panel/RestartButton

  func _ready() -> void:
      process_mode = Node.PROCESS_MODE_ALWAYS
      visible = false
      GameManager.game_over_triggered.connect(_on_game_over)
      restart_btn.pressed.connect(GameManager.restart)

  func _on_game_over() -> void:
      visible = true
      var player := get_tree().get_first_node_in_group("player") as Player
      level_label.text = "达到等级：%d" % player.level
      var t := int(GameManager.elapsed_time)
      time_label.text = "存活时长：%02d:%02d" % [t / 60, t % 60]
  ```

- [ ] **Step 2: Create DeathScreen scene via godot-ai MCP**

  Root: `CanvasLayer`, name `DeathScreen`, path `res://scenes/ui/death_screen.tscn`
  - `script = res://scenes/ui/death_screen.gd`
  - `layer = 20`

  Node structure:
  ```
  DeathScreen (CanvasLayer)
  └── BG (ColorRect)
        anchors: fill screen (0,0,1,1)
        color: Color(0, 0, 0, 0.8)
      └── Panel (VBoxContainer)
            anchors: centered, size≈300×200
          ├── TitleLabel (Label)  text="游戏结束"
          ├── TimeLabel (Label)   text="存活时长：--"
          ├── LevelLabel (Label)  text="达到等级：--"
          └── RestartButton (Button)  text="重新开始"
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add scenes/ui/death_screen.gd scenes/ui/death_screen.tscn
  git commit -m "feat: death screen with stats and restart"
  ```

---

## Task 14: Main Scene Assembly

**Files:**
- Create: `scenes/main/main.gd`
- Create: `scenes/main/main.tscn`
- Modify: `project.godot`

- [ ] **Step 1: Write main.gd**

  ```gdscript
  # scenes/main/main.gd
  extends Node

  func _ready() -> void:
      var player := $YSort/Player as Player
      player.leveled_up.connect(func(_lvl: int): GameManager.trigger_level_up())
      player.died.connect(GameManager.game_over)
  ```

- [ ] **Step 2: Create Main scene via godot-ai MCP**

  Root: `Node`, name `Main`, path `res://scenes/main/main.tscn`
  - `script = res://scenes/main/main.gd`

  Node structure:
  ```
  Main (Node)
  ├── Arena           (instance of res://scenes/arena/arena.tscn)
  ├── EnemySpawner    (Node with script res://scenes/enemies/enemy_spawner.gd)
  ├── YSort           (Node2D — add to group "ysort")
  │   └── Player      (instance of res://scenes/player/player.tscn)
  │                   position: Vector2(640, 360)
  ├── HUD             (instance of res://scenes/ui/hud.tscn)
  ├── LevelUpUI       (instance of res://scenes/ui/level_up_ui.tscn)
  └── DeathScreen     (instance of res://scenes/ui/death_screen.tscn)
  ```

  Step-by-step MCP calls:
  1. `scene_manage op=create_scene` → root=Node, name=Main, path=`res://scenes/main/main.tscn`
  2. `node_create` → instance Arena tscn as child of Main
  3. `node_create` → Node child of Main, name=EnemySpawner, script=`res://scenes/enemies/enemy_spawner.gd`
  4. `node_create` → Node2D child of Main, name=YSort
  5. `node_manage op=add_to_group` → YSort to group `"ysort"`
  6. `node_create` → instance Player tscn as child of YSort
  7. `node_set_property` → Player.position = Vector2(640, 360)
  8. `node_create` → instance HUD tscn as child of Main
  9. `node_create` → instance LevelUpUI tscn as child of Main
  10. `node_create` → instance DeathScreen tscn as child of Main
  11. `script_attach` → attach `res://scenes/main/main.gd` to Main node
  12. `scene_save` → save `res://scenes/main/main.tscn`

- [ ] **Step 3: Set main.tscn as the run scene**

  Add to `project.godot` under `[application]`:
  ```ini
  run/main_scene="res://scenes/main/main.tscn"
  ```

- [ ] **Step 4: Run the game (F5)**

  Expected behavior:
  - Dark background, blue player square in center
  - WASD moves player, blocked by arena walls
  - Red enemy circles spawn from edges and chase the player
  - Green XP gems drop when enemies are killed (but nothing kills them yet — test manually via console or just wait to verify spawning)
  - No console errors

- [ ] **Step 5: Commit**

  ```bash
  git add scenes/main/main.gd scenes/main/main.tscn project.godot
  git commit -m "feat: main scene assembly — game is runnable"
  ```

---

## Task 15: MVP Verification

- [ ] **Step 1: WASD 移动**

  Run (F5). Press WASD — player moves. Player stops at arena walls. ✓

- [ ] **Step 2: 自动武器攻击**

  Verify a weapon spawns when leveling up. As a quick test: in `player.gd` `_ready()`, temporarily add:
  ```gdscript
  func _ready() -> void:
      add_weapon(load("res://scenes/weapons/knife/knife_weapon.tscn"))
  ```
  Run game — yellow projectiles should fire at nearby enemies after 1 second. Remove this line after verifying.

- [ ] **Step 3: 敌人生成并追逐**

  Run game for 10 seconds. Red enemies appear from edges and move toward player. ✓

- [ ] **Step 4: XP 宝石收集**

  Wait for an enemy to be killed by a knife projectile. Green gem drops, moves toward player when near, disappears on contact. XP bar in HUD increases. ✓

- [ ] **Step 5: 升级界面显示 3 种武器**

  Collect enough XP to fill the bar (100 XP = 10 gems). Game pauses. 3 weapon buttons appear: 飞刀 / 护盾球 / 爆炸. ✓

- [ ] **Step 6: 武器选中后实际生效**

  Pick 飞刀 — projectiles start firing. Pick 护盾球 — two orbs orbit the player. Pick 爆炸 — explosion flashes appear near enemies. ✓

- [ ] **Step 7: 死亡界面可重开**

  Let enemies touch the player until HP reaches 0. Death screen shows survival time and level reached. Click "重新开始" — game resets and restarts. ✓

- [ ] **Step 8: 最终 commit**

  ```bash
  git add -A
  git commit -m "feat: VSL MVP prototype complete — core loop verified"
  ```

---

## 已知限制（原型范围内可接受）

- **武器重复选择：** 三种武器全选后再升级，会有重复武器叠加（多把飞刀）。可以接受，不影响验证核心循环。
- **无敌帧：** 玩家无受击无敌帧，快速被多只敌人围攻时 HP 掉很快。可以接受，后期加 iFrames。
- **无敌人死亡动画：** 敌人被杀后直接消失。Placeholder 行为。
- **YSort 未激活：** `Node2D` 的 YSort 在 Godot 4 中需确认是否需要改用内置排序行为，否则视觉层级可能有问题。简单处理：使用 `Node2D` 即可，不影响玩法。
