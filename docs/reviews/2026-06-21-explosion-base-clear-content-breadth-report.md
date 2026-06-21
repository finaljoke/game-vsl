# 内容广度 · explosion 武器线 base 清场强度复衡报告（先测后定 + nuke 残留治本）

- **日期**：2026-06-21
- **定位**：落实 [P3c 后衡报告](2026-06-21-dominance-criterion-p3c-report.md) §5#1「explosion 武器线 base 清场强度（→ 内容广度阶段）：base explosion L3 自身 backlog 13（落带边）是 nuke 残留的真源」。属基石 spec（[combat-system-foundation](../superpowers/specs/2026-06-20-combat-system-foundation-design.md)）「先精后扩」的 base 武器平衡 track，受契约 C1–C6 约束。
- **用户指令**：先测后定（先用遥测隔离 base explosion 自身清场贡献，再据数据决定动不动、怎么动）；范围与方向由最佳判断定，要「最有游戏性」的调整。
- **数据**：新建 base 清场组遥测 telemetry/base_clear（solobase_ 永不进化 5 武器 × 5 种子）+ nuke 复测 telemetry/nuke_recheck（solo_explosion 8 种子复跑 → 新 nuke，余 10 进化复用现存 p3b_solo 有效数据）。

## 0. 一句话结论

> **P3c 把 nuke 残留定性为「base explosion 清场强度」并延到内容广度阶段。本轮先补一层 base 武器支配测量基建（`solobase_` 永不进化档 + `max_level_time` 满级窗口锚 + `analyze_base_clear`，纯分析/谐场层、零游戏码、8 条 TDD），证 base explosion 在 base 清场组里是决定性最强清场者（backlog 13.5、dev −0.49 OP，组中位 26.4），确证 §5① 真根。再以「周期化爆发，非持续地面控制」身份做 A/B 复衡：base explosion 经 cooldown 1.3→1.9 + 地火减半，从 −0.49 OP 降到 −0.36（带边，与 frostbite 同级、survival 安全 hp 0.66）；连带 nuke 平行下调（cooldown 1.3→1.6、burn 10→8、field 3.0→2.5，守 C4「进化≥base」+ 保二连爆 P4 身份），nuke 进化支配从 11.69/−0.40 OP → 13.45/−0.31 **ok**——§5① 残留治本完成。途中 A/B 证伪两件事并记为方法资产：① cooldown 是弱杠杆（地火 field_dur>cooldown 形成无视冷却的连续地火地毯 + 最密簇瞄准自补偿）；② blast_radius 是**生存杠杆非清场杠杆**（削半径不降 backlog 却把 hp 砸到 0.11，回退）。gdUnit 562/562 绿、C6 核数无截断、C4 绿。**

## 1. Deliverable A · base 武器支配测量基建（纯分析/谐场层，零游戏改动）

现存遥测只测**进化形态**（`analyze_dominance` 窗口锚在 `evolution_unlock_time`，`solo_profile` 必授进化），无路径测 base explosion L3 自身。P3c 的 `secondary_count=0` 诊断是近似（混入 nuke damage 40≠base 35）。本轮补：

- **`solobase_<wid>` 档**（[run_analysis.gd `solo_spec`](../../tools/run_analysis.gd) + [run_harness.gd `_grant_solo`](../../autoloads/run_harness.gd)）：复用 `solo_profile` 选卡，但 grant 时 `banish("evolve_"+wid)` → bot 永卡 base L3（同 `_grant_mix` 底盘永不进化机制）。即「若该武器从不进化」的纯净隔离——与 solo 唯一差别是不进化。
- **`max_level_time(events, wid)`**（[run_analysis.gd](../../tools/run_analysis.gd)）：首个 `picked==wid+"_3"` 的 t，作 base 窗口锚，与 `evolution_unlock_time` 对称；复用 `window_rows`/`window_metrics`/`summarize_evolution`/`flag_dominance`。
- **`analyze_base_clear.gd`**（[tools/](../../tools/analyze_base_clear.gd)）：仅 `is_base` 档、满级锚、P3c 角色感知清场组判据（`EVOLUTION_ROLE` + `flag_dominance`），键 `base_<wid>`。`analyze_dominance` 加 `is_base` 跳过守卫（base 无进化，防误判未达污染）。
- **TDD**：test_run_analysis +5（solo_spec is_base / max_level_time 三态），test_run_harness +3（solobase 解析 / profile 复用 / grant banish 集成），均排套件末（C6）。

零游戏码改动，可对任意未来 base/混编遥测零重跑重算——沉淀为长期 base 武器支配判据基建。

## 2. Deliverable B · base 清场组支配测量（决定性证 §5①）

`solobase_` 5 清场武器（P3c `EVOLUTION_ROLE` 的 clear 角色）× 5 种子（7/42/101/1/2），`--fixed-fps 60`（C5），满级窗口：

| base 武器 | backlog（低=强清场） | dev vs 组中位 | hp_min | verdict |
|---|---|---|---|---|
| **explosion** | **13.50** | **−0.49** | 0.71 | **OP** |
| frostbite | 16.80 | −0.36 | 0.80 | OP（带边） |
| lightning | 26.39 | 0.00（中位） | 0.90 | ok |
| maul | 136.71 | +4.18 | 0.86 | ok |
| aura | 167.67 | +5.35 | 0.78 | ok |

组中位 26.39，带 [17.15, 35.63]。**结论**：

1. **§5① 证实**：base explosion 是 base 清场组**决定性最强**（−0.49，比组中位低 49%，hp 安全）。P3c 单种子诊断的「带边 ok（−0.33）」是拿它跟**进化**组比的假象；正经 base 组 × 5 种子下它**明确 OP**，确为 nuke 残留真根。
2. **frostbite 带边 OP（−0.36）**：压带下沿一点点（噪声内）。本轮**判定不动**（决定性 act、带边记），承内容广度后续。
3. **maul/aura 是 base 弱清场者**（backlog 137/168）：base 形态非清场支配，仅在进化（earthshatter/inferno_aura）成清场者。即 base 清场角色组**双峰、分化不足**——内容广度的更大课题。

## 3. Deliverable C · 复衡（A/B 迭代）+ nuke 治本

**方向**：「周期化爆发，非持续地面控制」——保满威力爆发（damage/radius 不动，boom 不缩），把武器从「常驻清场引擎」改成「周期重炮」。逐杠杆 A/B（solobase_explosion ×5 重跑重算，余 4 武器数据不变、带稳定）：

| 迭代 | 改动 | explosion backlog | dev | hp_min | verdict |
|---|---|---|---|---|---|
| baseline | cd1.3 / burn10 / field3.0 / r100 / dmg35 | 13.50 | −0.49 | 0.71 | OP |
| i1 | cooldown 1.3→1.9 | 15.39 | −0.42 | 0.77 | OP |
| i2 | ＋地火 burn 10→6、field 3.0→2.0 | **16.83** | **−0.36** | 0.66 | OP（带边） |
| i3 | ＋blast_radius 100→88 | 16.58 | −0.37 | **0.11** | weak |
| 终值 | 回退 radius（=i2） | 16.83 | −0.36 | 0.66 | 带边 |

**两条方法发现（A/B 证伪，记为资产）**：
- **i1：cooldown 是弱清场杠杆**（−32% 频率仅 +14% backlog）。根因：`field_dur(3.0) > cooldown` → 地火**连续地毯**，给一个**无视冷却**的持续清场地板；且最密簇瞄准自补偿（冷却越长→单爆簇越密→单爆杀更多）。⇒「持续地面控制」正是要削的身份，对应削地火。
- **i3：blast_radius 是生存杠杆非清场杠杆**。削半径 100→88 几乎不动 backlog（16.83→16.58），却把 hp_min 砸到 0.11（边缘敌漏到玩家）。「清场没降只损安全」严格变差 → **回退**。这细化了 P3c「爆发驱动清场」：半径管的是**贴身保命式清场**，非总吞吐。

**裁决**：i2（cd1.9 + 地火减半，boom 满威力）是 survival 安全的最佳落点——explosion 从决定性 OP（−0.49）降到带边（−0.36，与可接受的 frostbite 同级）。爆发/生存纠缠使最后 2% 入带须损手感，**不强入带**（诚实落点，记残留）。

**nuke 连带治本**（[nuke.tres](../../data/weapons/nuke.tres)，平行身份下调，守 C4/P4）：cooldown 1.3→1.6、burn_dps 10→8、field_dur 3.0→2.5（radius 100 / damage 40 / blast_scale 1.6 / secondary_count 1 全留）。

| | 基线（p3b_solo） | 复衡后（nuke_recheck，8 种子） |
|---|---|---|
| **nuke**（evolve_explosion，进化组中位 19.54） | backlog 11.69、dev −0.40、**OP** | backlog 13.45、dev **−0.31、ok ✅** |

进化清场组复衡后全 ok（nuke −0.31 / thunderstorm −0.25 / earthshatter 0.00 / blizzard +0.19；余 10 进化数据不变、逐字节复用）。**§5① 进化残留治本完成**——nuke 入带，不再 OP。

**终值**（[explosion.tres](../../data/weapons/explosion.tres) / [nuke.tres](../../data/weapons/nuke.tres)）：

| | radius | burn_dps | field_dur | cooldown | damage |
|---|---|---|---|---|---|
| explosion L1/L2/L3 | 80/90/100（不变） | **4/5/6**（原 6/8/10） | **1.5/1.75/2.0**（原 2.0/2.5/3.0） | 3.2/2.0/**1.9**（原 …/1.3） | 32/34/35（不变） |
| nuke | 100（不变） | **8**（原 10） | **2.5**（原 3.0） | **1.6**（原 1.3） | 40（不变） |

## 4. 退出判据核对

| # | 判据 | 结果 |
|---|---|---|
| 1 | base explosion 不再决定性 OP | ✅ −0.49 → −0.36（带边，与 frostbite 同级；决定性 OP 已除，余为噪声级） |
| 2 | nuke §5① 残留治本 | ✅ −0.40 OP → −0.31 **ok**（进化组入带） |
| 3 | C4「进化≥base」+ 保二连爆（P4 身份） | ✅ nuke radius100≥100 / burn8≥6 / field2.5≥2.0 / cd1.6≤1.9 / secondary>0；test_nuke_clearing_ge_base_l3 绿。nuke 现严格快于+地火强于 base → 质变更清晰 |
| 4 | gdUnit 全绿 + C6 核数 | ✅ **562/562 绿 0 error**（+8 基建 TDD；2 条 .tres 数值断言更新：explosion L3 cd 1.3→1.9、L1 地火 6/2.0→4/1.5）；39/39 套件无截断 |
| 5 | C5 确定性 | ✅ 游戏码仅改 2 个 .tres 数据（explosion/nuke）+ 测试；谐场/分析层逻辑不变 → 确定性继承 |
| 6 | 复衡报告 | ✅ 本文 |

## 5. 残留局限 / 下一步

1. **base 清场角色组双峰、分化不足（内容广度主线）**：explosion(−0.36) 与 frostbite(−0.36) 是强 base 清场者，maul(+4.18)/aura(+5.35) 是弱 base 清场者（仅进化后清场），lightning 居中。本轮聚焦 explosion 线决定性 OP，**frostbite 带边 OP 判定不动、记此**；base 清场身份的整体差异化是更大的内容广度课题。
2. **explosion 仍 −0.36（带边）**：爆发/生存纠缠（半径既清场又保命）使其难在不损手感下入带。要么接受它作清场组的「强清场」身份、要么需一条 survival 中性的清场杠杆（如单爆杀伤上限/簇内目标数上限）——留待内容广度专项。
3. **测量基建是长期资产**：`solobase_` + `max_level_time` + `analyze_base_clear` 已 TDD 锁，可对任意未来 base/混编遥测零重跑重算，沉淀为 base 武器支配判据基建（对偶 P3c 的进化角色感知判据）。
