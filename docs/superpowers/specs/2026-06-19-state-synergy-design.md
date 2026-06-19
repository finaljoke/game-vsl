# 状态协同系统（C2 State Synergy）—— 设计文档

> 日期：2026-06-19
> 来源：`docs/reviews/2026-06-19-weapon-arsenal-critique.md` §A3 / §C2（"状态之间、状态与伤害零交互"是把军械库从"合格"推到"有记忆点"的最大单点杠杆）。
> 前置：A1（charger 控制接通）、A4（mega_orb/thunderstorm 进化倒退）已修，提交于分支 `fix/charger-control-evolution-regressions`。本设计建立在"控制对 charger 已生效"之上——这正是"碎裂不消耗冻结"决策的直接动因。

## 1. 问题与目标

当前 burn/slow/freeze/stun 四个状态各自孤立结算：**互不增益、不放大伤害、无碎裂/引爆/处决 payoff**。所有"combo"（霜噬冻→收割、引力井聚→AoE）都只是走位涌现，没有任何机制奖励，玩家感受不到"我搭出了连携"。这直接掏空了"相互搭配 + 趣味性 + 独特性"。

**目标**：引入一组轻量、纯数值、可单测、确定性的**状态协同规则**，集中在伤害收口一处实现，使全体武器零改动即受益；让"控住→收割""聚怪→增伤""点燃→蔓延（保守版：引爆）"从涌现变成**可感知、可构筑的连携目标**。

**非目标（本期范围外，见 §8）**：蔓延型野火连锁、冻结到期碎冰 nova、每怪"易伤"指示器美术、协同卡（A9）、任何新增 VFX 美术。

## 2. 设计决策（四个关键取舍 + 理由）

1. **默认全局生效**（非卡/perk 解锁）。元素互动是基础游戏规则，每局都能感受到；卡池（A9）后续只做"放大器"叠加。零武器改动、全员受益。
2. **碎裂"不消耗"冻结**。若首击即解冻，环绕/光环/多重等高频武器会在第 1 帧打碎冻结，直接废掉刚在 A1 修好的"冻结能定住 charger"。不消耗 = 冻结既是完整定身、又是持续加伤窗口。
3. **硬直走"残血处决"而非平加伤**。去同质化是核心：若碎裂与硬直收益都是"对受控目标平加 X%"，等于把两者做成同一个东西。每个状态给一个**不同的机制形状**——冻结→脆（平加伤爆发）、硬直/感电→处决（随残血递增 = 收割）。处决专门 key 在 `has_status(&"stun")`（非 `is_stunned()` 聚合），使冻结**不会**也触发处决，两规则锁在互斥状态种类。
4. **复用现成反馈**。`ice_shard`/`crit_spark`/`fire_burst` 三个 `Vfx.BURST_PRESETS` 预设均已在库 → 零新美术，守住"视觉重做整体推迟"，但玩家明确看得见连携。

## 3. 架构（单点接管）

所有伤害都过 `Enemy.take_damage(amount, channel)` 这一收口。在此插入一个**纯静态**乘区函数，武器/法术完全不动。

```
take_damage(amount, channel) 进入
  → 扣血前快照：frozen=has_status(freeze), stun=has_status(stun),
                amp=status.magnitude(amp), hp_frac=hp/MAX_HP
  → mult = Enemy.synergy_multiplier(channel, frozen, stun, hp_frac, amp)
  → final = amount * mult
  → hp -= final
  → 若 channel==DIRECT 且触发了打击型协同(frozen/stun)：放对应复用 Vfx 爆发
  → GameFeel.enemy_hit.emit(final, ...)   # 跳字自然变大
  → 死亡分支：若"死时带 burn"(用扣血前快照)，触发"燃尽"AoE
```

### 受影响文件
- `scenes/enemies/status_component.gd`：新增通用 `magnitude(kind: StringName) -> float` getter（缺省返回 0.0）。新状态 `amp` 走**现有泛型** apply/tick——默认 `_is_stronger`（非 slow 即"更大更强"）正好适用 amp，无需特判。amp **不**进入 `move_speed_mult()` / `is_stunned()`，纯作伤害读取项。
- `scenes/enemies/enemy.gd`：
  - 新增纯静态 `synergy_multiplier(channel, frozen, stun, hp_frac, amp_frac) -> float`（可测核心）。
  - `take_damage`：按上述流程插入乘区 + DIRECT 协同的 Vfx 反馈。
  - 死亡分支：若死时带 burn（用扣血前快照），经模块级重入守卫 `static var _conflagrating` 调"燃尽"helper（遍历 enemies 组，对邻怪一次性 DOT；守卫保证单波，见 §6）。
- `scenes/weapons/gravity_well/gravity_well.gd`：在**已有的**"半径内每帧遍历"循环（拉力那段）里多加一行 `e.apply_status(&"amp", GRAVITY_AMP, AMP_DUR)`。引力井天然每帧触达半径内每只怪，amp 在离场后约 3 帧自然衰减。奇点（singularity）复用同脚本，自动继承。

## 4. 四条规则与数值（初值，待遥测校准）

常量集中定义在 `Enemy`（或一处常量块），便于后续遥测调参：

| 规则 | 触发状态 | 效果 | 通道 | 反馈预设 | 常量 |
|---|---|---|---|---|---|
| **碎裂 Shatter** | `freeze` | 直击 ×1.5（不消耗，冻结期持续生效） | 仅 DIRECT | `ice_shard` | `SHATTER_MULT = 1.5` |
| **处决 Execute** | `stun`（含感电） | 直击 ×(1 + 0.2 + 0.8·(1−hp_frac))：满血 +20% → 濒死 ×2.0 | 仅 DIRECT | `crit_spark` | `EXECUTE_BASE = 0.2`, `EXECUTE_SCALE = 0.8` |
| **引力增幅 Gravity Amp** | 井内（`amp`） | 受到所有伤害 ×(1 + amp) = ×1.25 | DIRECT + DOT | 井场已有视觉（无逐击爆发，防刷屏） | `GRAVITY_AMP = 0.25`, `AMP_DUR = 0.25` |
| **燃尽 Conflagration** | 带 `burn` 死亡 | 半径内一次性火伤（DOT 通道），不蔓延、不级联 | 死亡触发 | `fire_burst` | `CONFLAG_RADIUS = 60.0`, `CONFLAG_DAMAGE = 10.0` |

### 组合模型 = 乘算
状态键**互斥**（冻结只走碎裂、硬直只走处决，单一状态不双吃）；跨来源叠加是**有意**的连携奖励：
- 冻结 + 井内，直击：1.5 × 1.25 = **1.875×**
- 濒死硬直 + 井内，直击：2.0 × 1.25 = **2.5×**

### slow 刻意不给独立收益
slow 的回报就是"喂进冻结"（霜噬 slow→二次命中升级 freeze 的机制循环）。留白避免"什么都加成什么"的元素稀释。

### synergy_multiplier 形状（伪代码）
```gdscript
static func synergy_multiplier(channel, frozen, stun, hp_frac, amp_frac) -> float:
    var m := 1.0
    if amp_frac > 0.0:                       # 引力增幅：两个通道都吃
        m *= (1.0 + amp_frac)
    if channel == DamageChannel.DIRECT:      # 打击型协同：仅直击
        if frozen:
            m *= SHATTER_MULT
        if stun:                             # key 在 stun，不含 freeze → 与碎裂互斥
            m *= (1.0 + EXECUTE_BASE + EXECUTE_SCALE * (1.0 - hp_frac))
    return m
```

## 5. 反馈（复用，零新美术）
- DIRECT 触发碎裂 → `Vfx.spawn_burst(pos, &"ice_shard")`；触发处决 → `crit_spark`。
- 燃尽死亡 → `fire_burst` 于死亡点。
- 引力增幅**不**逐击放爆发（井内高频命中会刷屏）；靠井场已有视觉 + 自然变大的跳字传达。
- 跳字：`take_damage` 传出的是放大后的 `final`，沿用现有 `GameFeel._spawn_damage_number`，数字自然变大即视觉强化。
- 同时多条协同时可叠放多个爆发（成本极低，cosmetic）。

### 确定性说明
`Vfx.spawn_burst` 用实时 timer 清理 + CPUParticles，纯视觉、不碰任何 gameplay 状态或 RNG（与现有 DoT 跳字节流同源,已被标注为 RunHarness 确定性安全）。全套规则零 RNG → `--fixed-fps 60` 下仍字节一致。

## 6. 燃尽（Conflagration）防级联细节
- 触发条件：`take_damage` 死亡分支中，用**扣血前的 burn 快照**判定（"死时正在燃烧"）。
- 效果：遍历 `enemies` 组，对半径 `CONFLAG_RADIUS` 内、非自身的存活敌人各打一次 `CONFLAG_DAMAGE`，走 **DOT 通道**（抑制白闪/击退/音效，避免一次群伤炸出 N 份完整命中反馈）。该伤害仍过 `take_damage` → 井内邻怪正常吃引力增幅，语义一致。
- **不蔓延**：燃尽只造成一次性伤害，**不施加** burn 状态 → 不会把燃烧"传染"给新的怪。
- **不级联（单波，靠重入守卫）**：燃尽的 AoE 经 `take_damage` 击杀邻怪时，若邻怪**本就带 burn**（火球/光环铺场下极常见），其死亡分支会再触发燃尽 → 在燃烧尸群里链式炸开。为兑现"一次性 nova"，用一个模块级重入守卫 `Enemy._conflagrating`：
  ```gdscript
  if had_burn and not Enemy._conflagrating:
      Enemy._conflagrating = true
      _trigger_conflagration()
      Enemy._conflagrating = false
  ```
  GDScript 单线程 + 同步嵌套调用 → 守卫期内所有嵌套死亡都跳过再触发，**只炸一波**。零 RNG、确定。
- 数值保守：本期最受益者是已 OP 的火球线（A11），故取一次性小 nova 而非蔓延，先观测再升级。蔓延型野火列为遥测门控的后续（§8）。

## 7. 测试计划（TDD，红→绿→重构）

### 纯函数 `Enemy.synergy_multiplier`（无场景，约 10 例）
- 无任何状态 → 1.0
- 冻结 + DIRECT → 1.5；冻结 + DOT → 1.0（碎裂不沾 DoT）
- 硬直 + DIRECT + 满血(hp_frac=1.0) → 1.2；硬直 + DIRECT + 濒死(hp_frac≈0) → 2.0；硬直 + DOT → 1.0
- amp=0.25 + DIRECT → 1.25；amp=0.25 + DOT → 1.25（引力增幅吃两通道）
- 冻结 + amp + DIRECT → 1.875
- 濒死硬直 + amp + DIRECT → 2.5
- **互斥守卫**：冻结（非 stun）→ 不含处决项；硬直（非 freeze）→ 不含碎裂项

### `StatusComponent`
- `magnitude(kind)`：存在返回值、缺省返回 0.0
- amp 走泛型：apply 后 `has(&"amp")` 真、`magnitude(&"amp")` 正确；"更大更强"覆盖；tick 到期 erase
- amp **不**影响 `move_speed_mult()` / `is_stunned()`

### 集成（实例化 enemy.tscn，沿用现有 `_make_enemy` 模式）
- take_damage 对冻结怪 → 实际扣血 = 基础 ×1.5
- take_damage 对濒死硬直怪 → 扣血显著高于满血硬直怪
- `gravity_well`：井内怪被打上 `amp`（magnitude>0）、井外怪不被打
- 燃尽：带 burn 的怪死亡 → 邻怪掉血；不带 burn 的怪死亡 → 邻怪不掉血
- 燃尽单波守卫：两只相邻燃烧怪，击杀其一触发一次燃尽；邻怪因该 AoE 致死**不**再触发第二波（重入守卫，单波）

### 回归 / 确定性
- 全量套件保持绿（当前基线 414/414）
- 确定性不变（无 RNG）

## 8. 明确不做（范围外）
蔓延/级联野火、冻结到期碎冰 nova、每怪 amp/易伤指示器美术、协同卡（A9）、新 VFX 美术、暴击轴补卡（A2，独立工作项）。

## 9. 已知遥测缺口（诚实标注）
W4 solo bot 是**单武器**档，**测不到跨元素协同**（协同本质需要多元素同场）。本期出货 = 有原则 + 单测覆盖的数值；真正的协同平衡需要一个"配对/多元素" bot 场景（如 frostbite + 一把直击武器、或引力井 + 火球），列为后续工作项，**非本期阻塞**。MVP 以原则数值出货，遥测校准随后。

## 10. 验收标准
- 四条规则按 §4 数值实现，集中在 `take_damage` + `synergy_multiplier` + `gravity_well` 三处。
- 全部新逻辑有单测，且按 TDD 先看红再转绿。
- 全量套件绿、确定性保持。
- 武器/法术 `.tres` 与各武器脚本**零改动**（gravity_well 仅加一行 apply_status）。
- 反馈复用现有预设，无新美术资源。
