# base 清场组差异化 · 设计 spec（判据轻量重桶 + frostbite 控场预算搬移）

- **日期**：2026-06-21
- **定位**：落实 [explosion base 清场复衡报告](../../reviews/2026-06-21-explosion-base-clear-content-breadth-report.md) §5 残留①「base 清场角色组双峰、分化不足」+ frostbite 带边 OP。属基石 spec（[combat-system-foundation](2026-06-20-combat-system-foundation-design.md)）「先精后扩」的 base 武器平衡 / 内容广度 track，受契约 C1–C6 约束。承 P3c §4b#6 / §5② 非清场支配轴（本轮只轻量重桶，不补全多轴）。
- **用户决策**（brainstorm）：核心目标＝**两者结合**（修判据角色桶 + 轻改 frostbite 身份）；判据深度＝**轻量重桶**（不补全多轴）；frostbite 方向＝**预算搬移**（伤害→控制，保 densest_center 机制）。

## 0. 一句话定调

> **base「清场角色」组其实角色异质：explosion/lightning 是清场专精，frostbite/maul 是控场，aura 是防御。判据把后三者混进清场带拉高中位，使真清场专精显「OP」（桌桶假阳）。本轮①判据轻量重桶（base 形态角色映射,清场带只含 explosion/lightning → 各落自己基准 ok,非清场角色 clear_axis=na 免判,纯分析层零游戏码）；②frostbite 预算搬移（伤害↓、slow/freeze↑,保 densest_center）真正坐实其「控场非清场」身份、与 explosion 爆发杀分明、强化混编底盘角色；③blizzard 连带上调控制守 C4「进化≥base」。explosion/lightning/maul/aura 零游戏改动。**

## 1. 北极星与背景

报告 §2 测得 base 清场组（solobase_ 5 武器 × 5 种子，满级窗口，backlog 低=强清场）：

| base 武器 | 瞄准 | 机制 | backlog | 真角色 |
|---|---|---|---|---|
| explosion | densest cluster | 爆发 + 地火 | 16.8 | 清场专精 |
| frostbite | densest cluster | slow→freeze **控制** + 伤害 | 16.8 | **控场**（混编底盘） |
| lightning | 贪心链跳 | 分散链 | 26.4 | 清场（分散） |
| maul | 自我中心 | 重击 + 硬直 + 击退 | 137 | **重控**（进化后清场） |
| aura | 自我中心 | 被动燃烧脉冲 | 168 | **防御**（进化后吸血） |

组中位 26.4 由 maul/aura 拉高 → explosion/frostbite 显「低 49%/36% = OP」。但 maul/aura 非清场专精（仅进化后清场或本就防御），这是**桌桶假阳**。frostbite 的「OP」同时是其**身份危机**：它是控场底盘（低清场设计），却因 freeze + 自碎裂 1.5× + 攻速堆叠把控制变成伤害清场。

## 2. Deliverable A · 判据轻量重桶（[run_analysis.gd](../../../tools/run_analysis.gd) / [analyze_base_clear.gd](../../../tools/analyze_base_clear.gd)，纯分析层）

- **加 `BASE_ROLE` 覆盖 + `base_roles_for(by_wid)`**：base 形态角色映射 `explosion/lightning=clear`、`frostbite/maul=control`、`aura=defense`；未覆盖的 wid 回退 `EVOLUTION_ROLE`。
- **`analyze_base_clear` 改用 `base_roles_for`**（建 roles 时）。**不动 `analyze_dominance`/进化层**——进化角色不变（maul→earthshatter 进化后确是清场、aura→inferno 仍防御）。
- **效果**（复用 `flag_dominance` P3c 角色感知，零新判据逻辑）：base 清场带 = clear∩达满级 = {explosion, lightning}（中位 21.6，±0.35 带 [14.0, 29.2]）→ **explosion 16.8 / lightning 26.4 双双 ok**；frostbite/maul/aura `clear_axis="na"`、不参清场中位、不判清场 OP（其 backlog 仍记录，只是不当清场判）。
- **TDD**（test_run_analysis，排套件末，C6）：① `base_roles_for` 映射正确（explosion clear / frostbite control / maul control / aura defense / 未覆盖回退）；② `flag_dominance` 带 base roles → explosion/lightning ok、三非清场 clear_axis=na 且非 OP。
- **局限（记残留）**：清场带仅 2 员（explosion/lightning），base 形态判 OP 较弱判别力——可接受，base 非主支配关口（进化层才是），且未来加清场武器自动入带。非清场角色仅免判、**无专属支配轴**（全 §5② 多轴留残留）。

## 3. Deliverable B · frostbite 控场预算搬移（[frostbite.tres](../../../data/weapons/frostbite.tres)，游戏）

把数值预算从「杀」挪到「控」，保 `densest_center` 机制（与 explosion 爆发杀的区别从「同瞄准不同效果」坐实为「控场 vs 清场」）：

| 轴 | 现 L1/L2/L3 | 新 L1/L2/L3（起始假设，A/B 定量） | 方向 |
|---|---|---|---|
| damage | 13/14/16 | **9/10/11** | raw 清场 ↓（约 −30%） |
| slow_factor（低=更慢） | 0.6/0.5/0.45 | **0.5/0.42/0.35** | 减速 ↑ |
| slow_dur | 1.5/1.8/2.0 | **1.8/2.2/2.5** | 控制时长 ↑ |
| freeze_dur | 0.6/0.8/1.0 | **0.7/0.9/1.1** | 冻结时长 ↑ |
| area / cooldown | 90/100/110 · 1.8/1.4/1.1 | 不变 | — |

- **目标**：frostbite raw 清场明显下降（backlog 升、与 explosion 分明），控制明显增强（真控场身份 + 更强混编底盘），且仍能 solo 存活。**重桶后 frostbite 是 control 角色（clear_axis=na），无清场 OP 目标**——本变更是身份/手感/差异化，非入带。
- **副作用（正向）**：低清场 + 强控制让 frostbite 作 `MIX_CHASSIS` 更称职（更好为目标武器留敌 + 护场）。

## 4. Deliverable C · blizzard 连带复核（[blizzard.tres](../../../data/weapons/blizzard.tres)，守 C4/P4）

frostbite 控制增强后会超现 blizzard，违「进化≥base」。平行上调 blizzard 控制使严格 ≥ 新 frostbite L3：

| 轴 | 现 | 新 | 校验 vs 新 frostbite L3 |
|---|---|---|---|
| slow_factor | 0.45 | **0.30** | ≤ 0.35（更强） ✓ |
| slow_dur | 2.0 | **2.8** | ≥ 2.5 ✓ |
| freeze_dur | 1.0 | **1.3** | ≥ 1.1 ✓ |
| damage / area / field_dur / cooldown | 20 / 130 / 3.0 / 2.0 | 不变 | damage 20 ≥ 11 ✓ |

只升控制不升伤害 → blizzard 清场（靠伤害+地场）不应上窜；A/B 复核它在进化清场组仍 ok（不被控制 buff 经自碎裂推成 OP）。

## 5. 验证

- **gdUnit 全绿 + 测数核对（C6）**：更新值断言（`test_weapons_w2` frostbite L1 反射 damage/slow_factor；任何 frostbite/blizzard 数值断言）；blizzard ≥ frostbite 守恒（slow/freeze/damage）。新增判据 TDD 排末。
- **A/B（C5，`--fixed-fps 60`）**：① `solobase_frostbite` ×5 重跑 → `analyze_base_clear`：base 清场带 = {explosion, lightning} 双 ok、frostbite/maul/aura na、frostbite backlog 升且存活；② `solo_frostbite`→blizzard ×8 → `analyze_dominance`（余 10 进化复用 p3b_solo 有效数据）：blizzard 仍 ok。
- **C5**：游戏码仅改 2 个 .tres（frostbite/blizzard）+ 测试；分析层纯函数 → 确定性继承。
- **报告**：`docs/reviews/2026-06-21-base-clear-differentiation-report.md`（仿前报告骨架）+ 更新 MEMORY。

## 6. 退出判据

| # | 判据 | 验法 |
|---|---|---|
| 1 | base 清场带重桶为 {explosion, lightning}，二者 ok | `analyze_base_clear` + test_run_analysis |
| 2 | frostbite/maul/aura clear_axis=na 不判清场 OP | 同上 |
| 3 | frostbite raw 清场下降（backlog 升）、控制增强、仍存活 | `solobase_frostbite` A/B |
| 4 | C4 blizzard ≥ frostbite（slow/freeze/damage）；blizzard 进化组仍 ok | 守恒断言 + `solo_frostbite`→blizzard A/B |
| 5 | gdUnit 全绿 + 测数核对无截断 | 全量 gdUnit |
| 6 | C5 确定性继承（游戏码仅 2 .tres + 测试） | git diff 范围 |

## 7. 不做（YAGNI / 记残留）

- **全 §5② 多轴度量**（control 覆盖率 / defense 续航 / single DPS / summon 吞吐）：本轮只轻量重桶，非清场角色仍只免判、无专属支配轴。
- **maul/aura 零游戏改动**：仅重分类；base 弱清场对其控场/防御角色本就合适。
- **explosion/lightning 不再动**：重桶后落带 ok（explosion 已于上一报告复衡）。
- **frostbite 机制改动**（瞄准/加基础减速场）：本轮选预算搬移（最稳），机制差异化留后续。
