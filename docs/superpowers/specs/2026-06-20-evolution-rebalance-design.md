# P2b · 进化复衡 + 可达性地板测量 设计 spec

- **日期**：2026-06-20
- **定位**：P2「平衡完整性」后半（P2b）。承 [P2a 支配性报告](../../reviews/2026-06-20-evolution-dominance-report.md) 的实测诊断，对 off-band 进化做**数据闭环复衡**，并为 P2a 测不到的三个不可达进化建立可达性地板测量法。
- **上位契约**：[基石设计](2026-06-20-combat-system-foundation-design.md) §3（柱 P4「进化=质变」）· §6 不变量 **C1**（伤害管线，本 spec 只改数值输入不动管线）/ **C4**（进化=质变+透明门控+就绪即投）/ **C5**（遥测 `--fixed-fps 60`，OP 先 solo 档）/ **C6**（契约 gdUnit 锁 + 截断陷阱核对数）。
- **本 spec 含数值改动**（区别于 P2a「先测后衡」的零改动）。

## 1. 目标与非目标

**目标**：把 P2a 实测出的 off-band 进化拉回平衡带，并补齐三个「纯 solo 测不到」进化的测量手段。

- A. 砍 **inferno_aura(+87%)** / **cyclone(+53%)** 两个真 OP 进化，落回 ±35% 带（不掉底）。
- B. 加强 **horde**（reached 0.63 但 8/8 死、hp_min 0.03）——唯一需要「加强」的进化，目标后期能活。
- C. 给 **thousand_edge / mega_orb / bloody_whip**（纯 solo reached=0）建立**可达性地板**测量档，量到 verdict；明显 off-band 才在本轮复衡，否则记 P3。

**非目标**（YAGNI / 留后续阶段）：

- 不动 thunderstorm(+27%) 的数值——它是观察项，仅在砍 OP 后**复查它对新中位是否破带**。
- 不做真·混编多武器遥测（P3 内容广度阶段）。地板测量是单武器 + 纯防御垫，不是混编。
- 不改伤害管线 / 状态系统 / 卡池可达性（P0/P1 已立，C1–C3 守恒）。
- 不给敌人 AI 加「索敌 summons」（horde 随从不被攻击是现状，本轮靠堆 DPS 而非改 AI 解决生存）。

## 2. 复衡哲学（贯穿决策）

1. **数据闭环裁决**：改数值是**首轮假设**，不是终值。每轮改动后重跑 P2a 同配方 campaign（11 solo × 8 种子）+ 地板 campaign，按多轴判据看落带情况，**迭代到达标**。这让首轮数值不必精确——measurement loop 自纠偏。
2. **砍到带顶不砍到中位**：进化是质变奖励（柱 P4），复衡目标是 kpm 落到 **+35% 带顶附近**（仍明显强、但不支配），而非压到跨进化中位。宁可第一轮砍轻些、看数据再补刀（重砍易过校正、再回调更难判）。
3. **中位漂移复查**：砍掉两个高位离群后，跨进化 kpm 中位（P2a=177.6）会下移→相对效应量重算。**退出前必须用新中位复查 thunderstorm 及所有原平衡区进化是否被动破带**。
4. **质变守恒（C4 契约锁）**：复衡后每个进化仍须在其设计意图轴上**严格强于基础武器满级 L3**。过砍若让进化变成「退化」即违反 C4——用 gdUnit 契约测试**永久锁住**这条，防未来手滑。
5. **地板测量诚实标注**：不可达三个在「带防御垫的单武器」下测，与纯 solo 八个**不同辈**。判据对**地板同辈基准**先判，再交叉参考纯 solo 中位，报告显式写偏移 caveat，不混表误导。

## 3. 工作流 A —— 复衡 3 个已知 off-band 进化

### 3a. inferno_aura（OP +87% kpm → 目标落带）

**诊断**（报告 §1/§6）：贴身燃烧光环在 dodge bot「绕圈拉条」下覆盖全屏，**覆盖密度**（半径 × 命中频率 × 持续 DoT）是 kpm 驱动，单击伤害不是。杠杆方向：**优先降覆盖密度**（命中坍缩②）。

**首轮数值**（`data/weapons/inferno_aura.tres` 第 15–21 行 `levels[0]`）：

| 字段 | 现值 | 首轮新值 | 理由 |
|---|---|---|---|
| `radius` | 170.0 | **145.0** | 覆盖面积 ∝ r²，主杠杆。145²/170²≈0.73，砍 ~27% 覆盖 |
| `burn_dps` | 10.0 | **7.0** | 持续 DoT ×0.7 |
| `cooldown` | 0.4 | **0.5** | 命中频率 ×0.8（脉冲变疏） |
| `damage` | 12.0 | 12.0（不动） | 非 kpm 驱动 |
| `lifesteal_on_hit` | 0.3 | **0.25** | 轻收生存裕度（次要，安全轴饱和） |

**质变守恒**（vs 基础 aura L3：r130/burn6/cd0.5/dmg14/无吸血）：r145>130 ✓、burn7>6 ✓、cd0.5=0.5 ✓、lifesteal0.25>0 ✓ → 仍是清晰升级（更大半径 + 更高 DoT + 吸血）。

### 3b. cyclone（OP +53% kpm → 目标落带）

**诊断**（报告 §1/§6）：回旋斧 count3 多发 + pierce8 高穿透 + cd0.7 快 + orbit_return 环绕逗留，密集战收割过强。杠杆：降折返穿透收益 / 加冷却。**保 count3 + orbit 的「旋风」视觉身份**。

**首轮数值**（`data/weapons/cyclone.tres` 第 15–23 行 `levels[0]`）：

| 字段 | 现值 | 首轮新值 | 理由 |
|---|---|---|---|
| `pierce` | 8 | **5** | 每航程命中数 ×0.625，主杠杆 |
| `cooldown` | 0.7 | **0.85** | 出手频率 ×0.82 |
| `throw_range` | 300.0 | **270.0** | 覆盖收窄 |
| `count` | 3 | 3（不动） | 旋风身份 |
| `damage` | 20.0 | 20.0（不动） | — |
| `orbit_return` | true | true（不动） | 身份 |

**质变守恒**（vs boomerang L3：cd1.0/pierce5/count1/range280/无 orbit）：count3>1 ✓、orbit ✓、cd0.85<1.0 ✓、pierce5=5（count 补偿）、range270<280（略低，可接受）→ 仍清晰升级（三发 + 环绕 + 更快）。

### 3c. horde（真弱，8/8 死 → 目标后期能活）

**诊断**（报告 §3a）：随从 DPS 跟不上后期密度，本体无防护被压死。随从 `collision_layer/mask=0`**不挡身**、敌人 AI **不索敌随从**，故随从零防御价值——但**更多 + 更快 + 更痛的随从清密度更快 = 间接降危险 = 间接保命**。本轮走 DPS 路线（不改 AI、不加碰撞）。

**首轮数值**（`data/weapons/horde.tres` 第 15–23 行 `levels[0]`）：

| 字段 | 现值 | 首轮新值 | 理由 |
|---|---|---|---|
| `max_minions` | 6 | **9** | 同时在场随从 +50%，清场总量 |
| `damage` | 16.0 | **22.0** | 单随从 DPS +37% |
| `minion_speed` | 130.0 | **165.0** | 更快贴敌、覆盖更广 |
| `lifetime` | 18.0 | **22.0** | 在场时间更长，维持密度 |
| `split_chance` | 0.35 | **0.5** | 裂尸补充，密集战滚雪球 |
| `minion_hp` | 35.0 | 35.0（不动） | 当前无效字段（敌不索敌随从） |

**质变守恒**（vs reanimate L3：cd3/dmg14/life11/minions3/split0）：全字段严格更强 ✓。

**契约升级 contingency**：若地板/重测显示堆 DPS 仍救不回生存（death_ratio 仍 >0.5），**升级到防御杠杆**——给 horde 一个本体减伤或随从命中回血（lifesteal）。本轮先试纯 DPS，数据说话。

### 3d. 复衡回归（A 的验证）

- 重跑 P2a 同配方 campaign：**11 个 solo 全跑**（不只改的三个），因为要重算跨进化中位并复查未动进化是否被动破带。
- 退出前用**新中位**复查 thunderstorm + 五个原平衡区进化，无新 off-band。

## 4. 工作流 B —— 可达性地板测量 3 个不可达进化

### 4a. 地板档 harness 扩展

**问题**（报告 §5-A）：纯 solo 剥离起手 knife 后，knife/orb/whip 在 Act1 暴毙、进化无窗口可测——**测量局限，非进化弱**。

**方案**：harness 加 `solofloor_<weapon>` 档（前缀钉死 `solofloor_`，单 token，与现有 `solo_` 解析风格一致；`profile_for` 先匹配更长的 `solofloor_` 再匹配 `solo_`）：

- 与 `solo_<weapon>` 一样剥离所有非目标武器（含起手 knife，除非目标即 knife）。
- **额外**：开局授 `perk_hp × K`（K 首轮=5，即 +100 max HP 当场补满），作纯防御生存垫。`perk_hp` 只加 HP 不加击杀（`_apply_perk_hp`：`max_hp += 20; hp 补满`），故 kpm 仍是单武器击杀归属。
- K 自适应：若 K=5 仍 reached<0.5，升 K=8（max_stacks=10 上限内）；报告记实际 K。
- 注：mega_orb 进化门=`perk_hp×3`，开局授 perk_hp≥3 顺带满足其门控（利于窗口存在）；thousand_edge/bloody_whip 门=`perk_attack×3`，仍靠 bot 自然升级取 perk_attack，perk_hp 纯保命。

### 4b. 地板测量判据

- 跑 thousand_edge/mega_orb/bloody_whip 各 8 种子（同 7/42/101/1-5），地板档 + dodge 探针 + `--fixed-fps 60 --fast=8`。
- 用既有 `flag_multi_axis`，但**基准 = 地板同辈三个的跨中位**（独立子表），不与纯 solo 八个混判。报告显式标注「带 +K perk_hp 防御垫，kpm 含生存垫导致的窗口延长偏移，仅地板辈内可比」。
- **条件复衡**：仅当某进化在地板辈内**明显 off-band**（效应量 >+50% 或 <−50% 且 death 高）才在本轮改数值；否则记「需 P3 真混编遥测」不臆改。**不据纯 solo reached=0 判进化弱**（报告 §6）。

## 5. 契约测试（TDD 永久锁，C6）

数值 `.tres` 改动本身非「行为」单测，但以下契约把设计意图锁成 gdUnit 用例，防未来回归：

1. **进化质变守恒**（守 C4，防过砍变退化）：读 `.tres`，断言复衡后进化在设计意图轴上严格 ≥ 基础武器满级 L3：
   - `inferno_aura.radius ≥ aura.L3.radius` 且 `inferno_aura.burn_dps ≥ aura.L3.burn_dps`。
   - `cyclone.count ≥ 2`（基础 boomerang 无 `count` 字段、脚本默认 1，故进化须显式多发）且 `cyclone.cooldown ≤ boomerang.L3.cooldown`。
   - `horde.max_minions > reanimate.L3.max_minions` 且 `horde.damage ≥ reanimate.L3.damage` 且 `horde.lifetime ≥ reanimate.L3.lifetime`。
2. **地板档 harness 逻辑**：`profile_for("solofloor_knife")` 返回含「授 knife + 剥离其它 + 授 perk_hp×K」的 profile；`solofloor_orb` 同理。`_grant_solo_weapon` 的地板变体在 grant 后 owned 仅目标武器、player.max_hp 已抬升 K×20。
3. **截断陷阱核对**（C6）：跑全量后精确核对用例数（基线 508 + 本轮新增），风险测试排末位。

## 6. 文件结构（影响面）

- **改**：`data/weapons/inferno_aura.tres`、`cyclone.tres`、`horde.tres`（数值，工作流 A）。
- **改**：`autoloads/run_harness.gd`（加 `solofloor_` 档逻辑，工作流 B）。
- **改**：`tools/run_p2a_campaign.ps1` 或新增 `tools/run_p2b_floor_campaign.ps1`（跑地板三个）。
- **改/新**：`tools/analyze_evolutions.gd`（地板辈独立分组 / 子表），若需。
- **新**：`tests/test_evolution_contracts.gd`（质变守恒契约，§5.1）。
- **改**：`tests/test_run_harness.gd`（地板档逻辑，§5.2）。
- **新**：`docs/reviews/2026-06-20-evolution-rebalance-report.md`（P2b 后衡报告，最终交付物）。

每改一个 `.tres` 或 harness 单元 = 独立提交、独立绿测、对应契约测试同提交。

## 7. 退出判据（对照本 spec 验证）

1. inferno_aura & cyclone 重跑后 kpm 落 ±35% 带内（**不掉底**，仍 ≥ 带顶下沿）。
2. horde 重跑：`death_ratio` 显著下降（目标 <0.5）、`survived_post_med` 上升、`hp_min_post_med` 上升——后期能活。
3. 用新跨进化中位复查，**无原平衡区进化被动破带**；thunderstorm 仍 ok 或记观察。
4. thousand_edge/mega_orb/bloody_whip 在地板档下 `reached>0.5` 且拿到地板辈 verdict；off-band 者已复衡或显式记 P3。
5. 契约测试上线锁定（§5）；全量绿（508 + 新增，精确核对无截断）；C5 同种子两跑聚合稳定。
6. P2b 后衡报告产出（复衡前后对照表 + 地板辈子表 + 中位漂移复查 + 质变守恒核对）。

## 8. 风险与缓解

- **过校正**（砍太狠 → aura/cyclone 掉底变弱）：measurement loop 抓得到（落带判据含「不掉底」），回调数值再跑。首轮故意砍轻。
- **horde 堆 DPS 不够保命**：§3c contingency 升级防御杠杆，数据触发。
- **地板垫扭曲 kpm 可比性**：perk_hp 不加击杀 → kpm 仍单武器归属；用地板同辈基准 + 显式 caveat，不跨辈混判。
- **campaign 耗时**（A 的 88 run + B 的 24 run = 112 run，每轮迭代重跑）：可只重跑改动相关档做快速迭代，最终验证再全跑；跑前关编辑器（LimboAI 双实例陷阱）。
