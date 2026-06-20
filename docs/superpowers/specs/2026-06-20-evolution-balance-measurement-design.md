# P2a · 进化平衡测量与诊断 · 设计 spec

- **日期**：2026-06-20
- **状态**：待用户复审
- **定位**：Phase 2「平衡完整性」的**前半（P2a）**。上位 = [战斗系统基石设计](2026-06-20-combat-system-foundation-design.md) §3/§5/§6 与 [全战斗系统分析](../../reviews/2026-06-20-combat-system-analysis.md) §5。
- **关键纪律**：**先测后衡**。本 spec 只产出「数据背书的进化支配性报告」，**不动任何数值**。复衡（nuke/thousand_edge/数值倒退/坍缩三类向量）留给 **P2b**——拿到本报告后再立独立 spec。遵守 C5「OP 嫌疑先开 solo 档定位支配性，再动数值」。

---

## 0. 一句话定调

> **11 个进化从未被真实遥测过；它们的数值是手填的。P2a 用已就位的 solo+dodge 遥测管线，把每个进化的后期真实表现测出来、用多轴判据判 OP/weak，产出一份能直接驱动 P2b 复衡的支配性报告。**

---

## 1. 已验证的前提（2026-06-20 实测，非假设）

写本 spec 前实跑了一发探针验证核心假设（`telemetry/p2a_probe/solo_explosion_s7`，配方见 §3）：

| 验证项 | 结果 | 证据 |
|---|---|---|
| solo 档 + dodge 探针能否到达进化后期窗口 | ✅ **能**：`evolve_explosion` 于 t=191.9s(Lv15) 解锁，victory @ 548.7s/Lv29/1478 kills | `solo_explosion_s7.summary.json` + `.events.jsonl` |
| 进化卡就绪后是否可靠投放 | ✅ **是**：Phase 0 确定性投放生效，进化就绪即占槽被选 | events L15 `picked=="evolve_explosion"` |
| 进化窗口分段是否可算 | ✅ **可**：`t_evo` 取自 events 的 `picked=="evolve_<w>"` level_up，tick.csv(515 行/1s) 切 `t>=t_evo` 得 ~357 行后期窗口 | 同上 |

**两个由实测暴露的方法学缺口（本 spec 必须解决，否则数据无效）**：

- **缺口 A · solo 隔离泄漏**：`solo_explosion` 的 build 混进了 `knife_3`/`gravity_well_3`/`boomerang_2`。根因：solo profile 无 `type:weapon`，但 `RunHarness.choose_card` 在「三张都不匹配 profile」时**兜底取 `offered[0]`**（[run_harness.gd:120](../../../autoloads/run_harness.gd#L120)），于是捡了外来武器。→ 实测的是**混合 build**，不是目标进化单独。**per-evolution 判据被污染。**
- **缺口 B · dodge bot 防御饱和**：该 run `danger_total=0、dmg_taken=2.1、hp_min=0.984`——bot 整局几乎零伤（dodge 后近乎无敌，dodge spec 已预警）。→ 多轴判据的**安全轴对「强」进化普遍饱和**（都显示极安全），主要 OP 分辨力落在 kpm + 生存；安全轴只对**弱尾**有分辨力。

---

## 2. 复用既有基建（不重造）

| 组件 | 复用 | 说明 |
|---|---|---|
| `RunHarness` solo 档 | ✅ | `--cards=solo_<weapon>` 自动授武器→升满级→拿 `evolve_<weapon>`→堆 perk（[run_harness.gd:37](../../../autoloads/run_harness.gd#L37)） |
| dodge 探针 | ✅ | `--bot=kite` 即后期探针，bot 到 Lv29/victory |
| `RunRecorder` | ✅ | tick CSV（每秒 level/kills/dmg/hp/danger/enemies）+ events JSONL（level_up 含 offered/picked/t）+ summary |
| `tools/run_ab_matrix.ps1` | ✅（改配方） | 11 solo 档 × 种子批跑；本 spec 收紧默认（见 §3） |
| `tools/analyze_runs.gd` + `run_analysis.gd` | ✅（扩） | 现仅读 summary、kpm 单轴判 OP/weak；本 spec 扩为「窗口分段 + 多轴」 |

**唯一新增/改动**：① 一个**小 harness 改动**（solo 隔离闸，缺口 A）；② **分析层扩展**（窗口分段 + 多轴判据，纯函数 TDD）。**零游戏平衡改动。**

---

## 3. 测量配方（实测验证）

```
& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --fixed-fps 60 \
  --path "D:\Workspace\GAME\game_0_vsl" -- \
  --bot=kite --cards=solo_<weapon> --seed=<N> --fast=8 --maxtime=600 --out=telemetry/p2a/solo_<weapon>_s<N>
```

- `--fixed-fps 60`：C5 确定性根因（**非** `--fast`）。
- `--fast=8`：**已实测 dodge 在 fast=8 下有效**（探针 victory 取 2.1 伤），无需回退 fast=3。墙钟 ≤ maxtime/fast ≈ 75s/run + 启动。
- **种子默认 8 个**（`7 42 101` + 5 新，如 `1 2 3 4 5`）。墙钟估算 ~88 run × ~50s ≈ 1.2h。可先 3 种子验管线再扩。← *最可能想调的参数*
- **操作约束**：跑前**关编辑器**（CLAUDE.md LimboAI 双实例陷阱）。

---

## 4. 组件设计

### 组件 1 · solo 隔离闸（修缺口 A，小 harness 改动）

**问题**：`choose_card` 兜底 `offered[0]` 让 bot 捡外来武器，污染隔离。

**设计**：solo 档**开局 banish 掉除目标外的全部武器卡**，使池子永不提供外来武器 → bot 的非目标 pick 只会落到目标武器升级 / perk / synergy / 目标进化，build 纯净。
- 实现位点：`RunHarness._grant_solo_weapon`（[L246](../../../autoloads/run_harness.gd#L246)）授予目标后，对 `WeaponDB` 全武器 id（除目标）调 `CardPool.banish(id)`。
- 外来武器被 banish → 永不 owned → 其 `_2/_3` 升级（`has:<weapon>` 门控）永不就绪 → 其进化永不 ready。池仍含目标升级/perk/synergy/目标进化 + Phase 0 空池兜底券，**不软锁**（C3）。
- **仅 solo 档触发**（`_cards_name_val.begins_with("solo_")`）；`default` 档与真人路径不受影响。

**验收**：solo 档启动后 `CardPool.pick` 永不返回非目标 `type==weapon` 卡；目标进化仍能就绪投放。

### 组件 2 · 进化窗口分段（扩分析器，纯函数 TDD）

把分析从「整局 summary」改为「进化后窗口」——直接测**进化**而非 base+evo 混合。

**数据流**（纯函数核 `run_analysis.gd`，IO 由 `analyze_runs.gd` 喂）：
1. `evolution_unlock_time(events: Array, weapon_id) -> float`：扫 events，返回首个 `type=="level_up" 且 picked=="evolve_"+weapon_id` 的 `t`；无 → 返回 `-1`（该 run **未达进化**）。
2. `window_rows(tick_rows: Array, t_evo) -> Array`：取 `t >= t_evo` 的 tick 行。
3. `window_metrics(window_rows, outcome, t_end) -> Dictionary`：算后期窗口三轴（§5）。
4. 未达进化的 run（`t_evo==-1`）**单列**为 `reached_evolution=false`，不混入窗口聚合（其本身是强 weak 信号）。

**鲁棒性**：`t_evo` 逐 run 取自该 run 自己的进化事件，跨种子各切各的窗口、再对窗口指标取中位数 → 对 13-文件非确定性的时机微抖鲁棒（C5）。

### 组件 3 · 多轴透明判据（扩 `flag_off_band`）

每个进化报**三轴**，跨进化中位数 ±band 判偏：

| 轴 | 数值度量（走 ±band 判偏） | 定性标注（可强制 verdict） | 主要分辨 |
|---|---|---|---|
| **清场效率 kpm** | `kpm_post` 中位 | — | **OP**（强进化清场飞快） |
| **生存力** | `survived_post` 中位（窗口存活时长） | `outcome` 分布 + `reached_evolution` 比例 | **weak**（弱进化早死/到不了进化） |
| **安全裕度** | `hp_min_post` 中位（辅 `danger_mean_post`） | — | **weak 尾**（缺口 B：对强进化饱和，只分辨弱尾） |

**判定规则**（band 默认 0.35，沿用现值；可调）：
- **数值轴判偏**：每轴对**跨进化中位数** `m_axis` 算 ±band；`v > m×(1+band)` 为高、`v < m×(1−band)` 为低。
- **效应量** = 相对偏离 `v / m_axis − 1`（如 kpm 高出中位 80% → 效应量 +0.80）。报告每轴列效应量，供 P2b 判"偏多少 → 调多少"。
- **OP** = kpm 轴偏高 **且** 生存轴非劣（多数 victory/跑满）。安全轴不作 OP 必要条件（缺口 B 饱和）。
- **weak** = ≥2 数值轴偏低，**或** 定性强制：多数种子 `reached_evolution=false`（到不了进化本身即 weak），或多数 `outcome==death` 且 `survived_post` 偏低。
- 报告每进化列：三轴值 + 各轴效应量、各轴 verdict、综合 verdict、**偏在哪轴**（→直指 P2b 复衡杠杆）。

> **缺口 B 的明确记录**：因 dodge bot 防御近无敌，"安全轴"对强进化普遍饱和。故 **OP 检测主要靠 kpm + 决定性（多快通关）**，安全/生存轴主要用于**弱尾**与"未达进化"检测。这是有意识的非对称，不是 bug。P2b 若需更强的 OP 安全分辨，可另设"调高威胁"的探针档（留作 P2b 决策，YAGNI）。

### 组件 4 · 支配性报告（产出物 = P2b 输入）

- `telemetry/p2a/report.json` + 控制台 CSV：11 进化 × 三轴中位 + 各轴/综合 verdict + 效应量 + `reached_evolution` 比例。
- **叙事核对段**（人工 + 数据）：
  - **坍缩三类对账**：OP 旗是否命中假设 —— `nuke`(evolve_explosion)=全屏覆盖②、`thousand_edge`(evolve_knife)=绕冷却③。命中即在报告标注「坍缩原型」。
  - **数值倒退核对**：进化窗口 dmg/kpm 是否低于同 run 进化前满级窗口（血鞭/炼狱嫌疑）。
- 该报告**不含修法**，只含「谁偏、偏多少、偏在哪轴、像哪类坍缩」。修法是 P2b。

---

## 5. 后期窗口三轴的精确定义

对单个 run（已切出 `window_rows`，窗口 = `[t_evo, t_end]`）：
- `win_dur = t_end - t_evo`
- `kpm_post = (kills_total[末行] - kills_total[首行]) / win_dur × 60`
- `hp_min_post = min(hp_pct over window_rows)`
- `danger_mean_post = mean(danger_ps over window_rows)`
- `survived_post = win_dur`（victory/timeout 则为跑满到终局；death 则到死亡）
- `outcome ∈ {victory, death, timeout}`、`reached_evolution = (t_evo >= 0)`

跨种子聚合：每个量取**中位数**；`reached_evolution` 取**比例**。

---

## 6. 测试（C6 TDD）

- **纯函数核**（`run_analysis.gd` 新增 `evolution_unlock_time` / `window_rows` / `window_metrics` / 多轴 `flag`）走 TDD：`tests/test_run_analysis.gd`（现有套件）追加用例——喂构造的 events/tick 数组，断言：① 进化时刻定位（含"无进化→-1"）；② 窗口切分（边界 `t>=t_evo`）；③ 三轴算值；④ 多轴 verdict（OP/weak/ok 各一例 + "多数未达进化→weak"）。
- **solo 隔离闸**：`tests/test_run_harness.gd` 或 `test_card_pool.gd` 加用例——solo 设置后 `CardPool.pick` 不含非目标武器卡；目标进化仍可就绪。
- **全量回归绿 + 核对用例数**（截断陷阱 C6：新用例排末尾，GREEN 态核对发现数 == 预期）。
- **C5 聚合稳定复验**：同种子重跑 1 个 solo 档两次，确认窗口三轴中位漂移 < 噪声（非逐字节）。

---

## 7. 退出判据（P2a）

1. **solo 隔离闸**上线且 TDD 锁定：solo build 纯净（无外来武器）。
2. **11 进化全部**跑出 N(默认8) 种子 × 后期窗口数据（含"未达进化"标记）。
3. **多轴判据**上线 + TDD 锁定（窗口分段 + 三轴 + flag）。
4. **支配性报告**产出：每进化三轴 verdict + 综合 + 效应量；OP 旗与坍缩三类对账；数值倒退核对。
5. 全量绿 + C5 聚合稳定复验。
→ **P2b 据此报告立复衡 spec。**

---

## 8. 不做（P2a Out，明确边界）

- ❌ **任何数值/平衡改动**（nuke/thousand_edge 复衡、数值倒退修复、坍缩向量封堵）—— 全是 **P2b**。
- ❌ **坍缩向量的新游戏侧埋点**（coverage density 显式仪表）—— 多轴 OP 旗 + 叙事核对足以定位；若 P2b 诊断需要再加。
- ❌ **mixed-build / 混编遥测** —— solo 隔离是 C5 指定方法（"先 solo 定位支配性"）。
- ❌ **"调高威胁"探针档**以破安全轴饱和（缺口 B）—— 留作 P2b 决策，先不做（YAGNI）。

---

## 9. 风险与决策记录

| 风险/决策 | 处置 |
|---|---|
| **solo 隔离泄漏**（缺口 A，实测确认） | 组件 1 开局 banish 外来武器，build 纯净。**否则 per-evolution 数据无意义。** |
| **安全轴饱和**（缺口 B，实测确认） | 组件 3 记录非对称：OP 靠 kpm+决定性，安全/生存轴主分辨弱尾。不强行破饱和（P2b 决策）。 |
| **C5 后期非逐字节** | 多种子 + 窗口中位聚合 + 效应量>噪声判定（沿用 dodge spec 裁决）。 |
| **fast=8 是否毁 dodge** | 实测 fast=8 dodge 有效（victory 取 2 伤），用 fast=8。 |
| **gdUnit 截断陷阱** | 新用例排末尾，GREEN 态核对发现数（C6）。 |
| **stale 遥测误导**（det/ 的 51s 暴毙、smoke 手写桩） | 已识别为 pre-dodge stale；P2a 全部重采，旧 telemetry 不作基线。 |

---

## 10. 实现衔接

本 spec 由 **writing-plans** 转为带 TDD 步骤的实现计划 `docs/superpowers/plans/2026-06-20-evolution-balance-measurement.md`。建议落地顺序：
**组件1（隔离闸，TDD）→ 组件2+3（分析器窗口+多轴，TDD）→ 跑 campaign（11×8）→ 组件4（出报告 + 叙事核对）→ 退出判据核验。**
