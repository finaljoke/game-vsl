# Bot 驱动器 + 遥测管线 — 设计 spec

- 日期：2026-06-17
- 状态：已通过设计评审，待写实现计划
- 目标读者：实现者（人或 agent）

## 1. 背景与动机

当前平衡观测仪 `autoloads/debug_metrics.gd` 只订阅三个信号——`enemy_died`（击杀）、
`player_leveled_up`（升级）、`player_healed`（有效嗜血），**全部落在"进攻/成长"轴**。
玩家受伤链路（`player_hit` 在 `player.gd:103` 已 emit、GameFeel 已用于红屏/震动）
**从未被采集**，所以仪表系统性偏盲：只看得见玩家在赢，数据必然好看。

更深的瓶颈在**取样方式**：

- 玩家是真人键盘驱动（`player.gd:67` `Input.get_vector`），没有任何 bot。
- 整局 `time_scale=1.00`，~10 分钟实时。

合起来 = 每取一个数据点都要真人手玩 10 分钟，操作水平是不受控变量，且每局 RNG 世界不同。
这让"改数值 → 看效果"的迭代闭环转不起来，也让 agent 无法主动跑实验。

本设计引入一个 **bot 驱动器 + headless 快进 + 确定性种子 + 结构化遥测导出** 的管线，
把取样从"分钟级人力"变成"秒级自动化"，并补齐威胁轴，使平衡/挑战/心流/闭环可量化、可 A/B。

### 不在本设计范围（诚实边界）

- **趣味性 / 爽快感** 这类主观手感测不出来，仍由人（设计者）判断；遥测只给结构（有没有挑战、闭环闭没闭）。
- **分武器 DPS 拆解**（v1 砍掉，见 §6）。

## 2. 既有代码事实（设计依据）

- **运行生命周期**：`autoloads/game_manager.gd` 状态机 `PLAYING/LEVEL_UP/DEAD`；
  `WIN_TIME=600.0`（10 分钟生存=胜利 → `victory_triggered`）；死亡 → `game_over` → `game_over_triggered`。
  **天然终局已存在**。
- **武器自动开火**：玩家唯一输入是移动 → bot 只需每帧决定一个移动向量，**无需瞄准**。
- **选卡是暂停式**：`game_manager.gd:34` `get_tree().paused=true` → `level_up_triggered`
  → `level_up_ui._on_level_up`（`scenes/ui/level_up_ui.gd:67`）用 `CardPool.pick(player)` 出 3 张
  → 点击 → `CardPool.apply` + `GameManager.resume_game()`。
- **RNG 全局**：`enemy_spawner.gd` 与 `card_pool.gd` 都用全局 `randi()/randf()` →
  **一句 `seed(N)` 即可让整局确定性可复现**。

## 3. 架构

采用「独立 `RunHarness` autoload + 玩家极小注入钩子」方案（评审中对比过
`Input.action_press` 合成离散输入、`BotPlayer` 替身场景两案，均更差）。

四个单元，各一个职责：

| 单元 | 类型 | 职责 | 关闭时 |
|---|---|---|---|
| `RunHarness` | 新 autoload | 编排：读命令行配置、驱动 bot、自动消解升级、设种子/快进、检测终局、收尾退出 | 无 `--bot` 参数则**完全惰性**，真人游玩不受影响 |
| `DebugMetrics` | 扩现有 | 指标模型 + 实时视图：订阅全部 GameFeel 信号、每 interval poll HP、累计进攻+威胁两轴、5s 控制台打印、注册 `add_custom_monitor` | 原样可独立删除 |
| `RunRecorder` | 新，纯序列化 | 把 DebugMetrics 累计值每 interval 写一行 tick CSV；订阅离散事件写 event log；终局写 summary.json | 不启用不开文件 |
| `player.gd` | +5 行钩子 | 注入式移动向量 | 钩子为 INF 即真人路径 |

### 3.1 玩家注入钩子

```gdscript
# player.gd
var bot_input: Vector2 = Vector2.INF   # 默认 INF = 真人；harness 每帧覆写

func _physics_process(delta: float) -> void:
    var dir := bot_input if bot_input != Vector2.INF else \
        Input.get_vector("move_left", "move_right", "move_up", "move_down")
    velocity = dir * SPEED * speed_mult
    move_and_slide()
    ...
```

## 4. Bot 移动策略（两模式可切换，`--bot=kite|still`）

- **kite**：每物理帧取 `enemies` 组，斥力向量 = Σ 归一化 `(player − enemy) · 权重(1/dist)`，
  叠"拉回竞技场中心"避墙偏置（竞技场固定 1280×720，边界已知），归一化 → 写 `player.bot_input`。
  可调参数：感知半径、避墙权重。此走位天然制造"爆发波里挨几下"的模式（正是要观测的威胁轴），
  且能活满 10 分钟，威胁数据接近真实战斗。
- **still**：`bot_input = Vector2.ZERO`，最大威胁暴露下界。完全确定、实现 trivial，但不代表正常玩法。

## 5. 选卡策略（固定优先级表 + 命名 profile，`--cards=<profile>`）

- 升级时由 **RunHarness 单点解决**：监听 `level_up_triggered` →
  `CardPool.pick(player)` 出 3 张 → 按优先级表选最高 → `CardPool.apply` → `GameManager.resume_game()`。
- **确定性陷阱（必须处理）**：`level_up_ui.gd:70` 自己也监听 `level_up_triggered` 并**独立再 `pick()` 一次**，
  两次 `randi()` 会让种子复现失效。解法：`_on_level_up` 开头加
  `if RunHarness.active: return`，唯一一次 pick 交给 harness。
- 优先级表 v1 用 harness 里的 const 字典存命名 profile（先给一套 `default`），
  以后再外置成 `data/bot_profiles/`。
- profile 形态：有序的 card-id / type 模式列表；从 3 张里取排序最靠前者；无命中则取第 0 张兜底。

## 6. 数据产物

写到 repo 内 `telemetry/`（**gitignore**，不入库），而非 `user://`（方便 agent 直接 `Read`）。

- **tick CSV**（每 interval 一行，快进时可调到 1s 取细曲线）。列：
  `t, level, kills_total, kills_ps, dmg_dealt_ps, dmg_taken_ps, hp, hp_pct, hp_min_win,
  danger_s, enemies_alive, enemies_near, healed_ps, time_scale`
  （`dmg_dealt_ps`=真实输出 DPS；`danger_s`=本窗口 hp<25% 时长；`enemies_near`=玩家半径内敌人数）。
  **进攻 + 威胁两轴齐全。**
- **event log**（`<out>.events.jsonl`）：离散事件——
  `level_up{level, picked_id, offered:[id...]}`、`player_hit{amount, hp_after, enemies_near}`、
  `director{type, count}`、`death{t, level}`、`victory`。让分析能找**因**，不只画曲线。
  - 注：`player_hit(amount)` 不带伤害来源；event log 在 emit 时由 RunRecorder 顺手查"当前敌人数/最近敌人类型"近似归因，不改战斗信号。
- **summary.json**（A/B diff 目标）：
  `outcome(win|death), survived_s, final_level, kills, dmg_taken_total, dmg_dealt_total,
  hp_pct_avg, hp_pct_min, danger_total_s, build:[picked_id...], seed, config`。

### 范围裁剪（YAGNI，v1 不做）

- **分武器 DPS**：`enemy_hit` 不带武器 id，要给每把武器 / `weapon_base` 打标，是独立一档改动。
  v1 只记总 DPS；等需要定位"哪把超模"时再单开。

## 7. 运行生命周期 + 确定性

- **配置入口**：`RunHarness._ready()` 读 `OS.get_cmdline_user_args()`：
  `--bot=kite|still`、`--cards=<profile>`、`--seed=<int>`、`--fast=<float>`、`--out=<path>`、`--maxtime=<s>`。
- **种子**：`seed(seed_value)` 须早于任何 `randi()`。autoload 先于主场景 init；
  首个 `randi()` 发生在首次 spawn/升级（晚于所有 autoload `_ready`），故 harness 在 `_ready` 中 seed 即足够。
  若顺序有疑虑，将 RunHarness 在 `project.godot` autoload 列表置顶。
- **快进（两根杠杆，含取舍）**：
  1. `--headless` 去掉 GPU/渲染；
  2. `Engine.time_scale = fast` 压缩 sim 时间。
  - 纯 headless（time_scale=1）对本 CPU-轻游戏仍≈实时；真正压缩 10 分钟靠 time_scale>1。
  - 代价：高 time_scale 放大每物理帧 `delta`，过高会碰撞穿透/不稳定。
  - 策略：默认 `--fast=3`；用"**同种子跑两遍 diff summary**"验确定性——能复现就升，发散就降。这是旋钮非魔法。
- **快进陷阱（必须处理）**：`game_feel.gd:166-169` hitstop 结束时**硬恢复 `time_scale=1.0`**，会冲掉快进值。
  修法：hitstop 恢复到基线变量（`RunHarness.base_time_scale`，默认 1.0）而非写死 1.0。
- **终局**：harness 连 `victory_triggered` / `game_over_triggered` + `--maxtime` 兜底 →
  触发 RunRecorder 收尾（关 CSV、写 summary.json）→ `get_tree().quit()`，headless 进程退出。

## 8. 触发与批量（agent 用法）

- 单跑（Windows 须用 `_console.exe` + headless）：
  ```
  Godot_v4.6.3-stable_win64_console.exe --headless --path . -- \
    --bot=kite --cards=default --seed=42 --fast=3 --out=telemetry/run_42
  ```
  harness 经 `OS.get_cmdline_user_args()` 读 `--` 之后的参数。
- agent 用 Bash 起进程（长则后台）→ harness 终局 `quit` → `Read` summary + CSV。
- **批量 A/B**：shell 循环 `5 seeds × 2 配置 = 10 局`，收 summary 对比；改一个数值前后各一批，输出威胁轴/存活/心流差异。
- 依赖：项目需已装 LimboAI GDExtension（enemy AI），headless 会加载——既有约束，不新增。

## 9. 测试（gdUnit4）

- **单元**：
  - kite 向量：给定敌人位置 → 移动方向符号正确（远离敌群、避墙）。
  - 选卡：给定 3 张 offered + 优先表 → 选中预期 id；空命中 → 取第 0 张。
  - CSV 行格式：字段顺序/数量正确。
  - 确定性：同种子两次（进程内）→ summary 相等。
- **冒烟**：`--maxtime=10 --fast=3` 短跑一局，进程正常退出且 CSV/summary 非空。

## 10. 受影响文件清单

- 新增：`autoloads/run_harness.gd`、`autoloads/run_recorder.gd`、`telemetry/`（gitignore）。
- 改：`project.godot`（注册两个 autoload，RunHarness 置顶）、`scenes/player/player.gd`（注入钩子）、
  `autoloads/debug_metrics.gd`（补威胁轴订阅 + getters + custom monitor）、
  `scenes/ui/level_up_ui.gd`（harness active 时 `_on_level_up` 早退）、
  `autoloads/game_feel.gd`（hitstop 恢复到基线而非写死 1.0）、`.gitignore`（加 `telemetry/`）。
- 测试：`tests/` 下新增对应 gdUnit 套件。

## 11. 验收标准

1. 无 `--bot` 时真人游玩行为与现在完全一致（钩子惰性、UI 正常、无新文件）。
2. `--bot=kite --seed=N --fast=3` headless 跑完一局自动退出，产出非空 CSV + events + summary。
3. 同 `--seed --cards --bot` 两跑，summary 关键字段相等（确定性）。
4. CSV 同时含进攻轴（kills_ps/dmg_dealt_ps）与威胁轴（dmg_taken_ps/hp_pct/danger_s/enemies_near）。
5. boss 击杀触发 hitstop 后，快进 time_scale 正确恢复到 `fast` 而非 1.0。
