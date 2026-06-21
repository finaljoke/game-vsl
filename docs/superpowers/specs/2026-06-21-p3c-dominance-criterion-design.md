# P3c · 支配判据治本 + nuke 二连爆 P4 保形复衡（设计 spec）

- **日期**：2026-06-21
- **定位**：治本 [P3b 后衡报告](../../reviews/2026-06-21-evolution-rebalance-p3b-report.md) §5#1 列为「最高优先后续」的判据局限。承 [P3 判据闭环报告](../../reviews/2026-06-20-dominance-criteria-report.md) §4b#6「无单一轴是完整支配度量 / 判据持续改进」。
- **上位契约**：[基石设计](2026-06-20-combat-system-foundation-design.md) 柱 P4「进化=质变」· C4（质变守恒，gdUnit 锁）/ C5（遥测确定性）/ C6（测试核数）。
- **用户指令**：`/goal 请治本`——修根因，不治标，自治推进。

## 0. 问题陈述（根因诊断，经真实数据量化）

P3b 收尾遗留：nuke / thunderstorm 砍到 P4 身份地板后 `flag_dominance` 仍判 **OP**，earthshatter 判 ok。P3b 报告 §2a 把这归为「判据局限」但**根因诊断有误**——它叙述的是 `clear_eff` 被弱进化压低，而 verdict 实际跑的是 **backlog 主轴**（`clear_eff` 仅 context 列）。

读 [telemetry/p3b_solo/dominance_report.json](../../../telemetry/p3b_solo/dominance_report.json) 量化真根因（backlog_mean_med，反向：低=强清场）：

```
orb 0.0(未达)  knife 0.0(未达)  nuke 11.69  thunderstorm 14.71  earthshatter 19.54
frostbite 23.28  reanimate 37.32  gravity 38.04  whip 50.53  boomerang 97.94  aura 175.12
```

全 11 进化中位 = **23.28**，带底 `23.28×0.65 = 15.13`。nuke(11.69) / thunderstorm(14.71) 落带底下 → 判 OP。

**两层真根因**：

1. **未达进化 backlog 退化为 0.0**：`summarize_evolution` 对 reached=0 的 knife/orb，`median([])` 返回 0.0。这是「无数据」冒充「完美清场」，污染中位基准。**当前数据集里它把中位压低（反而掩盖 OP）**，但是潜在正确性 bug：换数据集会任意扭曲。

2. **跨角色比较（真驱动 nuke/thunderstorm 假阳）**：backlog 是**角色依赖**量。aura(175)/boomerang(98) 是非清场角色（单体/控场/远轨），天然高 backlog。把它们和清场专精塞进同一个中位基准，清场专精**永远显得"异常强"**。这是 nuke/thunderstorm 被误判的真因——它们没真 OP，是判据角色盲。

**验证**：把清场专精 {aura, frostbite, explosion, lightning, maul} 单独成组算中位 = 19.54、带底 12.70 → **thunderstorm(14.71)/earthshatter(19.54) 落带 = ok（假阳消除）**；nuke(11.69) 仍差一点（−40% vs 带 ±35%）= **被隔离出的单一真残留**。

3. **隔离后 nuke 是真阳（非判据假阳）**：读 [explosion_weapon.gd](../../../scenes/weapons/explosion/explosion_weapon.gd) `_spawn_explosion`——nuke `secondary_count=1`（二连爆）第二次 detonate 时 `burn_dps>0 and field_dur>0` 分支**再铺一团地火**，即在最密人堆叠**双层持续地火**（各 3s×10dps）。这是 nuke backlog 仍全场最低的真驱动。base explosion `secondary_count=0` 无此叠加。

## 1. 目标 / 非目标

**目标**（完整治本 = 两层都修，根因消除非掩盖）：
- **A 判据治本**（分析层，零游戏改动，对现存遥测零重跑重算）：`flag_dominance` 改**角色感知清场组 + 未达过滤**，消除 thunderstorm/earthshatter 假阳，隔离真阳。
- **B nuke 二连爆 P4 保形治本**（游戏层，针对 A 隔离出的单一真残留）：二连爆**不叠第二团地火**（保留延迟再引爆的爆发质变，去掉翻倍的持续清场），守 P4/C4。

**非目标**（沿用 P3b §1 边界）：
- 不动 nuke/thunderstorm/earthshatter 的 `.tres` 数值（已在 P4 身份地板；A 修判据、B 改 script 行为，均非数值倒退）。
- 不重做非清场角色的支配轴（单体/控场/召唤的支配该用各自相关轴度量——超本轮，记残留）。
- 不碰 inferno_aura 手感、base 早期可达性（→ 内容广度阶段）。

## 2. Deliverable A — 支配判据 v2（`flag_dominance` 角色感知 + 未达过滤）

### 2.1 接口（向后兼容）

`flag_dominance(by_evo, band=0.35, roles={})` 加第三参 `roles`（by_evo-key → 角色字符串）。**`roles` 空 → 退化为旧单组行为 + 未达过滤**（现有合成单测无角色 → 零破坏）；非空 → 角色组。

新增纯模块常量 + 助手（run_analysis.gd）：

```gdscript
const REACH_MIN: float = 0.5   # 达进化比例下沿;低于此 → 基准不计 + verdict weak

# 进化角色(设计意图,独立于 backlog 测量值,非循环):clear=AoE 区域清场专精。
const EVOLUTION_ROLE := {
    "aura": "clear", "frostbite": "clear", "explosion": "clear",
    "lightning": "clear", "maul": "clear", "whip": "clear",
    "boomerang": "single", "knife": "single",
    "orb": "control", "gravity_well": "control",
    "reanimate": "summon",
}

# by_evo 键("evolve_<wid>") → 角色映射(供 analyze_dominance 传入 flag_dominance)。
static func roles_for(by_evo: Dictionary) -> Dictionary:
    var out := {}
    for k in by_evo:
        var wid := String(k).trim_prefix("evolve_")
        out[k] = EVOLUTION_ROLE.get(wid, "clear")
    return out
```

> 角色取**设计意图**（aura/frostbite/explosion/lightning/maul/whip 是 AoE 清场武器，与各自机制一致），独立于 backlog 测量值声明，**非循环**（不是"测出来清场强就标 clear"）。这是与坍缩三类同源的领域知识。

### 2.2 v2 判据逻辑

```
reached_keys = { k : reached_ratio(k) >= REACH_MIN }          # 未达过滤:基准只用达进化
surv_med, hp_med, clear_med = median over reached_keys         # 安全/context 轴:全角色达进化
clearing_keys = roles 非空 ? { reached_keys : role=="clear" } : reached_keys
backlog_med = median(backlog) over clearing_keys               # 清场轴:仅清场角色组

for k in by_evo:
    role = roles.get(k, "clear");  is_clear = (role == "clear")
    clear_v = is_clear ? band_verdict(backlog, backlog_med) 反向 : "na"   # 非清场角色不参清场 OP
    surv_v, hp_v = band_verdict vs reached-pop 中位
    low_axes = (clear_v=="low") + (surv_v=="low") + (hp_v=="low")
    verdict:
        weak  if reached<REACH_MIN  or (death>0.5 and surv_v=="low")  or low_axes>=2
        OP    elif is_clear and clear_v=="high" and hp_v!="low"
        ok    else
flags[k] += { "role": role }                                   # 输出加 role 列
```

**关键**：非清场角色（single/control/summon）`clear_v="na"`，**不参与清场组中位、不会被判清场 OP**（其高 backlog 是角色非弱）；仍可因 reached<0.5/死亡主导判 weak。

### 2.3 预期重算结果（对现存 p3b_solo，可证）

clearing_keys = {aura,explosion,frostbite,lightning,maul}（whip clear 但 reached0.125 排除）。backlog 中位 19.54、带 [12.70, 26.38]：

| 进化 | backlog | v1 verdict | **v2 verdict** | 说明 |
|---|---|---|---|---|
| explosion(nuke) | 11.69 | OP | **OP（隔离真残留）** | −40%，单一过带，→ Deliverable B |
| lightning(thunderstorm) | 14.71 | OP | **ok ✅ 假阳消除** | 落清场组带内 |
| maul(earthshatter) | 19.54 | ok | ok | 组中位 |
| aura/frostbite | 175/23.28 | ok | ok | clear 组,backlog 高/中但 hp 安全 |
| boomerang/gravity/reanimate | — | ok/ok/ok | ok | 非清场角色,不参清场 OP（reanimate 旧 kpm 误 OP 也消） |
| knife/orb/whip | 0/0/50.5 | weak | weak | reached<0.5 |

## 3. Deliverable B — nuke 二连爆不叠第二团地火（P4 保形）

### 3.1 改动（[explosion_weapon.gd](../../../scenes/weapons/explosion/explosion_weapon.gd)）

`_spawn_explosion` 加 `lay_field: bool = true` 参；地火分支加 `lay_field and` 守卫；二连爆调用传 `false`：

```gdscript
func _spawn_explosion(center: Vector2, lay_field: bool = true) -> void:
    ...（生成 explosion、detonate 不变）...
    if lay_field and burn_dps > 0.0 and field_dur > 0.0:   # 二连爆 lay_field=false → 不铺第二团
        ...（BurnField 生成不变）...

# attack() 内二连爆:
for i in range(secondary_count):
    var c := center
    get_tree().create_timer(secondary_delay * float(i + 1)).timeout.connect(
        func() -> void: _spawn_explosion(c, false))   # 二连爆只爆发,不叠地火
```

**质变守恒**：二连爆仍延迟再 detonate（爆发 AoE 伤害 + 视觉），保「延迟再引爆」质变；仅去掉**第二团持续地火**（翻倍清场驱动）。base explosion `secondary_count=0` 不受影响（无二连爆）。nuke `.tres` 数值零改（primary 地火 burn_dps10/field_dur3 = base L3、secondary_count=1>base 0 全不变）→ **C4 契约 `test_nuke_clearing_ge_base_l3` 仍绿、P4 仍守**。

### 3.2 预期效应

去掉 kill-zone 第二层 3s 地火 → nuke 持续清场降 → backlog 由 11.69 升向清场组带 [12.70, 26.38]。目标=落带（v2 判 ok）。实测为准；若过冲偏弱则诚实记（nuke 在数值地板,二连爆地火是唯一 P4 内可调杠杆）。

## 4. 测试策略（TDD）

**A 单测**（[test_run_analysis.gd](../../../tests/test_run_analysis.gd)）：
- `roles_for` 映射正确（evolve_explosion→clear、evolve_knife→single、未知→clear 默认）。
- `flag_dominance` 角色组：合成 by_evo（清场组 + 高 backlog 非清场角色），断言**非清场高 backlog 不被判 OP/不进清场中位**；清场组带内 ok、过带 OP。
- 未达过滤：reached<0.5 进化不计入中位基准（构造一个 reached=0、backlog=0 的项，断言它不把基准拖向 0 → 其余进化 verdict 不被它扭曲）。
- **回归**：现有 3 条 `flag_dominance` 单测（roles 缺省）保持绿。

**B 单测**（[test_weapons_w3b.gd](../../../tests/test_weapons_w3b.gd) 或 explosion 测试）：
- `_spawn_explosion(center, false)` → ysort 下**零** BurnField（仅 explosion）。
- `_spawn_explosion(center, true)` → 一个 BurnField（base 行为保持）。

**契约回归**：`test_evolution_contracts.gd` 13/13（nuke C4 不变）；全量 gdUnit 绿 + **C6 核数**（改值/改判据后跑所有相关套件,核对用例数,防截断——P3b §5 教训）。

## 5. 验证（数据闭环）

1. **A 重算**：判据 v2 落地后，`analyze_dominance --dir=telemetry/p3b_solo --report=.../dominance_v2.json` **对现存遥测零重跑重算** → 核对 thunderstorm/earthshatter→ok、nuke 隔离。
2. **B 重跑**：editor 关闭后，explosion solo 重跑（`run_p2a_campaign.ps1 -Weapons explosion -OutDir telemetry/p3c_nuke`，bot=kite/fast=8/maxtime=600/8 种子）→ v2 判据重算 → 核对 nuke backlog 升、verdict 走向。
3. **C5**：mix_orb 或 explosion 同种子两跑聚合稳定（沿用 P2b「聚合稳定非逐字节」裁决）。

## 6. 退出判据

| # | 判据 |
|---|---|
| 1 | 判据 v2：现存 p3b_solo 重算下 thunderstorm/earthshatter verdict **OP→ok**（假阳消除）；非清场角色不被判清场 OP；未达进化不污染基准 |
| 2 | nuke 二连爆 script 改后：C4 契约绿、P4 守（数值零改、二连爆质变保留）；新 BurnField 行为 2 单测绿 |
| 3 | nuke explosion solo 重跑 + v2 重算：backlog 升向清场组带（理想 verdict→ok；若过冲偏弱诚实记，nuke 在 P4 地板无更优杠杆） |
| 4 | 现有 3 条 flag_dominance 单测 + 全量 gdUnit 绿 + C6 核数无截断 + C5 聚合稳定 |
| 5 | 后衡报告（含 v2 重算前后对照表 + nuke 前后 backlog） |

## 7. 风险 / 缓解

- **角色映射被质疑"为凑答案而选"**：缓解——角色按设计意图声明（机制一致）、独立于 backlog 测量；且**承诺诚实报告 v2 真 verdict**（nuke 即便仍 OP 也照报，不剔 aura 凑 nuke 入带）。
- **B 过冲使 nuke 偏弱**：nuke 数值在地板,二连爆地火是唯一 P4 内杠杆;过冲则记诚实残留（不为入带违 P4 反向加数值）。
- **C6 截断**（P3b 血泪）：改判据/改 script 后跑所有相关套件 + GREEN 态核对用例数。
