# 战斗系统 Phase 1 · 构筑身份 · 设计 spec

- **日期**：2026-06-20
- **状态**：已批准设计，待用户复审
- **定位**：本文是 [2026-06-20 战斗系统基石 spec](2026-06-20-combat-system-foundation-design.md) 路线图里 **Phase 1** 的施工图。基石 spec 立宪法（6 契约 C1–C6 + 5 支柱 P1–P5 + 分阶段路线）；本文把 Phase 1「构筑身份」写到可由 writing-plans 转实现计划。
- **前置**：Phase 0（卡池投放层）已 TDD 实现并 FF 合并 master（456/456 绿、C5 确定性过）。Godot 4.7 升级验证已全闭环。
- **诊断来源**：[2026-06-20 全战斗系统分析](../../reviews/2026-06-20-combat-system-analysis.md)（§2.2 slow 孤儿、§4.2 元素骨架缺席、§4.3 暴击死轴、§2.3 桶纪律风险）。

---

## 0. 一句话定调

> **Phase 0 让深度"到得了玩家手里"；Phase 1 让深度"玩家能主动搭"。**

机制层已奖励"踩中协同条件"的构筑（碎裂/处决/引力增幅），但这些协同当前**不可被主动 draft、不可读**：没有元素标签让玩家选"走火/冰/雷"，暴击轴有字段无卡（半挂），slow 是无收割的孤儿状态。Phase 1 立起 **4 条可读构筑路线**，每条有完整的 enabler→payoff→synergy 卡链。

---

## 1. 目标与北极星对齐

| 支柱 | Phase 1 如何兑现 |
|---|---|
| **P1 深度 > 广度** | 不加新武器，给现有武器**贴流派、补收割轴**，让它们更会联动。 |
| **P2 构筑可达性** | 新协同卡走 Phase 0 的就绪投放/门控机制；元素标签让"补哪条线"可达可选。 |
| **P3 显式连携 · 独立乘区** | 元素标签 + 卡面徽标把隐式协同显式化；slow 易伤作为**有界、可读**的新增益。 |
| **P5 每次三选一都是真决策** | 元素卡把"选第 4 把武器"变成"补强我的火系/冰系"——真流派取舍。 |

**退出判据**（对齐基石 spec §3）：

1. 11 基础 + 11 进化武器有元素标签；🔥燃烧 / ❄️控制 / ⚡感电 / 🗡️暴击 4 主路线各有 enabler→payoff→synergy 卡链。
2. `slow` 有基线易伤 payoff，**C2 转全绿**；易伤桶加法纪律就位。
3. 暴击成可堆轴：物理武器吃暴击、有 crit 卡、封顶防必暴、长弓锁敌矛盾修正。
4. 元素/控制协同卡到位且经 Phase 0 可靠投放；卡面显示元素。
5. 全程 TDD，`tests/` 全绿且测试数符合预期（C6 截断核对）。

---

## 2. 设计决策记录（brainstorm 已拍板）

| # | 决策 | 选项 | 理由 |
|---|---|---|---|
| D1 | 元素系统重量 | **轻量标签 + 状态向协同卡** | 新威力全留在现有状态协同框架内，不引入通用 per-element 伤害乘区 → C1 契约面小、桶纪律天然守住（弃"每元素乘子层"与"元素反应系统"，YAGNI）。 |
| D2 | 暴击定位 | **暴击 = 物理流派招牌轴** | 给无状态可施的物理武器一条与火/冰/雷并列的可读身份；crit 仍是 C1 已就位的独立乘区桶（弃"通用伤害轴"摊平身份、弃"逐武器开关"碎片化）。 |
| D3 | slow payoff 形态 | **易伤（对 slow 目标增伤）** | 范本 PoE Shock / StS Vulnerable，有界、给所有 slow 打标者跨武器价值（弃"触发型"难有界、弃"slow→freeze 挡注型"slow 仍非独立收割）。 |
| D4 | 易伤叠加纪律 | **amp + slow_vuln 加法并桶** | 实现分析 §2.3.2 桶纪律，防"增伤源越加越炸"；向后兼容已锁 C1 测试。 |
| D5 | slow 基线 | **基线 +30%（无卡即生效）** | 与 shatter/execute/amp 一样是基线机制，C2 当场转全绿；卡把它推向 +50% 硬封。 |
| D6 | 进化门控（A10） | **不纳入 P1，留 Phase 2** | 重门控会动 Phase 0 确定性投放 + 11 .tres + 测试面，属平衡/路线塑形，更贴 Phase 2。P1 先立身份骨架。 |

---

## 3. 单元拆分

5 个**独立可测**单元，按依赖与杠杆排序，各自独立提交、独立绿测。落地顺序：**U1 → U2 → U3 → U4 → U5**。

### 单元 1 · 元素标签体系（数据地基）

**现状问题**：`WeaponData`（[data/weapons/weapon_data.gd](../../../data/weapons/weapon_data.gd)）无 `element/tag/school` 字段，零元素概念。synergy 卡靠硬编码 `has_any:<id 列表>`（[card_pool.gd:50-53](../../../autoloads/card_pool.gd#L50)）指定关联武器，新武器要改 card_pool。

**设计**：
- `WeaponData` 加 `@export var tags: Array[StringName] = []`（**多标签**：一把武器可同属多路线）。
- 条件 DSL 加 `has_tag:<tag>` 分支（`_check_condition()` [card_pool.gd:310](../../../autoloads/card_pool.gd#L310)）：遍历 `player.owned_weapons` 的 WeaponData.tags，命中即真。
- 把现有 synergy 卡的 `has_any:` 换成 `has_tag:`（pierce/multishot → `has_tag:physical`），去硬编码。
- 进化形态（11 个 evolved .tres）继承/复刻源武器标签（如 thousand_edge 继承 knife 的 `physical`，blizzard 继承 frostbite 的 `ice`）。

**数据结构/接口**：
- `WeaponData.tags: Array[StringName]`。
- 新 helper（card_pool 或 player）：`player_has_tag(player, tag) -> bool`（纯函数、好测）。

**验收/测试**（新增 `test_weapon_tags.gd`，排套件末尾）：
- 11 基础 + 11 进化武器各自 tags 符合 §5 映射表。
- `has_tag:` DSL：持有打标武器 → 真；不持有 → 假。
- 进化形态标签 = 源武器标签。

### 单元 2 · slow payoff（易伤桶）

**现状问题**：`slow`（[status_component.gd](../../../scenes/enemies/status_component.gd) `move_speed_mult()`）只作减速乘子、被 BT 移动读取，**无任何收割**——唯一孤儿状态（违 C2"每状态至少 1 跨武器 payoff"）。

**设计——引入统一「易伤桶」**：
- 被 `slow` 的目标受到的伤害 ×(1 + slow_vuln)。
- **加法并桶**（D4）：把 `amp_frac`（敌方状态）与 `slow_vuln_frac`（攻击方值，命中减速目标时生效）并入同一加法桶：
  ```
  易伤桶 = 1 + amp_frac + slow_vuln_frac
  synergy_multiplier = 易伤桶 × shatter × execute     （crit、damage_mult 仍在武器侧另算，见 C1）
  ```
  同类"目标易伤"来源**桶内相加**，与碎裂/处决/暴击这些不同语义乘区**跨桶相乘**。
- **基线 + 卡**（D5）：`SLOW_VULN_BASE = 0.30`（基线，目标被 slow 即生效，无需卡）；冰封/控制卡把攻击方 `slow_vuln_bonus` 累加，**硬封** `slow_vuln_frac ≤ 0.50`。
- **接线**：slow_vuln 是攻击方值（玩家卡），经 `take_damage` 传入（类比 damage_mult/crit 已是武器侧计算后传入的 base）；enemy 按自身 `status.has(&"slow")` 决定是否把 slow_vuln 计入易伤桶。`synergy_multiplier` 保持纯函数，新增 `slow_vuln_frac` 参数。

**数据结构/接口**：
- `Enemy.SLOW_VULN_BASE := 0.30`、`Enemy.SLOW_VULN_CAP := 0.50`。
- `Player.slow_vuln_bonus: float = 0.0`（卡累加；effective = clamp(BASE + bonus, 0, CAP)，仅当目标 slowed）。
- `synergy_multiplier(channel, frozen, stun, hp_frac, amp_frac, slow_vuln_frac)`：易伤桶改 `(1 + amp_frac + slow_vuln_frac)`。
- `take_damage` 增参把攻击方 slow_vuln 传入（默认 0 → 不破坏现有调用点，逐武器接入）。

**验收/测试**（扩 `test_enemy_synergy.gd` + `test_enemy_status.gd`）：
- slow-only（base 0.30）→ ×1.30。
- slow + amp0.25 → ×1.55（**加法**：1+0.25+0.30，非 1.25×1.30）。
- slow_vuln 加卡封顶：base+bonus 超 0.50 仍取 0.50。
- 已锁回归不变：`frozen+amp0.25 = ×1.875`、`frozen+stun = ×1.8`（slow_vuln=0 时桶 = (1+amp)，公式不变）。
- C2：slow 现有基线 payoff → 孤儿缺口消除。

### 单元 3 · 暴击轴（物理流派）

**现状问题**（分析 §4.3 / A2）：`crit_chance` 默认 0.0（[player.gd:30](../../../scenes/player/player.gd#L30)）、`crit_mult` 2.0（:31），**零卡可堆**；仅长弓传 `can_crit=true`（[knife_weapon.gd:44](../../../scenes/weapons/knife/knife_weapon.gd#L44)）。长弓锁最近敌 → 永远不在远距 `crit_range` → 距离暴击半挂。crit roll 在 [weapon_base.gd:76-79](../../../scenes/weapons/weapon_base.gd#L76)（`crit_multiplier(randf(), chance, bonus, mult)`），管线就位。

**设计**：
- `physical` 标签武器在 attack 时传 `can_crit=true`（长弓/斩/回旋斧/碎/缚灵）。crit 仍走 C1 已就位的独立乘区桶 `base × damage_mult × crit × synergy`，不碰状态/易伤桶。
- 新卡：
  - `perk_crit` 锐利：`crit_chance += 0.08`，**封顶** `crit_chance ≤ 0.60`（防 100% 必暴退化为纯 +伤害）。门控 `has_tag:physical`（无物理武器不进池，防废牌）。
  - `synergy_crit` 致命：`crit_mult += 0.40`，门控 `has_tag:physical`，`max_stacks` 限叠。
- **修长弓矛盾**：把 `longbow_crit_bonus`（距离/满血加成）作为 `crit_chance` 的**加成项**而非唯一来源——有全局 `crit_chance` 时锁近敌也能暴击；距离 bonus 叠加其上。具体数值在 plan 定。

**数据结构/接口**：
- `Player.crit_chance` 加封顶语义（应用侧 clamp 或 perk 应用时 clamp）。
- effect_registry 注册 `perk_crit`/`synergy_crit`。

**验收/测试**（新增 `test_crit_axis.gd`）：
- `perk_crit` 累加 crit_chance 且封顶 0.60。
- `synergy_crit` 累加 crit_mult。
- 物理武器 `can_crit=true`、非物理武器不暴击。
- `crit_multiplier` 纯函数：roll < chance 返回 mult，否则 1.0（回归）。
- 门控：无物理武器时 crit 卡不进池。

### 单元 4 · 元素/控制协同卡

**现状问题**（分析 §4.2 / A9）：synergy 仅 pierce/multishot（仅投射类）/magnet/lifesteal，**无元素/状态流派卡**，玩家无法主动选"走火系/冰系"。

**设计**（新卡见 §6 权威清单）：5 张新卡 + 4 张现有重门控。各卡 = 玩家字段 + 武器消费点：

| 卡 | 字段 | 消费点 |
|---|---|---|
| 🔥 `synergy_fire` 火势 | `burn_mult`（+0.30/层） | 火球/烈焰/斩流血 施加 burn 时乘 dps |
| ❄️ `synergy_frost` 冰封 | `freeze_dur_bonus`（+0.5s）+ `slow_vuln_bonus`（+0.10，封顶 0.50） | 霜噬冻结时长 / U2 易伤桶 |
| ⚡ `synergy_shock` 感电 | `shock_dur_bonus`（+0.15s/层） | 闪电链尾 / 碎砸击 硬直时长 |
| 🗡️ `perk_crit` 锐利 | `crit_chance`（见 U3） | weapon_base crit roll |
| 🗡️ `synergy_crit` 致命 | `crit_mult`（见 U3） | weapon_base crit roll |

- 现有 4 张：pierce/multishot 改 `has_tag:physical`，magnet/lifesteal 维持无门控。
- 重力/召唤 P1 **只打标签、不发专属卡**（留 Phase 2/3，避免摊大 YAGNI）。
- 新卡 `rarity` 默认按类型（synergy→rare、perk→common），走 Phase 0 现有稀有度/投放。

**验收/测试**（扩 `test_card_pool.gd` + 各武器测试）：
- 每张新卡的 effect 正确改对应玩家字段、`max_stacks` 封顶。
- 门控：`has_tag:fire` 仅在持火系武器时进池（无则不进，防废牌）。
- 武器读 modifier：burn dps/freeze dur/shock dur 按字段缩放。

### 单元 5 · 卡面元素徽标（可读性）

**现状问题**（分析 §3.5 / §4.2）：卡面不标元素，协同"打标者/收割者"身份对玩家不可见。

**设计**：`level_up_ui._make_card()`（[level_up_ui.gd:143](../../../scenes/ui/level_up_ui.gd#L143)）在 type label（:192-197）旁/下加一行小元素标签，武器与协同卡显示其 `tags`（含 emoji/颜色，复用现有渲染）。低成本，服务"流派可感知"。

**验收**：编辑器内 game_eval 烟测确认武器/协同卡显示元素标签（视觉层，沿用 4.7 验证手法；非 gdUnit）。

---

## 4. 契约影响（C1–C6）

- **C1 伤害管线 ★**：`synergy_multiplier` 加 `slow_vuln_frac` 参数，易伤桶 `(1 + amp_frac + slow_vuln_frac)`。crit 仍是独立乘区桶（已就位，物理武器接入）。更新 `test_enemy_synergy.gd`。**契约新增条款**：易伤类来源（amp/slow_vuln）桶内相加；碎裂/处决/暴击跨桶相乘；slow_vuln 硬封 0.50。
- **C2 状态契约 ★**：slow 获基线易伤 payoff → **孤儿缺口消除，C2 转全绿**。更新 `test_enemy_status.gd`。
- **C3 卡池**：新卡走 Phase 0 就绪投放/稀有度/门控；`has_tag:` 新 DSL（`test_card_pool.gd`）。
- **C4 进化**：P1 不动门控（D6）；进化形态继承元素标签。
- **C5 遥测**：新卡/标签不引入新 RNG 节拍；改完跑 A/B 基线对照确认未漂移（**正式 4.7 重采 A/B 基线留 Phase 2**）。
- **C6 测试**：全程 TDD；新测试（test_weapon_tags / test_crit_axis）排套件**末尾**，GREEN 态核对"发现测试数 == 预期"防截断。

---

## 5. 元素标签 → 武器映射表（权威，U1 据此实现）

| 武器 | 标签 | 进化形态 → 标签（继承） |
|---|---|---|
| 长弓 knife | `physical` | thousand_edge → `physical` |
| 斩 whip | `physical`, `fire`(流血) | bloody_whip → `physical`,`fire` |
| 回旋斧 boomerang | `physical` | cyclone → `physical` |
| 碎 maul | `physical`, `ice`(冲击波减速), `lightning`(砸击硬直) | earthshatter → 同 |
| 缚灵 orb | `physical` | mega_orb → `physical` |
| 火球 explosion | `fire` | nuke → `fire` |
| 烈焰护体 aura | `fire` | inferno_aura → `fire` |
| 连锁闪电 lightning | `lightning` | thunderstorm → `lightning` |
| 霜噬 frostbite | `ice` | blizzard → `ice` |
| 引力井 gravity_well | `gravity`, `ice`(拉拽减速) | singularity → 同 |
| 亡者召唤 reanimate | `summon` | horde → `summon` |

> **4 主路线**：🔥燃烧（fire）/ ❄️控制（ice）/ ⚡感电（lightning）/ 🗡️暴击（physical）。重力/召唤为次要/跨路线。多标签让"碎/斩"跨流派。具体标签以 plan 实现时按 .tres 机制微调，但以上为基准。

---

## 6. 新卡清单（权威，U3/U4 据此实现）

| id | 名称 | 类型 | 效果 | 门控 | max_stacks |
|---|---|---|---|---|---|
| `synergy_fire` | 火势 | synergy | burn dps +30% | `has_tag:fire` | 3 |
| `synergy_frost` | 冰封 | synergy | freeze 时长 +0.5s + slow 易伤 +10%(封顶0.5) | `has_tag:ice` | 3 |
| `synergy_shock` | 感电 | synergy | shock/stun 时长 +0.15s | `has_tag:lightning` | 3 |
| `perk_crit` | 锐利 | perk | 暴击率 +8%(封顶0.60) | `has_tag:physical` | 7（真正上界是 crit_chance ≤0.60） |
| `synergy_crit` | 致命 | synergy | 暴伤 +0.4 | `has_tag:physical` | 3 |

现有 4 张重门控：`synergy_pierce`/`synergy_multishot` → `has_tag:physical`；`synergy_magnet`/`synergy_lifesteal` 维持无门控。

> 数值（每层增量、封顶层数、rarity）为基准，plan/平衡阶段可调；门控与字段语义为契约。

---

## 7. 风险与决策记录

- **风险：全乘区 × 无减伤层的指数起飞**（分析 §2.3）。**缓解**：D4 易伤加法并桶 + slow_vuln 硬封 0.50 + crit_chance 封顶 0.60；crit 与状态/易伤分桶相乘但各自有界。补暴击轴后最坏全条件叠满（frozen×stun×amp+slow×crit）需 4 流派投入才触发，视作 build-defining spike，可接受。
- **风险：改 C1 破坏已锁测试**。**缓解**：易伤桶在 slow_vuln=0 时退化为 `(1+amp)`，与现公式逐字节等价；新增参数默认 0，逐调用点接入。先写失败测试再改（TDD）。
- **风险：多标签武器使路线边界模糊**。**缓解**：标签描述"武器做什么"，路线是玩家堆哪条收割轴；多标签是特性（碎可进暴击流或控制流），非 bug。卡面徽标（U5）让玩家看清。
- **风险：新卡稀释卡池 / 废牌**（违 P5/C3）。**缓解**：所有元素卡 `has_tag:` 门控——不持对应流派武器不进池；走 Phase 0 就绪投放与 Skip 经济。
- **风险：gdUnit 截断陷阱**。**缓解**：新测试排套件末尾，每次核对发现测试数 == 预期。
- **风险：headless 跑测试与编辑器双实例撞 LimboAI DLL**。**缓解**：跑 headless 前先关编辑器（见 CLAUDE.md）。

---

## 8. 实现衔接

本 spec 由 **writing-plans** 转为带 TDD 步骤的实现计划（`docs/superpowers/plans/2026-06-20-combat-build-identity-*.md`）。落地顺序按依赖：**U1（标签地基）→ U2（slow 易伤）→ U3（暴击轴）→ U4（元素卡）→ U5（卡面徽标）**，每单元独立提交、独立绿测。P1 实现在独立分支进行，完成后 FF 合并 master（对齐 Phase 0 流程）。
