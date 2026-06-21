# P3c · 支配判据治本后衡报告（角色感知判据 v2 + nuke 残留根因诊断）

- **日期**：2026-06-21
- **定位**：治本 [P3b 后衡报告](2026-06-21-evolution-rebalance-p3b-report.md) §5#1「nuke/thunderstorm 残留 OP = 判据局限（最高优先后续）」。承 [P3 判据闭环报告](2026-06-20-dominance-criteria-report.md) §4b#6「无单一轴是完整支配度量 / 判据持续改进」。落实 [P3c 设计 spec](../superpowers/specs/2026-06-21-p3c-dominance-criterion-design.md) + [实现计划](../superpowers/plans/2026-06-21-p3c-dominance-criterion.md)。
- **用户指令**：`/goal 请治本`。
- **数据**：现存 [telemetry/p3b_solo](../../telemetry/p3b_solo)（11×8）零重跑重算 + nuke `secondary_count=0` 诊断 8 跑（telemetry/p3c_diag）+ 二连爆去地火 8 跑（telemetry/p3c_merged，已回退）。

## 0. 一句话结论

> **P3b 残留「nuke/thunderstorm OP」的真根因经诊断分为两层并分别处置：①判据层假阳——`flag_dominance` 用全 11 进化 backlog 中位做清场基准，混入非清场角色（aura175/boomerang98 天然高 backlog）+ 未达进化（backlog 退化 0）污染，使清场专精恒显异常强。判据 v2（角色感知清场组 + 未达过滤）对现存遥测零重跑重算即修正：thunderstorm OP→ok、earthshatter 守 ok、reanimate 召唤角色不再误判清场 OP，nuke 被隔离为唯一残留。②nuke 真残留——`secondary_count=0` 诊断证 base explosion L3 自身已清场到 backlog 13（dev −0.33，落带边），二连爆质变仅再 +−0.07 推到 −0.40；即 nuke 残留是 explosion 武器线的 base 清场强度，P4 内无有效杠杆（削二连爆到≈23%威力=砍质变违 P4 精神；削 base=违「进化≥base」且 base 平衡是范围外的内容广度阶段项）。先试的「二连爆去第二团地火」杠杆被数据证伪（backlog 不降只掉 hp 0.87→0.77）已回退。治本=判据 v2 正确归因隔离，nuke 残留诚实定性为 base 武器特征。全程零游戏侧改动（游戏码与 P3b 逐字节一致，C5 继承），gdUnit 554/554 绿、C6 核数无截断。**

## 1. 根因诊断（纠正 P3b §2a 的误诊）

P3b §2a 把 nuke/thunderstorm 残留 OP 归为「evolution-median 清场带被弱进化**压低**（median clear_eff≈7）」。**此诊断口径有误**：`flag_dominance` 的 verdict 实际跑 **backlog 主轴**（`clear_eff` 仅 context 列，见 [run_analysis.gd](../../tools/run_analysis.gd) 注释）。读 [p3b_solo/dominance_report.json](../../telemetry/p3b_solo/dominance_report.json) 量化真相（backlog_mean_med，反向：低=强清场）：

```
orb 0(未达) knife 0(未达) | nuke 11.69  thunderstorm 14.71  earthshatter 19.54
frostbite 23.28  reanimate 37.32  gravity 38.04  whip 50.53  boomerang 97.94  aura 175.12
```

全 11 中位 = 23.28、带底 15.13。nuke/thunderstorm 落带底下 → OP。**真根因是两层扭曲**：

1. **未达进化 backlog 退化为 0**：`summarize_evolution` 对 reached=0 的 knife/orb，`median([])`=0。「无数据」冒充「完美清场」污染基准（潜在正确性 bug：换数据集任意扭曲）。
2. **跨角色比较（真驱动假阳）**：backlog 是**角色依赖**量。非清场角色（aura 175 远轨 / boomerang 98 单体）天然高 backlog，混进同一中位基准，**清场专精恒显异常强**。这才是 nuke/thunderstorm 被误判的真因——非「弱进化压低 clear_eff」。

## 2. Deliverable A · 判据 v2（角色感知清场组 + 未达过滤）

`flag_dominance(by_evo, band, roles)` 改（[run_analysis.gd](../../tools/run_analysis.gd)，纯函数，零游戏改动）：
- **未达过滤**：`reached_ratio ≥ REACH_MIN(0.5)` 才计入任何带基准；未达仍判 weak，但不污染中位。
- **角色感知清场组**：`EVOLUTION_ROLE` 按**设计意图**（非测量值，非循环）分 clear/single/control/summon；backlog（清场轴）中位**仅在 clear 角色 ∩ 达进化组**内取。非清场角色 `clear_axis="na"`，不参清场中位、不判清场 OP（其高 backlog 是角色非弱）。
- `roles` 空 → 退化旧单组（现有 3 条 flag_dominance 单测回归绿）。

**重算前后对照**（现存 p3b_solo 零重跑重算，verdict v1 取 [p3b_solo/dominance_report.json](../../telemetry/p3b_solo/dominance_report.json) 的 dominance 判据）：

| 进化 | role | backlog | dev(v2) | **v1 dominance** | **v2** | 处置 |
|---|---|---|---|---|---|---|
| explosion(nuke) | clear | 11.69 | −0.40 | OP | **OP** | 隔离真残留 → §3 |
| **lightning**(thunderstorm) | clear | 14.71 | −0.25 | **OP** | **ok ✅** | **假阳消除**（落清场组带内）|
| maul(earthshatter) | clear | 19.54 | +0.00 | ok | ok | 清场组中位 |
| aura | clear | 175.12 | +7.96 | ok | ok | clear 但 backlog 高、hp 安全 |
| frostbite | clear | 23.28 | +0.19 | ok | ok | 清场组带内 |
| boomerang | single | 97.94 | — | ok | ok | 非清场角色不参清场轴(`na`) |
| gravity_well | control | 38.04 | — | ok | ok | 同上 |
| reanimate | summon | 37.32 | — | （旧 kpm 误 OP）| ok | 召唤角色不再误判清场 OP |
| knife/orb/whip | single/control/clear | 0/0/50.5 | — | weak | weak | reached<0.5 未达过滤 |

**治本效果**：thunderstorm 假阳消除（OP→ok）、earthshatter 守 ok、非清场角色不再被清场轴误判，nuke 被干净隔离为**唯一**残留。判据 v2 是分析层（[analyze_dominance.gd](../../tools/analyze_dominance.gd) 传 `roles_for`），零游戏改动、可对任意现存遥测重算。

## 3. Deliverable B · nuke 残留根因诊断（base 驱动，P4 不可削）

判据 v2 隔离出 nuke（dev −0.40，仅过 ±0.35 带一点点）。**先试「二连爆不叠第二团地火」（保 P4，去翻倍持续清场）杠杆，再用诊断验根因**：

| nuke 配置 | backlog | dev | verdict | hp_min |
|---|---|---|---|---|
| 原始（二连爆 + 双地火） | 11.69 | −0.40 | OP | 0.87 |
| 杠杆 1：二连爆去第二团地火 | ~11.8 | −0.39 | OP | **0.77** |
| **诊断：secondary_count=0（纯 base explosion L3）** | **13.0** | **−0.33** | **ok** | 0.85 |

**两条决定性发现**：
1. **去第二团地火被证伪**：backlog 几乎不动（11.69→11.8），只掉 hp（0.87→0.77）——第二团**地火**不是清场驱动，**二连爆的爆发伤害**才是。该杠杆「清场没削、只损安全」严格变差 → **已回退**（[explosion_weapon.gd](../../scenes/weapons/explosion/explosion_weapon.gd) 精确复原，git diff 空）。
2. **残留是 base 驱动**：secondary_count=0（无任何二连爆=纯 base explosion L3 行为）backlog=13、dev −0.33、**verdict ok**。即 **base explosion L3 自身已清场到落带边**，二连爆质变仅再 +−0.07 推过线。

**裁决（治本而非治标）**：nuke 残留 OP **不是进化缺陷，是 explosion 武器线的 base 清场强度**。P4 内无有效杠杆：
- 削二连爆至 ≈23% 威力才能把 backlog 从 11.69 抬到带底 12.70 → 二连爆近乎装饰，**违 P4「进化=质变」精神**。
- 削 base 形态 → **违 P4「进化≥base」**；且 base 武器清场/可达性是 P3c **明确范围外**（spec §1，→ 内容广度阶段）。

故**保持 nuke 原值**（零改动），判据 v2 已把它从「与 thunderstorm/earthshatter 混判」净化为「唯一真残留 + 正确归因为 base 特征」。这是诚实治本：根因查清并正确归属，不为入带强削质变（那是治标）。

## 4. 退出判据核对（对照 spec §6）

| # | 判据 | 结果 |
|---|---|---|
| 1 | 判据 v2：thunderstorm/earthshatter OP→ok；非清场角色不判清场 OP；未达不污染基准 | ✅ thunderstorm OP→ok、earthshatter ok、reanimate 召唤不误判、knife/orb/whip 未达过滤为 weak |
| 2 | nuke 二连爆 script 改后 C4 绿/P4 守 + 行为单测 | ⚠ **改向**：去地火杠杆被诊断证伪 → 回退（数据闭环）。C4 13/13 绿、P4 守（零改动）。保主爆铺地火回归测试 |
| 3 | nuke backlog 升向清场组带 → ok | ⚠ **诊断证 P4 内不可达**：base L3 自身已 backlog 13/落带边，二连爆仅 +−0.07；残留=base 武器特征（范围外），诚实记录非强削 |
| 4 | 现有 3 条 flag_dominance 单测 + 全量 gdUnit 绿 + C6 核数 + C5 | ✅ **554/554 绿 0 error**（基线 550 + 判据 v2 三单测 + explosion 回归一单测）；C6 核数无截断；C5 游戏码与 P3b 逐字节一致（P3c 仅改 tools/tests/docs）→ 继承 P3b 聚合稳定 |
| 5 | 后衡报告 | ✅ 本文 |

**总评**：核心目标（判据治本）**完全达标**——assert 的「判据局限」根因查清并修正，thunderstorm/earthshatter 假阳消除，nuke 净化隔离。#2/#3 诚实改向：nuke 残留经诊断证为 base 武器特征（P4 不可削、范围外），杠杆证伪即回退，未为入带违 P4。零游戏侧改动、零破坏既有绿测。

## 5. 残留局限 / 下一步

1. **explosion 武器线 base 清场强度（→ 内容广度阶段）**：base explosion L3 自身 backlog 13（落带边）是 nuke 残留的真源。属 base 武器平衡（spec §1 范围外）。下一步若复衡 base explosion 清场，须连带复核其进化 nuke——但那是 base 平衡课题，非进化判据课题。
2. **非清场角色的支配轴（判据持续改进）**：判据 v2 让非清场角色（single/control/summon）`clear_axis="na"`、只在清场轴免判 OP；但它们各自的支配度量（单体 DPS / 控场覆盖 / 召唤吞吐）尚无专属轴。承 P3 §4b#6，属判据后续。本轮聚焦清场支配假阳，未扩。
3. **REACH_MIN / band 灵敏度**：nuke dev −0.40 仅过 −0.35 带一点点，且清场组仅 5 员（小样本中位有噪声）。「带边」case 本质上对组成敏感；判据 v2 已尽量公平（同角色比），但单一进化卡带边的精度极限仍在——绝对清场阈值（backlog 距 FLOOR 的绝对量）可作未来补充轴。
4. **判据 v2 是分析层资产**：`flag_dominance` 角色感知 + `roles_for` + `EVOLUTION_ROLE` 已 TDD 锁（test_run_analysis 32/32），可对任意未来 solo/混编遥测零重跑重算，沉淀为长期判据基建。
