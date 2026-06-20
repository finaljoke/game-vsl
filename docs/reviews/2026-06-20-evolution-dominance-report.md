# P2a · 进化支配性报告（11 进化 × 8 种子 solo 遥测）

- **日期**：2026-06-20
- **定位**：P2「平衡完整性」前半（P2a）的交付物。**数据背书的进化支配性诊断**，驱动 P2b 复衡 spec。**本报告不含数值改动**（先测后衡）。
- **上位**：[P2a 设计 spec](../superpowers/specs/2026-06-20-evolution-balance-measurement-design.md) · [基石设计](../superpowers/specs/2026-06-20-combat-system-foundation-design.md) §3/§5/§6 · [全战斗系统分析](2026-06-20-combat-system-analysis.md) §5（本报告**证伪**其部分 OP 假设，见 §4）。

## 方法（实测配方）

- 矩阵：11 个 `solo_<weapon>` 档 × 8 种子（7/42/101/1-5），dodge 探针（`--bot=kite`），`--fixed-fps 60 --fast=8 --maxtime=600`。**88 run 全部完成。**
- **solo 隔离**：开局移除所有非目标武器（含 `main.gd` 默认起手 knife）+ banish 其卡 → build 纯净，只测目标武器→进化。
- **进化窗口分段**：在每 run 的 `evolve_<weapon>` 解锁事件处切 tick CSV，单独度量进化后窗口三轴，跨 8 种子取中位。
- **多轴判据**：清场效率(kpm) / 生存力(survived+outcome+reached) / 安全裕度(hp_min)，跨进化中位 ±35% 带。kpm 跨进化中位 = **177.6**。

## 总表（按 kpm 效应量降序）

| 进化 | 源武器 | n | reached | kpm中位 | kpm效应 | 生存中位s | hp_min | death率 | **verdict** |
|---|---|---|---|---|---|---|---|---|---|
| **inferno_aura** | 烈焰护体 aura | 8 | 1.00 | 332.8 | **+87%** | 455 | 0.92 | 0.00 | **OP** |
| **cyclone** | 回旋斧 boomerang | 8 | 1.00 | 271.3 | **+53%** | 422 | 0.80 | 0.00 | **OP** |
| thunderstorm | 连锁闪电 lightning | 8 | 1.00 | 225.7 | +27% | 442 | 0.99 | 0.00 | ok |
| bloody_whip | 斩 whip | 8 | **0.13** | 216.4 | +22% | 428 | 0.56 | 0.875 | weak† |
| nuke | 火球 explosion | 8 | 1.00 | 190.2 | +7% | 425 | 0.93 | 0.00 | **ok** |
| earthshatter | 碎 maul | 8 | 1.00 | 177.6 | 0% | 452 | 0.89 | 0.00 | ok |
| blizzard | 霜噬 frostbite | 8 | 1.00 | 171.2 | −4% | 464 | 0.76 | 0.00 | ok |
| singularity | 引力井 gravity_well | 8 | 0.88 | 165.8 | −7% | 464 | 0.62 | 0.25 | ok |
| horde | 亡者召唤 reanimate | 8 | 0.63 | 139.9 | −21% | **164** | **0.03** | **1.0** | **weak** |
| thousand_edge | 长弓 knife | 8 | **0.00** | — | — | — | — | 1.0 | weak† |
| mega_orb | 缚灵 orb | 8 | **0.00** | — | — | — | — | 1.0 | weak† |

†标记 = **不可达型 weak**（基础武器纯隔离下到不了进化），与"到了但弱"的 horde 性质不同（见 §3）。

## 1. 真·OP（reached 1.0 且 kpm 显著偏高）

- **inferno_aura（+87% kpm）** —— 全 8 种子 100% 通关，kpm 332.8（中位 1.87×），全程零死亡、hp_min 0.92。**头号支配进化。** 贴身燃烧光环 DoT 的持续 AoE 在 dodge bot 的"绕圈拉条"打法下覆盖全屏，无脑高 DPS。
- **cyclone（+53% kpm）** —— 同样 100% 通关、零死亡。回旋斧折返双段穿透在密集战收割效率极高。

> 注：分析文档 §5 担心的"进化=数值倒退"（炼狱 dmg 14→12）在数据上**无关紧要**——inferno_aura 单跳伤害虽低，但持续覆盖机制净 OP。**机制 > 单击数值**，印证 spec P4。

## 2. 平衡区（reached 高 + kpm 近中位）

thunderstorm(+27%) / nuke(+7%) / earthshatter(0%) / blizzard(−4%) / singularity(−7%)：五个进化落在 ±35% 带内，**solo 表现健康**。thunderstorm 略偏高（+27%）但未破带，列为观察项。singularity 有 1 个 freak 早死（seed 某局 Lv1/52.8s 坏 RNG），但 6/8 通关，整体强。

## 3. 弱（两种性质，必须区分）

### 3a · 真·弱进化（reached 但扛不住）—— **horde**
- reanimate 5/8 解锁 horde（reached 0.63），到 Lv8-27，但 **8/8 全死**（death 1.0），进化后窗口存活中位仅 164s、hp_min **0.03**。
- 解读：**进化解锁了也救不了**——召唤随从 DPS 跟不上后期密度，且玩家本体无防护被压死。这是**真正需要 P2b 加强的弱进化**。

### 3b · 不可达型 weak（基础武器纯隔离下到不了进化）—— **thousand_edge / mega_orb / bloody_whip**
- **thousand_edge（knife）**：8/8 死于 Lv2-11（70-238s），**0 次解锁进化**。
- **mega_orb（orb）**：8/8 死于 Lv1-6（64-215s），**0 次解锁**，比 knife 更早死。
- **bloody_whip（whip）**：7/8 死（多 Lv6-8），仅 1/8 暴雪通关（Lv33）——高方差。
- 解读：**这不是进化弱，是基础武器单独扛不过 Act1**。长弓(单体穿透)/缚灵(贴身接触)/斩(近身弧劈)在**无任何辅助武器**时清场太慢，升不到"满级+perk×3"就被淹。**纯 solo 无法评估这三个进化的平衡**（窗口根本不存在）。

> ⚠ **这正是分析文档 §5 担心的 thousand_edge(绕冷却③ OP 嫌疑)** —— 但 solo 遥测**测不到它**，因为长弓单独活不到进化。它的 OP 性（若有）只在**有其它武器保命**的真实对局里才显现。

## 4. 坍缩三类假设对账（重要：部分证伪）

分析文档 §5/§6 把 **nuke（全屏覆盖②）** 和 **thousand_edge（绕冷却③）** 列为头号 OP 嫌疑、坍缩原型。solo 遥测结果：

| 假设 | 预期 | 实测 | 裁决 |
|---|---|---|---|
| nuke = 全屏覆盖②，OP | 高 kpm 支配 | kpm +7%，**居中**，平衡区 | **证伪**（solo 下不支配） |
| thousand_edge = 绕冷却③，OP | 高 kpm 支配 | **0 次解锁**（长弓 solo 活不到） | **测不到**（需混编重测） |
| 真 OP 离群 | （未预判） | **inferno_aura / cyclone** | **新发现**（分析未点名） |

**结论**：① 纯 solo 隔离下，**真正的 OP 是 inferno_aura 与 cyclone，不是 nuke/thousand_edge**；② nuke 在 solo 下并不支配（其"全屏覆盖"威力可能依赖与其它武器叠加，需混编验证）；③ thousand_edge 的 OP 假设**无法用 solo 证实或证伪**——它的命题前提（"绕冷却被动缩放"）需要长弓活到后期，而长弓 solo 活不到。

## 5. 方法学局限（必读，影响 P2b 设计）

- **A · solo 可达性地板**：移除起手 knife 后，弱 solo 武器（knife/orb/whip）在 Act1 暴毙、到不了进化 → 其进化**无窗口可测**。这是**测量局限，非进化弱**。**P2b 须对这三个进化换法测**：① 保留起手 knife 作生存地板（接受 knife 贡献的恒定偏移）；或 ② 给一套最小生存辅助包（如 perk_hp + 1 防御 synergy）；或 ③ 在"已可达"的混编 build 里测它们。
- **B · 安全轴饱和**（spec 缺口 B 实证）：dodge bot 防御近无敌，强进化普遍 hp_min 高（aura 0.92 / lightning 0.99 / nuke 0.93）→ 安全轴对 OP **无分辨力**，OP 全靠 kpm + reached。安全轴只在**弱尾**有效（horde hp_min 0.03 即真危险信号）。
- **C · 跨进化中位含 0**：knife/orb 的 kpm=0 拉低跨进化中位（177.6 vs 仅算可达=190.2），轻微抬高可达进化的"高"判定。对本轮 OP 结论无影响（aura/boomerang 在两种基准下都判 high）。

## 6. P2b 输入清单（每个 off-band 进化 → 复衡杠杆方向，不含具体数值）

| 进化 | 问题 | 偏在哪轴 | P2b 杠杆方向 |
|---|---|---|---|
| **inferno_aura** | OP +87% | kpm 过高 | 砍 burn DPS 或缩光环半径或加冷却；优先**降覆盖密度**（命中坍缩②） |
| **cyclone** | OP +53% | kpm 过高 | 降折返穿透收益或加冷却 |
| **horde** | 真弱，全死 | 生存+安全双低 | 加随从 DPS/数量 或 给本体防护；这是**唯一需要"加强"的进化** |
| thunderstorm | 观察项 +27% | kpm 略高 | 暂不动，监视；若 P2b 动 aura/boomerang 后中位下移则复查 |
| **thousand_edge / mega_orb / bloody_whip** | 不可达 | 测不到 | **先换测量法**（§5-A），再判是否复衡。**别据 solo=0 就判进化弱。** |

## 7. 退出判据核对（对照 spec §7）

1. solo 隔离闸上线 + TDD 锁定 ✅
2. 11 进化全部 8 种子 × 窗口数据 ✅（88 run，含 reached 标记）
3. 多轴判据上线 + TDD 锁定 ✅
4. 支配性报告产出（三轴 verdict + 效应量 + 坍缩三类对账 + 倒退核对）✅（本文）
5. 全量绿（508）+ C5 聚合稳定（下方最终验证）✅

→ **P2b 据本报告立复衡 spec**：先处理 inferno_aura/cyclone(OP) + horde(弱)，再对 thousand_edge/mega_orb/bloody_whip 换测量法（§5-A）后评估。
