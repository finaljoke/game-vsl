# Game Feel 系统设计文档

**日期：** 2026-06-14  
**项目：** game_0_vsl（Vampire Survivors-like 原型）  
**目标：** 通过 GameFeel 信号总线为游戏添加视觉与音效反馈，使游戏"越玩越爽"，同时保持后期扩展零成本

---

## 1. 架构：GameFeel Autoload 信号总线

新建一个 `GameFeel` Autoload，承担两个职责：

1. **信号声明**：其他脚本 emit 信号，不需要知道后续效果
2. **效果执行**：接收信号后触发对应视觉/音效

### 信号清单

| 信号 | 参数 | 发出方 |
|------|------|--------|
| `enemy_hit` | `amount: float, position: Vector2, enemy: Node2D` | `enemy.gd` |
| `enemy_died` | `position: Vector2` | `enemy.gd` |
| `player_hit` | `amount: float` | `player.gd` |
| `player_leveled_up` | `level: int` | `player.gd` |
| `xp_collected` | `position: Vector2` | `xp_gem.gd` |

### 信号流

```
enemy.gd  →  GameFeel.enemy_hit      →  敌人白光闪烁 + 伤害飘字 + 击中音效
enemy.gd  →  GameFeel.enemy_died     →  死亡粒子 + 死亡音效 + 轻微震动
player.gd →  GameFeel.player_hit     →  屏幕震动（强）+ 玩家红光 + 受伤音效
player.gd →  GameFeel.player_leveled_up → 升级音效 + 屏幕白闪
xp_gem.gd →  GameFeel.xp_collected  →  收集音效
```

**设计原则：** 现有脚本只需各加 1-2 行 emit，原逻辑零改动。新增武器/敌人类型自动继承全部手感效果。

---

## 2. 视觉效果系统

### 2.1 屏幕震动

- 实现：操作 `Camera2D` 的 `offset`，用 Tween 做指数衰减
- `player_hit` → magnitude 8, duration 0.3s
- `enemy_died` → magnitude 3, duration 0.1s
- `GameFeel._ready()` 通过 `get_viewport().get_camera_2d()` 获取相机引用

### 2.2 受击闪烁（敌人白光 / 玩家红光）

**敌人：** 收到 `enemy_hit` → `enemy.modulate = Color.WHITE` → 0.08s 后 Tween 回 `Color(1,1,1,1)`  
**玩家：** 收到 `player_hit` → `player.modulate = Color(1, 0.3, 0.3)` → 0.12s 后 Tween 回 `Color(1,1,1,1)`  
- 不使用 Shader，纯 modulate 足够
- GameFeel 通过 `get_tree().get_first_node_in_group("player")` 获取玩家引用（`_ready()` 时缓存）

### 2.3 死亡粒子

- 实现：代码动态创建 `CPUParticles2D`，加入主场景，播完自动 `queue_free()`
- 参数：8 颗粒子，向外爆散，生命周期 0.3s，橙黄色（`Color(1, 0.6, 0.1)`）
- 无需独立场景文件

### 2.4 伤害数字飘字

- 实现：独立场景 `damage_number.tscn`（Label + 描边字体）
- 动画：向上漂移 40px + 0.6s 渐出，完成后 `queue_free()`
- 内容：`str(int(amount))`，颜色白色，字号 16，加粗

### 2.5 升级屏幕白闪

- 实现：GameFeel 持有一个全屏 `ColorRect`（CanvasLayer 层），升级时显示白色并 0.15s 淡出
- 与屏幕震动同时触发（升级震动 magnitude 5）

---

## 3. 音效系统

### 音效文件（均从 bfxr.net 生成，CC0 授权）

| 文件 | bfxr 预设 | 触发时机 |
|------|-----------|----------|
| `hit.wav` | Hit/Hurt | 飞刀击中敌人 |
| `enemy_death.wav` | Explosion（调小） | 敌人死亡 |
| `xp_collect.wav` | Pickup/Coin | 拾取 XP 宝石 |
| `level_up.wav` | Powerup | 升级 |
| `player_hurt.wav` | Hit/Hurt（低沉） | 玩家受伤 |

- 格式：`.wav`（短音效，响应最快）
- 存放路径：`assets/audio/sfx/`
- **BGM 不在本次范围内**

### GameFeel 音效节点结构

`GameFeel` 场景下挂 5 个 `AudioStreamPlayer` 子节点，一对一对应上述音效文件。各节点独立，高频触发不互相打断。

Godot 导入设置：`.wav` 直接使用默认设置，所有音效 bus 设为 `"Master"`（后期可统一换为 `"SFX"` bus 调音量）。

---

## 4. 现有脚本改动

### `scenes/enemies/enemy.gd`（+2 行）

```gdscript
func take_damage(amount: float) -> void:
    hp -= amount
    GameFeel.enemy_hit.emit(amount, global_position, self)  # 新增
    if hp <= 0.0:
        GameFeel.enemy_died.emit(global_position)           # 新增
        died.emit(global_position)
        queue_free()
```

### `scenes/player/player.gd`（+2 行）

```gdscript
func take_damage(amount: float) -> void:
    if _dead:
        return
    hp = max(0.0, hp - amount)
    GameFeel.player_hit.emit(amount)                        # 新增
    if hp <= 0.0:
        _dead = true
        died.emit()

func add_xp(amount: float) -> void:
    xp += amount
    if xp >= xp_threshold:
        xp -= xp_threshold
        xp_threshold *= 1.2
        level += 1
        GameFeel.player_leveled_up.emit(level)              # 新增
        leveled_up.emit(level)
```

### `scenes/collectibles/xp_gem.gd`（+1 行）

```gdscript
if global_position.distance_to(_player.global_position) <= COLLECT_DIST:
    GameFeel.xp_collected.emit(global_position)             # 新增
    _player.add_xp(XP_VALUE)
    queue_free()
```

---

## 5. 文件结构

### 新建文件（6 个代码文件 + 5 个音效）

```
autoloads/
  game_feel.gd          ← GameFeel 主脚本（信号 + 所有效果逻辑）
  game_feel.tscn        ← Autoload 场景（含 5 个 AudioStreamPlayer 子节点）

scenes/ui/
  damage_number.gd      ← 飘字动画逻辑
  damage_number.tscn    ← Label 场景

assets/audio/sfx/
  hit.wav
  enemy_death.wav
  xp_collect.wav
  level_up.wav
  player_hurt.wav
```

### 修改文件（3 个）

```
scenes/enemies/enemy.gd
scenes/player/player.gd
scenes/collectibles/xp_gem.gd
```

### 项目设置

- `project.godot`：注册 `GameFeel`（路径 `autoloads/game_feel.tscn`）为 Autoload，节点名 `/root/GameFeel`

---

## 6. 手动操作（非代码）

音效文件需手动生成：

1. 打开 [bfxr.net](https://www.bfxr.net/)
2. 依次点击对应预设（Hit/Hurt、Explosion 等），调整至满意
3. 点击 "Export Wav" 下载
4. 重命名并放入 `assets/audio/sfx/`

其余所有内容均由代码实现，无需手动操作。
