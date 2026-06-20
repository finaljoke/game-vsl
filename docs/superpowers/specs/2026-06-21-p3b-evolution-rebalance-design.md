# P3b · 进化复衡 设计 spec（据 P3 终判复衡 5 个进化）

- **日期**：2026-06-21
- **定位**：P3「判据闭环」的复衡后续。**承** [P3 判据闭环报告](../../reviews/2026-06-20-dominance-criteria-report.md) §4b「P3b 输入清单」——P3 用 backlog 主轴判据 + 混编 A/B 边际归因**测量并终判**了 5 个进化的支配/偏弱，本轮**据已验证的判据动数值**（P3 本身零数值改动，复衡留 P3b，见 [P3 spec](2026-06-20-p3-dominance-criteria-design.md) §5「OP→P3b」）。
- **上位契约**：[基石设计](2026-06-20-combat-system-foundation-design.md) §1 柱 **P4「进化=质变」**（mega_orb 被宪法点名为反例）· §6 不变量 **C1**（伤害管线，本 spec 只改数值输入 + 一处武器行为，不动管线）/ **C4**（进化=质变 + 透明门控）/ **C5**（遥测 `--fixed-fps 60`，OP 先 solo 档）/ **C6**（契约 gdUnit 锁 + 截断陷阱核数）。
- **本 spec 含数值改动 + 一处武器行为改动**（mega_orb 质变重做），区别于 P3「测量+终判」的零改动。

---

## 1. 目标与非目标

**目标**：把 P3 §4b 确认的 5 个进化复衡到健康带，全程守 C4 质变守恒、零破坏既有绿测。

- **A. 削三个 nuke 类**（nuke / thunderstorm / earthshatter）：backlog 主轴判据下最强场地清空者 + 安全非劣（P3 §1d，backlog 5/8/12、hp 0.93/0.99/0.89，kpm 完全掩盖）。削**清场覆盖**为主、安全微收为辅，目标 `verdict_new` 从 **OP→ok**（不掉底）。
- **B. 削 thousand_edge**（绕冷却缩放）：混编 A/B 边际 +16（=控制组 nuke 64%）+ 安全 hp 0.88，「绕冷却 OP」部分支持（P3 §3b②）。削**绕冷却缩放上限**（满血恒暴击 cheese 为首要——降 crit_bonus 而非 crit_range，§4 详解），目标边际降向控制组。
- **C. 质变重做 mega_orb**（宽轨 + 扑击 AoE）：混编 A/B 边际仅 +3（清场可忽略）+ 三者最不安全（hp 0.18），疑偏弱（P3 §3b③），且宪法 P4 点名其为「进化只是更高数字」反例。**质变重做**而非堆数值，目标边际升、hp_min 升、守 P4。

**非目标**（YAGNI / 留后续阶段）：

- 不动伤害管线 / 状态系统 / 卡池可达性（C1–C3 守恒，P0/P1/P3 已立）。
- **不纳入 inferno_aura 手感回调**（P3 §4b#5）：P2b 已削 radius 170→145（安全削），再回调会撤销该削，且手感非平衡、难用 bot 遥测背书——留「手感子项」单独处理。
- **不碰 base 武器早期可达性**（P3 §4b#4）：knife/orb/whip 单独活不过 Act1 属卡池/早期生存设计（内容广度阶段），非进化平衡。
- 不动未被判 OP/偏弱的进化数值（cyclone/inferno_aura/horde/blizzard/singularity/bloody_whip 本轮不碰；砍 OP 后用**新中位**复查它们是否被动破带，破带才追加）。

## 2. 复衡哲学（继承 P2b §2 + P3 判据）

1. **数据闭环裁决**：改数值是**首轮假设**，不是终值。每轮改动后重跑相关 campaign，按 **backlog 主轴判据（nuke 类，analyze_dominance.gd）/ 混编 A/B 边际（knife/orb，analyze_mix_ab.gd）** 看落带，**迭代到达标**。首轮数值不必精确——measurement loop 自纠偏。
2. **砍到带顶不砍中位**：进化是质变奖励（柱 P4），nuke 类复衡目标是 `clear_eff` 落 **带上沿附近**（backlog 升入带、仍明显强但不支配），而非压到跨进化中位。宁可第一轮砍轻、看数据补刀（重砍易过校正、再回调更难判）。
3. **中位漂移复查**：砍掉三个高位清场离群后，跨进化 backlog/clear_eff 中位会漂移 → 相对效应量重算。**退出前必须用新中位复查所有未动进化是否被动破带**。
4. **质变守恒（C4 契约锁）**：复衡后每个进化仍须在**设计意图轴**上严格 ≥ 基础武器满级 L3。过砍若让进化变「退化」即违 C4 / P4——用 gdUnit 契约测试**永久锁住**（§5），防未来手滑。mega_orb 的重做尤须守此：质变是**新机制**（扑击 AoE），不是更大的数字。
5. **mega_orb 加强诚实迭代**：mega_orb 是唯一「加强」方向，首轮买入后用混编 A/B 边际 + hp_min 双轴看效果；**若首轮过冲翻 OP 则回收，若仍偏弱则补强**，数据说话（镜像 P2b §3c horde 加强）。

## 3. 工作流 A —— 三个 nuke 类削清场（solo 验证）

三者纯 solo 可达（P3 §1b：explosion/lightning/maul `reached` 均 1.00），复用 P2a/P2b solo campaign 重验。

### 3a. nuke（explosion 进化，OP → 落带）

**诊断**（P3 §1d）：backlog 5（全场最强清空）、hp 0.93。清场来自 `field_dur4` 炼狱地火（128 半径持续 4s、每 0.5s 引爆刷新 ≈ 常驻地火）+ `blast_radius128` 大爆 + `secondary` 二连引爆。命中坍缩②「全屏覆盖密度」。杠杆方向：**优先降持续覆盖**（地火时长 + 引爆频率 + 爆半径）。

**首轮数值**（`data/weapons/nuke.tres` `levels[0]`）：

| 字段 | 现值 | 首轮新值 | 理由 |
|---|---|---|---|
| `field_dur` | 4.0 | **3.0** | 128 半径地火 4s ≈ 常驻，最大持续清场源；落到 base L3 地板（仍 ≥ base） |
| `cooldown` | 0.5 | **0.7** | 引爆频率 ×0.71（仍 ≪ base 1.3） |
| `blast_radius` | 128.0 | **112.0** | 面积 ∝ r²，112²/128²≈0.77，−23% 覆盖（仍 > base 100） |
| `damage` | 40.0 | 40.0（不动） | 单体非 backlog 驱动；守身份 |
| `burn_dps` | 14.0 | 14.0（不动） | 地火时长已削；保 ≥ base 10 |
| `secondary_count` | 1 | 1（不动） | 二连爆=核爆身份 |

**质变守恒**（vs explosion L3：r100/burn10/cd1.3/dmg35/field3）：r112>100 ✓、burn14>10 ✓、cd0.7<1.3 ✓、dmg40>35 ✓、field3≥3 ✓、+ secondary（base 无）→ 仍清晰升级。

### 3b. thunderstorm（lightning 进化，OP → 落带）

**诊断**（P3 §1d）：backlog 8、hp 0.99（最安全）。清场来自 `sky_strikes3`（每次攻击额外砸 3 道 70 半径独立 AoE 天雷）+ `chains8` 高连锁，命中坍缩②。杠杆：**降天雷覆盖 + 连锁数 + 频率**。

**首轮数值**（`data/weapons/thunderstorm.tres` `levels[0]`）：

| 字段 | 现值 | 首轮新值 | 理由 |
|---|---|---|---|
| `sky_strikes` | 3 | **2** | 每 0.45s 砸 3 道天雷=主覆盖源，−33% AoE 砸点 |
| `cooldown` | 0.45 | **0.6** | 施放频率 ×0.75（仍 < base 0.7） |
| `chains` | 8 | **6** | 连锁命中数 −25%（仍 > base 5） |
| `sky_radius` | 70.0 | 70.0（不动） | 首轮先削砸点数，radius 留二轮补刀位 |
| `sky_damage` | 22.0 | 22.0（不动） | 同上 |
| `damage` | 22.0 | 22.0（不动） | 守身份 |

**质变守恒**（vs lightning L3：chains5/cd0.7/dmg22/shock0.3）：chains6>5 ✓、cd0.6<0.7 ✓、+ sky_strikes≥1（base 无天雷）→ 仍清晰升级。

### 3c. earthshatter（maul 进化，OP → 落带）

**诊断**（P3 §1d）：backlog 12、hp 0.89。earthshatter 与 base maul L3 唯一差别就是**冲击波**（`shockwave_radius280` 巨型环带 + 40 伤 + 减速）+ knockback 300（vs 280）——清场 OP 全来自冲击波环带，命中坍缩②。杠杆：**收窄冲击波环带 + 降环带伤**。

**首轮数值**（`data/weapons/earthshatter.tres` `levels[0]`）：

| 字段 | 现值 | 首轮新值 | 理由 |
|---|---|---|---|
| `shockwave_radius` | 280.0 | **240.0** | 环带（170~R）donut 面积 (240²−170²)/(280²−170²)≈0.58，−42% 覆盖 |
| `shockwave_damage` | 40.0 | **32.0** | 环带伤 ×0.8 |
| `radius` | 170.0 | 170.0（不动） | =base L3，核心命中身份；守恒下沿 |
| `damage` | 72.0 | 72.0（不动） | =base L3；守恒下沿 |
| `knockback` | 300.0 | 300.0（不动） | 控场身份 |
| `shockwave_slow` | 0.5 | 0.5（不动） | 减速身份，首轮留 |

**质变守恒**（vs maul L3：cd1.6/dmg72/r170/knock280/stun0.6、**无** shockwave）：dmg72≥72 ✓、r170≥170 ✓、knock300>280 ✓、+ shockwave_radius>0（base 无）→ 冲击波即质变身份，仍清晰升级。

### 3d. 工作流 A 验证（solo 回归）

- 快迭代：先单跑 explosion/lightning/maul solo（各 8 种子）看趋势。
- 定稿：重跑 **11 solo 全量**（不只改的三个，因需重算跨进化中位、复查未动进化被动破带）→ `analyze_dominance.gd` 看 `verdict_new`。
- 退出前用**新中位**复查 cyclone/inferno_aura/frostbite/gravity_well/boomerang 等未动进化无新 OP。

## 4. 工作流 B —— thousand_edge 削绕冷却上限（混编 A/B 验证）

**诊断**（P3 §3b②）：纯 solo 不可达（base knife 太脆），混编 A/B 边际 +16（=控制组 nuke 64%）+ hp 0.88。

**暴击机制（先厘清，否则削错方向）**：[knife_weapon.gd](../../../scenes/weapons/knife/knife_weapon.gd) `longbow_crit_bonus(dist, crit_range, full_hp, crit_bonus)` = `dist > crit_range OR full_hp → 给 crit_bonus`。thousand_edge `crit_range99999`（极大）使 `dist>crit_range` **永不触发** → 暴击**纯由满血门控**；`crit_bonus1.0` 使 `guaranteed_crit=(crit_chance+1.0)>=1.0` **恒真** → **每个满血敌必定暴击**（swarm 中新刷敌皆满血 → 几乎首次命中皆暴）。OP 签名命中坍缩③「绕过冷却的被动缩放」（暴击维度对满血敌恒触发 = 绕过任何门控）。

⚠ **不可降 crit_range**：降它（如 320）会让 `dist>320` 的**远敌也暴击 = buff**（反向）。正确削法 = **降 crit_bonus**（恒暴击→概率暴击）+ 降齐射弹数 + 降射速。

**首轮数值**（`data/weapons/thousand_edge.tres` `levels[0]`）：

| 字段 | 现值 | 首轮新值 | 理由 |
|---|---|---|---|
| `crit_bonus` | 1.0 | **0.6** | **核心**：crit_bonus≥1.0 致满血敌**必暴**(guaranteed_crit)；降 0.6 → guaranteed_crit 转假、满血暴击概率化为 60%（仍 > base 0.35） |
| `volley` | 5 | **3** | 齐射弹数 ×0.6（仍多发身份 ≥2） |
| `cooldown` | 0.15 | **0.22** | 射速 ×0.68（仍 ≪ base 0.5） |
| `crit_range` | 99999.0 | 99999.0（**不动**） | 降它=远敌也暴=反向 buff；保极大值=暴击纯由满血门控 |
| `pierce` | 8 | 8（不动） | 首轮保留；不够再补刀（留二轮位） |
| `damage` | 15.0 | 15.0（不动） | 守身份 |

**质变守恒**（vs knife L3：cd0.5/crit_bonus0.35/crit_range240/dmg18/pierce4）：volley3≥2（多发身份，base 无 volley=单发）✓、pierce8>4 ✓、cd0.22<0.5 ✓、crit_bonus0.6>0.35 ✓ → 仍清晰升级（多发 + 高穿透 + 快 + 满血暴击区）。注：damage15<base18 是 thousand_edge 现有设计（靠 volley/穿透/暴击换 DPS），守恒锁多发/穿透/射速/暴击轴，不锁单发 damage。

## 5. 工作流 C —— mega_orb 质变重做（脚本 + 数值，混编 A/B 验证）

**诊断**（P3 §3b③ + 宪法 P4）：混编 A/B 边际 +3（清场可忽略）+ hp 0.18（最不安全）。根因：`orbit_radius68` 贴身环绕（须贴脸吃环绕伤 → 不安全）+ dash 单体接触扑击（清场微弱）。与 base orb L3 唯一差别 = total_orbs 翻倍 + dash——**正是宪法 P4 点名的「进化只是更高数字」**。

**重做方向（用户拍板）：宽轨 + 扑击 AoE**——质变是「贴身护盾 → 宽幅区域控制 + AoE 扑击」。

### 5a. 脚本行为改动（质变核心）

[scenes/weapons/orb/orb_shield.gd](../../../scenes/weapons/orb/orb_shield.gd)：dash 到点（`_dashing` 结束、抵达目标）时，对 `dash_aoe_radius` 内**全体**敌人造成 `dash_aoe_damage`（含 player.damage_mult），而非仅单体接触伤。新字段 `dash_aoe_radius` / `dash_aoe_damage` 由 `OrbWeapon._sync_shields()` 注入，**默认 0 → AoE 不触发**（base orb `dash_enabled=false` 本就不扑击，零影响；契约守恒）。

- **质变**：扑击从「飞向最近敌、接触掉 1 个」→「飞向敌群、到点爆裂群伤」。
- **C5 确定性**：dash 取 `_nearest_enemy()`（确定性）、AoE 遍历 `enemies` group（确定性），**无新 RNG** → 同种子复现不破。
- **TDD**（C6）：新增 dash AoE 行为单测（gdUnit）——构造带 `dash_aoe_radius/damage` 的 OrbShield + 范围内/外敌人，断言 dash 到点后范围内敌受伤、范围外不受伤。行为测试排套件末尾。

### 5b. 数值改动（`data/weapons/mega_orb.tres` `levels[0]`）

| 字段 | 现值 | 首轮新值 | 理由 |
|---|---|---|---|
| `orbit_radius` | 68.0 | **120.0** | 宽轨扫环=**不必贴脸**（安全 hp_min↑）+ 扫更大环带（清场↑） |
| `dash_aoe_radius` | (新键) | **90.0** | 扑击到点群伤范围 |
| `dash_aoe_damage` | (新键) | **24.0** | 有意义群伤（>环绕单体 damage） |
| `dash_interval` | 3.0 | **2.0** | 扑击更频，维持 AoE 输出 |
| `damage` | 14.0 | **18.0** | 环绕 DPS 微升（=base orb L3 14 的 +29%） |
| `total_orbs` | 8 | 8（不动） | 8 球扫宽环已足；过多→视觉糊 |
| `hit_cooldown` | 0.3 | 0.3（不动） | =base L3 |

**质变守恒**（vs orb L3：dmg14/cd0.3/r68/orbs4、无 dash、无 aoe）：total_orbs8>4 ✓、orbit_radius120>68 ✓、damage18>14 ✓、dash_enabled（base 无）✓、`dash_aoe_radius>0`（base 无 = 新机制）✓ → **真质变**（宽幅 + AoE 扑击），非「更高数字」。

### 5c. 工作流 C 验证（混编 A/B）

- 复用 P3 混编机架（mixbase + mix_orb + mix_explosion 控制组 ×8 种子）→ `analyze_mix_ab.gd` 看 mega_orb 边际（目标显著 >+3）+ hp_min（目标显著 >0.18）。
- **过冲守卫**：若 mega_orb 边际翻到 ≈ 控制组 nuke 甚至更高 = 过强，回收数值（降 dash_aoe_damage / orbit_radius）。目标是「健康的中位清场 + 安全改善」，非新 OP。

## 6. 契约测试（TDD 永久锁，C6）

扩 [tests/test_evolution_contracts.gd](../../../tests/test_evolution_contracts.gd)，为 5 个进化各加质变守恒断言（读 `.tres`，断言复衡后进化在设计意图轴上严格 ≥ base L3 / 含 base 无的新机制键）：

1. **nuke**：`blast_radius ≥ explosion.L3.blast_radius`（100）、`burn_dps ≥ L3`（10）、`field_dur ≥ L3`（3.0）、`cooldown ≤ L3`（1.3）。
2. **thunderstorm**：`chains ≥ lightning.L3.chains`（5）、`cooldown ≤ L3`（0.7）、`sky_strikes ≥ 1`（天雷身份，base 无）。
3. **earthshatter**：`shockwave_radius > 0`（冲击波身份，base maul 无）、`damage ≥ maul.L3.damage`（72）、`radius ≥ L3`（170）。
4. **thousand_edge**：`volley ≥ 2`（多发身份，base knife 无 volley）、`pierce ≥ knife.L3.pierce`（4）、`cooldown ≤ L3`（0.5）、`crit_bonus ≥ knife.L3.crit_bonus`（0.35，防过砍暴击轴退化）。
5. **mega_orb**：`total_orbs > orb.L3.total_orbs`（4）、`orbit_radius ≥ L3`（68）、`damage ≥ L3`（14）、`dash_aoe_radius > 0`（扑击 AoE 质变身份，base 无）。

加 mega_orb dash AoE **行为**单测（§5a，区别于上述纯数据守恒断言）。所有新测试排套件末尾，GREEN 态核对发现用例数（C6 截断陷阱）。

## 7. 文件结构（影响面）

- **改**：`data/weapons/nuke.tres` / `thunderstorm.tres` / `earthshatter.tres` / `thousand_edge.tres` / `mega_orb.tres`（数值）。
- **改**：`scenes/weapons/orb/orb_shield.gd`（dash AoE 行为，工作流 C）。
- **改**：`scenes/weapons/orb/orb_weapon.gd`（`_sync_shields()` 注入 `dash_aoe_radius/damage`）。
- **改**：`tests/test_evolution_contracts.gd`（5 条守恒契约，§6）。
- **新/改**：mega_orb dash AoE 行为测试（`tests/test_weapons_*.gd` 既有套件追加，或新 `tests/test_orb_dash_aoe.gd`，plan 定）。
- **新**：`docs/reviews/2026-06-21-evolution-rebalance-p3b-report.md`（P3b 后衡报告，最终交付物）。
- 复用（不改）：`tools/run_p2a_campaign.ps1`（solo）、`tools/run_p3_mix_campaign.ps1`（混编 A/B）、`tools/analyze_dominance.gd`、`tools/analyze_mix_ab.gd`。

每改一个 `.tres` 或脚本单元 = 独立提交、独立绿测、对应契约测试同提交。**绝不 `git add -A`**（仓库 ~2500 未追踪 + 一批预存 M 的 .tscn/.import）；每提交只 add 该步碰的文件。

## 8. 退出判据（对照本 spec 验证）

1. **nuke/thunderstorm/earthshatter** 重跑 solo 后 `verdict_new` 从 **OP→ok**（不掉底，clear_eff 落带上沿 / backlog 升入带）；新跨进化中位下**无未动进化被动破带**。
2. **thousand_edge** 混编 A/B 边际 ≤ 控制组 nuke（消「强清场+安全」OP 签名）；仍 ≥ base（契约绿）。
3. **mega_orb** 混编 A/B 边际显著 >+3、hp_min 显著 >0.18、dash AoE 行为 TDD 绿、未翻 OP。
4. 5 条质变守恒契约 + mega_orb 新行为测试全绿（守 C4 / P4）。
5. 全量 gdUnit 绿 + **C6 截断核对用例数**（基线 543 + 本轮新增，GREEN 态核对）+ **C5 确定性**（改动相关档同种子两跑聚合稳定；脚本无新 RNG）。
6. P3b 后衡报告产出（复衡前后对照表 + 中位漂移复查 + 质变守恒核对 + mega_orb 重做证据）。

## 9. 风险与缓解

- **过校正**（nuke 类砍太狠 → 掉底变弱）：measurement loop 抓得到（退出判据含「不掉底」），回调数值再跑。首轮故意砍轻。
- **mega_orb 重做过冲翻 OP / 仍偏弱**：§5c 双轴（边际 + hp_min）守卫，数据触发回收或补强（镜像 P2b horde 加强迭代）。
- **mega_orb 脚本改动破 C5 确定性**：dash AoE 无新 RNG（最近敌 + group 遍历均确定性），同种子复现不破；改后跑同种子两跑核对。
- **thousand_edge crit_range 收紧与 crit 轴（A2）交互**：暴击目前仅 knife/thousand_edge 有；收到 320 仍保暴击身份，不波及他卡。
- **砍三 nuke 后中位漂移致他卡破带**：§3d / §8#1 用新中位复查，破带才追加（本轮范围内）。
- **C6 截断陷阱**：新测试排套件末尾，GREEN 态核对发现用例数（基线 543）。
- **campaign 耗时**（solo 88 + 混编 32，每轮迭代重跑）：方法学 B——快迭代只重跑改动相关档，定稿再全跑；跑前关编辑器（LimboAI 双实例 DLL 冲突陷阱）。

## 10. 实现衔接

三工作流由 **writing-plans** 转为带 TDD 步骤的实现计划。建议落地顺序按依赖与杠杆：
**工作流 A（3 nuke 类 .tres + 契约，solo 验证）→ 工作流 B（thousand_edge .tres + 契约，混编验证）→ 工作流 C（mega_orb 脚本 + .tres + 行为 TDD + 契约，混编验证）**。每工作流独立提交、独立绿测；完后全量核对用例数（C6）+ 确定性回归（C5）+ 后衡报告。
