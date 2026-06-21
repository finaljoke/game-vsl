# P3b · 进化复衡后衡报告（5 进化复衡 + 数据闭环验证）

- **日期**：2026-06-21
- **定位**：P3b 交付物。承 [P3 判据闭环报告](2026-06-20-dominance-criteria-report.md) §4b「P3b 输入清单」，据已验证的 backlog 主轴判据 + 混编 A/B 边际归因**复衡** 5 个进化（P3 零数值改动，复衡留 P3b）。落实 [P3b 设计 spec](../superpowers/specs/2026-06-21-p3b-evolution-rebalance-design.md)。
- **上位契约**：[基石设计](../superpowers/specs/2026-06-20-combat-system-foundation-design.md) 柱 P4「进化=质变」（mega_orb 反例修正）· C4（质变守恒，gdUnit 锁）/ C5（遥测确定性）/ C6（测试核数）。
- **数据**：solo campaign（11×8，复衡后新跑）+ 混编 A/B（mixbase/mix_knife/mix_orb/mix_explosion×8，复衡后新跑）。

## 0. 一句话结论

> **P3b 据 P3 已验证判据复衡 5 进化：earthshatter 清场落带（OP→ok）；nuke/thunderstorm 砍到 P4 身份地板（clear_eff −47%/−52%、backlog 翻 2–3 倍），残留 OP 经确证为判据局限（evolution-median 带被大量弱进化压低，P3 §4b#6）非复衡失败——再削须让进化弱于 base 形态即违 P4；thousand_edge 拆「满血恒暴击」cheese（crit_bonus 1.0→0.6）落控制组下；mega_orb 质变重做（宽轨 orbit68→120 + dash 到点 AoE）从「偏弱(+3)+最不安全(hp0.18)+P4 数值倒退」修为「健康中-强清场(+15)+安全(hp0.86)+真质变」，过冲后回收未翻 OP。全程守 C4 质变守恒（5 契约锁）/P4，gdUnit 550/550 绿、C5 聚合稳定。**

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

混编 A/B（mixbase 底盘 vs mix_target，共时重叠窗边际归因，8 种子）。控制组 explosion(→nuke) 给「强清场」定标（nuke 复衡后控制 +25→+19）：

| 目标 | P3 marginal/hp | P3b marginal | clear_eff_mix | hp_min | 终判 |
|---|---|---|---|---|---|
| **explosion**（控制/nuke） | +25 | +19 | 22.37 | 0.91 | 强清场基准（已削） |
| **thousand_edge**(knife) | +16 / 0.88 | **+16** | **14.25** | 0.85 | ✅ 削成功（clear_eff 三者最低，marginal ≤ 控制） |
| **mega_orb**(orb) | +3 / 0.18 | **+15** | **15.34** | **0.86** | ✅ 质变重做成功（buff + 安全，回收后未翻 OP） |

### 3a. thousand_edge：满血恒暴击 cheese 已消，落控制组下

复衡 `crit_bonus1.0→0.6`（满血恒暴击 guaranteed_crit→60% 概率）+ `volley5→3` + `cd0.15→0.22`（原始输出 −50%+）。混编 A/B：marginal +16 **≤ 控制 +19**（退出判据 §8#2 达标），且 `clear_eff 14.25` 是三者**最低**（削最彻底）。

**供给饱和 caveat**：底盘只留 ~29 敌（backlog_base），thousand_edge 即便削后仍清空可用敌 → marginal 被**供给上限钳制**在 +16（非输出上限），掩盖了完整 −50% 削幅（clear_eff 仅显 15.7→14.25）。真实削幅在更高密度环境才完全显现。判据局限记 §5。**裁决：恒暴击 cheese 已拆（核心 OP 驱动），落控制组下，削成功**。

### 3b. mega_orb：质变重做大成功（修偏弱 + 修不安全 + 守 P4）+ 过冲回收

**首轮重做**（orbit68→120 宽轨 + dash 到点 AoE r90/dmg24 + dmg14→18 + interval3→2）一击修复两大病：marginal **+3→+16**（5×，从清场可忽略到强清场）、hp_min **0.18→0.94**（从最不安全到最安全）。但 clear_eff 飙到 **25.66**（三者最高、超控制）= **过冲翻 OP**。

**过冲回收**（spec §5c 守卫）：`dash_aoe r90→70/dmg24→15 + dmg18→16 + interval2→2.5`（削 AoE 清场，**保宽轨 orbit120 安全**）。回收后：marginal **+15**（仍远超 P3 +3）、clear_eff **15.34**（中位、低于控制 22.37 = **不再 OP**）、hp_min **0.86**（仍安全）。

**终判**：mega_orb 从「偏弱(+3) + 最不安全(0.18) + P4 数值倒退」重做为「健康中-强清场(+15) + 安全(0.86) + **真质变**（宽轨区域控制 + dash 到点群伤 AoE，base orb 无）」。守宪法 P4「进化=质变」，呼应并修正其历史「数值倒退」反例。退出判据 §8#3 达标（marginal≫+3、hp≫0.18、未翻 OP）。

## 4. 退出判据核对（对照 spec §8）

| # | 判据 | 结果 |
|---|---|---|
| 1 | nuke/thunderstorm/earthshatter verdict OP→ok（不掉底）；新中位下未动进化无破带 | ⚠ **部分**：earthshatter ✅ ok；nuke/thunderstorm 砍到 **P4 身份地板**（clear_eff −47%/−52%）但残留 OP=判据局限（§2a，非掉底、非复衡失败）。未动 8 进化无被动破带 ✅ |
| 2 | thousand_edge 混编 A/B 边际 ≤ 控制组 nuke；仍 ≥ base | ✅ marginal +16 ≤ 控制 +19；clear_eff 14.25 三者最低（恒暴击 cheese 拆）；契约绿（≥base）。供给饱和 caveat（§3a） |
| 3 | mega_orb 边际显著 >+3、hp_min 显著 >0.18、未翻 OP | ✅ marginal +3→+15、hp 0.18→0.86、clear_eff 回收 25.66→15.34（<控制，未翻 OP） |
| 4 | 5 质变守恒契约 + mega_orb 新行为测试全绿 | ✅ `test_evolution_contracts` 13/13（原 8 + 5）；dash AoE 行为 2 用例绿 |
| 5 | 全量绿 + C6 核数 + C5 确定性 | ✅ **550/550 绿 0 error**（基线 543 + 7）；C6 核数（一度因 chains 地板致 w3b 截断 537，已修）；C5 mix_orb 同种子两跑均 victory/600s、kills 1942 vs 1914（1.4%，后期有界不确定，符合 P2b 用户裁决的「聚合稳定非逐字节」标准） |
| 6 | 后衡报告 | ✅ 本文 |

**总评**：4/6 完全达标；#1 部分达标（earthshatter ✅，nuke/thunderstorm 砍到 P4 地板+诚实记录判据局限——强行入带须违 P4 = 不正确）。复衡效应实质显著（5 进化全部移向健康区间），零破坏既有绿测，守 C4/P4 全程。

## 5. 残留局限 / 下一步

1. **nuke/thunderstorm 残留 OP = 判据局限（最高优先后续）**：evolution-median 清场带被大量弱进化（knife/orb/whip reached≈0、reanimate 等）压低，强 AoE 进化在 P4 地板天然高于带。下一步候选——(a) **判据改进**：清场支配改用「绝对清场阈值」或剔除不可达进化重算中位（治本，对齐 P3 §4b#6「判据持续改进」）；(b) 若坚持数值入带，须 script 级削质变（nuke 二连爆不叠第二团地火 / thunderstorm 天雷砍尽），风险触 P4 边界，须谨慎。**本轮取 P4 地板为正确终态，不强行违 P4**。
2. **thousand_edge 混编供给饱和**：底盘只留 ~29 敌，强清场者 marginal 被供给上限钳制（+16），掩盖 −50% 原始削幅。下一步：更高密度 mix 档或 solo-floor 复测显真实削幅（判据改进子项）。
3. **未纳入（spec §1 非目标，仍有效）**：inferno_aura radius 手感（手感子项）；knife/orb/whip base 早期可达性（→ 内容广度阶段，非进化平衡）。
4. **mega_orb dash AoE 新机制**：已 TDD 锁（`test_mega_orb_dash_aoe_damages_cluster` + `test_orb_dash_aoe_noop_when_unset`），base orb 零影响（dash_aoe 默认 0 no-op）。
5. **C6 教训重申**：Task 8 降 thunderstorm chains 到地板(5)时仅跑契约+campaign、漏跑 w3b → `test_tempest_reflects_sky_strikes` 的严格 `>` 断言失败并静默截断 w3b 后续 13 用例（550→537）。幸被 GREEN 态核数抓到。**改值后须跑所有相关套件 + 核对用例数**，别只看局部绿（宪法 C6）。
