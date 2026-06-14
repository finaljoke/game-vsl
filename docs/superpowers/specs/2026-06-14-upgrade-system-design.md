# Upgrade System Design

**Goal:** 用 CardPool Autoload 实现随机选卡升级系统，支持武器获取、武器强化（Lv.2）、属性加成三类卡片，为后续升级树奠定架构基础。

**Architecture:** 新增 `CardPool` Autoload 持有全部卡片定义和抽卡/应用逻辑；`LevelUpUI` 退化为纯显示层；`Player` 新增4个属性乘数字段；`WeaponBase` 动态读取 `attack_speed_mult`。

**Tech Stack:** Godot 4.6 GDScript，无新依赖。

---

## 文件改动清单

| 文件 | 操作 | 职责 |
|---|---|---|
| `autoloads/card_pool.gd` | 新建 | 卡片注册表 + `pick()` + `apply()` |
| `project.godot` | 修改 | 注册 CardPool 为 Autoload |
| `scenes/player/player.gd` | 修改 | 新增属性字段，`add_xp`/移速应用乘数 |
| `scenes/weapons/weapon_base.gd` | 修改 | `_process()` 动态算 `effective_cd` |
| `scenes/ui/level_up_ui.gd` | 修改 | 瘦身为显示层，调用 CardPool |
| `scenes/main/main.gd` | 修改 | 初始登记飞刀到 `owned_weapons` |

---

## CardPool Autoload

### 卡片数据结构

每张卡是一个 Dictionary：

```gdscript
{
    "id":        "knife",           # 唯一标识
    "name":      "飞刀",
    "desc":      "朝最近敌人射出飞刀",
    "type":      "weapon",          # weapon | upgrade | perk
    "condition": "no:knife",        # 见下方条件规则
}
```

### 条件规则

| condition 字符串 | 含义 |
|---|---|
| `""` | 始终进入候选池 |
| `"no:knife"` | `player.owned_weapons` 中不含 `"knife"` |
| `"upgrade:knife"` | `player.owned_weapons.get("knife", 0) >= 1` 且 `< 2` |

### 全部卡片（10张）

```gdscript
const CARDS: Array[Dictionary] = [
    # ── 武器（首次获取）──────────────────────────────────────────────
    { "id": "knife",       "name": "飞刀",     "desc": "朝最近敌人射出飞刀",     "type": "weapon",  "condition": "no:knife"       },
    { "id": "orb",         "name": "护盾球",   "desc": "绕身旋转的能量球",       "type": "weapon",  "condition": "no:orb"         },
    { "id": "explosion",   "name": "爆炸",     "desc": "随机位置触发范围爆炸",   "type": "weapon",  "condition": "no:explosion"   },
    # ── 强化（Lv.2，已持有时出现）────────────────────────────────────
    { "id": "knife_2",     "name": "飞刀 Lv.2",     "desc": "冷却 1.0s → 0.5s",         "type": "upgrade", "condition": "upgrade:knife"     },
    { "id": "orb_2",       "name": "护盾球 Lv.2",   "desc": "护盾球数量 2 → 3",          "type": "upgrade", "condition": "upgrade:orb"       },
    { "id": "explosion_2", "name": "爆炸 Lv.2",     "desc": "冷却 3.0s → 1.5s",         "type": "upgrade", "condition": "upgrade:explosion" },
    # ── 属性（始终可抽，可叠加）──────────────────────────────────────
    { "id": "perk_speed",  "name": "移速提升", "desc": "移动速度永久 +15%",      "type": "perk",    "condition": ""               },
    { "id": "perk_hp",     "name": "生命上限", "desc": "最大 HP +20，当场补满",  "type": "perk",    "condition": ""               },
    { "id": "perk_attack", "name": "攻速提升", "desc": "攻击速度永久 +15%",      "type": "perk",    "condition": ""               },
    { "id": "perk_xp",     "name": "XP 加成",  "desc": "XP 获取量永久 +25%",     "type": "perk",    "condition": ""               },
]
```

### 公开接口

```gdscript
# 返回过滤后随机抽取的 count 张卡（不足 count 时返回全部可用卡）
func pick(player: Player, count: int = 3) -> Array[Dictionary]

# 将卡片效果应用到玩家
func apply(card: Dictionary, player: Player) -> void

# 初始登记武器（main.gd 在 add_weapon 后调用）
func register_weapon(player: Player, weapon_id: String) -> void
```

### apply() 效果映射

| card.id | 效果 |
|---|---|
| `knife` / `orb` / `explosion` | `player.add_weapon(scene); player.owned_weapons[id] = 1` |
| `knife_2` | 找 `KnifeWeapon` 子节点 → `cooldown = 0.5` |
| `orb_2` | 实例化第3个 OrbShield（`orbit_index=2, total_orbs=3`），更新已有2个球的 `total_orbs=3` |
| `explosion_2` | 找 `ExplosionWeapon` 子节点 → `cooldown = 1.5` |
| `perk_speed` | `player.speed_mult *= 1.15` |
| `perk_hp` | `player.max_hp += 20; player.hp = min(player.hp + 20, player.max_hp)` |
| `perk_attack` | `player.attack_speed_mult *= 1.15` |
| `perk_xp` | `player.xp_mult *= 1.25` |

---

## Player 变更

### 新增字段

```gdscript
var owned_weapons: Dictionary = {}   # {"knife": 1, "orb": 2}
var speed_mult: float = 1.0
var attack_speed_mult: float = 1.0
var xp_mult: float = 1.0
# max_hp 已存在，不新增
```

### 修改逻辑

```gdscript
# _physics_process
velocity = dir * SPEED * speed_mult

# add_xp
func add_xp(amount: float) -> void:
    xp += amount * xp_mult
    while xp >= xp_threshold:
        ...
```

---

## WeaponBase 变更

```gdscript
func _process(delta: float) -> void:
    _timer += delta
    var effective_cd := cooldown / _player.attack_speed_mult
    if _timer >= effective_cd:
        _timer = 0.0
        attack()
```

`cooldown` 字段保持各武器 `_ready()` 里写死的基础值；`attack_speed_mult` 只在 Player 上累积，武器无感知。

---

## LevelUpUI 变更

```gdscript
func _on_level_up() -> void:
    visible = true
    var player := get_tree().get_first_node_in_group("player") as Player
    _build_cards(CardPool.pick(player))

func _build_cards(cards: Array) -> void:
    for child in card_container.get_children():
        child.queue_free()
    for card in cards:
        card_container.add_child(_make_card(card))

func _on_card_picked(card: Dictionary) -> void:
    visible = false
    var player := get_tree().get_first_node_in_group("player") as Player
    CardPool.apply(card, player)
    GameFeel.item_selected.emit()
    _gm.resume_game()
```

### 卡片视觉（Layout C）

| type | 顶部色条 | 类型标签 | scale |
|---|---|---|---|
| `weapon` | `#4a9eff` | 新武器 | 1.0 |
| `upgrade` | `#f5a623` | ★ 强化 | 1.04 |
| `perk` | `#50fa7b` | 属性 | 1.0 |

卡片用 `PanelContainer` + `StyleBoxFlat` 实现顶部色条；强化牌通过 `Control.scale = Vector2(1.04, 1.04)` 放大。

---

## 数据流

```
Player 升级
  → GameManager.trigger_level_up()
    → LevelUpUI._on_level_up()
      → CardPool.pick(player, 3)
        → 过滤 CARDS 中满足 condition 的牌
        → 随机取3张（不足则全取）
      → _build_cards(cards)
        → 渲染 Layout C 风格卡片
          → 玩家点击某张
            → CardPool.apply(card, player)
            → GameManager.resume_game()
```

---

## 测试覆盖

| 测试文件 | 覆盖点 |
|---|---|
| `tests/test_card_pool.gd` | `pick()` 条件过滤、不足3张时全取、`apply()` 各卡效果（纯数学，不需要场景） |
| `tests/test_player.gd` | 新增：`speed_mult`/`attack_speed_mult`/`xp_mult` 乘数效果 |

---

## 不在本次范围内

- 难度曲线调整（敌人伤害/速度随时间扩大）→ 下一个 spec
- 武器升级树 Lv.3+（方案 B）→ 以后扩展，CardPool 条件系统预留接口
- 抽卡保底机制（pity system）
- 武器进化（两武器合成）
