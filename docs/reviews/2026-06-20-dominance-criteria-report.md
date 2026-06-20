# P3 · 判据闭环报告（支配判据改进 + 验证闸 + 终判）

- **日期**：2026-06-20
- **定位**：P3「判据闭环」交付物。承 [P2b 复衡报告](2026-06-20-evolution-rebalance-report.md) §7「P3 输入清单」第 ①②，落实 [P3 设计 spec](../superpowers/specs/2026-06-20-p3-dominance-criteria-design.md)。
- **上位契约**：[基石设计](../superpowers/specs/2026-06-20-combat-system-foundation-design.md) C5 遥测 / C6 测试。
- **数据**：现存 p2a（88 run，复衡前）+ p2b_main（88 run，复衡后）遥测**零重跑重算**；混编 A/B（§3）新跑。

## 0. 一句话结论

**P2b 的 kpm 判据被一个密度/时长鲁棒的「清场强度」判据取代——主轴是 `backlog`（窗口内全场存活敌均值，反向：低=强清场）。验证闸（在现存遥测上证伪式自检）一次性证伪了 kpm 对 inferno_aura（密度饱和）与 horde（生存时长）的两处误判，二者新判据下均 `ok`（非 OP）；cyclone 落中位锚定。新判据还浮现一个 kpm 完全掩盖的真信号：explosion/lightning/maul（nuke/thunderstorm/earthshatter）是最强场地清空者——记 P3b，本轮不调数值。**

## 1. 验证闸（可证伪自检）

### 1a. 判据演进：clear_eff → backlog（闸驱动的定稿）

初版主轴取 `clear_eff = kpm_post / max(backlog_mean, FLOOR)`（密度归一）。**验证闸在 p2b_main 上当场证伪它**：

| 进化 | clear_eff | kpm(ctx) | backlog | clear_eff 初版 verdict |
|---|---|---|---|---|
| reanimate(horde) | 6.68 | **277** | 37 | **OP（误判）** |

`clear_eff` 分子的 `kpm` 仍含 P2b 指出的**生存时长污染**——§3c 让 horde 活进后期高密度窗口 → kpm 假高（139→277）→ clear_eff 假高 → 误判 OP。**密度归一（除 backlog）修不了时长污染（污染在分子）。**

**定稿**：主轴改 **`backlog`（瞬时量，反向：低=强清场）**。backlog 无累积速率/生存污染，且密度污染天然反向（swarm 堆积 → backlog 高 → 清场弱）。`clear_eff` 降级为 context 列。`BACKLOG_FLOOR` 自此**不再决定 verdict**（仅影响 context 的 clear_eff），floor 敏感性一并消解。

> 这是验证闸的价值实证：**判据先失败、被诊断、被定稿，而非走过场**。闸不通过不进 Unit 3（spec §7 前置纪律）。

### 1b. 闸结果（backlog 主轴，p2b_main = 复衡后 ground truth 参照）

```
evolution        n  reached backlog backlog_dev clear_eff(ctx) kpm(ctx) hp_min verdict_new verdict_old(kpm)
evolve_aura      8   1.00    175     +6.52       4.61          779      0.74   ok          OP
evolve_boomerang 8   1.00     98     +3.21       1.89          189      0.70   ok          ok
evolve_explosion 8   1.00      5     -0.80      37.09          190      0.93   OP          ok
evolve_frostbite 8   1.00     23     +0.00       7.33          171      0.76   ok          ok
evolve_gravity   8   0.88     38     +0.63       4.40          166      0.62   ok          ok
evolve_knife     8   0.00      0     -1.00       0.00            0      0.00   weak        weak
evolve_lightning 8   1.00      8     -0.64      27.80          226      0.99   OP          ok
evolve_maul      8   1.00     12     -0.49      15.06          178      0.89   OP          ok
evolve_orb       8   0.00      0     -1.00       0.00            0      0.00   weak        weak
evolve_reanimate 8   0.63     37     +0.60       6.68          277      0.59   ok          OP
evolve_whip      8   0.13     51     +1.17       4.28          216      0.56   weak        weak
```

### 1c. 闸逐条核验（对照 spec §3 ground truth）

| # | 闸条件 | 结果 | 判定 |
|---|---|---|---|
| 1 | **cyclone 落中位**（锚点）| boomerang backlog 98，verdict ok（非 weak 非 OP）| ✅ 锚定。clear 轴上 cyclone 是中-低清场者（穿透机动非清场身份），未被误判 |
| 2 | **inferno_aura 非 OP** | aura backlog 175（全场最高=最弱清场），verdict **ok**（kpm 779 旧判 OP）| ✅ **密度饱和假信号消除** |
| 3 | **horde 非 OP** | reanimate backlog 37（中），verdict **ok**（kpm 277 旧判 OP）| ✅ **生存时长假信号消除**（backlog 主轴修了 clear_eff 修不了的） |
| 4 | 8 未动进化在带内 | frostbite/gravity ok；**explosion/lightning/maul 翻 OP**（见 §1d）| ⚠ 见 §1d：真信号非闸失败 |
| 5 | 无进化命中 floor 致区分塌 | 仅 explosion backlog 5≈floor；且 backlog 主轴**不用 floor** 定 verdict | ✅ floor 已与 verdict 解耦 |

### 1d. explosion/lightning/maul 翻 OP 是真信号，非闸失败

`verdict_old(kpm)` 对这三个全是 `ok`，新判据翻 OP。**核 t_evo 排除「早进化→窗口浅→backlog 低」混淆**：

| 进化 | t_evo_med | backlog | 解读 |
|---|---|---|---|
| explosion | 127.5 | 5 | 进化时刻与全群同档（多数 127–141），backlog 却远低 |
| lightning | 130.9 | 8 | 同上 |
| maul | 138.1 | 12 | 进化**最晚之一**，backlog 仍极低 |
| aura | 133.5 | 175 | 同档 t_evo，backlog 35× 于 explosion |

t_evo 同档而 backlog 天差 → backlog 差异是**真实清场强度差**，非窗口深度伪迹。**kpm 完全看不到**（三者 kpm 190/226/178，平平无奇——kpm≈刷怪率守恒，对「把场清空」失明）。explosion=nuke 正是宪法「坍缩三类·全屏覆盖密度」点名类。**结论：这是新判据揭示的真清场支配，kpm 掩盖了它。按 spec §5「OP→P3b，本轮不调数值」记入 §4 P3b 清单。**

### 1e. 复衡前后对照（p2a vs p2b_main，新判据视角）

| 进化 | p2a backlog/hp | p2b backlog/hp | 复衡效应（新判据） |
|---|---|---|---|
| aura | 123 / 0.92 | 175 / 0.74 | 安全 0.92→0.74 被削；清场更弱（削 AoE 后更堆积，backlog↑）——**支配（安全）确被削，新判据 ok 两轮** |
| reanimate | 31 / **0.03** | 37 / **0.59** | §3c 把濒死(0.03)救到 0.59；新判据 p2a=weak(濒死)→p2b=ok(生存)——**§3c 奏效，非 OP** |
| boomerang | 41 / 0.80 | 98 / 0.70 | 复衡(pierce8→5/cd↑/range↓)使清场变弱(backlog 41→98)、落中位——**教科书落带** |

## 2. P2b 悬置 verdict 终判

P2b 报告 §2 裁决「verdict 列本轮不作终判，改进判据=P3 头号输入」。据 §1 通过的 backlog 主轴判据，逐条终判：

- **cyclone**：✅ **定稿·落带**。backlog 98 中位、verdict ok、death 0.125（P2b）。复衡（pierce8→5/cd0.7→0.85/range300→270）使其清场落中位，身份（穿透机动）保留。kpm 189 与 backlog 98 一致指向「中位」。
- **inferno_aura**：✅ **定稿·非 OP**。kpm 779 经证实为 swarm-chipping 密度假象（backlog 175=全场最弱清场）。真支配（安全 hp_min）已由复衡 0.92→0.74 削到中游。**新判据 ok，不据 kpm 779 再砍**（追它会把 aura 砍成真垃圾而 backlog 仍高）。
- **horde(reanimate)**：✅ **定稿·非 OP（生存被救起，可达性仍弱）**。kpm 277 经证实为生存时长假象（backlog 37=中位清场，非支配）。§3c 把 hp_min 0.03→0.59、death 1.0→0.5。**新判据 ok**。残留弱点是 reached 0.63（base reanimate 进化前脆，3/8 早死）——属 base 可达性（§4 P3b/内容广度），非进化支配。
- **`flag_multi_axis` verdict 列（旧 kpm 判据）整体**：✅ **废止为终判依据**。对 AoE（aura）与召唤（horde）失真已实证。`flag_dominance`（backlog 主轴）接任。旧函数保留仅供新旧对照。
- **8 未动进化一致性**：frostbite/gravity_well 两轮 backlog 逐值一致（C5）；explosion/lightning/maul 的 OP 是新判据真信号（§1d）；knife/orb 纯 solo 不可达（→ §3 混编）；whip 可达性弱（reached 0.13，P2b「弱†」确为可达性非进化弱）。

## 3. 混编 A/B 边际归因（thousand_edge / mega_orb 终判）

> Unit 3（Task 10）填。底盘标定见 §3 前言（Task 9）。

## 4. 退出判据核对 + P3b 输入清单

> Task 11 填。**P3b 候选（本轮不调数值，仅记录）**：explosion(nuke)/lightning(thunderstorm)/maul(earthshatter) 经 backlog 主轴判据为最强场地清空者 + 安全非劣（§1d）——nuke 属宪法坍缩三类，优先复核。
