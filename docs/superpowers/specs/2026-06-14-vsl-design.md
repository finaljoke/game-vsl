# VSL — Vampire Survivors-Like 原型设计文档

**日期：** 2026-06-14
**引擎：** Godot 4.x
**平台：** PC（Windows/Mac），后续考虑移植

---

## 目标

开发一个可玩的 Vampire Survivors 核心循环原型。验证"移动 → 自动攻击 → 收经验 → 升级选武器"这个闭环是否好玩，为后续扩展（地图形式、主题、Meta 层）打基础。美术全部使用 placeholder，主题后定。

---

## 核心循环

```
开始 → 敌人持续涌入
     → 玩家移动 + 武器自动攻击
     → 敌人死亡 → 掉落 XP 宝石
     → 玩家收集宝石 → 经验条满
     → 游戏暂停，显示升级界面
     → 从 3 张武器卡中选 1 张
     → 武器挂载到玩家，游戏恢复
     → 玩家 HP 归零 → 死亡界面（时长 / 等级 / 重开）
```

---

## 架构方案

**方案 A — 扁平场景层级**（选定）

不引入组件系统或 Resource 数据驱动。实体是自包含的 Godot 场景，脚本直接挂在节点上。适合快速迭代的原型阶段；武器量到 10+ 后可评估是否迁移到 Resource 驱动。

---

## 场景结构

```
Main.tscn
├── Arena                   # 固定竞技场，边界 StaticBody2D × 4
├── EnemySpawner            # Node，计时生成敌人
├── YSort                   # 所有动态实体的父节点（自动排序层级）
├── Player.tscn
│   ├── Sprite2D
│   ├── CollisionShape2D
│   ├── HurtBox (Area2D)    # 受伤检测
│   └── [动态挂载的武器子节点]
└── UI (CanvasLayer)
    ├── HUD.tscn            # HP 条、XP 条、计时器、等级
    ├── LevelUpUI.tscn      # 升级武器选择界面
    └── DeathScreen.tscn    # 死亡结算界面

# 运行时实例化的场景：
Enemy.tscn
XPGem.tscn
KnifeProjectile.tscn
OrbShield.tscn
Explosion.tscn
```

**Autoload：**
- `GameManager.gd` — 管理状态机（`playing` / `level_up` / `dead`）、触发升级、重开

---

## 玩家（Player）

| 属性 | 初始值 |
|------|--------|
| HP | 100 |
| 移速 | 200 px/s |
| XP | 0 |
| XP 升级阈值 | 100（每级 × 1.2） |
| 武器槽 | Array，无上限（原型阶段） |

- 输入：WASD 移动，`CharacterBody2D.move_and_slide()`
- XP 收集半径：80 px，宝石进入后磁吸飞向玩家

---

## 武器系统

所有武器继承 `WeaponBase`（Node），作为子节点挂载到 Player 下。升级时动态实例化并 `add_child()`。

```gdscript
# weapon_base.gd
var cooldown: float
func _on_cooldown_timeout() -> void:
    attack()
func attack() -> void:
    pass  # 子类覆盖
```

### 三种武器（原型）

| 武器 | 攻击方式 | 伤害 | 冷却 |
|------|----------|------|------|
| 🗡️ 飞刀 `KnifeWeapon` | 向最近敌人发射 `KnifeProjectile`，飞出边界后 `queue_free()` | 15 | 1.0 s |
| 🔮 护盾球 `OrbWeapon` | 2 个 `OrbShield` 绕玩家旋转（半径 60 px），接触敌人造成伤害；同一敌人被命中后有 0.5 s 命中冷却，防止持续秒伤 | 8 / hit | 0.5 s/orb |
| 💥 爆炸 `ExplosionWeapon` | 在最近敌人位置生成 `Explosion`（AOE 半径 80 px），播放动画后消失 | 40 | 3.0 s |

---

## 敌人 & 生成系统

**Enemy（原型只有 1 种，彩色圆形 placeholder）：**

| 属性 | 值 |
|------|----|
| HP | 20 |
| 移速 | 80 px/s |
| 接触伤害 | 8 / s |
| 掉落 | XP 宝石（+10 XP） |

- 行为：每帧朝 Player 方向 `move_and_slide()`
- 死亡：播放消失动画 → `emit_signal("died", global_position)` → `queue_free()`

**EnemySpawner：**

| 参数 | 初始值 |
|------|--------|
| 生成间隔 | 1.5 s |
| 每 20 s 缩短 | × 0.85 |
| 最小间隔 | 0.3 s |
| 场上上限 | 200 只 |

生成位置：竞技场四条边随机一点（边缘外 20 px），敌人从边界外涌入。

---

## 竞技场

- 尺寸：1280 × 720（与窗口等大）
- 边界：4 个 `StaticBody2D` 阻挡玩家，敌人可从外穿入
- 背景：纯色或简单网格，placeholder

---

## 碰撞层规划

| Layer | 名称 | 用途 |
|-------|------|------|
| 1 | `world` | 竞技场边界 |
| 2 | `player` | 玩家 HurtBox |
| 3 | `enemy` | 敌人碰撞体 |
| 4 | `projectile` | 飞刀、爆炸 Area2D |
| 5 | `xp_gem` | XP 宝石 Area2D |

---

## UI

### HUD（方案 A — 四角分布）

```
[左上] ❤ HP 条
[中上] 计时器（存活时长）
[右上] Lv.N
[底部] XP 条（满了触发升级）
```

### 升级界面

- 游戏暂停（`get_tree().paused = true`）
- 全屏半透明遮罩
- 横排展示 3 张武器卡（图标 + 名称 + 描述 + NEW/已拥有标识）
- 选中一张 → 取消暂停 → 武器挂载

### 死亡界面

- 存活时长、达到等级
- "重新开始"按钮（重载主场景）

---

## 信号流

```
enemy.died(pos)
  → EnemySpawner → 在 pos 生成 XPGem

xp_gem.collected
  → player.add_xp(10) → 检查 xp >= threshold
    → player.emit_signal("leveled_up")
      → GameManager.trigger_level_up()
        → 暂停游戏 + 显示 LevelUpUI

level_up_ui.weapon_selected(weapon_id)
  → player.add_weapon(weapon_id)
    → 实例化武器场景，add_child 到 Player
  → GameManager → 恢复游戏

player.died
  → GameManager.game_over()
    → 显示 DeathScreen
```

---

## 原型完成标准（MVP）

- [ ] 玩家可用 WASD 移动
- [ ] 至少 1 种武器自动攻击
- [ ] 敌人持续生成并追逐玩家
- [ ] 敌人死亡掉落 XP 宝石，玩家可收集
- [ ] 经验条满后出现升级界面，可选 3 种武器之一
- [ ] 武器选中后实际生效
- [ ] 玩家 HP 归零后显示死亡界面，可重开

---

## 后续扩展方向（不在本原型范围内）

- 无限滚动地图 / Isaac 式房间地图
- 更多武器与升级词条
- 属性强化词条（移速、伤害、HP）
- Boss 波次
- Meta 层（解锁、角色选择）
- 正式美术主题
- 音效与音乐
