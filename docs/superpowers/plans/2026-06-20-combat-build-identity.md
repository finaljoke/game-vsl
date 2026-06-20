# 构筑身份（Phase 1）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: 用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现本计划。步骤用 `- [ ]` 复选框跟踪。

**Goal:** 立起 4 条可读构筑路线（🔥燃烧/❄️控制/⚡感电/🗡️暴击），各有 enabler→payoff→synergy 卡链：给武器贴元素标签、补 slow 易伤 payoff（C2 转全绿）、把暴击做成可堆轴、加元素/控制协同卡。不加新武器。

**Architecture:** 玩家的构筑 modifier 集中在 `Player` 字段；其消费**尽量集中在单一 chokepoint**——`Enemy.apply_status`（burn/freeze/stun 增益）与 `Enemy.take_damage`（slow 易伤），以及 `WeaponBase.damage_for`（物理暴击）——避免逐武器改动。所有战斗数学抽成 `Enemy`/`WeaponBase` 的**纯静态函数**单测。元素标签存于 `WeaponData.tags`（数据驱动），协同卡门控用新 `has_tag:` DSL。

**Tech Stack:** Godot 4.7 / GDScript / gdUnit4（headless）/ LimboAI v1.7.1。

**上位 spec:** [docs/superpowers/specs/2026-06-20-combat-build-identity-design.md](../specs/2026-06-20-combat-build-identity-design.md)（实现其 5 个单元 U1–U5）。

## Global Constraints

- **测试命令**（单套件，PowerShell）：
  ```
  & "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_pool.gd
  ```
  末尾 `-a res://tests/<file>.gd` 换套件；`-a res://tests` 跑全量。
- **跑 headless 前先关 Godot 编辑器**：编辑器开着时再跑 headless，第二实例复制 `~liblimboai…dll` 临时名会撞 → LimboAI 加载失败、BTPlayer 未注册（见 CLAUDE.md「Windows 双实例冲突」）。本计划很多任务**不需要**编辑器，跑测试前确认编辑器已关。
- **`--ignoreHeadlessMode` 必加**，否则 gdUnit abort 退出码 103。
- **gdUnit 截断陷阱（C6）**：某测试解析/脚本错误会**静默截断**其后测试的发现。每次跑完**核对发现用例数**，不能只看"全绿"。新增测试若让总数不升反降 → 有解析错误，先修。新测试文件排查时单独跑。
- **确定性契约（C5）**：`pick()` 是 bot 遥测路径唯一选卡入口；新增卡/标签**不得引入 `randf`/时间依赖**。新 modifier 默认值必须是无效果中性值（`burn_mult=1.0`、其余 `=0.0`），保证无卡时行为逐字节不变。
- **向后兼容已锁契约（C1）**：`synergy_multiplier` 新增的 `slow_vuln_frac` 参数**必须带默认值 `:= 0.0`**，且 `slow_vuln_frac=0` 时公式退化为原式——现有 `test_enemy_synergy.gd` 全部用例不得变红。
- **注释/文案一律简体中文**（全仓库约定）。
- **提交规范**：conventional commits；执行时按本仓库规范追加 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer。**只 `git add` 本任务明确列出的文件，禁止 `git add -A`**（仓库有 ~2600 预存未追踪文件，收录是用户决策）。
- **元素标签权威映射**（§5 of spec，本计划据此）：

  | 武器 / 进化 | tags |
  |---|---|
  | knife / thousand_edge | `physical` |
  | whip / bloody_whip | `physical`, `fire` |
  | boomerang / cyclone | `physical` |
  | maul / earthshatter | `physical`, `ice`, `lightning` |
  | orb / mega_orb | `physical` |
  | explosion / nuke | `fire` |
  | aura / inferno_aura | `fire` |
  | lightning / thunderstorm | `lightning` |
  | frostbite / blizzard | `ice` |
  | gravity_well / singularity | `gravity`, `ice` |
  | reanimate / horde | `summon` |

---

## Task 0: 确认分支 + 记录基线用例数

P1 spec 已提交在分支 `feat/combat-build-identity`（commit 9356867）。本计划在同分支继续。

- [ ] **Step 1: 确认在 P1 分支**

Run: `git branch --show-current`
Expected: `feat/combat-build-identity`。若不在，`git checkout feat/combat-build-identity`。

- [ ] **Step 2: 关闭 Godot 编辑器**（若开着），再跑全量基线

Run:
```
& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: 全绿；**记下用例总数 N_base**（记忆基线 ≈456）。后续每加一批测试，总数应**只增不减**。

---

## Task 1: `WeaponData.tags` + 22 个 .tres 标注

**Files:**
- Modify: `data/weapons/weapon_data.gd`（加 `tags` 字段）
- Modify: 22 个 `data/weapons/*.tres`（11 基础 + 11 进化，加 `tags`）
- Test: `tests/test_weapon_tags.gd`（**新建**）

**Interfaces:**
- Produces: `WeaponData.tags: Array[StringName]`；每把武器（经 `WeaponDB.get_data(id)`）暴露其元素标签。

- [ ] **Step 1: 写失败测试**（新建 `tests/test_weapon_tags.gd`）

```gdscript
# tests/test_weapon_tags.gd
# 锁定 11 基础 + 11 进化武器的元素标签(spec §5 权威映射)。
extends GdUnitTestSuite

const EXPECTED_TAGS := {
	"knife": [&"physical"],
	"whip": [&"physical", &"fire"],
	"boomerang": [&"physical"],
	"maul": [&"physical", &"ice", &"lightning"],
	"orb": [&"physical"],
	"explosion": [&"fire"],
	"aura": [&"fire"],
	"lightning": [&"lightning"],
	"frostbite": [&"ice"],
	"gravity_well": [&"gravity", &"ice"],
	"reanimate": [&"summon"],
	"thousand_edge": [&"physical"],
	"bloody_whip": [&"physical", &"fire"],
	"cyclone": [&"physical"],
	"earthshatter": [&"physical", &"ice", &"lightning"],
	"mega_orb": [&"physical"],
	"nuke": [&"fire"],
	"inferno_aura": [&"fire"],
	"thunderstorm": [&"lightning"],
	"blizzard": [&"ice"],
	"singularity": [&"gravity", &"ice"],
	"horde": [&"summon"],
}

func test_all_weapons_have_expected_tags() -> void:
	for id in EXPECTED_TAGS:
		var data := WeaponDB.get_data(id)
		assert_object(data).override_failure_message("缺武器数据 %s" % id).is_not_null()
		for tag in EXPECTED_TAGS[id]:
			assert_bool(data.tags.has(tag)) \
				.override_failure_message("%s 缺标签 %s" % [id, tag]).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_weapon_tags.gd`
Expected: FAIL —— 报 `Invalid get index 'tags'`（字段不存在）。

- [ ] **Step 3a: 加 `tags` 字段**（`data/weapons/weapon_data.gd`，`evolution` 行之后）

```gdscript
# 元素/机制标签(P1 构筑身份)：fire/ice/lightning/physical/gravity/summon。
# 协同卡门控(has_tag:) + 暴击轴(physical 自动可暴) + 卡面可读性。多标签=武器可属多路线。
@export var tags: Array[StringName] = []
```

- [ ] **Step 3b: 给 22 个 .tres 加 tags**

每个 `data/weapons/<id>.tres` 的 `[resource]` 块内加一行（按上表）。格式为 Godot 4 typed-StringName-array：
```
tags = Array[StringName]([&"physical", &"fire"])
```
例：`data/weapons/whip.tres` 加 `tags = Array[StringName]([&"physical", &"fire"])`；`data/weapons/explosion.tres` 加 `tags = Array[StringName]([&"fire"])`；`data/weapons/maul.tres` 加 `tags = Array[StringName]([&"physical", &"ice", &"lightning"])`；依此类推全 22 个。

> **若 import 报 .tres 解析错误**（手写格式不确定）：改用 Godot 编辑器 Inspector——选中 .tres → 在 `Tags` 数组属性逐个加元素 → 保存，编辑器写出的格式必正确。test_weapon_tags 会逐项锁定，漏标/错标即红。
> **加完 .tres 后必须 headless `--import` 一次**让 Godot 重新导入（编辑器没开时）：
> `& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" --import`

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_weapon_tags.gd`
Expected: PASS。若仍红 → 看失败信息里是哪把武器缺哪个标签，补对应 .tres。

- [ ] **Step 5: 提交**

```
git add data/weapons/weapon_data.gd data/weapons/*.tres tests/test_weapon_tags.gd
git commit -m "feat(weapons): WeaponData.tags + 22武器元素标签(火/冰/雷/物理/重力/召唤)"
```

---

## Task 2: `has_tag:` 条件 DSL

**Files:**
- Modify: `autoloads/card_pool.gd`（`_check_condition()` 加分支；新增 `_player_has_tag()`）
- Test: `tests/test_card_pool.gd`（文件末尾追加）

**Interfaces:**
- Consumes: `WeaponDB.get_data()`、`WeaponData.tags`（Task 1）、`player.owned_weapons`。
- Produces: 条件 DSL 新增 `has_tag:<tag>`——持有任一带该标签的武器即真；`CardPool._player_has_tag(player, tag: StringName) -> bool`。

- [ ] **Step 1: 写失败测试**（追加到 `tests/test_card_pool.gd` 末尾）

```gdscript
# ── P1 单元1：has_tag 条件 DSL ─────────────────────────────────────────────
func test_has_tag_false_when_no_tagged_weapon() -> void:
	assert_bool(CardPool._check_condition("has_tag:fire", _player)).is_false()

func test_has_tag_true_when_owns_fire_weapon() -> void:
	_stub_owns("explosion", 1)
	assert_bool(CardPool._check_condition("has_tag:fire", _player)).is_true()

func test_has_tag_physical_true_for_knife() -> void:
	_stub_owns("knife", 1)
	assert_bool(CardPool._check_condition("has_tag:physical", _player)).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_card_pool.gd`
Expected: FAIL —— `has_tag:` 未识别，`_check_condition` 末尾 `return false` 让真断言变红。

- [ ] **Step 3: 实现**（`autoloads/card_pool.gd`）

(a) `_check_condition()` 里、`if condition.begins_with("has:")` 分支**之前**插入：
```gdscript
	if condition.begins_with("has_tag:"):
		return _player_has_tag(player, StringName(condition.substr(8)))
```
(b) `_check_condition()` 函数**之后**加 helper：
```gdscript
# 持有任一带该标签的武器即真(数据驱动：标签存于 WeaponData.tags)。
func _player_has_tag(player: Player, tag: StringName) -> bool:
	for id in player.owned_weapons:
		var data := WeaponDB.get_data(id)
		if data != null and data.tags.has(tag):
			return true
	return false
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_card_pool.gd`
Expected: PASS（含 Task 0 基线在内全绿）。

- [ ] **Step 5: 提交**

```
git add autoloads/card_pool.gd tests/test_card_pool.gd
git commit -m "feat(cardpool): has_tag 条件 DSL(按元素标签门控,去硬编码)"
```

---

## Task 3: slow payoff —— 易伤桶（C2 转全绿）

**Files:**
- Modify: `scenes/enemies/enemy.gd`（常量、`synergy_multiplier` 加参、新增 `effective_slow_vuln`、`take_damage` 接线）
- Modify: `scenes/player/player.gd`（加 `slow_vuln_bonus` 字段）
- Test: `tests/test_enemy_synergy.gd`（追加）

**Interfaces:**
- Consumes: `player.slow_vuln_bonus`、`has_status(&"slow")`、`_player`。
- Produces:
  - `Enemy.SLOW_VULN_BASE := 0.30`、`Enemy.SLOW_VULN_CAP := 0.50`。
  - `Enemy.effective_slow_vuln(slowed: bool, player_bonus: float) -> float`（纯）。
  - `Enemy.synergy_multiplier(channel, frozen, stun, hp_frac, amp_frac, slow_vuln_frac := 0.0) -> float`：易伤桶 `(1 + amp_frac + slow_vuln_frac)`。
  - `Player.slow_vuln_bonus: float = 0.0`。

- [ ] **Step 1: 写失败测试**（追加到 `tests/test_enemy_synergy.gd` 末尾）

```gdscript
# ── P1 单元2：slow 易伤(加法并桶) ──────────────────────────────────────────
func test_slow_vuln_increases_direct() -> void:
	# slow_vuln 0.30、无其他 → ×1.30
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, false, 1.0, 0.0, 0.30)).is_equal_approx(1.30, 0.0001)

func test_slow_vuln_applies_to_dot() -> void:
	# 易伤桶在通道门控之外 → DOT 也吃(同 amp)
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DOT, false, false, 1.0, 0.0, 0.30)).is_equal_approx(1.30, 0.0001)

func test_amp_and_slow_vuln_add_in_same_bucket() -> void:
	# 加法并桶：1 + 0.25 + 0.30 = 1.55(非 1.25×1.30=1.625)
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, false, 1.0, 0.25, 0.30)).is_equal_approx(1.55, 0.0001)

func test_slow_vuln_multiplies_across_shatter_bucket() -> void:
	# 碎裂 ×1.5 与易伤桶(1+0.30) 跨桶相乘 → 1.5 × 1.3 = 1.95
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, false, 1.0, 0.0, 0.30)).is_equal_approx(1.95, 0.0001)

func test_synergy_default_slow_vuln_is_zero() -> void:
	# 不传 slow_vuln → 退化旧式(向后兼容已锁契约)
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, false, 1.0, 0.25)).is_equal_approx(1.875, 0.0001)

func test_effective_slow_vuln_zero_when_not_slowed() -> void:
	assert_float(Enemy.effective_slow_vuln(false, 0.5)).is_equal_approx(0.0, 0.0001)

func test_effective_slow_vuln_baseline_when_slowed() -> void:
	# 无卡也有基线 +30%(C2:slow 不再是孤儿状态)
	assert_float(Enemy.effective_slow_vuln(true, 0.0)).is_equal_approx(0.30, 0.0001)

func test_effective_slow_vuln_caps_at_half() -> void:
	# 基线 0.30 + 卡 0.50 → 封顶 0.50
	assert_float(Enemy.effective_slow_vuln(true, 0.5)).is_equal_approx(0.50, 0.0001)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_enemy_synergy.gd`
Expected: FAIL —— `effective_slow_vuln` 不存在；带 6 参的 `synergy_multiplier` 调用因签名只有 5 参而报错。

- [ ] **Step 3: 实现**

(a) `scenes/enemies/enemy.gd` 的状态协同常量区（`CONFLAG_DAMAGE` 行后）加：
```gdscript
const SLOW_VULN_BASE: float = 0.30   # 减速目标的基线易伤(无卡即生效,补 C2 slow 孤儿缺口)
const SLOW_VULN_CAP: float = 0.50    # 易伤硬封(范本 StS Vulnerable/PoE Shock)
```
(b) 整体替换 `synergy_multiplier`：
```gdscript
# 纯函数(便于单测)：状态协同乘区。
# 易伤桶(amp + slow_vuln)桶内相加；碎裂/处决跨桶相乘(C1 桶纪律,防全乘区指数起飞)。
static func synergy_multiplier(channel: DamageChannel, frozen: bool, stun: bool, hp_frac: float, amp_frac: float, slow_vuln_frac: float = 0.0) -> float:
	var m := 1.0
	if amp_frac > 0.0 or slow_vuln_frac > 0.0:   # 易伤桶：引力增幅 + 减速易伤，相加
		m *= (1.0 + amp_frac + slow_vuln_frac)
	if channel == DamageChannel.DIRECT:          # 打击型协同：仅直击
		if frozen:
			m *= SHATTER_MULT
		if stun:
			m *= (1.0 + EXECUTE_BASE + EXECUTE_SCALE * (1.0 - hp_frac))
	return m

# 纯函数(便于单测)：减速目标的有效易伤 = (基线 + 攻击方卡加成)，封顶；非减速则 0。
static func effective_slow_vuln(slowed: bool, player_bonus: float) -> float:
	if not slowed:
		return 0.0
	return minf(SLOW_VULN_BASE + player_bonus, SLOW_VULN_CAP)
```
(c) `take_damage` 里把快照与 final 计算改为（替换 `var amp :=` 到 `var final :=` 两行）：
```gdscript
	var amp := status.magnitude(&"amp")
	# slow 易伤(C2)：减速目标受额外伤害。攻击方加成读 _player(单点接线,基线对所有通道生效)。
	var slow_bonus := 0.0
	if _player != null and is_instance_valid(_player) and "slow_vuln_bonus" in _player:
		slow_bonus = _player.slow_vuln_bonus
	var slow_vuln := effective_slow_vuln(has_status(&"slow"), slow_bonus)
	var final := amount * synergy_multiplier(channel, frozen, stun, hp_frac, amp, slow_vuln)
```
(d) `scenes/player/player.gd`，`lifesteal` 字段（:38）后加：
```gdscript
var slow_vuln_bonus: float = 0.0  # 减速目标易伤加成(冰封/控制卡叠加;基线 0.30 在 Enemy 侧)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_enemy_synergy.gd`
Expected: PASS —— 8 新用例 + 原 13 个回归全绿（`test_frozen_plus_amp_direct_stacks_multiplicatively`=1.875 仍绿，证明向后兼容）。

- [ ] **Step 5: 提交**

```
git add scenes/enemies/enemy.gd scenes/player/player.gd tests/test_enemy_synergy.gd
git commit -m "feat(combat): slow 易伤桶(基线+30%封顶+50%,与amp加法并桶),补 C2 孤儿状态"
```

---

## Task 4: 物理武器自动暴击（暴击轴机制就位）

**Files:**
- Modify: `scenes/weapons/weapon_base.gd`（新增 `crit_enabled`；`damage_for` 用之）
- Test: `tests/test_crit_axis.gd`（**新建**）

**Interfaces:**
- Consumes: `WeaponData.tags`（Task 1）。
- Produces: `WeaponBase.crit_enabled(can_crit: bool, tags: Array) -> bool`（纯）——`can_crit` 或武器带 `physical` 标签即可暴击。

- [ ] **Step 1: 写失败测试**（新建 `tests/test_crit_axis.gd`）

```gdscript
# tests/test_crit_axis.gd
# 暴击轴：物理标签武器自动可暴 + crit_multiplier 纯函数回归。
extends GdUnitTestSuite

func test_crit_enabled_when_physical_tag() -> void:
	assert_bool(WeaponBase.crit_enabled(false, [&"physical"])).is_true()

func test_crit_enabled_when_can_crit_flag() -> void:
	assert_bool(WeaponBase.crit_enabled(true, [])).is_true()

func test_crit_disabled_for_nonphysical_without_flag() -> void:
	assert_bool(WeaponBase.crit_enabled(false, [&"fire"])).is_false()

func test_crit_multiplier_hits_on_low_roll() -> void:
	assert_float(WeaponBase.crit_multiplier(0.0, 0.5, 0.0, 2.0)).is_equal_approx(2.0, 0.0001)

func test_crit_multiplier_misses_on_high_roll() -> void:
	assert_float(WeaponBase.crit_multiplier(0.99, 0.5, 0.0, 2.0)).is_equal_approx(1.0, 0.0001)

func test_crit_multiplier_distance_bonus_stacks_on_chance() -> void:
	# 长弓矛盾修正：距离 bonus 叠加在全局 crit_chance 上(chance 0.2 + bonus 0.3 = 0.5 > roll 0.4)
	assert_float(WeaponBase.crit_multiplier(0.4, 0.2, 0.3, 2.0)).is_equal_approx(2.0, 0.0001)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_crit_axis.gd`
Expected: FAIL —— `crit_enabled` 不存在（其余 crit_multiplier 用例本会绿，但文件含未定义函数 → 整套件红，正是要先实现）。

- [ ] **Step 3: 实现**（`scenes/weapons/weapon_base.gd`）

(a) `crit_multiplier` 函数前加纯函数：
```gdscript
# 纯函数(便于单测)：是否可暴击 —— 显式 can_crit 或武器带 physical 标签(暴击=物理流派轴)。
static func crit_enabled(can_crit: bool, tags: Array) -> bool:
	return can_crit or tags.has(&"physical")
```
(b) 整体替换 `damage_for`：
```gdscript
# 伤害 = 基础 × 玩家全局伤害加成；物理武器(或显式 can_crit)按 (crit_chance+crit_bonus) 概率 ×crit_mult。
func damage_for(base: float, can_crit: bool = false, crit_bonus: float = 0.0) -> float:
	var dmg := base * (_player as Player).damage_mult
	var tags: Array = data.tags if data != null else []
	if crit_enabled(can_crit, tags):
		var p := _player as Player
		dmg *= crit_multiplier(randf(), p.crit_chance, crit_bonus, p.crit_mult)
	return dmg
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_crit_axis.gd`
Expected: PASS。再跑 `-a res://tests/test_card_pool.gd` 确认武器升级/进化用例未受影响（`damage_for` 行为对 crit_chance=0 不变：物理武器 ×crit_multiplier(roll, 0, bonus, mult)，bonus 通常 0 → 不暴，等价旧值）。

- [ ] **Step 5: 提交**

```
git add scenes/weapons/weapon_base.gd tests/test_crit_axis.gd
git commit -m "feat(combat): 物理标签武器自动可暴击,暴击轴机制就位(A2)"
```

---

## Task 5: 暴击卡 `perk_crit` / `synergy_crit`

**Files:**
- Modify: `autoloads/card_pool.gd`（`CARDS` 加 2 卡；effect 注册 + 回调）
- Test: `tests/test_card_pool.gd`（追加）

**Interfaces:**
- Consumes: `player.crit_chance`、`player.crit_mult`。
- Produces: 卡 `perk_crit`（暴击率 +8%，封顶 0.60，`has_tag:physical`）、`synergy_crit`（暴伤 +0.4，`has_tag:physical`）。

- [ ] **Step 1: 写失败测试**（追加到 `tests/test_card_pool.gd` 末尾）

```gdscript
# ── P1 单元3：暴击卡 ───────────────────────────────────────────────────────
func test_perk_crit_increases_crit_chance() -> void:
	CardPool.apply({"id": "perk_crit", "type": "perk"}, _player)
	assert_float(_player.crit_chance).is_equal_approx(0.08, 0.001)

func test_perk_crit_caps_at_60_percent() -> void:
	for i in range(20):
		CardPool.apply({"id": "perk_crit", "type": "perk"}, _player)
	assert_float(_player.crit_chance).is_equal_approx(0.60, 0.001)

func test_synergy_crit_increases_crit_mult() -> void:
	CardPool.apply({"id": "synergy_crit", "type": "synergy"}, _player)
	assert_float(_player.crit_mult).is_equal_approx(2.4, 0.001)

func test_crit_cards_gated_by_physical_weapon() -> void:
	for c in CardPool.pick(_player, 99):
		assert_str(c["id"]).is_not_equal("perk_crit")
	_stub_owns("knife", 1)
	var found := false
	for c in CardPool.pick(_player, 99):
		if c["id"] == "perk_crit":
			found = true
	assert_bool(found).is_true()
```

**改现存计数用例** `test_pick_returns_all_available_when_pool_smaller_than_count`（约 L43）—— 本任务加了 perk_crit + synergy_crit，满血 6 武器满级场景含物理武器(knife/orb/whip/boomerang) → 这 2 张入池，9 改 **11**：
```gdscript
func test_pick_returns_all_available_when_pool_smaller_than_count() -> void:
	# 占满 6 武器槽全满级 → 武器/升级/进化全剔除。满血 → perk_heal 剔除。
	# 剩：5 属性 + 4 现有质变 + perk_crit + synergy_crit(物理武器在) = 11
	for id in ["knife", "orb", "explosion", "lightning", "whip", "boomerang"]:
		_stub_owns(id, 3)
	_player.hp = _player.max_hp
	var cards := CardPool.pick(_player, 99)
	assert_int(cards.size()).is_equal(11)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_card_pool.gd`
Expected: FAIL —— 4 个新 apply/gating 用例红（卡不存在）；改过的计数用例此刻仍是 9 ≠ 11 也红。

- [ ] **Step 3: 实现**（`autoloads/card_pool.gd`）

(a) `CARDS` 数组末尾（`perk_heal` 行后）加：
```gdscript
	# P1 暴击轴(物理流派)：门控 has_tag:physical,无物理武器不进池(防废牌 P5)
	{ "id": "perk_crit",    "name": "锐利",  "desc": "暴击率 +8%(封顶60%)", "type": "perk",    "condition": "has_tag:physical", "max_stacks": 7 },
	{ "id": "synergy_crit", "name": "致命",  "desc": "暴击伤害 +0.4",       "type": "synergy", "condition": "has_tag:physical", "max_stacks": 3 },
```
(b) `_register_perk_effects()` 末尾（`fallback_token` 行后）加：
```gdscript
	effect_registry["perk_crit"] = _apply_perk_crit
```
(c) `_register_synergy_effects()` 末尾加：
```gdscript
	effect_registry["synergy_crit"] = _apply_synergy_crit
```
(d) 质变效果回调区（`_apply_synergy_lifesteal` 后）加：
```gdscript
# P1 暴击卡(物理流派)
const CRIT_CHANCE_STEP: float = 0.08
const CRIT_CHANCE_CAP: float = 0.60
const CRIT_MULT_STEP: float = 0.40

func _apply_perk_crit(player: Player) -> void:
	player.crit_chance = minf(player.crit_chance + CRIT_CHANCE_STEP, CRIT_CHANCE_CAP)

func _apply_synergy_crit(player: Player) -> void:
	player.crit_mult += CRIT_MULT_STEP
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_card_pool.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```
git add autoloads/card_pool.gd tests/test_card_pool.gd
git commit -m "feat(cardpool): 暴击卡 perk_crit(封顶60%)/synergy_crit,暴击成可堆轴"
```

---

## Task 6: 元素增益消费点（burn_mult / freeze_dur / shock_dur）

**Files:**
- Modify: `scenes/enemies/enemy.gd`（新增纯函数 `modified_status_input`；`apply_status` 读 `_player` 后调用之）
- Modify: `scenes/player/player.gd`（加 3 字段）
- Test: `tests/test_enemy_synergy.gd`（追加）

**Interfaces:**
- Consumes: `player.burn_mult`、`player.freeze_dur_bonus`、`player.shock_dur_bonus`。
- Produces:
  - `Enemy.modified_status_input(kind, magnitude, duration, burn_mult, freeze_dur_bonus, shock_dur_bonus) -> Dictionary`（纯，键 `magnitude`/`duration`）。
  - `Player.burn_mult: float = 1.0`、`freeze_dur_bonus: float = 0.0`、`shock_dur_bonus: float = 0.0`。

> 设计：所有状态施加都过 `Enemy.apply_status`（武器调它，见 enemy.gd:115 注释）。在这单点按 kind 应用玩家元素增益 → 零武器脚本改动。`burn_mult` 默认 1.0、其余默认 0.0 → 无卡时逐字节不变(C5)。

- [ ] **Step 1: 写失败测试**（追加到 `tests/test_enemy_synergy.gd` 末尾）

```gdscript
# ── P1 单元4：元素增益消费点(状态输入修正) ─────────────────────────────────
func test_burn_mult_scales_burn_magnitude() -> void:
	var r := Enemy.modified_status_input(&"burn", 10.0, 1.0, 1.3, 0.0, 0.0)
	assert_float(r["magnitude"]).is_equal_approx(13.0, 0.0001)
	assert_float(r["duration"]).is_equal_approx(1.0, 0.0001)

func test_freeze_dur_bonus_extends_freeze() -> void:
	var r := Enemy.modified_status_input(&"freeze", 0.0, 0.6, 1.0, 0.5, 0.0)
	assert_float(r["duration"]).is_equal_approx(1.1, 0.0001)

func test_shock_dur_bonus_extends_stun() -> void:
	var r := Enemy.modified_status_input(&"stun", 0.0, 0.4, 1.0, 0.0, 0.15)
	assert_float(r["duration"]).is_equal_approx(0.55, 0.0001)

func test_slow_status_unaffected_by_element_mods() -> void:
	var r := Enemy.modified_status_input(&"slow", 0.6, 1.5, 1.3, 0.5, 0.15)
	assert_float(r["magnitude"]).is_equal_approx(0.6, 0.0001)
	assert_float(r["duration"]).is_equal_approx(1.5, 0.0001)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_enemy_synergy.gd`
Expected: FAIL —— `modified_status_input` 不存在。

- [ ] **Step 3: 实现**

(a) `scenes/enemies/enemy.gd`，整体替换 `apply_status`：
```gdscript
# 武器命中调此施加状态。在此单点应用玩家元素增益(burn_mult/freeze_dur/shock_dur)。
func apply_status(kind: StringName, magnitude: float, duration: float) -> void:
	var bm := 1.0
	var fb := 0.0
	var sb := 0.0
	if _player != null and is_instance_valid(_player):
		if "burn_mult" in _player: bm = _player.burn_mult
		if "freeze_dur_bonus" in _player: fb = _player.freeze_dur_bonus
		if "shock_dur_bonus" in _player: sb = _player.shock_dur_bonus
	var adj := modified_status_input(kind, magnitude, duration, bm, fb, sb)
	status.apply(kind, adj["magnitude"], adj["duration"])

# 纯函数(便于单测)：按 kind 应用玩家元素增益。burn→放大 dps；freeze/stun→延长时长；其余不变。
static func modified_status_input(kind: StringName, magnitude: float, duration: float, burn_mult: float, freeze_dur_bonus: float, shock_dur_bonus: float) -> Dictionary:
	var mag := magnitude
	var dur := duration
	if kind == &"burn":
		mag *= burn_mult
	elif kind == &"freeze":
		dur += freeze_dur_bonus
	elif kind == &"stun":
		dur += shock_dur_bonus
	return {"magnitude": mag, "duration": dur}
```
(b) `scenes/player/player.gd`，`slow_vuln_bonus`（Task 3 加的）后加：
```gdscript
var burn_mult: float = 1.0         # 火势卡：燃烧 dps 倍率
var freeze_dur_bonus: float = 0.0  # 冰封卡：冻结时长加成(秒)
var shock_dur_bonus: float = 0.0   # 感电卡：感电/硬直时长加成(秒)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_enemy_synergy.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```
git add scenes/enemies/enemy.gd scenes/player/player.gd tests/test_enemy_synergy.gd
git commit -m "feat(combat): apply_status 单点消费元素增益(burn/freeze/shock),零武器改动"
```

---

## Task 7: 元素/控制协同卡 `synergy_fire` / `synergy_frost` / `synergy_shock`

**Files:**
- Modify: `autoloads/card_pool.gd`（`CARDS` 加 3 卡；effect 注册 + 回调）
- Test: `tests/test_card_pool.gd`（追加 + **改 1 个现存计数用例**）

**Interfaces:**
- Consumes: `player.burn_mult` / `freeze_dur_bonus` / `shock_dur_bonus`（Task 6）、`player.slow_vuln_bonus`（Task 3）。
- Produces: 卡 `synergy_fire`（`has_tag:fire`）、`synergy_frost`（`has_tag:ice`）、`synergy_shock`（`has_tag:lightning`）。

> synergy_pierce/multishot **保留** `has_any:` 精确门控不动——改成 `has_tag:physical` 会让 owns maul/orb（物理但不读 pierce）拿到废牌(违 P5)。`has_tag:` 只服务新元素卡。

- [ ] **Step 1: 写失败测试 + 改现存计数用例**

追加到 `tests/test_card_pool.gd` 末尾：
```gdscript
# ── P1 单元4：元素/控制协同卡 ──────────────────────────────────────────────
func test_synergy_fire_increases_burn_mult() -> void:
	var before := _player.burn_mult
	CardPool.apply({"id": "synergy_fire", "type": "synergy"}, _player)
	assert_float(_player.burn_mult).is_equal_approx(before + 0.30, 0.001)

func test_synergy_frost_extends_freeze_and_vuln() -> void:
	CardPool.apply({"id": "synergy_frost", "type": "synergy"}, _player)
	assert_float(_player.freeze_dur_bonus).is_equal_approx(0.5, 0.001)
	assert_float(_player.slow_vuln_bonus).is_equal_approx(0.10, 0.001)

func test_synergy_shock_extends_shock() -> void:
	CardPool.apply({"id": "synergy_shock", "type": "synergy"}, _player)
	assert_float(_player.shock_dur_bonus).is_equal_approx(0.15, 0.001)

func test_synergy_fire_gated_by_fire_weapon() -> void:
	for c in CardPool.pick(_player, 99):
		assert_str(c["id"]).is_not_equal("synergy_fire")
	_stub_owns("explosion", 1)
	var found := false
	for c in CardPool.pick(_player, 99):
		if c["id"] == "synergy_fire":
			found = true
	assert_bool(found).is_true()
```

**改现存计数用例** `test_pick_returns_all_available_when_pool_smaller_than_count`（Task 5 已改为 11）—— 本任务再加 synergy_fire[有 explosion/whip 火]、synergy_shock[有 lightning]入池（synergy_frost 无冰武器→不入）→ 11 改 **13**：
```gdscript
func test_pick_returns_all_available_when_pool_smaller_than_count() -> void:
	# 占满 6 武器槽全满级 → 武器/升级/进化全剔除。满血 → perk_heal 剔除。
	# 剩：5 属性 + 4 现有质变 + perk_crit + synergy_crit + synergy_fire + synergy_shock = 13
	# (synergy_frost 因无冰系武器不入池)
	for id in ["knife", "orb", "explosion", "lightning", "whip", "boomerang"]:
		_stub_owns(id, 3)
	_player.hp = _player.max_hp
	var cards := CardPool.pick(_player, 99)
	assert_int(cards.size()).is_equal(13)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_card_pool.gd`
Expected: FAIL —— 3 个 apply 用例红（卡不存在）；改过的计数用例此刻仍是 11 ≠ 13 也红。

- [ ] **Step 3: 实现**（`autoloads/card_pool.gd`）

(a) `CARDS` 数组里、Task 5 加的暴击卡之后加：
```gdscript
	# P1 元素/控制协同卡：门控 has_tag:<元素>,无对应流派武器不进池(防废牌 P5)
	{ "id": "synergy_fire",  "name": "火势", "desc": "燃烧 DPS +30%",                "type": "synergy", "condition": "has_tag:fire",     "max_stacks": 3 },
	{ "id": "synergy_frost", "name": "冰封", "desc": "冻结时长 +0.5s,减速目标易伤 +10%", "type": "synergy", "condition": "has_tag:ice",      "max_stacks": 3 },
	{ "id": "synergy_shock", "name": "感电", "desc": "感电/硬直时长 +0.15s",          "type": "synergy", "condition": "has_tag:lightning", "max_stacks": 3 },
```
(b) `_register_synergy_effects()` 末尾（Task 5 的 `synergy_crit` 后）加：
```gdscript
	effect_registry["synergy_fire"] = _apply_synergy_fire
	effect_registry["synergy_frost"] = _apply_synergy_frost
	effect_registry["synergy_shock"] = _apply_synergy_shock
```
(c) 回调区（Task 5 的暴击回调后）加：
```gdscript
# P1 元素/控制协同卡
const FIRE_BURN_STEP: float = 0.30
const FROST_FREEZE_STEP: float = 0.5
const FROST_VULN_STEP: float = 0.10
const SHOCK_DUR_STEP: float = 0.15

func _apply_synergy_fire(player: Player) -> void:
	player.burn_mult += FIRE_BURN_STEP

func _apply_synergy_frost(player: Player) -> void:
	player.freeze_dur_bonus += FROST_FREEZE_STEP
	player.slow_vuln_bonus += FROST_VULN_STEP

func _apply_synergy_shock(player: Player) -> void:
	player.shock_dur_bonus += SHOCK_DUR_STEP
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_card_pool.gd`
Expected: PASS（含改过的计数用例 =13）。

- [ ] **Step 5: 提交**

```
git add autoloads/card_pool.gd tests/test_card_pool.gd
git commit -m "feat(cardpool): 元素/控制协同卡 火势/冰封/感电(按元素标签门控)"
```

---

## Task 8: 卡面元素徽标（可读性）

**Files:**
- Modify: `scenes/ui/level_up_ui.gd`（`_make_card()` 加元素标签行）
- 验证：编辑器内 game_eval 烟测（非 gdUnit；视觉层）。

**Interfaces:**
- Consumes: `WeaponDB.get_data()`、`WeaponData.tags`、`CardPool._weapon_id_of()`。
- Produces: 武器/升级/进化/暴击卡显示其元素标签（perk 等无关联武器的卡不显示）。

> 元素徽标取自卡关联武器的 tags（`CardPool._weapon_id_of(card)` 反推武器 id；synergy 卡无单一武器 → 按 condition 的 `has_tag:` 取元素）。最小实现：只给"有关联武器 id"的卡显示，synergy 元素卡按 condition 推断。

- [ ] **Step 1: 加元素徽标渲染**（`scenes/ui/level_up_ui.gd` 的 `_make_card()`，`type_lbl` 之后、`name_lbl` 之前插入）

```gdscript
	var tag_text := _card_element_text(card)
	if tag_text != "":
		var tag_lbl := Label.new()
		tag_lbl.text = tag_text
		tag_lbl.add_theme_font_size_override("font_size", 11)
		tag_lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.95))
		tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(tag_lbl)
```
并在文件末尾加 helper：
```gdscript
# 卡的元素徽标文本：武器/升级/进化卡取关联武器 tags；synergy 元素卡按 condition 的 has_tag: 取。
const _ELEMENT_LABELS := {
	&"fire": "🔥火", &"ice": "❄️冰", &"lightning": "⚡雷",
	&"physical": "🗡️物理", &"gravity": "🌀重力", &"summon": "💀召唤",
}
func _card_element_text(card: Dictionary) -> String:
	var tags: Array = []
	var wid: String = CardPool._weapon_id_of(card)
	if wid != "":
		var data := WeaponDB.get_data(wid)
		if data != null:
			tags = data.tags
	else:
		var cond := String(card.get("condition", ""))
		if cond.begins_with("has_tag:"):
			tags = [StringName(cond.substr(8))]
	var parts: Array = []
	for t in tags:
		if _ELEMENT_LABELS.has(t):
			parts.append(_ELEMENT_LABELS[t])
	return " ".join(parts)
```

- [ ] **Step 2: 编辑器内烟测**（开 Godot 编辑器 + godot-ai MCP）

跑一局，用 `editor_manage(game_eval)` 强制构造一个含火球(fire)、长弓(physical)、synergy_fire 的 draft（参照 4.7 验证手法），截图确认：武器卡显示"🔥火"/"🗡️物理"、synergy_fire 显示"🔥火"、perk 卡无徽标且布局不乱。

- [ ] **Step 3: 提交**

```
git add scenes/ui/level_up_ui.gd
git commit -m "feat(ui): 卡面元素徽标(火/冰/雷/物理/重力/召唤),流派可感知"
```

---

## 最终验证

- [ ] **Step 1: 关编辑器 → 全量套件绿 + 核对用例数**

Run:
```
& "C:\Dev\GAME\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: 全绿，用例总数 = `N_base` + **30**：
- Task1 test_weapon_tags：1
- Task2 has_tag：3
- Task3 slow 易伤：8
- Task4 crit_axis：6
- Task5 暴击卡：4
- Task6 元素消费点：4
- Task7 元素卡：4（`test_pick_returns_all_available…` 是改动非新增，不计）
- 合计 30 … 复核：1+3+8+6+4+4+4 = **30**。期望总数 = `N_base` + 30。
**若总数不升反降 → 某套件解析错误被静默截断，单独跑各新文件定位先修（C6）。**

- [ ] **Step 2: bot 遥测确定性回归（C5）**

跑两次同种子 bot（`--fixed-fps 60`），比对聚合行逐字节一致。新增 modifier 默认中性值、无新 RNG 节拍 → 理论不破复现；此步兜底确认。
> 注：4.7 数值 A/B 基线**正式重采留 Phase 2**（本步只验"仍确定"，不比数值）。

- [ ] **Step 3: 人工/编辑器烟测（推荐）**

开一局验证：① 武器卡显示元素徽标；② 拿火系武器后 synergy_fire 入池、拿物理武器后 perk_crit/synergy_crit 入池、无对应流派武器时这些卡不出现；③ 对减速敌人伤害肉眼更高（易伤）。

---

## Spec 覆盖自检（计划作者已核）

| spec 单元 | 对应任务 | 覆盖 |
|---|---|---|
| U1 元素标签体系 | Task 1（字段+22.tres）+ Task 2（has_tag DSL） | ✅ |
| U2 slow payoff（易伤桶） | Task 3 | ✅ C2 转全绿（effective_slow_vuln 基线锁定） |
| U3 暴击轴 | Task 4（物理自动暴击）+ Task 5（crit 卡） | ✅ 长弓矛盾经 `chance+crit_bonus` 叠加修正（test_crit_axis 锁） |
| U4 元素/控制协同卡 | Task 6（消费点）+ Task 7（3 卡） | ✅ |
| U5 卡面徽标 | Task 8 | ✅ |
| C1 桶纪律（易伤加法并桶） | Task 3 | ✅ test_amp_and_slow_vuln_add_in_same_bucket |
| C2 slow 不再孤儿 | Task 3 | ✅ |
| C6 TDD + 截断核对 | 各任务 + 最终验证 | ✅ |

**与 spec 的 plan 级精炼（已在正文标注理由）：**
1. **U2/U4 接线**：modifier 在 `Enemy.apply_status`/`take_damage` 单点读 `_player` 消费，**非逐武器传参**（spec U2 原写"经 take_damage 传入"）。更省、零武器改动、基线对所有通道统一；纯函数 `synergy_multiplier`/`effective_slow_vuln`/`modified_status_input` 契约不变、仍可单测。
2. **synergy_pierce/multishot 不 re-gate**（spec §6 写改 has_tag:physical）：改了会对 owns maul/orb 塞废牌(违 P5)，保留 has_any 精确门控更对。`has_tag:` 仅服务新元素卡。
3. **不引入 projectile 标签**：因不再 re-gate pierce，YAGNI。

---

## 执行方式（选一）

**1. Subagent-Driven（推荐）** —— 每任务派新 subagent，任务间复审，迭代快。需 `superpowers:subagent-driven-development`。

**2. Inline Execution** —— 本会话内批量执行，带检查点。需 `superpowers:executing-plans`。

> ⚠ 执行任何含 headless 测试的任务前**先关 Godot 编辑器**（双实例撞 LimboAI DLL）。Task 8 烟测需要编辑器开着，安排在最后。
