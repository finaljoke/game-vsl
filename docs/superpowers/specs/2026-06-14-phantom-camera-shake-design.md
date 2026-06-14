# Phantom Camera Shake 替换设计

**目标：** 用 Phantom Camera 插件的 `PhantomCameraNoiseEmitter2D`（Perlin 噪声）替换 `game_feel.gd` 中手写的随机偏移震动逻辑，并同时为游戏首次添加有效的 `Camera2D`（当前场景没有 Camera2D，导致现有震动代码静默失效）。

**约束：**
- 固定 1280×720 竞技场，相机不跟随玩家（FollowMode.NONE）
- 保留 GameFeel 其他所有效果不变（闪光、粒子、伤害数字、音效）
- Phantom Camera 插件已安装：`addons/phantom_camera/`

---

## 架构

### 场景变更（main.tscn）

新增 3 个节点：

```
Main (Node)
├── Arena, EnemySpawner, YSort, HUD...（不变）
├── Camera2D                  ← 新增，position=(640,360)，anchor_mode=DRAG_CENTER
│   └── PhantomCameraHost     ← 新增，Camera2D 的子节点，桥接 PCam → Camera
└── PhantomCamera2D           ← 新增，FollowMode.NONE，priority=0
```

`Camera2D` 锁定在竞技场中心（640, 360），不设 limit，不跟随。`PhantomCameraHost` 是 Phantom Camera 系统必须的桥接节点，必须是 `Camera2D` 的直接子节点。

### game_feel.gd 变更

**删除（手写 shake 系统）：**
- 状态变量：`_shake_magnitude`、`_shake_decay`、`_camera`
- 方法：`_process()`、`_get_camera()`、`_shake()`

**新增（Phantom Camera shake）：**
- 成员变量：`_emitter_hit`、`_emitter_player`、`_emitter_levelup`（均为 `PhantomCameraNoiseEmitter2D`）
- 方法：`_setup_shake_emitters()`，在 `_ready()` 末尾调用，用代码创建 3 个 emitter 并 `add_child`

**信号处理函数改动：**

| 函数 | 删除 | 新增 |
|---|---|---|
| `_on_enemy_died` | `_shake(3.0, 0.1)` | `_emitter_hit.emit()` |
| `_on_player_hit` | `_shake(8.0, 0.3)` | `_emitter_player.emit()` |
| `_on_player_leveled_up` | `_shake(5.0, 0.2)` | `_emitter_levelup.emit()` |

---

## Emitter 参数配置

每个 emitter 绑定一个 `PhantomCameraNoise2D` 资源，用代码创建（不保存为 .tres 文件）。

| Emitter | 触发事件 | amplitude | frequency | duration | decay_time | rotational_noise |
|---|---|---|---|---|---|---|
| `_emitter_hit` | 敌人死亡（小震） | 4 | 8 | 0.08 | 0.05 | false |
| `_emitter_levelup` | 玩家升级（中震） | 10 | 6 | 0.15 | 0.10 | false |
| `_emitter_player` | 玩家受伤（大震+倾斜） | 18 | 5 | 0.25 | 0.15 | true |

说明：
- `amplitude`：Perlin 噪声的位移幅度（像素级别，trauma² 曲线，实际峰值约为 amplitude 的一半）
- `frequency`：噪声密度，值越高抖动越急促
- `duration`：全强度震动持续时间（秒）
- `decay_time`：从全强度衰减到 0 的时间（秒）
- `rotational_noise`：玩家受伤时加入轻微相机倾斜感

所有参数均为初始值，后续可在编辑器 Inspector 里实时调参（emitter 支持 preview 预览）。

---

## 文件清单

**修改：**
- `scenes/main/main.tscn` — 新增 Camera2D + PhantomCameraHost + PhantomCamera2D
- `autoloads/game_feel.gd` — 替换 shake 系统

**不变：**
- 其余所有文件

---

## 验收标准

| 触发动作 | 预期效果 |
|---|---|
| 飞刀击中敌人 | 无震动（仅伤害数字 + 白闪，与之前一致） |
| 敌人死亡 | 轻微短促震动（Perlin 噪声，比随机偏移更流畅） |
| 玩家受伤 | 强烈震动 + 轻微倾斜感 |
| 玩家升级 | 中等震动 + 白色全屏闪光 |
| 任意时刻 | 输出面板无报错 |
