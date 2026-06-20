# P3 · 判据闭环设计 spec（支配判据改进 + 真混编重测 + 终判）

- **日期**：2026-06-20
- **状态**：待用户复审
- **定位**：P3「判据闭环」阶段的施工图。**承** [P2b 进化复衡后衡报告](../../reviews/2026-06-20-evolution-rebalance-report.md) §7「P3 输入清单」第 ① 条（判据改进，高优先）与第 ② 条（真混编遥测），**上接** [基石设计](2026-06-20-combat-system-foundation-design.md)（C5 遥测 / C6 测试 两条契约）。
- **不是什么**：**不是**宪法 §3 路线图里的大 Phase 3「内容广度 + 元进度」。那一阶段被宪法显式门控在「只有 Phase 0–2 的精达标后才启动」之后——而 P2b 恰恰证明 Phase 2 的「精」**尚未真正达标**：我们的平衡 verdict 因 kpm 判据失真而不可信（`flag_multi_axis` 的 verdict 列本轮不作终判）。**先补齐这块测量方法学债，再谈扩。**

---

## 0. 一句话定调

> **P2b 发现 kpm 判据对持续 AoE（swarm-chipping）与召唤流（生存时长）失真，误报 inferno_aura/horde 为 OP。P3 用一个密度/时长鲁棒的支配判据替换它，在现存遥测上证伪式验证，给 P2b 悬置的 verdict 下终判，并以真混编 A/B 终判两个纯 solo 测不到的进化（thousand_edge/mega_orb）。**

P3 是**测量/判据阶段**（对齐 P2a 的「先测后衡」纪律），**本轮不改任何数值**；若新可信判据确认真 OP/破坏性失衡，记为 **P3b** 输入。

---

## 1. 问题陈述（精确版）

P2a/P2b 的后期支配判据是 `kills_per_min`（kpm）。在 spawn-capped 竞技场里，后期窗口的 kpm ≈「在场可杀敌数 × 命中率」，被两条机制污染：

1. **密度饱和（swarm-chipping AoE）**：削弱持续 AoE → 敌人不再被秒杀、堆积到刷怪上限 → 每次脉冲命中更大一群 → **击杀数反升**。kpm 与单体/清场强度在密度饱和场**负相关**。
   - **铁证**：`telemetry/p2a/solo_aura_s1.tick.csv` t≈598s：`kills_total=2394, enemies_alive=206, enemies_near=3`——满场 206 敌堆积，玩家身边仅 3。aura 的高 kpm 来自饱和的积压，不是清场强。P2b 复衡把 aura 砍弱后 kpm 不降反升 332→779，就是这条。

2. **生存时长（召唤流）**：§3c 让 horde 活更久 → 更多后期高密度窗口 → 累积击杀更多 → kpm 139→277。但 horde `reached` 仅 0.63，谈不上支配；kpm 升是「生存时长 × 密度」假象。

**共因**：① dodge bot 防御近无敌 → 安全轴（hp_min）对强进化饱和（spec 缺口 B）；② kpm 受敌密度上限钳制，对「清得慢反而吃更多目标」的机制反向。**追 kpm 假信号会把 aura 砍成真垃圾而 kpm 仍高。**

P2b 的临时裁决：以 `hp_min + reached + death` 为可信轴，verdict 列不作终判。**P3 的任务是把这个临时裁决升级为一个可计算、可证伪、密度/时长鲁棒的支配判据，并据它下终判。**

---

## 2. 关键洞察：积压量（backlog）是已录的干净信号

`run_recorder.gd` 的 tick CSV **一直**记录 `enemies_alive`（全场存活敌数）与 `enemies_near`（玩家 140px 内敌数）。**这是反转密度污染的现成信号**：

- 强清场武器**让全场敌数维持低位**（清得快，积压小）。
- 弱的 swarm-chipping AoE **让敌人堆到上限**（积压大，如 aura 的 206）。

→ **积压量 `enemies_alive` 与清场强度负相关**，直接反转 kpm 的密度膨胀。且它**已在全部 88 个 p2a + 120 个 p2b run 的 tick CSV 里**——判据改进的验证**零重跑**，纯离线重算现存遥测即可。

---

## 3. 设计：三单元

### 单元 1 · 支配判据改进（纯函数，analyzer 核）

扩 [tools/run_analysis.gd](../../../tools/run_analysis.gd)（无 IO 纯模块，单测 + analyzer + harness 共用）。新指标，**保留** kpm 与旧 `flag_multi_axis` 不删（验证闸要新旧对照）。

**新指标族**（窗口 = 进化解锁后 `t >= t_evo` 的 tick 行，沿用现有 `window_rows`）：

| 代号 | 名称 | 公式 | 方向 |
|---|---|---|---|
| **M2** ⭐ | 清场效率 `clear_eff` | `kpm_post / max(backlog_mean, BACKLOG_FLOOR)` | **越高越强**（主判据）|
| **M1** | 积压量 `backlog_mean` | 窗口内 `mean(enemies_alive)` | **越低越强**（可读辅轴）|
| **M3** | 到进化时刻 `t_evo` | events 首个 `evolve_<wid>` 的 t | 越早越强（次轴）|
| 安全 | `hp_min_post` / `danger_mean_post` / `reached` / `death` | （沿用 P2a/P2b）| P2b 认定的可信轴 |
| context | `kpm_post` | （沿用）| **降级为仅打印的上下文，不入 OP 判据** |

**接口改动**：
- `window_metrics(win_rows, t_evo, t_end, outcome)`：返回 dict **增** `backlog_mean`（窗口内 `enemies_alive` 均值）、`clear_eff`（= `kpm_post / max(backlog_mean, BACKLOG_FLOOR)`）、`t_evo`（透传，供聚合取中位）。
- `summarize_evolution(metrics_list)`：**增** `clear_eff_med`、`backlog_mean_med`、`t_evo_med`（仅对 reached 的 run 取中位）。
- 新 `flag_dominance(by_evo, band)`（与旧 `flag_multi_axis` 并立）：
  - **OP** = `clear_eff` 高（>带上沿）**且** 安全非劣（hp_min 非 low）。
  - **weak** = `reached < 0.5` **或**（`death > 0.5` 且 surv low）**或** ≥2 可信轴低（clear_eff/surv/hp_min）。
  - **backlog 反向**：band verdict 对 backlog 取「低于带=强信号、高于带=清场弱」——作 OP 的**辅证/weak 的佐证**，不单独定 OP。
  - **kpm 不入判据**，仅作 context 列打印。
- 常量 `BACKLOG_FLOOR`（防强武器清空场地致分母→0 爆 clear_eff）。**定值与边界由 plan 标定**（初值候选 5.0），并在验证闸观察是否有进化命中地板。

**TDD（扩 [tests/test_run_analysis.gd](../../../tests/test_run_analysis.gd)，排套件末尾，C6 截断核对）**：
1. `clear_eff` 合成正确：已知 win_rows（kills/backlog）→ 期望 clear_eff。
2. **swarm-chipping 反转用例**（核心）：合成「高 kills + 高 backlog」tick（模拟 aura 206）→ `clear_eff` 低 → **不判 OP**。
3. **干净清场用例**：「中 kills + 低 backlog」→ `clear_eff` 高 → OP-candidate。
4. backlog 方向、`t_evo` 聚合、分母地板边界（backlog < FLOOR 时不爆）。
5. `flag_dominance` 的 OP/weak/ok 三态（仿现有 `test_flag_multi_axis_*`）。

### 单元 2 · 验证闸 + 重算报告（IO 壳，零重跑）

扩 [tools/analyze_evolutions.gd](../../../tools/analyze_evolutions.gd)（或新 `tools/analyze_dominance.gd`，`-s` 脚本，**不能 preload autoload** → 逻辑全在纯模块）：对 `telemetry/p2a` + `telemetry/p2b_main` 重算新指标，输出**新旧 verdict 对照**（kpm-verdict vs clear_eff-verdict）+ context kpm 列。

**验证闸（可证伪的退出闸）**——新指标在现存遥测上**必须**复现 P2b 散文订正后的 ground truth：

| 进化 | P2b 散文 ground truth | 新指标必须 |
|---|---|---|
| **cyclone** | 干净弹道，落中位（kpm 189.4 干净）| clear_eff 落中带 ✓ **锚点** |
| **inferno_aura** | 真支配在安全轴；kpm 779 是假象 | clear_eff 上**不 OP**（779 被 backlog 归一塌掉）|
| **horde** | reached 0.63，靠 §3c 生存非支配 | **不 OP** |
| **8 未动进化** | kpm 跨两轮逐值复现，在带内 | clear_eff 仍在带内（一致性）|

**闸失败处置**（若新指标仍把 aura/horde 误判 OP）：**不带病前进**，回炉重构公式——降级 M2 改用 M1 backlog 作主轴，或调 `BACKLOG_FLOOR`/band。闸是这套判据「正确」的保证，不是走过场。

产出 [docs/reviews/2026-06-20-dominance-criteria-report.md](../../reviews/2026-06-20-dominance-criteria-report.md)：新指标公式、验证闸结果、**对 P2b 悬置 verdict 的终判**（aura/cyclone/horde + flag_multi_axis verdict 列）。

### 单元 3 · 真混编 A/B 重测（新机架 + 新跑）

P2b §4 地板档证明：thousand_edge(knife)/mega_orb(orb) 即便 perk_hp×5 仍够不到稳定进化窗口（base 太脆）。P3 在「有保命武器」的混编 build 里测，用 **A/B 边际归因** 隔离目标进化的贡献。

**harness 加 `mix_` 方案**（扩 `run_analysis.solo_spec` 为更通用的档名解析，或并立 `mix_spec`，纯函数 DRY，harness + analyzer 共用）：
- `mixbase_<chassis>`：**生存底盘**——控制 + 续航、**低清场、留 headroom**。底盘武器集**由 plan 标定**（候选：frostbite 控制 + 防御 perk_hp + synergy_lifesteal 续航），硬约束：① 让 knife/orb 活到各自 `t_evo`；② **不自身清空场地**（否则 A/B delta 被底盘掩盖 = 地板效应）。
- `mix_<target>`：底盘 + 目标武器（堆满级 + 进化 perk → 进化）。

**A/B campaign**（`tools/run_p3_mix_campaign.ps1`）：thousand_edge(knife)/mega_orb(orb) 各跑 `mixbase` vs `mix`，8 种子（7/42/101/1-5，同 P2a/P2b），`--fixed-fps 60 --fast=8 --maxtime=600`。

**归因**：`clear_eff(mix) − clear_eff(mixbase)` = 目标进化的**边际支配**；并读安全轴 + reached + 新指标 vs 跨进化带。**终判** thousand_edge「绕冷却 OP」假说 + mega_orb。

**C5 确定性**：A/B 同种子两跑聚合稳定（后期有界不确定按 P2b 用户裁决，不要求逐字节）。

---

## 4. 退出判据

1. 新指标族（M2 主 + M1/M3 辅）实装、TDD 全绿，**swarm-chipping 反转用例**锁定；kpm 降级为 context。
2. **验证闸通过**：新指标在现存 p2a/p2b 遥测上复现 cyclone 中带 / aura+horde 非 OP / 8 未动进化在带内——**否则回炉重构公式**。
3. P2b 悬置的 verdict（aura/cyclone/horde + flag_multi_axis verdict 列）在新指标下下**终判**，报告散文记录。
4. thousand_edge/mega_orb 在 A/B 混编下有 `reached` + 边际支配读数 + **终判**（含「绕冷却 OP」假说裁决）；若混编仍够不到，披露可达种子子集 n 并记为 base 可达性问题（→ 内容广度阶段，非进化平衡）。
5. 全量 gdUnit 绿 + **C6 截断核对用例数**（GREEN 态核对，风险测试排末尾）+ **C5 确定性**（现存重算逐值复现 + 新混编同种子聚合稳定）。
6. 后衡报告（本阶段产物）；任何确认的真 OP/破坏性失衡 → 记 **P3b** 输入，**本轮不调数值**。

---

## 5. 范围边界（YAGNI）

| 进 P3 | 出 P3（明确不做）|
|---|---|
| 支配判据改进 + 验证闸 + 终判 | 任何**数值复衡**（→ P3b，若验证后确认真 OP）|
| 真混编 A/B 重测 thousand_edge/mega_orb | inferno_aura radius **手感**回调（P2b §7#3 → P3b / 手感子项）|
| 后衡报告 | base 武器 Act1 可达性的**早期生存设计**（P2b §7#4 → 内容广度阶段）|
| | 宪法 §3 大 Phase 3：元进度 / 多角色 / 多地图 / Boss / run modifier（单独立项）|

---

## 6. 风险与决策记录

- **M2 分母地板**：强武器清空场地 → backlog→0 → clear_eff 爆。**缓解**：`BACKLOG_FLOOR` 常量 + 验证闸观察是否有进化命中地板；若多个命中，主轴降级为 M1 backlog。
- **混编 chassis 标定是窄缝**：底盘要「活到 t_evo 又不抢清场」。**缓解**：plan 先单跑烟测 chassis 确认 reach + 留 headroom；若 knife/orb 仍够不到（perk_hp×5 都垫不起，P2b §4），记为 base 可达性问题，A/B 改测「能到的种子」子集 + 报告披露 n。
- **验证闸失败**（新指标也误判 aura/horde）：这正是闸的价值——失败即回炉（M2→M1 fallback 或调地板/band），**不带病前进**。
- **C6 截断陷阱**：复衡曾有失败断言静默截断同套件后续发现（505 假象）。新测试排末尾、GREEN 态核对用例数。
- **C5 确定性**：离线重算纯无随机；新混编同种子聚合稳定（后期有界不确定已被用户接受，逐字节加固另立子项目）。
- **决策：本轮不调数值（测量+终判，复衡另立 P3b）**。理由：在新判据本身被验证闸验证前，不应据它动数值——这正是 kpm 翻车的教训（据失真判据复衡）。镜像 P2a（测）/P2b（衡）的成功拆分。
- **决策：混编用 A/B 边际归因而非「可达即读」**。理由：底盘会搅进清场贡献，单读混编 clear_eff 无法归因到目标进化；A/B delta 干净隔离目标进化的边际支配，直接回答 thousand_edge「绕冷却 OP」假说。

---

## 7. 实现衔接

三单元由 **writing-plans** 转为带 TDD 步骤的实现计划。建议落地顺序按依赖：
**单元 1（判据纯函数，TDD）→ 单元 2（验证闸，零重跑，先验证判据正确再继续）→ 单元 3（混编 A/B，新跑）**。
单元 2 的验证闸是单元 3 的前置：判据未过闸不进混编（否则又是据失真判据测量）。每单元独立提交、独立绿测；完后全量核对用例数（C6）+ 确定性回归（C5）。
