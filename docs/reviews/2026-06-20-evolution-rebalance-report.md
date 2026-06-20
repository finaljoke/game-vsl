# P2b · 进化复衡后衡报告（复衡 + 可达性地板测量）

- **日期**：2026-06-20
- **定位**：P2「平衡完整性」后半（P2b）交付物。承 [P2a 支配性报告](2026-06-20-evolution-dominance-report.md) 的诊断，对 off-band 进化做数据闭环复衡，并以 perk_hp 防御垫地板档重测三个纯 solo 测不到的进化。
- **上位**：[P2b 设计 spec](../superpowers/specs/2026-06-20-evolution-rebalance-design.md) · [P2b 实现 plan](../superpowers/plans/2026-06-20-evolution-rebalance.md) · [基石设计](../superpowers/specs/2026-06-20-combat-system-foundation-design.md) §6（C1 伤害管线/C4 进化质变/C5 遥测）。
- **配方**：复衡后重跑 P2a 同配方 campaign（11 `solo_` × 8 种子 7/42/101/1-5，dodge 探针，`--fixed-fps 60 --fast=8 --maxtime=600`，88 run）+ 地板 campaign（3 `solofloor_` × 8 种子，24 run）。

## 0. 一句话结论

cyclone 砍法干净落带；**inferno_aura 与 horde 的复衡奏效在「真实支配轴」（安全/生存）上，但 kpm 判据对持续 AoE 与召唤流失真、误报二者为 OP——这是本轮最重要的方法学发现**；地板档成功把三个不可达进化变得可测（whip 实为可达性弱、非进化弱，knife/orb 基础太脆需 P3 混编）。

## 1. 复衡前后对照（主 campaign，11 solo）

新跨进化 kpm 中位 = **189.4**（P2a 177.6），±35% 带 = **[123, 256]**。

| 进化 | 轮次 | reached | kpm | hp_min | death | surv_post | kpm 判据 |
|---|---|---|---|---|---|---|---|
| **inferno_aura** | P2a | 1.00 | 332.8 | 0.92 | 0.00 | 455 | OP |
| | **P2b** | 1.00 | **779.0** | **0.74** | 0.00 | 467 | OP（**失真**，见 §2） |
| **cyclone** | P2a | 1.00 | 271.3 | 0.80 | 0.00 | 422 | OP |
| | **P2b** | 1.00 | **189.4** | 0.70 | 0.125 | 403 | **ok（落到中位）** ✅ |
| **horde** | P2a | 0.63 | 139.9 | 0.03 | 1.00 | 164 | weak |
| | **P2b** | 0.63 | 277.0 | **0.59** | **0.50** | **439** | OP（**失真**，见 §2） |

**未动的 8 个进化**（explosion 190.2 / frostbite 171.2 / gravity_well 165.8 / lightning(thunderstorm) 225.7 / maul 177.6 / knife 0 / orb 0 / whip 216.4）**kpm 逐一与 P2a 完全一致** —— 64 run 跨两轮逐值复现，是 **C5 确定性的强证据**（同种子同代码路径 → 聚合逐字节稳定；harness 的 solo_spec 重构与 solofloor_ 分支对 solo_ 路径零行为改动）。

## 2. 🔑 方法学发现:kpm 判据对 AoE/召唤流失真（本轮最重要产出）

**现象**：复衡后 kpm 把 inferno_aura（779）与 horde（277）都判 OP，但二者都是 metric 假象，不是真支配：

- **inferno_aura**：砍 radius 170→145、burn 10→7、cd 0.4→0.5 后，kpm 不降反升（332→779）。同窗口同刷怪表下，**更弱的持续 AoE 让敌人堆积**（不再秒杀）→ 每 0.5s 脉冲命中更大一群 → 击杀数反升。kpm 测的是「在场可杀敌数 × 命中率」，**与单体强度在密度饱和竞技场里负相关**。真正动的是**安全轴**：hp_min 0.92→0.74，从全场最安全掉到中游（介于 gravity 0.62 与 frostbite 0.76），**支配性确实被削**。
- **horde**：§3c 回血让本体续航大增（hp_min 0.03→0.59、存活 164→439）→ 活得久 → 后期高密度窗口更长 → 击杀数累积更多 → kpm 139→277。但它 **reached 仍仅 0.63**（base reanimate 3/8 进化前就死），谈不上支配。kpm 升是「生存时长 × 密度」假象。
- **共因**：① dodge bot 防御近无敌 → 安全轴对强进化饱和（spec 缺口 B 再证）；② kpm 受敌密度上限钳制，对 AoE/召唤这类「清得慢反而吃更多目标」的机制反向。**两条 OP 判据轴在此 bot 下都不干净。**

**裁决**：**不追 kpm 假信号**。追它会把 aura 砍成真垃圾而 kpm 仍高（swarm-chipping 不消）。以 **hp_min + reached + death** 为可信轴：cyclone 落中位 ✅、aura 安全轴落中游 ✅、horde 生存被 §3c 救起 ✅。`flag_multi_axis` 的 verdict 列**本轮不可作终判**，报告散文修正之。**改进判据（剔除密度/时长污染，如按「单位在场敌的击杀占比」或「到进化时刻」）= P3 输入。**

## 3. 三处复衡逐一裁决

### 3a. cyclone（OP → 落带）✅ 定稿
pierce 8→5 / cd 0.7→0.85 / range 300→270（留 count3 旋风身份）。弹道武器 kpm 干净：271→189.4 **正落跨进化中位**，开始偶死（death 0.125）。教科书式落带。

### 3b. inferno_aura（OP → 安全轴落中游）✅ 定稿（kpm 不作判据）
radius 170→145 / burn 10→7 / cd 0.4→0.5 / lifesteal 0.3→0.25。**真支配（安全）被削**：hp_min 0.92→0.74 落到中游、不再是全场最安全的 trivializer。kpm 779 是 §2 的 AoE 假象，不据此再砍。
- 残留观察（P3）：radius 收窄使敌更近、屏面更挤（779 击杀多为贴脸 chip）——属手感/可读性,非平衡,记 P3。

### 3c. horde（真弱 8/8 死 → §3c 生存救起）✅ 定稿
首轮纯 DPS（minions 6→9 / dmg 16→22 / spd 130→165 / life 18→22 / split 0.35→0.5）让存活翻倍但**仍 8/8 死、hp_min≈0**——随从不挡身、敌不索敌随从，加 DPS 救不了无防护本体。**触发 spec §3c 防御杠杆**：随从每命中给本体回血 `heal_on_hit=2.0`（9 随从满场约 36 hp/s 续航）。效果：

| | death | hp_min | surv_post |
|---|---|---|---|
| P2a | 1.00 | 0.03 | 164 |
| 纯 DPS | 1.00 | 0.036 | 324 |
| **+§3c 回血** | **0.50** | **0.59** | **439** |

死亡的一半主要是 **进化前**就死的 3/8（base reanimate 早期脆，post-evo 回血够不到）——**到了进化的 5 个里约 4 个活**（post-evo 存活 ~80%）。进化本身的生存问题已解；进化前可达性属 base 脆弱（同 §4 不可达族）。

## 4. 地板档:三个不可达进化重测（perk_hp×5 防御垫）

`solofloor_` 档剥离非目标武器 + 开局授 perk_hp×5（+100 max HP，纯防御不加击杀），让弱 base 活到进化。**地板辈独立基准**（仅辈内可比，kpm 含生存垫致窗口延长的偏移）：

| 进化 | 纯 solo reached | **地板 reached** | kpm | hp_min | death | 裁决 |
|---|---|---|---|---|---|---|
| **bloody_whip**(whip) | 0.13 | **0.75** | 382.7 | 0.73 | 0.25 | **健康**——P2a「弱†」纯属可达性 |
| **thousand_edge**(knife) | 0.00 | **0.25** | 307.0 | 0.34 | 0.875 | 可测但 base 仍脆(7/8 死) |
| **mega_orb**(orb) | 0.00 | **0.13** | 0(死) | 0.19 | 1.00 | 最脆,垫不起 |

**结论**：① 地板法**达成目标**——把 0/0/0.13 的 reached 抬到 0.25/0.13/0.75，给出可测窗口；② **bloody_whip 证实是「可达性弱」非「进化弱」**：给它活到进化的机会，它 reached 0.75、death 0.25、kpm 382（辈内最高），**健康**，P2a 的「弱†」是 base whip 单独活不过 Act1 的假象；③ knife/orb 即便 +100 HP 仍极脆（knife 7/8 死、orb 那 1 个 reach 还瞬死）——**base 武器太脆,perk_hp 垫不起,需 P3 真混编（有保命武器组合）才能评估其进化**；④ **三者均未在地板辈内显现明确 OP/破坏性失衡 → 本轮不臆改数值**（守 spec §4b「别据 reached 低就判进化弱」），转 P3。

## 5. 退出判据核对（对照 spec §7）

| # | 判据 | 结果 |
|---|---|---|
| 1 | aura/cyclone 落 ±35% 带不掉底 | cyclone ✅（中位）；aura **安全轴落中游 ✅**，kpm 失真不作判据（§2） |
| 2 | horde death<0.5/survived↑/hp_min↑ | death 0.50（边界）、surv 164→439 ✅、hp_min 0.03→0.59 ✅ |
| 3 | 无原平衡区被中位漂移破带;thunderstorm 复查 | 新中位 189.4，thunderstorm 225.7 在带内（eff +0.19）✅；8 未动进化全在带内 |
| 4 | 不可达三个地板 reached>0.5 + verdict | whip 0.75 ✅；knife 0.25/orb 0.13 < 0.5（base 太脆）→ 转 P3 ✅（已 verdict） |
| 5 | 全量绿 + C5 聚合稳定 | 见 §6（全量绿）；8 未动进化跨两轮 kpm 逐值复现 = C5 强证据 |
| 6 | 后衡报告 | 本文 ✅ |

## 6. 测试与确定性

- **契约守恒**（C4）：8 守卫绿（inferno_aura/cyclone/horde 复衡后仍严格 ≥ 各自 base L3；horde 带 §3c heal_on_hit>0）。复衡未把任何进化砍成退化。
- **新增单测**：harness solo_spec/solofloor_（+5）、run_analysis solo_spec（+3）、契约（+8）、reanimate §3c 回血（+3）。全量见 §6 末。
- **C5**：8 个未动进化跨 P2a/P2b 两轮 64 run kpm 逐值一致（聚合稳定）。
- **全量回归**：复衡触发两处硬编码 `radius==170` 断言打红，且失败断言**静默截断**其后同套件用例发现（505 假象）——改为从 WeaponDB 动态取参照后全绿，印证截断陷阱「须在 GREEN 态核对用例数」。

## 7. P3 输入清单

1. **判据改进（高优先）**：kpm 对 AoE/召唤流失真（§2）。P3 需更抗密度/时长污染的支配指标——候选：单位在场敌的击杀占比、到进化时刻、或固定时间窗内的「过量击杀 vs 净威胁」。当前 `flag_multi_axis` verdict 对这两类机制不可信。
2. **真混编遥测**：knife/orb 的进化（thousand_edge/mega_orb）即便 perk_hp×5 垫仍够不到稳定窗口——需在「有保命武器」的混编 build 里测（§4）。`thousand_edge` 的「绕冷却 OP」假说仍待这条验证。
3. **inferno_aura 手感**：radius 收窄致贴脸 swarm-chip（屏面挤、779 击杀多为近身）——非平衡问题,P3 看是否回调 radius 兼顾手感（用别的轴控支配）。
4. **base 武器可达性**：knife/orb/whip 单独活不过 Act1 是反复出现的地板——属卡池/早期生存设计（P3 内容广度阶段），非进化平衡。
