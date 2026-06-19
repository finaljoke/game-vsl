# 战斗系统基石 · 设计 spec（宪法 + 分阶段路线图）

- **日期**：2026-06-20
- **状态**：已批准骨架，待用户复审
- **定位**：这是支撑本游戏**长期开发**的纲领性文档。它不取代、而是**接续**两份分析——
  [2026-06-19 武器军械库审计](../../reviews/2026-06-19-weapon-arsenal-critique.md)（逐武器诊断 + A1–A11 系统问题）与
  [2026-06-20 全战斗系统分析](../../reviews/2026-06-20-combat-system-analysis.md)（权威/社区对照、卡池可达性论点）。
  前两份是**诊断**；本文是**纲领 + 第一步施工图**。
- **首个落地 plan**：Phase 0（卡池投放层），见 §4，将由 writing-plans 转为实现计划。

---

## 0. 一句话定调

> **本游戏的机制深度，已经长得超过了它的卡池投放能力。**

状态协同层（setup→payoff、独立乘区、具名连携、契约测试）已达业界一手设计水准且**已实装 + 测试**（提交 301d8de/b0e71c8/9eeb0c0/4d255a2）。但这些深度**到不了玩家手里**：进化解锁后单次升级仅约 2.4% 抽中，无保底、无 skip、有永久废牌稀释。

因此长期路线是 **「先精后扩」**：先把已有深度**可靠投放**给玩家（Phase 0），再立**构筑身份**（Phase 1）、**校准平衡**（Phase 2），最后才谈**内容广度与元进度**（Phase 3）。每一阶段都有明确的退出判据，避免在地基没夯实时就摊大饼。

---

## 1. 北极星 · 设计支柱

游戏的身份由 5 条支柱定义。任何新内容、新数值、新系统，若与支柱冲突，**改内容、不改支柱**。

| # | 支柱 | 含义 | 反面（要避免的） |
|---|---|---|---|
| P1 | **深度 > 广度** | 标志性体验是 setup→payoff 的状态协同，不是武器数量。 | 用"再加一把武器"代替"让现有武器更会联动"。 |
| P2 | **构筑可达性是一等公民** | 卡池必须把深度**可靠**投放给玩家。可达性问题 = 设计 bug，不是运气。 | 强内容存在但抽不到，等于不存在。 |
| P3 | **显式连携 · 独立乘区** | 协同是**具名**的、跨通道**乘算**的，玩家能看懂、能预期。 | 靠隐式数值叠加堆 DPS，玩家不知道为什么变强。 |
| P4 | **进化 = 质变** | 进化改变武器**怎么打**，不是 +x%。 | 进化只是更高的数字（参见 mega_orb 历史倒退）。 |
| P5 | **每次三选一都是真决策** | 每轮抽卡都该构成有意义的取舍：反稀释、反废牌、反"显然最优"。 | 池里混入满血即废的治疗、永远最优的暴力卡。 |

---

## 2. 宪法 · 系统不变量（新内容的验收契约）

这 6 条是**契约**：实现任何新武器/状态/卡牌前，先核对它是否守约；违约的设计要么改、要么显式记录为有意例外。带 ★ 的契约已有 gdUnit 测试锁定，改动须同步改测试。

### C1 · 伤害管线契约 ★

权威来源 [tests/test_enemy_synergy.gd](../../../tests/test_enemy_synergy.gd) + `Enemy.synergy_multiplier()`。

```
final = base × damage_mult × crit × synergy_multiplier
synergy_multiplier = shatter × execute × (1 + amp)
  shatter  = 1.5                       当 channel==DIRECT 且 frozen，否则 1.0
  execute  = 1.2 + 0.8 × (1 − hp_frac) 当 channel==DIRECT 且 stunned，否则 1.0   （满血1.2 → 濒死2.0）
  amp                                  ×(1+amp) 对 DIRECT 与 DOT 都生效
```

**规则**：
- 层内**加**、跨层**乘**。frozen+stun = 1.5 × 1.2 = **1.8**（已锁，禁止改成 if/elif 退化为单乘）。
- **通道门控**：碎裂/处决**只吃 DIRECT**，燃烧 DOT 不吃；amp 两者都吃。新机制必须声明它走哪个通道、动哪一层。
- **故意无敌方防御/护甲/抗性层**——这是设计选择（保持 setup→payoff 的纯乘算清晰）。要加减伤，必须作为新的显式乘区并更新本契约。
- **无隐藏伤害上限**（反"坍缩三类"之一，见 §6）。

### C2 · 状态契约 ★

权威来源 [scenes/enemies/status_component.gd](../../../scenes/enemies/status_component.gd)。

- 5 个状态：`burn`(DoT) / `slow`(速度乘子) / `freeze`(速0+硬直) / `stun`(硬直) / `amp`(增伤)。
- **refresh-not-stack**：同状态重复施加时，magnitude 取最强（slow 取更慢）、duration 取更久。
- **每个状态至少 1 个跨武器 payoff**。新状态必须**同时**定义 setup（谁施加）与 payoff（谁收割）。
- ⚠ **已知缺口**：`slow` 是唯一无收割的孤儿状态（其余 4 态都有跨武器 payoff）。Phase 1 补 slow payoff，届时本契约转全绿。

### C3 · 卡池契约

权威来源 [autoloads/card_pool.gd](../../../autoloads/card_pool.gd)。

- 每张卡有 `rarity`（缺省按类型补：weapon→uncommon / evolution→legendary / synergy→rare / 其余→common，[L87-92](../../../autoloads/card_pool.gd#L87)）。
- 强卡更稀有，**但就绪的门控卡必须可靠投放**——已解锁内容不靠运气（P2）。
- **池中无永久废牌/陷阱牌**：任何无条件、满状态即浪费的卡都违约（现状 `perk_heal` 违约，Phase 0 修）。
- 空池**永不软锁**：当可投放卡 < 3，UI 必须优雅降级（Skip 永远可用），而非靠填充废牌占位。

### C4 · 进化契约

权威来源 11 个 `data/weapons/*.tres` 的 `evolution` 字典 + `_is_evolve_ready()`（[L292](../../../autoloads/card_pool.gd#L292)）。

- 进化 = 质变（P4）：新行为，不只是更高数值。
- 门控：源武器 `max_level`（=3）**且** 主题 perk 累积 `requires_perk_stacks`（当前全部 =3）。
- **对玩家透明**：卡面/提示须写明"需 [武器] 满级 + [perk] ×N"，不能只写"解锁终极形态"。
- **就绪即可靠投放**（见 §4 单元 1 的确定性投放机制）。

### C5 · 遥测契约

权威来源 [autoloads/run_harness.gd](../../../autoloads/run_harness.gd) + W4 bot 遥测管线。

- 平衡结论须由 **bot 遥测**背书，不靠手感断言。
- 确定性靠引擎参数 `--fixed-fps 60`（**不是** `--fast`；根因是 spawner 帧时间 RNG 节拍）。
- OP 嫌疑先开 **solo 档**定位支配性，再动数值——不在混编里盲调。

### C6 · 测试契约

权威来源 [tests/](../../../tests/)（test_enemy_synergy / test_card_pool / test_player / test_weapons_* …）。

- 协同乘区、管线常量、卡池门控、进化就绪等**机制契约**由 gdUnit 测试锁定。
- 新机制走 TDD：先写失败测试，再实现。
- ⚠ gdUnit headless 有**截断陷阱**：某测试解析/脚本错误会静默吞掉其后测试的发现——别只看全绿，要核对预期测试数，风险测试排最后。

---

## 3. 分阶段路线图

每阶段一个独立 spec→plan→实现周期。**退出判据**未达成不进下一阶段。

| 阶段 | 主题 | 目标 | 退出判据 |
|---|---|---|---|
| **Phase 0**（现在） | **卡池投放层** | 让已实装的深度可靠到达玩家。 | 进化就绪后**必然**在数轮内被投放；池中无废牌；Skip + 可用的控池经济上线；全程绿测。 |
| **Phase 1** | **构筑身份** | 立起 3–4 条可读的构筑路线。 | 元素流派骨架 + 协同卡到位；crit 轴可成形（A2）；slow payoff 补齐（C2 转全绿）；每条路线有 enabler→payoff 链。 |
| **Phase 2** | **平衡完整性** | 数据驱动校准。 | 11 进化全量 solo 遥测；nuke/thousand_edge 等 OP 嫌疑复衡；坍缩三类向量封堵（§6）。 |
| **Phase 3** | **内容广度 + 元进度** | 从原型走向完整 roguelite。 | 持久解锁/天赋；多角色/地图/Boss；run modifier。（本阶段才谈"扩"。） |

> Phase 1–3 在 §5 只给框架，细节留给各自的 spec。本文档**只把 Phase 0 写到可施工**。

---

## 4. Phase 0 详细设计 · 卡池投放层

**总目标**：不加任何新武器/新协同，只修"投放管道"，让已有深度到得了玩家手里。拆为 4 个**独立可测**单元，可独立提交、独立测试。所有改动集中在 [autoloads/card_pool.gd](../../../autoloads/card_pool.gd) 与 [scenes/ui/level_up_ui.gd](../../../scenes/ui/level_up_ui.gd)（页脚为代码内建，**不动 .tscn**），少量触及 [scenes/player/player.gd](../../../scenes/player/player.gd) 与 [scenes/enemies/enemy_spawner.gd](../../../scenes/enemies/enemy_spawner.gd)。

### 单元 1 · 进化可达性（最高杠杆）

**现状问题**：进化 `legendary` 权重 6 vs perk `common` 100、**无保底**（[L64](../../../autoloads/card_pool.gd#L64)）→ 就绪后单次升级约 2.4% 抽中，约 40 次升级才稳定见一次。卡面只写"解锁 %s 的终极形态"（[L138](../../../autoloads/card_pool.gd#L138)），玩家不知道要满足什么。

**设计：就绪即确定性投放**（用户已拍板，对齐 VS 本体——已解锁进化不走抽奖）。

- 在 `pick()` 里**先于加权抽样**做一遍"就绪进化扫描"：收集所有 `_is_evolve_ready` 为真的进化卡（排除本局已 banish 的）。
- 若存在 ≥1 个就绪进化 → **确定性占据三选一的 1 个槽位**，余下 2 槽走原加权抽样（**保留决策密度** P5：不霸占整屏）。
- **多个就绪**时：按就绪武器 `id` 字典序取**第一个**确定性投放（确定性便于契约测试 + bot 复现 C5/C6）。被取走的进化离开就绪集 → 下一轮自然浮现下一个；玩家想优先另一个，可 banish 当前进化使其让位。
- **视觉锚**：就绪进化卡用 `legendary` 边框 + `✦ 就绪` 角标高亮（[level_up_ui.gd](../../../scenes/ui/level_up_ui.gd) 已有 RARITY_BORDER/RARITY_COLORS，复用即可）。
- **透明化卡面**：把 `_register_evolution_cards()`（[L130](../../../autoloads/card_pool.gd#L130)）的 `desc` 从"解锁终极形态"改为
  `"需 [display_name] 满级 + [perk 中文名] ×[N]"`，N 取 `requires_perk_stacks`。perk 中文名由一张 `perk_id → 名称` 映射表提供（perk_attack→"攻速提升" / perk_hp→"生命上限" / perk_speed→"移速提升" / perk_damage→"攻击强化"，源自 CARDS 定义）。
- **可选增强（同单元，低成本）**：对**接近就绪**的进化（武器已满级、perk 差 1–2 层）在卡面或 HUD 给一行提示"再 ×k [perk] 即可进化"——把"我该往哪堆"显式化（P2）。

**数据结构/接口**：
- 新增 `func ready_evolutions(player) -> Array[Dictionary]`（纯函数、好测）：返回当前就绪进化卡列表。
- `pick()` 改为：先取 `ready_evolutions`，确定性挑 1 注入结果，再对剩余槽位跑现有加权抽样（注意去重，避免该进化又被随机抽到）。
- bot 路径（RunHarness）同样经 `pick()`，自动受益、且确定性不破种子复现。

**验收/测试**（扩 [tests/test_card_pool.gd](../../../tests/test_card_pool.gd)）：
- 构造"1 个进化就绪" → `pick()` 结果**必含**该进化卡。
- "0 个就绪" → 结果**不含**任何进化卡（不能凭空塞）。
- "2 个就绪" → 本轮恰含 1 个，且选择确定性可复现；连续多轮能覆盖到全部。
- 就绪进化被 banish → 不再投放。
- 透明化 desc 含 perk 名与阈值。

### 单元 2 · perk_heal 去陷阱 + 空池兜底重构

**现状问题**：`perk_heal`（[L60](../../../autoloads/card_pool.gd#L60)）无 `max_stacks`、`condition=""` → 永久在池稀释（违 C3/P5），满血时抽到即废牌（陷阱卡）。它现在身兼"防空池软锁"的兜底职责（[L59 注释](../../../autoloads/card_pool.gd#L59)）。

**设计**：把"去陷阱"与"防软锁"两个职责**拆开**。
- **去陷阱**：给 `perk_heal` 加条件门控，仅在**受伤时**出现。新增条件 DSL：`hp_below:<frac>`（如 `hp_below:0.9`），在 `_check_condition()`（[L262](../../../autoloads/card_pool.gd#L262)）加分支，读 `player.hp / player.max_hp`。满血永不出现 → 不再是废牌。
- **防软锁**：兜底职责移交给"空池优雅降级"。`pick()` 允许返回 < count 张；UI 侧 Skip 永远可用（单元 3），故空池不再软锁（满足 C3"永不软锁"）。
  - 可选：当可投放卡 < count 时，注入一张**永不浪费**的兜底卡 `+1 重抽券`（reroll token 可存，绝不废）填补空槽——与单元 4 经济同币种，自洽。

**验收/测试**：
- 满血 → `pick()` 候选**不含** perk_heal。
- 残血 → 含 perk_heal。
- 极端"所有卡耗尽/封顶 + 满血" → `pick()` 不软锁（返回兜底券或允许 Skip），暂停可 resume。

### 单元 3 · Skip（放弃整轮换小额回报）

**现状问题**：玩家**必须**从三选一里选一张，即便三张都不想要——这违背 roguelite 控池共识（VS/StS/RoR2 均可跳过/弃选），也是 perk_heal 陷阱的帮凶（"被迫选废牌"）。

**设计**：在 [level_up_ui.gd](../../../scenes/ui/level_up_ui.gd) 页脚（`_build_footer` [L46](../../../scenes/ui/level_up_ui.gd#L46)）加 **Skip** 按钮。
- 点击 → 不取任何卡，给**小额回报**后 `resume_game()`。回报取**永不浪费**且**不破坏 P5 取舍**的形式：`+1 重抽券`（推荐，与经济同币种）或小额 XP。
- **反"skip 永远最优"**：回报必须**小于**一张普通卡的期望价值，确保 Skip 是"这轮没好牌"的逃生口，而非常态最优解。
- bot 路径不走 UI（RunHarness 单点 pick），Skip 仅影响人类对局，不影响遥测确定性。

**验收/测试**：Skip 后 `reroll_tokens` +1 且对局 resume；Skip 不改变 `perk_stacks`/武器。（UI 行为可用 player 状态断言间接测。）

### 单元 4 · reroll / banish 经济

**现状问题**：`reroll_tokens` 仅小 Boss 掉（各 +2，[enemy_spawner.gd:109](../../../scenes/enemies/enemy_spawner.gd#L109)），reroll 与 banish **共用**，默认 0（[player.gd:33](../../../scenes/player/player.gd#L33)）。控池工具存在但"用不起"——一局没几张券，banish 一用就没。

**设计**（保持克制，只让工具"用得起"，不做大改）：
- **每轮 1 次免费 reroll**：每次三选一给 1 次不耗券的 reroll（社区共识：免费首抽是控池地基）。实现：UI 侧每次 `_on_level_up` 重置一个 `_free_reroll_used=false`，`_on_reroll` 优先消耗免费次数再耗券。
- **更稳的券收入**（二选一，留给 plan 定）：(a) 维持 Boss 掉券但提高频次/数量；或 (b) 引入"每 N 级 +1 券"的稳定细水流。倾向 (a)+小幅，避免引入新计数系统。
- **可选拆分**：若实测 reroll 与 banish 抢券导致 banish 几乎不可用，再考虑拆成两种币（**留作 Phase 0 末的数据决策**，默认不拆，避免过度工程 YAGNI）。

**验收/测试**：扩 [tests/test_player.gd](../../../tests/test_player.gd) 的重抽券用例——免费 reroll 不扣券、券耗尽后 reroll 走付费、banish 正确扣券。

### Phase 0 退出判据（汇总）

1. 进化就绪后**必然**在 ≤ 数轮内被投放（不再 2.4% 抽奖）；卡面写明门控。
2. 满血时池中**无** perk_heal；空池**不软锁**。
3. Skip 可用且回报小于普通卡期望。
4. 每轮 1 次免费 reroll；控池工具实际可用。
5. 全部新增/修改走 TDD，`tests/` 全绿且测试数符合预期（C6 截断陷阱核对）。

---

## 5. Phase 1–3 框架（各自 spec 再展开）

> 此处只立**方向与边界**，防止 Phase 0 决策与未来冲突；不是施工图。

### Phase 1 · 构筑身份
- **元素流派骨架**：把 11 武器/11 进化归入可读的元素/机制流派（火/冰/雷/物理/召唤/引力…），让"我在走哪条路"可感知。
- **协同卡作为显式构筑路线**：让 setup→payoff 成为玩家**主动选**的路线（如"冰系强化：冻结时长 +x、碎裂 +y"），而非隐式涌现。
- **crit 轴**（修审计 A2）：补 crit 来源卡，让 `crit`/`crit_mult` 成为可成形的一条轴（当前无 crit 卡 → 暴击死轴）。
- **slow payoff**（补 C2 缺口）：给 slow 一个跨武器收割（如"减速目标受到的 DIRECT +x%"或"对减速目标触发某效果"），让它不再是孤儿状态。
- 退出判据见 §3。

### Phase 2 · 平衡完整性
- 11 进化逐一 solo 遥测（C5），定位支配性。
- 复衡 nuke（全屏覆盖型）、thousand_edge（绕冷却缩放型）等 OP 嫌疑。
- 封堵**坍缩三类向量**（§6）。

### Phase 3 · 内容广度 + 元进度
- 持久元进度（解锁/天赋树）、多角色、多地图/Boss、run modifier。
- 这是"扩"——只有 Phase 0–2 的"精"达标后才启动。

---

## 6. 风险与决策记录

### 决策：进化用"确定性投放"而非"概率 pity"
- **选**：就绪即确定性占 1 槽。**理由**：① 对齐 VS 本体（已解锁进化不抽奖）；② 确定性最易写契约测试 + bot 复现（C5/C6）；③ 零方差，彻底消灭"解锁了还抽不到"。
- **弃 pity**：仍有方差、要维护计数器状态、玩家仍可能连续吃不到。
- **弃混合**：调参空间大但最复杂、测试面最大，收益不抵成本（YAGNI）。

### 风险：坍缩三类向量（社区 tier 共识"什么真 OP"恒落三类）
未来任何新内容/数值都要对照自检，命中即高危：
1. **伤害上限/反伤** —— 本游戏**故意无防御层**（C1），等于天然规避此类；但若 Phase 3 引入减伤，须警惕。
2. **全屏覆盖密度** —— nuke 命中，Phase 2 重点复衡。
3. **绕过冷却的被动缩放** —— thousand_edge 命中，Phase 2 重点复衡。
把这三类当**事前筛子**，而非等 kpm 报表事后救火。

### 风险：Phase 0 改 `pick()` 可能影响 bot 遥测确定性
- 缓解：确定性投放 + 确定性多就绪选择规则，保证种子可复现；Skip/免费 reroll 仅人类路径。改完跑一遍 A/B 基线对照（C5）确认未漂移。

### 风险：gdUnit 截断陷阱
- 缓解：新增测试排在套件**末尾**，每次核对"发现测试数 == 预期"，别只看全绿（C6）。

---

## 7. 附录 · 精确事实表

### 7.1 协同乘区（C1 权威值，源 test_enemy_synergy.gd）
| 条件（DIRECT 通道） | 乘子 |
|---|---|
| 无状态 | ×1.0 |
| frozen（碎裂） | ×1.5 |
| stun 满血（处决基） | ×1.2 |
| stun 濒死（处决满） | ×2.0 |
| frozen + stun（满血） | ×1.8（=1.5×1.2，已锁） |
| frozen + amp0.25 | ×1.875（=1.5×1.25） |
| amp0.25（DIRECT 或 DOT） | ×1.25 |
| DOT + frozen / DOT + stun | ×1.0（DOT 不吃碎裂/处决） |

### 7.2 进化映射（C4 权威值，源 data/weapons/*.tres）
| 源武器 | → 进化 | 门控 perk | 阈值 |
|---|---|---|---|
| 斩 whip | bloody_whip | perk_attack 攻速 | 满级 + ×3 |
| 长弓 knife | thousand_edge | perk_attack 攻速 | 满级 + ×3 |
| 霜噬 frostbite | blizzard | perk_attack 攻速 | 满级 + ×3 |
| 连锁闪电 lightning | thunderstorm | perk_attack 攻速 | 满级 + ×3 |
| 回旋斧 boomerang | cyclone | perk_speed 移速 | 满级 + ×3 |
| 引力井 gravity_well | singularity | perk_speed 移速 | 满级 + ×3 |
| 缚灵 orb | mega_orb | perk_hp 生命 | 满级 + ×3 |
| 烈焰护体 aura | inferno_aura | perk_hp 生命 | 满级 + ×3 |
| 碎 maul | earthshatter | perk_hp 生命 | 满级 + ×3 |
| 亡者召唤 reanimate | horde | perk_hp 生命 | 满级 + ×3 |
| 火球 explosion | nuke | perk_damage 强化 | 满级 + ×3 |

### 7.3 卡池清单（C3 权威值，源 card_pool.gd CARDS + 注入）
- **54 张**：11 weapon + 22 upgrade + 4 synergy + 6 perk + 11 evolution（运行时注入）。
- 稀有度权重：common 100 / uncommon 50 / rare 20 / legendary 6。
- perk 上限：speed 8 / hp 10 / attack 8 / xp 6 / damage 8；**perk_heal 无上限（Phase 0 修）**。
- synergy：pierce(max3) / multishot(max2) / magnet(max3) / lifesteal(max4)。

---

## 8. 实现衔接

Phase 0 的 4 个单元将由 **writing-plans** 转为带 TDD 步骤的实现计划（`docs/superpowers/plans/2026-06-20-card-pool-delivery-*.md`）。建议落地顺序按杠杆：**单元 1（进化可达性）→ 单元 2（去陷阱）→ 单元 3（Skip）→ 单元 4（经济）**，每单元独立提交、独立绿测。
