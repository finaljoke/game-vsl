# Dodge 探针(late-game bot probe)设计

> 状态：设计已与用户确认（2026-06-20）。下一步 = writing-plans 产出 TDD 实现计划。
> 关联宪法：[2026-06-20-combat-system-foundation-design.md](2026-06-20-combat-system-foundation-design.md) 的 **C5 遥测确定性** / **C6 测试契约**。

## 目标（一句话）

给 bot 加上"躲飞弹"能力,使其能跑到游戏后期,从而为 P2 平衡提供一个**真·后期** A/B 遥测基线;harness-only,零游戏平衡改动,保 C5 确定性。

## 背景与问题

2026-06-20 在 Godot 4.7 + 当前 master(Phase0+P1)重采全程基线(`telemetry/base47_{7,42,101}`,配方 `--bot=kite --cards=default --fast=3 --maxtime=600`):

| 种子 | 结局 | 存活 | Lv |
|---|---|---|---|
| 7 | death | 174.7s | 10 |
| 42 | death | 104.4s | 7 |
| 101 | death | 101.7s | 5 |

**三种子全在 Act1(≤175s/≤Lv10)暴毙,无一触及 P2 目标内容**(11 进化 / nuke / thousand_edge / 坍缩三类全是后期)。根因:master 的 kite bot **不躲飞弹**——`enemy_projectile` 不入组、`run_harness._compute_input` 只调 `compute_kite_dir`。远程敌(ghost,弹速 220px/s)放冷枪即可耗死它(诊断铁证见 [[project-vsl-bot-telemetry]]:死亡帧 `enemies_near=0` 却持续 dmg_in)。

历史背景(澄清,防再误判):记忆曾称 `balance/heal-threat-pacing` 分支"已落地躲弹 bot + 回血令牌桶 + 威胁缩放,250/250 绿"。**经查该工作从未提交 git**:分支标签停在远古点 `828fd60`(无独有 commit)、`git log --all` 无对应提交、唯一 stash(`1c449f3`)是**武器军械库重做之前**的远古 weapon WIP(已被 W0–W4 全面取代,非 dodge 代码)。故本设计 = **照描述重新实现**,而非合并分支。

## 范围

**In(本设计交付)**
- 弹体可被 bot 感知(入组)。
- 纯静态 `compute_dodge_dir` 决策函数(垂直弹道侧移)。
- `_compute_input` 加权合成 kite + dodge。
- 全程确定性排序(C5 在后期密集战的前提)。
- 单测 + 全量回归 + C5 重验 + 重采后期基线。

**Out(明确不做——这是 P2 的工作,不是前置)**
- 回血令牌桶(`HEAL_CAP_PER_SEC`)、接触伤害威胁缩放(`_threat_scale`)、spawn 节拍调整等**游戏平衡改动**。理由:① 那套数值 predates Phase0(perk_heal 已门控)+P1(玩家因暴击/元素协同已变强)→ 已过时;② 它们是**游戏改动,会改变 P2 本该测量的对象**——盲搬旧数值 = 先污染再测量。平衡留给 P2 拿新探针 + 新数据去做。

## 架构

延续现有"纯静态决策函数 + `_compute_input` 编排"模式(见 [run_harness.gd](../../../autoloads/run_harness.gd))。`compute_dodge_dir` 与现有 `compute_kite_dir` 平级,均为无场景依赖的纯函数(便于单测)。唯一游戏侧改动是给弹体加组标签,对真人游玩完全惰性(bot 不活跃时无人读该组)。

## 组件

### 1. enemy_projectile 入组
[enemy_projectile.gd](../../../scenes/enemies/enemy_projectile.gd) 加 `_ready()`:`add_to_group("enemy_projectiles")`。弹体速度 = `direction * SPEED`(`direction` 单位向量,`SPEED=220.0` 常量),bot 据此算弹道。

### 2. compute_dodge_dir(纯静态)
签名:`compute_dodge_dir(player_pos: Vector2, projectiles: Array, dodge_radius: float) -> Vector2`,`projectiles` 为 `[{ "pos": Vector2, "vel": Vector2 }]`。

逻辑:
1. 求和前对 `projectiles` 按位置 (x→y) `sort_custom` 定序(C5)。
2. 对每颗弹:
   - `to_player = player_pos - pos`;`dist = to_player.length()`。
   - 超 `dodge_radius` 或 `dist <= 0.001` → 跳过。
   - **仅对正在接近的弹反应**:`vel.dot(to_player) <= 0` → 跳过(远离/已过)。
   - 取**垂直弹道的侧移分量**:`vdir = vel.normalized()`;`lateral = to_player - vdir * to_player.dot(vdir)`(玩家相对弹道直线的横向偏移,即"把玩家进一步推离子弹直线"的方向)。
   - 正中(`lateral.length() < 0.001`)→ 取确定性垂直方向 `Vector2(-vdir.y, vdir.x)`(避免零向量;固定取一侧,确定性)。
   - 按距离近强加权:`steer += side.normalized() * (1.0 - dist / dodge_radius)`。
3. 净向量 `< 0.001` → 返回 `ZERO`;否则归一化返回。

### 3. _compute_input 合成
`kite` 模式下:
```
kite  = compute_kite_dir(player_pos, enemy_positions, arena_center, PERCEPTION_RADIUS)
dodge = compute_dodge_dir(player_pos, projectiles, DODGE_RADIUS)
dir   = kite * W_KITE + dodge * W_DODGE
return dir.normalized() if dir.length() > 0.001 else Vector2.ZERO
```
默认 `W_KITE=1.0`、`W_DODGE=1.5`(dodge 占优——正面斥力对快弹无效,需要侧移压过避敌)、`DODGE_RADIUS=200.0`。三者为集中常量,后续可微调。`still` 模式不变(返回 ZERO)。

### 4. bot 模式
dodge **折叠进现有 `kite` bot**:`--bot=kite` 即升级为后期探针,基线命令不变(`--bot=kite`)。纯 kite 的 Act1 死法无单独保留价值,单一探针更简单。不新增 `--bot=dodge` 模式(避免死代码路径)。

### 5. 确定性排序(C5)
`compute_kite_dir` 也补同样的 `sort_custom`(当前未排序;之所以没暴露分叉,是因为现 kite bot 174s 就死、没进 `get_nodes_in_group` 顺序会抖的密集终幕)。两个纯函数都在求和前定序 → 同种子同序相加 → 逐位确定。

## 测试(C6:契约用 gdUnit 锁;先红后绿)

`tests/test_run_harness.gd` 扩展(纯函数,无场景):
- `compute_dodge_dir`:① 无弹 → ZERO;② **接近但偏离弹道线**的弹(弹在玩家左下、向右飞,玩家在弹道线上方)→ 非零、且方向为"推玩家更远离弹道线"的垂直分量(可断言其与弹速 `vel` 点积≈0 且指向玩家偏离的一侧);③ 远离弹(`vel.dot(to_player)<=0`)→ ZERO;④ 超半径弹 → ZERO;⑤ **正中弹**(玩家恰在弹道延长线上,`lateral≈0`)→ 走兜底分支 `(-vdir.y, vdir.x)`、确定性非零;⑥ 乱序输入两次 → 同结果(锁排序确定性);⑦ 非零时归一化(长度≈1)。
- `compute_kite_dir`:补一条乱序输入 → 同结果(锁新增排序)。
- 弹体入组:`tests/`(场景或纯)断言新建 `enemy_projectile` `_ready` 后 `is_in_group("enemy_projectiles")`。

回归:全量 gdUnit 保持绿(现 486 + 新增;按 C6 在 GREEN 态核对精确用例数防截断,风险用例排最后)。

## 验收标准

1. **新单测全绿 + 全量回归无红**(C6,核对用例数)。
2. **C5 确定性(实测后放宽,见下「确定性发现」)**:seed 7 两跑须**聚合稳定**——最终 level 相同、存活时间/击杀数差 ≤ 数 %、build 绝大部分卡相同。**不再要求逐字节**(原因:游戏侧武器结算顺序在后期破裂确定性,pre-existing,非本探针引入)。P2 A/B 用多种子分布 + 效应量 > 噪声判定。
3. **功能(探针有效)**:dodge bot 在 seed 7/42/101 中**至少 1–2 个**跑到深后期(Lv≥~20 / 解锁进化 / 进入终幕),相对当前 ≤Lv10 显著推进。
4. **重采后期基线**:跑 7/42/101 输出 `telemetry/probe47_*`,记录新 A/B 数值(结局/存活/Lv/kills/dmg/danger/build)入 [[project-vsl-bot-telemetry]],作为 P2 平衡的后期参考基线。

## 确定性发现(2026-06-20 实测,影响 C5)

实现后 seed 7 两跑(`probe47_7` / `probe47_7b`)**未逐字节一致**。诊断:首个分叉在 **t=209s**,此刻 bot 可观测状态(level/kills/hp/enemies/enemies_near)**全部相同**,唯一差异是 `dmg_dealt_ps`(220 vs 232)→ **分叉源在游戏侧武器伤害结算,不在 dodge 代码**(bot 决策已被 `sort_custom` 定序,两跑到 209s 行为一致)。

根因:**13 个文件**无序迭代 `get_nodes_in_group("enemies")` / `get_overlapping_bodies()`(gravity_well/snow_field/burn_field/explosion/orb_shield/boomerang/knife/roaming_minion 等多为 AoE/DoT),命中目标集/浮点累加 run-to-run 微变 → 级联。这是 **pre-existing**:旧 kite bot 174s 就死、从未触及此区间(`base47_*` 两跑在 174s 内逐字节一致);探针让 bot 活到 209s+ 才暴露。与 [[project-vsl-bot-telemetry]] 记录的"dmg_dealt_ps 引擎级浮点微抖、对 A/B 无影响"同源,只是此前只在 t≈566s 极密终幕出现。

**裁决(用户 2026-06-20):接受有界不确定**。幅度小且聚合等价(seed7 两跑均 death/Lv21/~265s,21 卡中 20 卡相同)。逐字节确定的代价(审计排序 13 文件、game 改动、超 harness-only 范围)不值;真要做应另开"确定性加固"子项目(spec/plan)。P2 用多种子分布做 A/B。

## 风险与回退

- **dodge 抖动/反复横跳**:权重/半径不当可能让 bot 在多弹下抽搐。回退:调 `W_DODGE`/`DODGE_RADIUS`;必要时对 steer 做时间平滑(YAGNI,先不做)。
- **后期仍不确定**:若排序后 seed7 仍在 <560s 分叉,按记忆经验排查 `get_nodes_in_group` 之外的逐帧 RNG 消费者;终幕极密的引擎级微抖可接受并记录。
- **dodge 后 bot 反而无敌**:可能(因未带威胁缩放)。这**不是缺陷**——一个能到 Lv30 的"偏强"基线正是 P2 测进化 OP 所需的起点;难度回调是 P2 的工作。
