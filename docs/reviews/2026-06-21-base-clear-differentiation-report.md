# 内容广度 · base 清场组差异化报告（判据轻量重桶 + frostbite 控场预算搬移）

- **日期**：2026-06-21
- **定位**：落实 [explosion base 清场复衡报告](2026-06-21-explosion-base-clear-content-breadth-report.md) §5 残留①「base 清场角色组双峰、分化不足」+ frostbite 带边 OP。属基石 spec（[combat-system-foundation](../superpowers/specs/2026-06-20-combat-system-foundation-design.md)）「先精后扩」的 base 武器平衡 / 内容广度 track，受契约 C1–C6 约束。承 P3c §4b#6 / §5② 非清场支配轴（本轮只轻量重桶，不补全多轴）。
- **用户决策**（brainstorm）：核心目标＝两者结合（修判据角色桶 + 轻改 frostbite 身份）；判据深度＝轻量重桶（不补全多轴）；frostbite 方向＝预算搬移（伤害→控制，保 densest_center）。
- **设计/计划**：[spec](../superpowers/specs/2026-06-21-base-clear-differentiation-design.md) · [plan](../superpowers/plans/2026-06-21-base-clear-differentiation.md)。
- **数据**：base 清场组复测 telemetry/base_clear（solobase_frostbite ×5 重跑覆盖新值，余 4 武器复用上一报告有效数据）+ blizzard 进化复测 telemetry/frostbite_recheck（solo_frostbite ×8 重跑 → 新 blizzard，余 18 进化复用 p3b_solo）。

## 0. 一句话结论

> **P3c 把「base 清场角色组双峰、分化不足」与 frostbite 带边 OP 列为内容广度残留。诊断证其一半是「桌桶假阳」：判据把 base 清场角色组当同质 clear 组，但组里 maul（重控）/aura（防御）只在进化后清场、frostbite 本是控场底盘——三者拉高清场带中位，使真清场专精（explosion/frostbite）显「OP」。本轮①判据轻量重桶（`BASE_ROLE` base 形态角色映射 + `base_role_for`，纯分析层零游戏码、+2 TDD）：base 清场带只含真清场专精 {explosion, lightning}，frostbite/maul/aura 重桶为 control/defense（clear_axis=na、免清场判）——复测 explosion 17（−0.22 ok）/ lightning 26（+0.22 ok）双双落带，假阳消除；②frostbite 控场预算搬移（damage 13/14/16→9/10/11，slow_factor 0.6/0.5/0.45→0.5/0.42/0.35，slow_dur/freeze_dur 上调）：base 清场 backlog 16.8→22（脱离与 explosion 并列的强清场底，坐实「控场非清场」身份），仍 5 种子全 victory；③blizzard 连带上调控制（slow_factor 0.45→0.30、slow_dur 2.0→2.8、freeze 1.0→1.3）守 C4「进化≥base」，进化复测 backlog 24（+0.24 **ok**，未被控制 buff 推成 OP）。途中一条诚实发现记为资产：frostbite 控制 buff 只「部分」补偿伤害损失的生存（hp_min 0.80→0.57，仍健康），证 frostbite 生存更依赖「杀」而非「控」——故不为追 backlog≥30 再砍伤害（会反向掏生存），止于「清场分明 + 生存健康」的最佳落点。gdUnit 565/565 绿、C6 核数无截断、C4 绿。**

## 1. Deliverable A · 判据轻量重桶（纯分析层，零游戏改动）

[explosion 报告](2026-06-21-explosion-base-clear-content-breadth-report.md) §2 用 `EVOLUTION_ROLE`（进化角色）当 base 清场组判据，把 5 个「进化后是 clear」的武器都当 base 清场专精比较。但 base 形态与进化角色**可不同**：

| base 武器 | 进化角色（EVOLUTION_ROLE） | **base 真角色** | 理由 |
|---|---|---|---|
| explosion | clear | **clear** | base 即爆发清场 |
| lightning | clear | **clear** | base 即链跳清场 |
| frostbite | clear | **control** | base 是 slow→freeze 控场底盘，进化 blizzard 才地场清场 |
| maul | clear | **control** | base 是重击硬直击退，进化 earthshatter 才冲击波清场 |
| aura | clear | **defense** | base/进化都防御（进化 inferno_aura 加吸血） |

**改动**（[run_analysis.gd](../../tools/run_analysis.gd)）：加 `BASE_ROLE` 覆盖表 + `base_role_for(wid)`（BASE_ROLE 优先 → 回退 `EVOLUTION_ROLE` → 默认 clear）；[analyze_base_clear.gd](../../tools/analyze_base_clear.gd) 建 roles 时改用 `base_role_for`。**不动 `analyze_dominance`/进化层**（进化角色不变）。复用 P3c `flag_dominance` 角色感知逻辑，零新判据。+2 TDD（排 [test_run_analysis](../../tests/test_run_analysis.gd) 套件末，C6）：① `base_role_for` 映射/回退；② `flag_dominance` 带 base roles → 清场带两专精 ok、三非清场 clear_axis=na。

**效果**（base 清场组复测，solobase_ × 5 种子，满级窗口，`--fixed-fps 60`）：

| base 武器 | 角色 | backlog（低=强清场） | backlog_dev | hp_min | verdict |
|---|---|---|---|---|---|
| **explosion** | clear | 17 | **−0.22** | 0.66 | **ok** |
| **lightning** | clear | 26 | **+0.22** | 0.91 | **ok** |
| frostbite | control | 22 | +0.04 | 0.57 | ok（na） |
| maul | control | 137 | +5.33 | 0.86 | ok（na） |
| aura | defense | 168 | +6.76 | 0.78 | ok（na） |

清场带现只在 {explosion 17, lightning 26} 上取（中位 21.5，±0.35 带 [14.0, 29.0]）→ **explosion −0.22 / lightning +0.22 双双落带 ok**。对比重桶前：explosion 跟 maul(137)/aura(168) 同组比，中位被拉高、explosion 显 −0.49 OP（上一报告）；重桶后假阳消除。frostbite/maul/aura 角色为 control/defense → `clear_axis="na"`、不参清场中位、不判清场 OP（backlog 仍记录为 context）。

## 2. Deliverable B · frostbite 控场预算搬移（[frostbite.tres](../../data/weapons/frostbite.tres)）

把数值预算从「杀」挪到「控」，保 `densest_center` 瞄准机制——与 explosion 爆发杀的区别从「同瞄准不同效果」坐实为「控场 vs 清场」：

| 轴 | 旧 L1/L2/L3 | 新 L1/L2/L3 | 方向 |
|---|---|---|---|
| damage | 13/14/16 | **9/10/11** | raw 清场 ↓（约 −30%） |
| slow_factor（低=更慢） | 0.6/0.5/0.45 | **0.5/0.42/0.35** | 减速 ↑ |
| slow_dur | 1.5/1.8/2.0 | **1.8/2.2/2.5** | 控制时长 ↑ |
| freeze_dur | 0.6/0.8/1.0 | **0.7/0.9/1.1** | 冻结时长 ↑ |
| area / cooldown | 90/100/110 · 1.8/1.4/1.1 | 不变 | — |

**A/B 前后**（base 清场组，solobase_frostbite ×5）：

| | backlog | backlog（与 explosion 关系） | hp_min | outcome |
|---|---|---|---|---|
| 旧 frostbite（上一报告 §2） | 16.80 | **与 explosion 16.8 并列**（清场组最强清场之一） | 0.80 | victory |
| **新 frostbite** | **22** | **explosion 17 之上**（脱离强清场底，向 lightning 26 靠） | 0.57 | victory（5/5） |

**结论**：raw 清场明显下降（backlog +31%），frostbite 从「与 explosion 并列的最强清场」移到「清场组中段」，与 explosion 的爆发清场身份**分明**；控制三轴（slow/slow_dur/freeze）全升，坐实控场底盘身份。5 种子全 victory、reached 1.0，仍能 solo 存活。

**一条诚实发现（记为方法资产）**：预算搬移的理论是「damage↓ 但 control↑ 补偿生存」。但数据显示生存**下降**（hp_min 0.80→0.57）——控制 buff 只**部分**补偿了伤害损失带来的生存损耗。这证 frostbite 的 solo 生存更依赖「杀」（damage）而非「控」（slow/freeze）：低伤害=杀得慢=更多敌触玩家，强控制只拦截了一部分。⇒ 若为追计划里「backlog≥30」的更大分离去再砍伤害，会进一步掏空生存（方向错）。故止于当前落点（backlog 22 / hp 0.57，清场分明 + 生存健康），不强求绝对分离值——对 control/mix-chassis 角色（设计就该让位给伤害 carry）这是恰当落点。

## 3. Deliverable C · blizzard 连带复核（[blizzard.tres](../../data/weapons/blizzard.tres)，守 C4/P4）

frostbite 控制增强后会超现 blizzard，违「进化≥base」。平行上调 blizzard 控制使严格 ≥ 新 frostbite L3：

| 轴 | 旧 | 新 | vs 新 frostbite L3 | C4 |
|---|---|---|---|---|
| slow_factor | 0.45 | **0.30** | ≤ 0.35（更强减速） | ✓ |
| slow_dur | 2.0 | **2.8** | ≥ 2.5 | ✓ |
| freeze_dur | 1.0 | **1.3** | ≥ 1.1 | ✓ |
| damage / area / field_dur / cooldown | 20 / 130 / 3.0 / 2.0 | 不变 | damage 20 ≥ 11、area 130 ≥ 110 | ✓ |

新增 C4 守恒契约 `test_blizzard_control_ge_base_l3`（[test_evolution_contracts.gd](../../tests/test_evolution_contracts.gd)，TDD RED→GREEN：先改 frostbite 使契约 FAIL，再改 blizzard 转 PASS）。

**进化复测**（telemetry/frostbite_recheck，solo_frostbite ×8 重跑 → blizzard，`analyze_dominance`）：

| | backlog | backlog_dev | hp_min | verdict_new |
|---|---|---|---|---|
| **blizzard**（evolve_frostbite） | 24 | **+0.24** | 0.82 | **ok** |

只升控制不升伤害 → blizzard 清场（靠伤害+地场）未上窜：backlog 不降反微升（dev +0.24，落进化清场带内），**未被控制 buff 经自碎裂推成 OP**。确证设计假设——blizzard 的控制 buff 是「纯控制」非「隐性清场」。

> **数据范围注**：frostbite_recheck 仅重跑 solo_frostbite（按计划复用 p3b_solo 的余 18 进化），故该报告里 explosion/lightning 等行是**旧值**（evolve_explosion 显示的 backlog 12/−0.40 是上一报告**复衡前**的旧 nuke，非当前）。唯 blizzard 行为新测。但 blizzard 的带内定位**稳健**：清场带中位由 maul（20）驱动，blizzard 24 居带中，旧/新 explosion 值（12 vs 复衡后 ~13.45）都不改中位 → 结论不受污染。

## 4. 退出判据核对（vs [spec §6](../superpowers/specs/2026-06-21-base-clear-differentiation-design.md)）

| # | 判据 | 结果 |
|---|---|---|
| 1 | base 清场带重桶为 {explosion, lightning}，二者 ok | ✅ explosion −0.22 ok / lightning +0.22 ok（假阳消除） |
| 2 | frostbite/maul/aura clear_axis=na 不判清场 OP | ✅ 三者重桶 control/control/defense，verdict ok（na），TDD + 实测双证 |
| 3 | frostbite raw 清场下降（backlog 升）、控制增强、仍存活 | ✅ backlog 16.8→22、控制三轴升、5/5 victory（hp_min 0.57 健康） |
| 4 | C4 blizzard ≥ frostbite + blizzard 进化组仍 ok | ✅ 守恒契约绿（0.30≤0.35 / 2.8≥2.5 / 1.3≥1.1 / 20≥11 / 130≥110）；blizzard verdict_new ok（+0.24，未成 OP） |
| 5 | gdUnit 全绿 + 测数核对无截断 | ✅ **565/565 绿 0 error**（562 + 2 判据 TDD + 1 C4 契约）；39/39 套件无截断 |
| 6 | C5 确定性继承（游戏码仅 2 .tres + 测试） | ✅ 游戏码仅改 frostbite/blizzard 两 .tres；分析层纯函数（base_role_for）→ 确定性继承 |

## 5. 残留局限 / 下一步

1. **base 清场带仅 2 员（explosion/lightning）**：重桶后真清场专精只剩两个，base 形态判 OP 的判别力较弱——可接受（base 非主支配关口，进化层才是；未来加清场武器自动入带）。
2. **非清场角色无专属支配轴（全 §5② 多轴未补）**：frostbite/maul/aura/单体/召唤现仅「免清场判」，无 control 覆盖率 / defense 续航 / single DPS / summon 吞吐的专属度量。本轮按用户「轻量重桶」决策只做角色桶，多轴度量整体留作内容广度后续专项（承 P3c §4b#6 / §5②）。
3. **frostbite 机制差异化留后续**：本轮选预算搬移（最稳），未动瞄准/未加基础减速场等机制层差异化；frostbite 生存「依赖杀更甚于控」的发现提示——若要它作纯控场而不掉生存，需的是机制补偿（如护场/拦截）而非继续砍伤害。
4. **测量基建延续为长期资产**：`base_role_for` 角色桶与上一报告的 `solobase_`/`max_level_time`/`analyze_base_clear` 一起，构成 base 武器支配判据基建（对偶 P3c 进化角色感知判据），可对未来 base/混编遥测零重跑重算。
