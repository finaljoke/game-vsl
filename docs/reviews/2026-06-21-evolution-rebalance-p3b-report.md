# P3b · 进化复衡后衡报告（5 进化复衡 + 数据闭环验证）

- **日期**：2026-06-21
- **定位**：P3b 交付物。承 [P3 判据闭环报告](2026-06-20-dominance-criteria-report.md) §4b「P3b 输入清单」，据已验证的 backlog 主轴判据 + 混编 A/B 边际归因**复衡** 5 个进化（P3 零数值改动，复衡留 P3b）。落实 [P3b 设计 spec](../superpowers/specs/2026-06-21-p3b-evolution-rebalance-design.md)。
- **上位契约**：[基石设计](../superpowers/specs/2026-06-20-combat-system-foundation-design.md) 柱 P4「进化=质变」（mega_orb 反例修正）· C4（质变守恒，gdUnit 锁）/ C5（遥测确定性）/ C6（测试核数）。
- **数据**：solo campaign（11×8，复衡后新跑）+ 混编 A/B（mixbase/mix_knife/mix_orb/mix_explosion×8，复衡后新跑）。

## 0. 一句话结论

> _（待 campaign 验证后填）_

## 1. 复衡总览（首轮数值 + 质变守恒）

5 个进化复衡，全程守 C4 质变守恒（每进化在设计意图轴严格 ≥ base 武器满级 L3，由 `test_evolution_contracts.gd` 新增 5 条契约永久锁）。gdUnit 全量 **550/550 绿 0 error**（基线 543 + 5 契约 + 2 dash AoE 行为 = 550，C6 核数无截断）。

| 进化 | 坍缩类/问题 | 复衡杠杆（首轮） | 质变守恒（vs base L3） |
|---|---|---|---|
| **nuke**(explosion) | ②全屏覆盖 | field_dur4→3 / cd0.5→0.7 / blast_radius128→112 | r112>100 / burn14>10 / field3≥3 / +二连爆 |
| **thunderstorm**(lightning) | ②全屏覆盖 | sky_strikes3→2 / cd0.45→0.6 / chains8→6 | chains6>5 / cd0.6<0.7 / +天雷 |
| **earthshatter**(maul) | ②全屏覆盖 | shockwave_radius280→240 / shockwave_damage40→32 | dmg72≥72 / r170≥170 / +冲击波 |
| **thousand_edge**(knife) | ③绕冷却缩放 | **crit_bonus1.0→0.6**（满血恒暴击→概率）/ volley5→3 / cd0.15→0.22 | volley3≥2 / pierce8>4 / cd0.22<0.5 / crit_bonus0.6>0.35 |
| **mega_orb**(orb) | 偏弱/不安全/P4 倒退 | **质变重做**：orbit68→120 宽轨 + dash 到点 AoE(r90/dmg24) + dmg14→18 / dash_interval3→2 | total_orbs8>4 / orbit120>68 / dmg18>14 / +dash AoE(base 无) |

**机制纠错记录**：thousand_edge 首版设计误写「crit_range 99999→320」。核 [knife_weapon.gd](../../scenes/weapons/knife/knife_weapon.gd) `longbow_crit_bonus` = `dist>crit_range OR full_hp→给暴击`：crit_range99999 使暴击**纯由满血门控**，降 crit_range 反让远敌也暴=**反向 buff**。正确削法 = 降 crit_bonus（恒暴击→概率），crit_range 保持极大。spec 已纠（commit）。

## 2. 工作流 A · 三个 nuke 类（solo 验证，11×8 重跑）

数据闭环三轮（首轮砍轻 → 二轮砍到契约下沿 → 三轮榨干剩余数据杠杆）。复衡前后（前=P3 §1b 原值 ground truth，后=P3b solo 重跑 `analyze_dominance`）：

| 进化 | 前 backlog/clear_eff/verdict | 后 backlog/clear_eff/verdict | clear_eff 降幅 | 终态 |
|---|---|---|---|---|
| **earthshatter**(maul) | 12 / 15.06 / OP | **20 / 9.15 / ok** | −39% | ✅ **落带** |
| **thunderstorm**(lightning) | 8 / 27.80 / OP | 15 / 13.34 / OP | **−52%** | ⚠ P4 身份地板（见下） |
| **nuke**(explosion) | 5 / 37.09 / OP | 12 / 19.60 / OP | **−47%** | ⚠ P4 身份地板（见下） |

复衡杠杆终值：nuke `field_dur4→3 / cd0.5→1.3 / blast128→100 / burn14→10`（除二连爆/damage 外全到 base 地板）；thunderstorm `sky_strikes3→1 / chains8→5 / cd0.45→0.7 / sky_radius70→35 / sky_damage22→14`（chains/cd 到 base 地板、天雷收至最小）；earthshatter `shockwave_radius280→240 / shockwave_damage40→32`。

**中位漂移复查**（新中位下）：未动 8 进化无被动破带——aura/boomerang/frostbite/gravity_well/reanimate 仍 `ok`；whip/knife/orb 仍 `weak`（可达性非进化弱，P3 已终判）。✅

### 2a. nuke/thunderstorm 残留 OP = P4 身份地板，非复衡失败

两者 clear_eff 已大幅降（−47%/−52%、backlog 翻 2–3 倍），但仍判 OP。**根因经数据闭环确证为身份地板**：

- **thunderstorm**：`chains5/cd0.7` 已 **= base lightning L3**，天雷收至 `radius35/damage14`（近无）。即 thunderstorm 清场 ≈ base lightning L3 的链式清场。再降须 `chains<5`（弱于 base 形态）= 违 P4「进化≥base」。
- **nuke**：`blast_radius100/burn_dps10/field_dur3` 已 = base explosion L3 地火，`cd1.3` = base。残留来自唯一质变「二连引爆」（base explosion 无）。再降须 gut 二连爆 = 退回「explosion + 大数字」的 P4 倒退（正是宪法点名要避免的）。

**判据局限定性**（承 P3 §4b#6「无单一轴是完整支配度量」）：evolution-median 清场带被大量弱进化（knife/orb/whip reached≈0、reanimate 等）**压低**（median clear_eff≈7，带上沿≈9.45）。强 AoE 进化在其 P4 地板（=base 形态清场 + 最小化质变）天然高于此带。earthshatter 是突发型（cd1.6 单砸）故能压进带；nuke（连续地火 + 二连爆）/thunderstorm（链 cd0.7）是连续/高频型，地板高于带。

**裁决**：取**砍到 P4 身份地板**为本轮终态（spec §2「砍到带顶不砍中位」+ §9 过校正守卫的下沿）。强行入带须违 P4，那才是"不正确"。三者全程守 C4 契约绿（`test_evolution_contracts` 13/13）。复衡效应显著（clear_eff −39%~−52%），支配性实质削弱。残留 verdict OP 列为**判据持续改进项**（§5）。

## 3. 工作流 B/C · thousand_edge / mega_orb（混编 A/B 验证）

> _（待混编 A/B campaign + analyze_mix_ab 填：thousand_edge 边际降向控制组 / mega_orb 边际升 + hp_min 升 + 未翻 OP）_

## 4. 退出判据核对

> _（待填：逐条对照 spec §8）_

## 5. 残留局限 / 下一步

> _（待填：二轮补刀记录、未纳入项〔inferno_aura 手感 / base 可达性→内容广度阶段〕、C5 确定性抽查）_
