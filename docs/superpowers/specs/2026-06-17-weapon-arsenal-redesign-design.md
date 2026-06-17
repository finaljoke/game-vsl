# 武器军械库重做 —— 设计文档（Spec）

**日期：** 2026-06-17
**引擎：** Godot 4.6.3
**状态：** 设计稿，待评审。本文档**不含实现**；实现与平衡验证另起 `writing-plans` 一轮。
**前序文档：** [2026-06-14-vsl-design.md](2026-06-14-vsl-design.md)（原型）、[2026-06-14-game-feel-design.md](2026-06-14-game-feel-design.md)（打击感层）

---

## 1. 目标与背景

原型期 14 把武器（7 基础 + 7 进化）能跑通核心循环，但**效果与视觉都停留在占位**：

- **效果重叠**：光环 ≈ 爆炸（都是"每 N 秒对半径内全体造成伤害"）；飞刀 ≈ 回旋镖（都是"朝最近敌人发射穿透投射物"）。进化几乎全是数值堆叠（冷却↓、穿透↑、加 tint/scale），**无机制质变**。
- **视觉占位**：全部武器由约 5 张复用的 Kenney 占位图染色+缩放拼成，无粒子、无着色器、无逐武器动画。

**本次重做的北极星**：把军械库锚定到**上古卷轴(TES)式的分类体系**——武器（近战/远程）与法术（毁灭/召唤/变幻），让**每一类有不可替代的机制签名**、**每一把有清晰身份**、**每一个进化是质变**，并为每把武器定义**可落地的视觉/模型配方**（法术走 Kenney FX 素材 + 程序化粒子/着色器；近战/远程走程序化形状 + 打击 FX）。次要参考：D&D、战锤 40K。

---

## 2. 设计原则

1. **机制签名优先**：类别由"玩法身份"定义，不是由"造型"定义。同类内部靠参数差异化，跨类绝不重叠。
2. **进化即质变**：每个进化至少引入一条**新机制规则**（新状态 / 改变命中模式 / 新增自主行为 / 留下地形效果），而非仅调数值。
3. **共享原语，不各写一套**：燃烧/减速/冻结/硬直/击退/暴击/召唤等跨武器复用的能力，先做成**独立、可单测、接口清晰**的底座，武器只调用。
4. **视觉服从机制可读性**：玩家一眼能从画面读出"这是什么武器、命中了谁、附了什么状态"。FX 不能盖过敌人/可走位空间。
5. **数据驱动不破坏**：沿用 `WeaponData.levels` 反射注入 + `WeaponDB` 自动入库 + `CardPool` 卡条件 DSL，新增武器尽量"只动数据 + 一个脚本"。
6. **可被遥测验证**：所有数值是草案基线，最终由现有 bot/telemetry 管线跑 A/B 确认（确定性须引擎参数 `--fixed-fps 60`）。

---

## 3. 分类体系（2 大族 · 6 类 · 机制签名）

| 族 | 类别 | 机制签名（不可与他类重叠） | TES 对应 |
|---|---|---|---|
| 武器 Martial | **单手近战** | 跟随**朝向**的快速正面弧劈，高频、近身、奖励走位贴脸 | 单手剑/匕首 |
| 武器 Martial | **双手近战** | 慢速大范围重击/砸地，**强击退 + 硬直**，低频高冲击、控场 | 巨剑/战锤 |
| 武器 Martial | **远程·弓** | 瞄准最近敌的**穿透**箭，**距离/满血暴击**，精准线性输出 | 箭术 |
| 武器 Martial | **远程·投掷** | 飞出 + **折返**双段命中，去程回程各结算穿透 | 投掷武器 |
| 法术 Magic | **毁灭 Destruction** | 火/冰/电元素伤害 **+ 状态**：火=燃烧 DoT、冰=减速→冻结、电=连锁+感电硬直 | 毁灭系 |
| 法术 Magic | **召唤 Conjuration** | **自主独立实体**（环绕守卫 / 漫游随从），放置后自行索敌作战 | 召唤系 |
| 法术 Magic | **变幻 Alteration** | **操控战场而非直伤**：拉拽聚怪 / 护盾 / 减速场，力量倍增器 | 变化系 |

> TES 的恢复/幻术不单列：恢复折入变幻（护盾/吸血），幻术折入变幻（控制）。用户强调的毁灭/召唤/变幻为三大法术学派。

每类机制签名互不重叠的逐对校验放在 §11 验证。

---

## 4. 共享机制原语（底座，先于武器）

这些是**新增的跨武器系统**。现状 `Enemy.take_damage(amount)` 只掉血（[enemy.gd:50](../../../scenes/enemies/enemy.gd)），移动由 LimboAI 行为树驱动（velocity 由 BT atom `chase/kite/bomber/move_to_target` 的 `_tick` 写入），仅有 sprite-only 的 `_apply_knockback`（[enemy.gd:105](../../../scenes/enemies/enemy.gd)）。

### 4.1 状态系统（StatusComponent on Enemy）

**接口（挂在 Enemy 上，或内联进 enemy.gd 的轻量字段）：**

```gdscript
# 统一入口：武器命中时调用
func apply_status(kind: StringName, magnitude: float, duration: float) -> void
# 供 BT move atom 读取
func move_speed_mult() -> float   # 所有 SLOW/FREEZE 取最强者，1.0=无影响，0.0=冻结
func is_stunned() -> bool         # STUN/FREEZE 期间为 true → atom 输出零速、跳过接触结算
```

| 状态 kind | magnitude 含义 | 行为 | 视觉 |
|---|---|---|---|
| `&"burn"` | DoT 的每秒伤害 | Enemy `_process` 累加计时，每 0.25s 调 `take_damage(dps*0.25)`；可刷新不可叠加（取最强） | 敌人贴图叠橙红脉冲 + 头顶小火粒子 |
| `&"slow"` | 速度乘子 0..1 | `move_speed_mult()` 取最小值 | 敌人贴图偏青 + 霜粒子 |
| `&"freeze"` | 0（=完全冻结） | `slow` 的极端：`move_speed_mult()=0` 且 `is_stunned()=true` | 冰晶 overlay |
| `&"stun"` | 忽略 | `is_stunned()=true`，持续期内 atom 零速、不接触伤害 | 敌人头顶星旋 `twirl_*` |

**BT 侧最小改动**：写 velocity 的 atom 在 `_tick` 末尾 `velocity *= agent.move_speed_mult()`；若 `agent.is_stunned()` 则 `velocity = Vector2.ZERO` 并直接返回。改动点集中在 `scenes/enemies/ai/enemy_bt.gd` 的 4 个移动 atom。

### 4.2 真击退（external_velocity）

把 sprite-only 击退升级为**可选的实体位移**，且不与 BT 的单次 `move_and_slide` 冲突：

```gdscript
# Enemy 持有一个随时间衰减的外力速度
var external_velocity: Vector2 = Vector2.ZERO   # 每帧 *= decay(约 0.85)
func apply_impulse(dir: Vector2, strength: float) -> void   # external_velocity += dir*strength
```

BT move atom 写 velocity 时改为 `velocity = desired_velocity * move_speed_mult() + agent.external_velocity`，仍只调用一次 `move_and_slide`。CLAUDE.md 已记录"sprite 位移与 BT move_and_slide 冲突"——本方案通过共用同一 velocity 通道规避。GameFeel 的 sprite 抖动保留作纯视觉反馈。

### 4.3 召唤/随从基类（SummonBase）

两种自主实体，**不依赖 LimboAI**（用轻量脚本，避免给召唤物再挂行为树）：

- **OrbitGuardian**（环绕守卫）：复用现有 `OrbShield` 的轨道+接触命中逻辑（[orb_shield.gd](../../../scenes/weapons/orb/orb_shield.gd)），泛化为基类。
- **RoamingMinion**（漫游随从，`CharacterBody2D`）：`_physics_process` 用 `get_nearest_enemy` 式索敌 → 朝目标 `move_and_slide` → 接触/近战结算伤害；加入 `summons` 组、目标取 `enemies` 组；有生命周期或常驻。索敌逻辑复用 `WeaponBase.get_nearest_enemy` 的同款实现（提取为静态工具或共享 util）。

### 4.4 暴击（crit）

伤害管线加暴击口径，集中在 `WeaponBase`：

```gdscript
func damage_for(base: float, can_crit := false, crit_bonus := 0.0) -> float
# = base * player.damage_mult，再按 (player.crit_chance + crit_bonus) 判定 *player.crit_mult
```

Player 新增 `crit_chance: float = 0.0`、`crit_mult: float = 2.0`（默认不暴击，保持现有手感）。弓用 `crit_bonus` 表达"距离/满血加成"。暴击命中向 GameFeel 发更强反馈（金色伤害数字 + 大档震屏）。

---

## 5. 进化哲学

- 进化卡仍由 `CardPool._register_evolution_cards()` 从 `WeaponDB.all_evolvable()` **自动注入**（基础武器 `.tres` 的 `evolution.evolved_id` 指向进化 `.tres`）。
- 解锁条件沿用 `_is_evolve_ready()`：基础武器满级 + 关联 `requires_perk` 累积到阈值。**进化的 perk 门槛按"该武器流派该堆的属性"指派**（见各条目），强化"武器 × perk 路线"的构筑协同。
- 每个进化在 §7 条目里**必须写明"新机制规则"那一行**——这是质变的硬性验收点。

---

## 6. 视觉/模型系统

### 6.1 主题

**TES 暗黑高奇幻军械库**：武器=有重量的金属实体（冷色钢 + 命中暖色火花）；法术=元素能量（火=橙红、冰=青白、电=紫蓝、召唤=幽绿/符文蓝、变幻=紫）。统一走"剪影清晰 + 命中爆点"的可读性。

### 6.2 资源映射（路径已核实真实存在）

根目录：`D:\Workspace\GAME\Assets\Kenney`。导入时拷入仓库 `assets/sprites/kenney/...`（注意记忆 [feedback_godot_asset_import]：新拷入文件需 headless `--import`，MCP reimport 不导入新文件）。

| 用途 | 真实路径（相对 `2D assets\`） | 关键文件 |
|---|---|---|
| **通用法术 FX**（火/光/魔法/火花/星/拖尾/旋涡/枪口闪/斩击/烟/烧痕/符号） | `Particle Pack\PNG (Transparent)\` | `fire_01..02`、`flame_01..06`、`flare_01`、`light_01..03`、`magic_01..05`、`spark_01..07`、`star_01..09`、`trace_01..07`、`twirl_01..03`、`muzzle_01..05`、`slash_01..04`、`smoke_01..10`、`scorch_01..03`、`circle_01..05`、`symbol_01..02` |
| **爆炸序列帧**（9 帧 00–08） | `Explosion Pack\PNG\{Regular,Simple,Sonic,Pixel,Ground} explosion\` | `regularExplosion00..08` 等 |
| **爆炸彩色烟云粒子** | `Explosion Pack\PNG\Particles\` | `burst`、`orangeCloud1..4`、`redCloud1..4`、`yellowCloud1..4`、`greyCloud1..4` |
| **烟/毒气/闪光帧** | `Smoke Particles\PNG\{Black smoke,Gas,Flash,White puff}\` | `blackSmoke00..24`、`gas00..08`、`flash00..08`、`whitePuff00..24` |
| **符文 / 法阵 / 学派标识** | `Rune Pack\PNG\{Blue,Grey,Black}\{Tile,Slab,Rectangle}\` | `runeBlue_tile_001..` 等（蓝=召唤/变幻、灰/黑=毁灭底纹） |
| **召唤随从拼装件** | `Monster Builder Pack\PNG\Default\` | `body_*`、`arm_*`、`eye_*`、`horn_*`（拼骷髅/幽魂；dark/blue 色） |
| **像素武器/小怪贴图兜底** | `Tiny Dungeon\Tiles\tile_0000.png..` | 16×16 像素图集，含刀剑/弓/骷髅小图（实现时按 tile 索引选取） |
| **卡面图标** | `Icons\Game Icons`、`Icons\Game Icons Fighter Expansion`、`Generic Items\PNG\Colored\` | 武器/动作/物品图标 |
| **额外辉光层** | `Light Masks\` | 法术柔光 |

> **近战/远程"模型"现实**：Kenney 无成套刀剑弓杖精灵。武器的"模型"由 **程序化形状（Polygon2D 刃形 / Line2D 刃光轨迹）+ 命中 FX（`slash_*`/`muzzle_*`/`spark_*`）+ 可选 Tiny Dungeon 像素图garnish** 共同构成；法术则直接用上表 FX 素材 + GPUParticles2D + 着色器。这是"认真做模型"在零原创美术约束下的落地路径。

### 6.3 程序化配方约定

每把武器的视觉用统一节点惯例描述（便于实现复用）：

- **持续/光环类**：`Sprite2D`(底纹) + `GPUParticles2D`(环绕) + 着色器(脉动/扭曲)。
- **投射类**：`Sprite2D`/`Polygon2D`(弹体) + `Line2D` 或 `GPUParticles2D`(拖尾，用 `trace_*`)。
- **瞬时打击类**：`AnimatedSprite2D`(序列帧) 或 `Sprite2D`+Tween(缩放/透明淡出)，叠 `slash_*`/`muzzle_*`。
- **着色器**：火=噪声扰动+加色混合；冰=折射/白边；电=UV 抖动；召唤=幽光描边；变幻=径向扭曲。

### 6.4 打击感接入（复用现有层）

复用 `GameFeel`（`enemy_hit`/`enemy_died` → 闪白/伤害数字/音效）与 Phantom Camera 震屏（**`noise_emitter_layer=1` 陷阱见 CLAUDE.md**）。每把武器在条目里指定：震屏档位（light/medium/heavy）、是否触发 hitstop、命中/暴击的额外反馈。

---

## 7. 阵容与逐武器设计

**总览**（标记：⟳ 重构现有 / ★ 新增 / 进化 perk 门槛）：

| # | 类别 | 基础武器 | 来源 | 进化 | 进化 perk 门槛 |
|---|---|---|---|---|---|
| 1 | 单手近战 | 斩 Cleave | ⟳ whip | 回旋斩 Whirlwind | perk_attack |
| 2 | 双手近战 | 碎 Maul | ★ | 震地 Earthshatter | perk_hp |
| 3 | 远程·弓 | 长弓 Longbow | ⟳ knife | 箭雨 Arrow Storm | perk_attack |
| 4 | 远程·投掷 | 回旋斧 Throwing Axe | ⟳ boomerang | 旋风斧 Cyclone | perk_speed |
| 5 | 毁灭·火 | 火球 Fireball | ⟳ explosion | 核爆 Cataclysm | perk_damage |
| 6 | 毁灭·火 | 烈焰护体 Flame Cloak | ⟳ aura | 炼狱 Inferno | perk_hp |
| 7 | 毁灭·电 | 连锁闪电 Chain Lightning | ⟳ lightning | 雷暴 Tempest | perk_attack |
| 8 | 毁灭·冰 | 霜噬 Frostbite | ★ | 暴雪 Blizzard | perk_attack |
| 9 | 召唤·守卫 | 缚灵 Spectral Wisps | ⟳ orb | 缚刃 Bound Blades | perk_hp |
| 10 | 召唤·进攻 | 亡者召唤 Reanimate | ★ | 群尸 Horde | perk_hp |
| 11 | 变幻 | 引力井 Gravity Well | ★ | 奇点 Singularity | perk_speed |

每条目结构：**身份 / 机制 / 数据 schema（3 级草案）/ 进化（含质变规则）/ 视觉配方 / 打击感 / 依赖原语 / 平衡定位**。

---

### 7.1 斩 Cleave（单手近战）⟳ whip

- **身份**：跟随移动朝向的快速正面弧劈，高频近身；奖励"贴脸走位"。TES 单手剑。
- **机制**：每 `cooldown` 朝 `_facing`（玩家速度方向，静止时保留上次）扫 `arc_deg` 扇形、`range` 半径，命中扇内全体（沿用 whip `in_cone` 几何，[whip_weapon.gd](../../../scenes/weapons/whip/whip_weapon.gd)）。与"双手"区分：小范围、高频、无击退；与"光环"区分：有朝向、瞬时、跟手。
- **数据 schema**（字段需在脚本声明以供反射）：`cooldown, arc_deg, range, damage`
  | Lv | cooldown | arc_deg | range | damage |
  |---|---|---|---|---|
  | 1 | 0.7 | 100 | 110 | 22 |
  | 2 | 0.6 | 110 | 120 | 24 |
  | 3 | 0.5 | 120 | 130 | 26 |
- **进化 → 回旋斩 Whirlwind**（perk_attack）：**质变规则**=改为 360° 环绕劈 + 命中附 `burn`式**流血 DoT**（`bleed_dps`）+ 命中回血（`lifesteal_on_hit`，复用 player.heal）。`double_sided`/全向。
- **视觉**：刃光用 `Particle Pack\slash_01..04` 旋转贴合扇形 + `Line2D` 弧形轨迹（冷钢青白→命中暖色）；进化转血红 + 残留 `scorch_*`。
- **打击感**：light 震屏，命中多目标轻微 hitstop。
- **依赖**：状态（流血，进化）；暴击（可选）。
- **定位**：贴脸高 DPS、强清杂，低安全性。

---

### 7.2 碎 Maul（双手近战）★ 新增

- **身份**：慢速大范围砸击，**强击退 + 硬直**，低频高冲击的控场近战。TES 战锤/巨剑。
- **机制**：每 `cooldown` 在玩家周身 `radius` 内（或朝 `_facing` 的宽扇）一次性重击全体 → 造成伤害 + `apply_impulse`（径向远离玩家，`knockback`）+ `apply_status(&"stun", 0, stun_dur)`。低频（长 CD）。与"斩"区分：慢、大、有击退硬直；与"火球"区分：物理、自身中心、即时无 DoT。
- **数据 schema**：`cooldown, radius, damage, knockback, stun_dur`
  | Lv | cooldown | radius | damage | knockback | stun_dur |
  |---|---|---|---|---|---|
  | 1 | 2.2 | 130 | 60 | 220 | 0.4 |
  | 2 | 1.9 | 150 | 66 | 250 | 0.5 |
  | 3 | 1.6 | 170 | 72 | 280 | 0.6 |
- **进化 → 震地 Earthshatter**（perk_hp）：**质变规则**=砸击后向外发射一圈**扩张冲击波**（延迟二次命中更远的敌人）+ 命中处留短暂 `slow` 地裂区。
- **视觉**：砸地用 `Explosion Pack\PNG\Ground explosion`（9 帧）+ `dirt_*`/`greyCloud*` 尘云；冲击波用 `Sonic explosion` 环。武器本体可用 Tiny Dungeon 像素战锤贴图在玩家手侧一闪。
- **打击感**：heavy 震屏 + hitstop（命中即停 ~0.06s），强调"沉重"。
- **依赖**：击退（4.2）、状态 stun（4.1）。
- **定位**：控场/解围，单体爆发高、覆盖广、频率低。

---

### 7.3 长弓 Longbow（远程·弓）⟳ knife

- **身份**：瞄准最近敌的穿透箭，**距离/满血暴击**，精准线性输出。TES 箭术。
- **机制**：每 `cooldown` 朝最近敌发射穿透箭（沿用 knife 投射+穿透+`global_pierce`/`extra_projectiles`，[knife_weapon.gd](../../../scenes/weapons/knife/knife_weapon.gd)）。新增**距离暴击**：目标距离 > `crit_range` 或满血时 `crit_bonus` 提升暴击率。弹体更快、更长射程。与"投掷"区分：直线不返回、吃暴击；与"火球"区分：单体穿透、无 AoE。
- **数据 schema**：`cooldown, pierce, damage, crit_range, crit_bonus, proj_speed`
  | Lv | cooldown | pierce | damage | crit_range | crit_bonus |
  |---|---|---|---|---|---|
  | 1 | 0.9 | 2 | 18 | 260 | 0.25 |
  | 2 | 0.7 | 3 | 18 | 260 | 0.30 |
  | 3 | 0.5 | 4 | 18 | 240 | 0.35 |
- **进化 → 箭雨 Arrow Storm**（perk_attack，沿用 thousand_edge 通路）：**质变规则**=改为**高速齐射多发**（`volley` 发并射，极短 CD），且首发对满血目标必暴。
- **视觉**：箭=细长 `Polygon2D` + `trace_*` 拖尾；暴击命中爆 `spark_*`+`star_*`。可用 Tiny Dungeon 箭/弓像素图作弹体。
- **打击感**：普通命中 light；暴击 medium 震屏 + 金色伤害数字。
- **依赖**：暴击（4.4）；复用 `mod_int("global_pierce"/"extra_projectiles")`。
- **定位**：稳定单体/穿线 DPS，构筑暴击流核心。

---

### 7.4 回旋斧 Throwing Axe（远程·投掷）⟳ boomerang

- **身份**：飞出 + 折返双段命中，去程回程各结算穿透。保留 boomerang 的差异化机制。TES 投掷武器/40K 链斧风味。
- **机制**：沿用 boomerang 去程到 `throw_range` 后折返、每段独立 `pierce`/`_hit_ids`（[boomerang_projectile.gd](../../../scenes/weapons/boomerang/boomerang_projectile.gd)）。与"弓"区分：折返双段、命中同一敌两次、不吃距离暴击。
- **数据 schema**：`cooldown, pierce, throw_range, damage, count`
  | Lv | cooldown | pierce | throw_range | damage | count |
  |---|---|---|---|---|---|
  | 1 | 1.5 | 3 | 220 | 20 | 1 |
  | 2 | 1.2 | 4 | 250 | 20 | 1 |
  | 3 | 1.0 | 5 | 280 | 20 | 1 |
- **进化 → 旋风斧 Cyclone**（perk_speed，沿用 cyclone）：**质变规则**=`count=3` 且折返路径改为**环绕玩家旋转**（不再直线返回，形成短时旋刃领域）。
- **视觉**：斧=旋转 `Sprite2D`（Tiny Dungeon 斧像素图或 Generic Items）+ `trace_*` 残影；旋风态加 `twirl_*`。
- **打击感**：去/回各一次 light 震屏。
- **依赖**：无新原语（纯投射）。
- **定位**：中距双段、走线清杂，速度流构筑。

---

### 7.5 火球 Fireball（毁灭·火，远程）⟳ explosion

- **身份**：投向**最密集敌群**的范围爆炸 + 地面**燃烧 DoT**。TES 毁灭·火球。
- **机制**：沿用 `densest_center` 选点（[explosion_weapon.gd](../../../scenes/weapons/explosion/explosion_weapon.gd)）→ 爆炸即时 AoE → 在落点留 `burn_field`（持续 `field_dur`，每 tick 对场内 `apply_status(&"burn", burn_dps, ...)`）。与"光环"区分：远程、选点、留火地；与"碎"区分：魔法、有 DoT、不击退。
- **数据 schema**：`cooldown, damage, blast_radius, burn_dps, field_dur`
  | Lv | cooldown | damage | blast_radius | burn_dps | field_dur |
  |---|---|---|---|---|---|
  | 1 | 2.6 | 40 | 80 | 6 | 2.0 |
  | 2 | 1.6 | 42 | 90 | 8 | 2.5 |
  | 3 | 1.0 | 44 | 100 | 10 | 3.0 |
- **进化 → 核爆 Cataclysm**（perk_damage，沿用 nuke）：**质变规则**=爆炸范围×1.6 + 留下**更大更久的炼狱地火**（更高 `burn_dps`），并对中心追加二次延迟引爆。
- **视觉**：`Explosion Pack\Regular/Simple explosion` 9 帧 `AnimatedSprite2D`；地火用 `flame_*`/`fire_*` GPUParticles2D 循环 + `scorch_*` 焦痕底；火着色器加色混合。
- **打击感**：medium 震屏；核爆 heavy + hitstop。
- **依赖**：状态 burn（4.1）。
- **定位**：AoE 主清场 + 持续区域控制。

---

### 7.6 烈焰护体 Flame Cloak（毁灭·火，自身）⟳ aura

- **身份**：自身环绕的持续燃烧光环，贴身灼烧。TES 烈焰护体（cloak）。与火球同为火系但机制不重叠（持续自体 vs 远程爆发）。
- **机制**：沿用 aura 的玩家中心半径脉冲（[aura_weapon.gd](../../../scenes/weapons/aura/aura_weapon.gd)），命中附 `burn`（短时）。高频小伤。与"斩"区分：无朝向、全向、魔法 DoT。
- **数据 schema**：`cooldown, radius, damage, burn_dps`
  | Lv | cooldown | radius | damage | burn_dps |
  |---|---|---|---|---|
  | 1 | 0.8 | 90 | 12 | 4 |
  | 2 | 0.65 | 110 | 13 | 5 |
  | 3 | 0.5 | 130 | 14 | 6 |
- **进化 → 炼狱 Inferno**（perk_hp，沿用 inferno_aura）：**质变规则**=半径大幅扩张 + **命中回血**（`lifesteal_on_hit`，保留现有）+ 更强 burn。维持现有炼狱风味。
- **视觉**：环底 `circle_*`/`light_*` 半透贴图 + 环绕 `flame_*` GPUParticles2D（沿玩家半径旋绕）；炼狱转橙红加大。
- **打击感**：无震屏（持续光环避免抖动疲劳），仅命中闪白。
- **依赖**：状态 burn（4.1）；player.heal（进化）。
- **定位**：贴身续航/坦克流，与近战站位协同。

---

### 7.7 连锁闪电 Chain Lightning（毁灭·电）⟳ lightning

- **身份**：向最近敌劈雷并贪心连锁跳跃，命中附**感电硬直**。TES 毁灭·电。
- **机制**：沿用贪心 `chain_targets` 链选（[lightning_weapon.gd](../../../scenes/weapons/lightning/lightning_weapon.gd)）→ 链上全体即时伤害 + 一定概率/链尾 `apply_status(&"stun", 0, shock_dur)`。与"弓"区分：多目标即时、无投射、带硬直。
- **数据 schema**：`cooldown, chains, damage, shock_dur, link_range`
  | Lv | cooldown | chains | damage | shock_dur |
  |---|---|---|---|---|
  | 1 | 1.2 | 3 | 22 | 0.2 |
  | 2 | 0.9 | 4 | 22 | 0.25 |
  | 3 | 0.7 | 5 | 22 | 0.3 |
- **进化 → 雷暴 Tempest**（perk_attack，沿用 thunderstorm）：**质变规则**=链数大增 + 每次攻击额外在随机敌头顶**召唤天雷**（独立 AoE 落雷），形成全场放电。
- **视觉**：沿用现有 `lightning_bolt` 分段拉伸 + `fx_glow` 命中辉光（加色混合）；可升级用 `Particle Pack\trace_*`/`spark_*`；天雷用纵向 bolt + `flash_*`。
- **打击感**：medium 震屏 + 命中短 hitstop（"噼啪"顿挫）。
- **依赖**：状态 stun（4.1）。
- **定位**：多目标点杀 + 软控，密集敌群放大。

---

### 7.8 霜噬 Frostbite（毁灭·冰）★ 新增

- **身份**：冰锥/冰爆，**减速 → 冻结**的控制型毁灭，补全元素三角。TES 毁灭·霜寒。
- **机制**：每 `cooldown` 朝最近敌（或最密集处）放一次冰爆/锥 → 范围伤害 + `apply_status(&"slow", slow_factor, slow_dur)`；对**已被减速**的敌人命中则升级为 `freeze`（短时完全冻结）。与"火球"区分：低直伤、强控制、靠"二次命中冻结"的机制循环。
- **数据 schema**：`cooldown, damage, area, slow_factor, slow_dur, freeze_dur`
  | Lv | cooldown | damage | area | slow_factor | slow_dur | freeze_dur |
  |---|---|---|---|---|---|---|
  | 1 | 1.4 | 16 | 90 | 0.6 | 1.5 | 0.6 |
  | 2 | 1.1 | 18 | 100 | 0.5 | 1.8 | 0.8 |
  | 3 | 0.9 | 20 | 110 | 0.45 | 2.0 | 1.0 |
- **进化 → 暴雪 Blizzard**（perk_attack）：**质变规则**=改为在区域内**持续降雪领域**（`field_dur` 内反复 slow + 周期冻结），脱离单次施放。
- **视觉**：冰爆用 `Smoke Particles\White puff` 重染青白 + `Particle Pack\star_*`(冰晶) + `circle_*` 霜环；冻结敌叠冰晶 overlay + 着色器白边。
- **打击感**：light 震屏；冻结瞬间一次脆响 + 短 hitstop。
- **依赖**：状态 slow/freeze（4.1）。
- **定位**：控制核心，与高 DPS 武器（弓/闪电）协同收割。

---

### 7.9 缚灵 Spectral Wisps（召唤·守卫）⟳ orb

- **身份**：环绕玩家的自主守卫灵，接触伤害的"放置型"防护。TES 召唤·束缚。
- **机制**：泛化现有 OrbShield（轨道 + 每敌命中冷却，[orb_shield.gd](../../../scenes/weapons/orb/orb_shield.gd)）为 **OrbitGuardian**（4.3）。`total_orbs` 个均匀环绕。与"投掷"区分：常驻自主、被动覆盖。
- **数据 schema**：`total_orbs, damage, orbit_radius, hit_cooldown`
  | Lv | total_orbs | damage | orbit_radius |
  |---|---|---|---|
  | 1 | 2 | 8 | 60 |
  | 2 | 3 | 8 | 64 |
  | 3 | 4 | 9 | 68 |
- **进化 → 缚刃 Bound Blades**（perk_hp，沿用 mega_orb）：**质变规则**=数量增多 + 灵体**周期性脱轨扑向最近敌**（短暂索敌冲刺后归位），从被动守卫变半主动攻击。
- **视觉**：灵体 = `magic_*`/`light_*` 幽蓝贴图 + 描边着色器 + `trace_*` 轨迹残影；缚刃态换成幽蓝剑形 `Polygon2D`。
- **打击感**：无震屏，命中闪白 + 轻 `spark_*`。
- **依赖**：召唤基类 OrbitGuardian（4.3）。
- **定位**：被动续航/防身，构筑数量协同。

---

### 7.10 亡者召唤 Reanimate（召唤·进攻）★ 新增 —— **冲刺项（实现成本最高）**

- **身份**：召唤**自主漫游的骷髅随从**，独立索敌、追击、近战。真正的"AI 盟友"。TES 召唤·复活尸/召唤亡魂。
- **机制**：每 `cooldown`（或保持固定数量）生成 **RoamingMinion**（4.3）：朝最近敌移动、接触/近战结算 `damage`、有 `lifetime` 或上限常驻 `max_minions`。与"缚灵"区分：脱离玩家、主动出击、独立走位。
- **数据 schema**：`summon_interval, max_minions, damage, minion_hp, minion_speed, lifetime`
  | Lv | max_minions | damage | minion_hp | lifetime |
  |---|---|---|---|---|
  | 1 | 1 | 14 | 30 | 12 |
  | 2 | 2 | 14 | 30 | 14 |
  | 3 | 3 | 16 | 35 | 16 |
- **进化 → 群尸 Horde**（perk_hp）：**质变规则**=上限大增 + 随从死亡时**有概率原地再裂出小尸**（自我延续的尸潮）。
- **视觉**：随从用 `Monster Builder Pack` 拼骷髅/幽魂（dark/blue 件）或 Tiny Dungeon 骷髅像素图；召唤瞬间地面亮 `Rune Pack\Blue\Tile` 法阵 + `magic_*` 涌出。
- **打击感**：召唤一次 light 闪光；随从命中走 GameFeel 标准反馈。
- **依赖**：召唤基类 RoamingMinion（4.3，**新 AI 实体，最大工作量**）。
- **定位**：分担仇恨/铺场，独立输出源。**评审可将本项延后到后续波次**。

---

### 7.11 引力井 Gravity Well（变幻）★ 新增

- **身份**：操控战场的漩涡——**把敌人拉向一点聚怪** + 轻微伤害，为 AoE 武器做铺垫的力量倍增器。TES 变化系（操控/麻痹风味）。
- **机制**：每 `cooldown` 在最密集处生成持续 `field_dur` 的引力井：场内敌人每帧被 `apply_impulse`（朝井心，`pull_strength`）+ 周期轻伤。不直接高伤，价值在"把散怪揉成团"。与所有直伤武器正交（控制位）。
- **数据 schema**：`cooldown, field_dur, radius, pull_strength, tick_damage`
  | Lv | cooldown | field_dur | radius | pull_strength | tick_damage |
  |---|---|---|---|---|---|
  | 1 | 4.0 | 2.0 | 140 | 120 | 3 |
  | 2 | 3.4 | 2.5 | 160 | 140 | 4 |
  | 3 | 3.0 | 3.0 | 180 | 160 | 5 |
- **进化 → 奇点 Singularity**（perk_speed）：**质变规则**=拉拽更强 + `field_dur` 结束时**坍缩引爆**（聚拢的敌群被一次高伤 AoE 收割）。
- **视觉**：井心 `twirl_*` 旋涡 GPUParticles2D（向心吸入）+ `Rune Pack` 法阵底 + 径向扭曲着色器；坍缩用 `Sonic explosion` 内爆。
- **打击感**：生成/坍缩各一次 medium 震屏。
- **依赖**：击退/冲量（4.2，方向取"朝井心"，复用 `apply_impulse`）。
- **定位**：团队增益位，放大火球/核爆/暴雪的 AoE 收益。

---

## 8. 与现有系统对齐（实现期需对接，本轮只记录改动面）

| 系统 | 文件 | 需要的改动 |
|---|---|---|
| 武器基类 | `scenes/weapons/weapon_base.gd` | `damage_for` 加暴击重载（4.4）；其余复用（`apply_level` 反射、`get_nearest_enemy`、`get_ysort`、`mod_int`） |
| 数据入库 | `autoloads/weapon_db.gd` | 无需改：新增/改写 `.tres` 自动入库 |
| 卡池 | `autoloads/card_pool.gd` | `_register_weapon_effects()` 的硬编码 id 列表加入 `maul/frostbite/reanimate/gravity_well`（及其 `_2/_3` 升级）；新增对应 `CARDS` 基础/升级/synergy 条目；进化卡仍自动注入 |
| 玩家 | `scenes/player/player.gd` | 新增 `crit_chance/crit_mult`；复用 `damage_mult/attack_speed_mult/global_pierce/extra_projectiles/lifesteal/heal/grant_weapon/level_up_weapon/replace_weapon`；6 武器槽不变 |
| 敌人 | `scenes/enemies/enemy.gd` | 加状态字段 + `apply_status/move_speed_mult/is_stunned`（4.1）、`external_velocity/apply_impulse`（4.2） |
| 敌人 AI | `scenes/enemies/ai/enemy_bt.gd` | 移动 atom（chase/kite/bomber/move_to_target）写 velocity 处乘 `move_speed_mult()`、叠 `external_velocity`、`is_stunned` 早退 |
| 召唤 | 新增 `scenes/summons/` | OrbitGuardian（由 orb_shield 泛化）+ RoamingMinion（新） |
| 打击感 | `GameFeel` + Phantom Camera | 复用；按条目接震屏档位 / hitstop / 暴击反馈 |

### 8.1 数据 `.tres` 与卡片清单（实现期产出）

- **改写现有 7 把基础 `.tres`** 的 `levels`/新增字段（cleave/maul…的字段需在对应 weapon 脚本声明才能反射）。命名沿用现有 id（whip→保留 id 但改名展示？见下注）。
- **新增 4 把基础 `.tres`**：`maul/frostbite/reanimate/gravity_well` + 各自 `evolution` 指向新进化 `.tres`。
- **改写 7 个进化 `.tres`** 注入质变字段；**新增 4 个进化 `.tres`**：`earthshatter/blizzard/horde/singularity`。
- **卡条件 DSL** 全部可表达：基础 `no:<id>`、升级 `upgrade:<id>:N`、进化 `evolve_ready:<id>`、synergy `has_any:`（参考现有 `synergy_pierce` 等）。

> **id 命名决策**：保留现有英文 id（`whip/knife/...`）以零破坏存量卡条件与 `effect_registry`，仅改 `display_name`（横扫鞭→斩、飞刀→长弓…）。新武器用新 id。评审若要求 id 也改名，则需同步迁移 `CARDS` 与 `_register_weapon_effects`。

---

## 9. 范围边界（本轮 spec 不做）

- 不写任何游戏代码、不改 `.tres/.gd/.tscn`、不导入素材。
- 不定最终平衡数值（表内为草案基线，待 telemetry 调）。
- 不把 perk 重做成 TES 18 技能树（用户明确"当前不是全部适用"）；进化门槛复用现有 perk。
- 不做原创美术；视觉一律 Kenney 库 + 程序化 FX。

---

## 10. 分波次实现建议（供下一轮 writing-plans）

1. **W0 底座**：状态系统（4.1）+ 击退（4.2）+ 暴击（4.4）+ 召唤基类（4.3）。先有底座，武器才能复用。配套 gdUnit 单测（纯函数：状态取最强、速度乘子、暴击判定）。
2. **W1 重构现有 7 把**（风险最低，复用最多）：cleave/maul…实为改 whip 等的数据 + 接状态/暴击；逐把垂直切片验证视觉框架与手感。
3. **W2 新增 3 把**：maul / frostbite / gravity_well（不依赖新 AI 实体）。
4. **W3 冲刺项**：reanimate（RoamingMinion AI 盟友）+ 全部进化质变 + 暴雪/奇点/震地/群尸。
5. **W4 平衡**：bot/telemetry 跑 A/B（确定性 `--fixed-fps 60`，见记忆 [project_vsl_bot_telemetry]），按 DPS/威胁轴回填数值。

---

## 11. 验证（spec 质量把关）

- [ ] **占位符扫除**：无 TODO/TBD/空表。
- [ ] **机制签名互不重叠**（逐对）：斩(朝向高频小范围) ≠ 碎(慢大击退硬直) ≠ 光环(全向持续DoT) ≠ 火球(远程选点+地火)；弓(单体穿透吃暴击) ≠ 投掷(折返双段) ≠ 闪电(多目标即时+硬直)；霜噬(减速→冻结控制) 独占冰位；缚灵(被动环绕) ≠ 亡者(主动漫游AI) ≠ 引力井(拉拽控场无直伤主体)。✔
- [ ] **进化均为质变**：11 个进化每个都写明"新机制规则"行（360°+流血 / 冲击波+地裂 / 齐射必暴 / 环绕旋刃 / 延迟二爆+地火 / 回血+扩张 / 天雷 / 持续雪域 / 脱轨扑击 / 尸潮自延 / 坍缩引爆）。✔
- [ ] **schema 可被反射承载**：每把字段为 `WeaponData.levels` 字典键，且约定在 weapon 脚本声明同名 var（否则 `apply_level` 静默忽略并告警）。
- [ ] **卡条件可被 DSL 表达**：见 §8.1。
- [ ] **共享原语改动面已写明**：enemy.gd / enemy_bt.gd / player.gd / weapon_base.gd / 新 summons（§8）。
- [ ] **资源路径真实**：§6.2 路径均已对 `D:\Workspace\GAME\Assets\Kenney` 实地核验（Particle Pack / Explosion Pack / Rune Pack / Smoke Particles / Monster Builder / Tiny Dungeon / Generic Items / Icons 均存在，文件名 stem 已确认）。
- [ ] **交接**：本 spec → 用户评审 → `writing-plans` 产出 W0–W4 实现计划。

---

## 附：决策点（评审重点）

1. **阵容规模**：11 基础 + 11 进化 = 22 条目。默认全收（"认真对待每一把"）；可裁剪。
2. **#10 亡者召唤** 依赖新的自主 AI 随从系统（RoamingMinion），实现成本最高 → 标为冲刺项 W3，可延后/砍。
3. **烈焰护体保持火属性**（与火球同火系、机制正交），冰属性交给全新 #8 霜噬，**不改 aura→inferno 的现有火风味**。
4. **id 保留英文不变**（仅改 display_name），换取存量卡条件零破坏（§8.1）。
