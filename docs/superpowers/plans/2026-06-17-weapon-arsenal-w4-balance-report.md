# 武器军械库重做 W4：遥测 A/B 平衡报告

> 方法、数值、与方法学发现的最终记录。本波只动「测量工具 + `.tres` 平衡数值」，不改任何武器机制。

## 1. 方法与管线

- **单武器 bot 档** `solo_<id>`（`RunHarness.profile_for` → `solo_profile`）：把 bot 漏斗进单把武器，隔离评估。
- **开局授予修复**（关键）：玩家开局无武器、随机三卡常不提供该 solo 武器 → bot Lv2 饿死、无信号。修复后 RunHarness 在 bot solo 模式下开局按 id 授予该武器（确定性，无 RNG）。solo_knife 由「51s/~0 杀」变为「230s/257 杀」。
- **纯分析核** `RunAnalysis`（`tools/run_analysis.gd`）：中位数 / 击杀每分（kpm）/ 跨武器 off-band 判定（带宽 ±35%）。
- **分析工具** `tools/analyze_runs.gd`（headless）：读 `telemetry/**.summary.json` → 按档分组 → 表 + `report.json`。
- **编排** `tools/run_ab_matrix.ps1`：「档 × 种子」矩阵，全程 `--fixed-fps 60`。
- 验收带宽：每档 `kills_per_min_med` 落在全档中位数 ±35%（`OP`/`weak` 之外即 `ok`）。

## 2. 确定性守卫（前置闸门）— 通过 ✅

同 (档, 种子) 跑两次，逐字段 diff `summary.json`：5 档（knife/explosion/maul/lightning/reanimate）全部**字节一致**。

根因确认：`run_harness._ready()` 调**全局** `seed(cfg.seed)` → 所有 `randi()`/`randf()`（暴击、雷暴 sky_strike、群尸分裂、spawner）确定；`create_timer` 在 `--fixed-fps 60` 下逐帧确定。

> **W3b 交接的「确定性风险」（核爆/震地 create_timer、雷暴 randi）= 在 `--fixed-fps 60` 下为虚惊**，实测 + 静态分析双重确认，无需修复。

## 3. 跑参环境

- 矩阵：11 档 × 5 种子（seed 1–5）= 55 局，`--fixed-fps 60 --fast 8 --maxtime 300`。
- 跨武器中位数 ≈ 68 kpm；带宽 **44.4–92.2**。

## 4. 调参记录（2 轮）

### Round 0（草案基线，5 种子中位 kpm）
| 武器 | kpm | 判定 |
|---|---|---|
| explosion 火球 | 115.6 | OP |
| frostbite 霜噬 | 113.0 | OP |
| reanimate 亡者召唤 | 93.6 | OP |
| gravity_well 引力井 | 91.6 | ok |
| boomerang 回旋斧 | 70.4 | ok |
| lightning 连锁闪电 | 68.3 | ok |
| maul 碎 | 64.8 | ok |
| aura 烈焰护体 | 64.7 | ok |
| knife 长弓 | 58.6 | ok |
| whip 斩 | 35.7 | **weak** |
| orb 缚灵 | 26.7 | **weak** |

5 档 off-band：OP=火球/霜噬/亡者召唤；weak=斩/缚灵。

### Round 1（damage 杠杆）— commit `38f172f`
OP↓：火球 damage 40/42/44→32/34/35；霜噬 16/18/20→13/14/16；亡者召唤 14/14/16→12/12/14。
weak↑：缚灵 8/8/9→12/12/14；斩 22/24/26→29/31/34。（同步 whip Lv1 damage 断言 22→29。）

结果：
- **斩 35.7→50.1（ok）✅** —— damage 杠杆对单体武器有效。
- 缚灵 26.7→25.9（仍 weak）—— +50% damage 几乎无效：缚灵是被动守卫，瓶颈是接触频率非 damage。
- 火球 115.6→113.6 / 霜噬 113.0→111.2（仍 OP）—— damage 削减几乎不动 kpm：二者**巡航至 maxtime**，kpm 受刷怪率封顶而非 damage；削 damage 只降了 hp_min（更险）。
- 亡者召唤 93.6→106.9（仍 OP，反升）—— 非线性：随从更弱 → 怪堆积更密 → 单位存活秒杀率反升。

**方法学发现**：`kills/min` 带宽对**巡航 / 被动 / 召唤**档不响应 damage 杠杆，需机制档（冷却 / 覆盖 / 存活 / 攻速）。

### Round 2（机制杠杆）— commit `8c38ee7`
火球 cooldown 2.6/1.6/1.0→3.2/2.0/1.3；霜噬 cooldown 1.4/1.1/0.9→1.8/1.4/1.1；亡者召唤 lifetime 12/14/16→9/10/11；缚灵新增 hit_cooldown 0.35/0.32/0.30。（同步 test_apply_explosion_3 cooldown 1.0→1.3、test_reanimate lifetime 12→9。）

结果：
- **亡者召唤 106.9→77.9（ok）✅** —— lifetime↓ 有效（随从早退场 → 持续清场↓，存活 252→199 更险）。
- 霜噬 111.2→103.2 —— 下降且**开始真受威胁**（存活 300→266、hp_min 0.35→0.18、danger 0→3.5），但 kpm 仍略 > 带宽。
- 火球 113.6→112.6 —— 几乎不动，**顽固巡航**（仍活满 300、hp_min 高）。提冷却未能拉下其 kpm。
- 缚灵 25.9→31.7 —— 改善（hit_cooldown↓，+22%）但仍 weak。

## 5. 最终状态

| 武器 | kpm | 判定 |
|---|---|---|
| explosion 火球 | 112.6 | **OP（巡航档，记为取舍）** |
| frostbite 霜噬 | 103.2 | **OP（接近带宽）** |
| gravity_well 引力井 | 91.6 | ok |
| reanimate 亡者召唤 | 77.9 | ok ✅(R2 收敛) |
| boomerang 回旋斧 | 70.4 | ok |
| lightning 连锁闪电 | 68.3 | ok |
| maul 碎 | 64.8 | ok |
| aura 烈焰护体 | 64.7 | ok |
| knife 长弓 | 58.6 | ok |
| whip 斩 | 50.1 | ok ✅(R1 收敛) |
| orb 缚灵 | 31.7 | **weak（被动·效用档，记为取舍）** |

**8/11 ok**（含 R1/R2 各收敛一把：斩、亡者召唤）。

## 6. 剩余 3 档 off-band — 有意取舍 + 建议（plan §收敛判据允许）

`kpm` 带宽是**伤害受限武器**的良好一阶信号（斩、亡者召唤经此收敛），但对以下原型失真：

- **火球 / 霜噬（巡航 AoE，OP）**：清场覆盖 ≥ 刷怪率 → 全程巡航，kpm 被刷怪率封顶，与自身 damage/cooldown 弱相关。要真正拉下 kpm 须削**覆盖**（blast_radius/area）使怪「漏过」→ 但那会过度牺牲手感（把强势-安全档削成挫败档）。**建议**：要么接受其「强但需走位」定位（霜噬已被 R2 推到真受威胁），要么改用「覆盖 + maxtime 存活率」的复合判据而非纯 kpm。霜噬已逼近带宽（103 vs 92.2），火球是最顽固的巡航档。
- **缚灵（被动守卫，weak）**：环绕守卫的 kpm 天然低（接触频率受限）。R2 的 hit_cooldown↓ 已 +22%；进一步需提 `total_orbs`（契约字段，且其进化 mega_orb 已 total_orbs 8）或重定义为「低 kpm 高生存/效用」档。**建议**：接受其效用定位，或后续单独提 total_orbs 基线 +1。

> 这些是 kpm 单指标对原型的盲区，宜由设计判断（覆盖/效用/手感），不宜机械地为凑指标而侵入式削改。

## 7. 最终数值（相对草案基线的净改动）

- 火球 explosion：damage 40/42/44→**32/34/35**，cooldown 2.6/1.6/1.0→**3.2/2.0/1.3**
- 霜噬 frostbite：damage 16/18/20→**13/14/16**，cooldown 1.4/1.1/0.9→**1.8/1.4/1.1**
- 亡者召唤 reanimate：damage 14/14/16→**12/12/14**，lifetime 12/14/16→**9/10/11**
- 缚灵 orb：damage 8/8/9→**12/12/14**，hit_cooldown(新注入) **0.35/0.32/0.30**
- 斩 whip：damage 22/24/26→**29/31/34**

其余 6 把（aura/boomerang/gravity_well/knife/lightning/maul）草案数值即落带宽，未改。

## 8. 回归与确定性确认

- 全量测试：**397/397，0 失败，31 套件全绿**（含被调契约字段的同步断言：whip Lv1 damage 29、explosion_3 cooldown 1.3、reanimate lifetime 9）。
- 所有 A/B 在 `--fixed-fps 60` 下确定（守卫闸门通过）。
- `telemetry/` gitignore，运行产物不入库；本报告与工具/档/数值已入库。

## 9. 复现命令

```powershell
# 跑矩阵(脚本默认 5 种子;勿用 -Seeds 逗号串,pwsh -File 会把数组折成单值)
pwsh -File "D:\Workspace\GAME\game_0_vsl\tools\run_ab_matrix.ps1" -MaxTime 300 -OutDir telemetry/ab
# 分析
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://tools/analyze_runs.gd -- --dir=telemetry/ab --report=telemetry/ab/report.json
# 确定性守卫(同档同种子两跑 diff)
# (见 .git/sdd 记录 / 计划 Task 5)
```

> **已知工具陷阱**：`pwsh -File run_ab_matrix.ps1 -Seeds 1,2,3,4,5` 会把数组实参折成单值 `12345`（[int[]] 绑定）。用脚本默认 `-Seeds`（不覆盖）或逐档调用规避。

## 10. 结论

- W4 交付：单武器 bot 档 + 纯分析核 + 分析工具 + 矩阵编排 + 确定性守卫（通过）+ 开局授武修复 + 2 轮数据驱动调参（收敛 2 把）+ 本报告。
- 最终 8/11 落 ±35% kpm 带宽；剩 3 把（火球/霜噬 OP 巡航、缚灵 weak 被动）为 kpm 单指标对原型的盲区，记为有意取舍并给出原型感知的后续建议。
- 整套军械库重做（W0–W3b 机制/进化 + VFX-W1/W2/W3 视效 + W4 平衡）实现完毕，全程 397/397 测试绿。
