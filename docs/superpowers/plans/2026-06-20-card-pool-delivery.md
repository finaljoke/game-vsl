# 卡池投放层（Phase 0）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: 用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现本计划。步骤用 `- [ ]` 复选框跟踪。

**Goal:** 不加任何新武器/协同，只修卡池"投放管道"，让已实装的状态协同深度可靠到达玩家——进化就绪即确定性投放、去除 perk_heal 废牌、加 Skip、每轮 1 次免费 reroll。

**Architecture:** 改动集中在两个文件：[autoloads/card_pool.gd](../../../autoloads/card_pool.gd)（进化可达性、perk_heal 门控、空池兜底）与 [scenes/ui/level_up_ui.gd](../../../scenes/ui/level_up_ui.gd)（Skip、免费 reroll；页脚为代码内建，**不动 .tscn**）。全程 TDD，扩 [tests/test_card_pool.gd](../../../tests/test_card_pool.gd) 并新建 [tests/test_level_up_ui.gd](../../../tests/test_level_up_ui.gd)。每任务独立提交、独立绿测。

**Tech Stack:** Godot 4.6.3 / GDScript / gdUnit4（headless）。

**上位 spec:** [docs/superpowers/specs/2026-06-20-combat-system-foundation-design.md](../specs/2026-06-20-combat-system-foundation-design.md) §4（本计划实现其 Phase 0 的 4 个单元）。

## Global Constraints

- **测试命令**（单套件，PowerShell）：
  ```
  & "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_pool.gd
  ```
  把末尾 `-a res://tests/test_card_pool.gd` 换成 `-a res://tests/test_level_up_ui.gd` 跑 UI 套件，换成 `-a res://tests` 跑全量。
- **`--ignoreHeadlessMode` 必加**，否则 gdUnit abort 退出码 103。
- **gdUnit 截断陷阱**：某测试解析/脚本错误会**静默截断**其后测试的发现。每次跑完**核对发现用例数**（基线全量 ≈397），不能只看"全绿"。新增测试若让总数不升反降 → 有解析错误，先修。
- **确定性契约（C5）**：`pick()` 是 bot 遥测路径的唯一选卡入口；进化投放必须**确定性**（按就绪武器 id 字典序），不得引入 `randf`/时间依赖，否则破坏种子复现。Skip/免费 reroll 仅人类 UI 路径（bot 早退）。
- **注释/文案一律简体中文**（全仓库约定）。
- **不改 .tscn**：选卡页脚按钮全部代码内建。
- **提交规范**：conventional commits（`feat(cardpool)`/`test(cardpool)`/`feat(ui)` 等）；agent 执行时按本仓库规范追加 `Co-Authored-By` trailer。**只 `git add` 本任务明确列出的文件，禁止 `git add -A`**（仓库有大量预存未追踪文件，收录是用户决策）。

---

## Task 0: 建分支

当前在默认分支 `master`，先开特性分支。

- [ ] **Step 1: 建并切到特性分支**

```
git checkout -b feat/card-pool-delivery
```

- [ ] **Step 2: 跑一遍全量基线，记录用例总数**

Run:
```
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: 全绿；**记下用例总数**（后续每加一批测试，总数应**只增不减**）。

---

## Task 1: `ready_evolutions()` — 就绪进化扫描（确定性排序）

**Files:**
- Modify: `autoloads/card_pool.gd`（新增 `ready_evolutions()`，紧邻 `pick()` 上方）
- Test: `tests/test_card_pool.gd`（文件末尾追加）

**Interfaces:**
- Consumes: 现有 `_check_condition()`、`_weapon_id_of()`、`_banished`、`_runtime_cards`。
- Produces: `CardPool.ready_evolutions(player: Player) -> Array[Dictionary]` —— 返回所有就绪进化卡（武器满级 + perk 达阈、未被 banish），按源武器 id 字典序。

- [ ] **Step 1: 写失败测试**（追加到 `tests/test_card_pool.gd` 末尾）

```gdscript
# ── Phase0 单元1：进化就绪扫描 ─────────────────────────────────────────────
func test_ready_evolutions_empty_when_none_ready() -> void:
	assert_int(CardPool.ready_evolutions(_player).size()).is_equal(0)

func test_ready_evolutions_returns_single_ready() -> void:
	_stub_owns("orb", 3)
	_player.perk_stacks["perk_hp"] = 3
	var ready := CardPool.ready_evolutions(_player)
	assert_int(ready.size()).is_equal(1)
	assert_str(ready[0]["id"]).is_equal("evolve_orb")

func test_ready_evolutions_sorted_by_weapon_id() -> void:
	# explosion(perk_damage) 与 orb(perk_hp) 同时就绪 → 字典序 explosion < orb
	_stub_owns("explosion", 3)
	_player.perk_stacks["perk_damage"] = 3
	_stub_owns("orb", 3)
	_player.perk_stacks["perk_hp"] = 3
	var ready := CardPool.ready_evolutions(_player)
	assert_int(ready.size()).is_equal(2)
	assert_str(ready[0]["id"]).is_equal("evolve_explosion")
	assert_str(ready[1]["id"]).is_equal("evolve_orb")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_card_pool.gd`
Expected: FAIL —— 3 个新用例红，报 `Invalid call. Nonexistent function 'ready_evolutions'`。

- [ ] **Step 3: 实现**（在 `card_pool.gd` 的 `func pick(` 定义**上方**插入）

```gdscript
# 返回当前所有「就绪」进化卡(武器满级+perk达阈且未被 banish)，按源武器 id 字典序。
# 确定性排序：便于契约测试与 bot 复现(C5)。
func ready_evolutions(player: Player) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for card in _runtime_cards:
		if card.get("type", "") != "evolution":
			continue
		if _banished.has(card["id"]):
			continue
		if _check_condition(card["condition"], player):
			out.append(card)
	out.sort_custom(func(a, b): return _weapon_id_of(a) < _weapon_id_of(b))
	return out
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_card_pool.gd`
Expected: PASS —— 全绿，且总用例数 = 原 + 3。

- [ ] **Step 5: 提交**

```
git add autoloads/card_pool.gd tests/test_card_pool.gd
git commit -m "feat(cardpool): 新增 ready_evolutions 就绪进化扫描(确定性排序)"
```

---

## Task 2: `pick()` 确定性投放就绪进化

**Files:**
- Modify: `autoloads/card_pool.gd`（重写 `pick()`）
- Test: `tests/test_card_pool.gd`

**Interfaces:**
- Consumes: `ready_evolutions()`（Task 1）。
- Produces: `pick()` 行为变更——存在就绪进化时，结果**确定性含且仅含 1 张**进化卡（字典序第一），其余槽位走原加权抽样；无就绪进化时结果不含任何进化卡。

- [ ] **Step 1: 写失败测试**（追加末尾）

```gdscript
# ── Phase0 单元1：就绪进化确定性投放 ───────────────────────────────────────
func test_pick_offers_ready_evolution() -> void:
	_stub_owns("orb", 3)
	_player.perk_stacks["perk_hp"] = 3
	var cards := CardPool.pick(_player, 3)
	var found := false
	for c in cards:
		if c["id"] == "evolve_orb":
			found = true
	assert_bool(found).is_true()

func test_pick_no_evolution_when_none_ready() -> void:
	var cards := CardPool.pick(_player, 3)
	for c in cards:
		assert_str(c.get("type", "")).is_not_equal("evolution")

func test_pick_offers_exactly_one_evolution_when_multiple_ready() -> void:
	_stub_owns("explosion", 3)
	_player.perk_stacks["perk_damage"] = 3
	_stub_owns("orb", 3)
	_player.perk_stacks["perk_hp"] = 3
	var cards := CardPool.pick(_player, 3)
	var evo_count := 0
	var evo_id := ""
	for c in cards:
		if c.get("type", "") == "evolution":
			evo_count += 1
			evo_id = c["id"]
	assert_int(evo_count).is_equal(1)
	assert_str(evo_id).is_equal("evolve_explosion")  # 字典序第一
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_card_pool.gd`
Expected: FAIL —— `test_pick_offers_ready_evolution` 与 `test_pick_offers_exactly_one_evolution_when_multiple_ready` 红（当前 legendary 权重 6，随机基本抽不到；且可能两张都漏）。

- [ ] **Step 3: 实现**（用下方整体替换现有 `pick()`）

```gdscript
func pick(player: Player, count: int = 3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Phase0 单元1：就绪进化「确定性投放」——已解锁内容不靠抽奖(P2/C4)。
	# 取就绪集字典序第一个占 1 槽；其余就绪进化本轮不进随机池(每轮只投放 1 个，保留决策密度 P5)。
	var ready := ready_evolutions(player)
	var ready_ids: Dictionary = {}
	for ev in ready:
		ready_ids[ev["id"]] = true
	if not ready.is_empty():
		result.append(ready[0])
	# 构建随机池：排除所有就绪进化 id(已确定性处理)
	var available: Array[Dictionary] = []
	var slots_full: bool = player.owned_weapons.size() >= player.MAX_WEAPON_SLOTS
	for card in _runtime_cards:
		if ready_ids.has(card["id"]):
			continue
		if _banished.has(card["id"]):
			continue
		if not _check_condition(card["condition"], player):
			continue
		if slots_full and card.get("type", "") == "weapon":
			continue
		if card.has("max_stacks"):
			if player.perk_stacks.get(card["id"], 0) >= card["max_stacks"]:
				continue
		available.append(card)
	# 加权无放回抽样填满剩余槽位
	while result.size() < count and not available.is_empty():
		var total := 0
		for c in available:
			total += rarity_weight(c)
		var r := randi() % total
		var acc := 0
		var chosen := 0
		for i in range(available.size()):
			acc += rarity_weight(available[i])
			if r < acc:
				chosen = i
				break
		result.append(available[chosen])
		available.remove_at(chosen)
	return result
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_card_pool.gd`
Expected: PASS —— 含 Task 1 在内全绿。注意现存的 `test_pick_returns_all_available_when_pool_smaller_than_count`（断言满 6 槽满级时恰 10 张）应仍绿：那些武器未达 perk 阈值，无就绪进化，行为不变。

- [ ] **Step 5: 提交**

```
git add autoloads/card_pool.gd tests/test_card_pool.gd
git commit -m "feat(cardpool): 就绪进化确定性占 1 槽,消灭 2.4% 抽奖(对齐 VS 本体)"
```

---

## Task 3: 进化卡描述透明化

**Files:**
- Modify: `autoloads/card_pool.gd`（改 `_register_evolution_cards()`；新增 `_perk_display_name()`）
- Test: `tests/test_card_pool.gd`

**Interfaces:**
- Consumes: `WeaponDB.all_evolvable()`、`WeaponData.evolution`、`_perk_max_stacks()`、`CARDS`。
- Produces: 进化卡 `desc` 形如 `"需 缚灵 满级 + 生命上限 ×3"`；新增 `_perk_display_name(perk_id) -> String`。

- [ ] **Step 1: 写失败测试**（追加末尾）

```gdscript
# ── Phase0 单元1：进化卡门控透明化 ─────────────────────────────────────────
func test_evolution_desc_states_requirement() -> void:
	var desc := ""
	for card in CardPool._runtime_cards:
		if card["id"] == "evolve_orb":
			desc = String(card["desc"])
	assert_str(desc).contains("生命上限")  # perk_hp 中文名
	assert_str(desc).contains("3")          # 阈值
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_card_pool.gd`
Expected: FAIL —— 现 desc 是"解锁 缚灵 的终极形态"，不含"生命上限"。

- [ ] **Step 3: 实现**

把 `_register_evolution_cards()` 整体替换为：

```gdscript
# 从 WeaponDB 扫描带 evolution.evolved_id 的武器，自动注入进化卡。
# 进化 evolved 形态 .tres 可缺失（占位通路）；_evolve_weapon 会回退用 source 数据。
func _register_evolution_cards() -> void:
	for d in WeaponDB.all_evolvable():
		var data: WeaponData = d
		var weapon_id: String = data.id
		var evo_id: String = "evolve_" + weapon_id
		var perk_id := String(data.evolution.get("requires_perk", ""))
		var threshold := int(data.evolution.get("requires_perk_stacks", _perk_max_stacks(perk_id)))
		# 透明化门控：写明"需 X 满级 + Y perk ×N"，而非泛泛的"解锁终极形态"(P2/C4)。
		var desc := "需 %s 满级 + %s ×%d" % [data.display_name, _perk_display_name(perk_id), threshold]
		var card: Dictionary = {
			"id": evo_id,
			"name": "%s 进化" % data.display_name,
			"desc": desc,
			"type": "evolution",
			"condition": "evolve_ready:" + weapon_id,
		}
		_runtime_cards.append(card)
		effect_registry[evo_id] = _evolve_weapon.bind(weapon_id)

# perk id → 中文显示名(取自 CARDS 定义，DRY)。
func _perk_display_name(perk_id: String) -> String:
	for c in CARDS:
		if c["id"] == perk_id:
			return String(c["name"])
	return perk_id
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_card_pool.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```
git add autoloads/card_pool.gd tests/test_card_pool.gd
git commit -m "feat(cardpool): 进化卡描述写明门控(武器满级+具名perk×N)"
```

---

## Task 4: perk_heal 去陷阱（`hp_below:` 条件门控）

**Files:**
- Modify: `autoloads/card_pool.gd`（`_check_condition()` 加分支；`CARDS` 里 `perk_heal` 的 `condition`）
- Test: `tests/test_card_pool.gd`（加 2 个新用例；**改 1 个现存用例**）

**Interfaces:**
- Consumes: `player.hp`、`player.max_hp`。
- Produces: 条件 DSL 新增 `hp_below:<frac>`；`perk_heal` 仅在 `hp < max_hp × 0.9` 时进池。

- [ ] **Step 1: 写失败测试 + 改现存测试**

追加末尾：
```gdscript
# ── Phase0 单元2：perk_heal 去陷阱 ─────────────────────────────────────────
func test_perk_heal_excluded_at_full_hp() -> void:
	_player.hp = _player.max_hp
	var cards := CardPool.pick(_player, 99)
	for c in cards:
		assert_str(c["id"]).is_not_equal("perk_heal")

func test_perk_heal_offered_when_wounded() -> void:
	_player.hp = _player.max_hp * 0.5
	var cards := CardPool.pick(_player, 99)
	var found := false
	for c in cards:
		if c["id"] == "perk_heal":
			found = true
	assert_bool(found).is_true()
```

**⚠ 必须同时改 3 个现存用例**（gate perk_heal 后它们会变红——前 2 个数池子大小/列表时把 perk_heal 算进去了，第 3 个正是用 perk_heal 当兜底）。`test_apply_perk_heal_restores_hp` / `..._does_not_overheal`（直接 `apply` 测效果、绕过 `pick`）**不受影响、不要动**。

**改 1** `test_pick_always_includes_perks`（约 L66）—— `perk_ids` 去掉 `"perk_heal"`：
```gdscript
	# 新(perk_heal 改为受伤条件卡，不再恒在池中):
	var perk_ids := ["perk_speed", "perk_hp", "perk_attack", "perk_xp", "perk_damage"]
```

**改 2** `test_pick_returns_all_available_when_pool_smaller_than_count`（约 L43）—— 满血显式化，数量 10→9：
```gdscript
func test_pick_returns_all_available_when_pool_smaller_than_count() -> void:
	# 占满 6 武器槽全满级 → 武器(槽满)/升级(满级)/进化(未达阈)全剔除。
	# 满血 → perk_heal(hp_below 门控)也剔除。剩：5 属性牌 + 4 质变卡 = 9
	for id in ["knife", "orb", "explosion", "lightning", "whip", "boomerang"]:
		_stub_owns(id, 3)
	_player.hp = _player.max_hp  # 确定满血 → perk_heal 不进池
	var cards := CardPool.pick(_player, 99)
	assert_int(cards.size()).is_equal(9)
```

**改 3** `test_pick_still_has_cards_when_all_capped`（约 L91）—— 删掉 `has_heal` 断言块（perk_heal 不再是兜底；非空现由就绪进化/质变卡保证，`size>=1` 已覆盖该不变量 C3）：
```gdscript
func test_pick_still_has_cards_when_all_capped() -> void:
	# 所有有上限 perk 全满 + 武器满级 → 池仍非空(现由就绪进化/质变卡保证，不再靠 perk_heal)。
	_stub_owns("knife", 3)
	_stub_owns("orb", 3)
	_stub_owns("explosion", 3)
	_player.perk_stacks["perk_speed"] = 8
	_player.perk_stacks["perk_hp"] = 10
	_player.perk_stacks["perk_attack"] = 8
	_player.perk_stacks["perk_xp"] = 6
	_player.perk_stacks["perk_damage"] = 8
	var cards := CardPool.pick(_player, 99)
	assert_int(cards.size()).is_greater_equal(1)
	# (原 has_heal 断言已删：perk_heal 满血不再进池)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_card_pool.gd`
Expected: FAIL —— `test_perk_heal_excluded_at_full_hp` 红（现 perk_heal 无条件，满血也出）。

- [ ] **Step 3: 实现**

(a) `_check_condition()` 里、`if condition.begins_with("has:")` 分支**之前**插入：
```gdscript
	if condition.begins_with("hp_below:"):
		var frac := float(condition.substr(9))
		return player.hp < player.max_hp * frac
```
(b) `CARDS` 里把 `perk_heal` 那行的 `condition` 从 `""` 改为 `"hp_below:0.9"`：
```gdscript
	{ "id": "perk_heal",   "name": "紧急治疗",  "desc": "立刻回复 30 HP",        "type": "perk",    "condition": "hp_below:0.9" },
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_card_pool.gd`
Expected: PASS —— 2 个新用例绿；3 个改过的现存用例（`test_pick_always_includes_perks` / `test_pick_returns_all_available_when_pool_smaller_than_count` / `test_pick_still_has_cards_when_all_capped`）也绿。

- [ ] **Step 5: 提交**

```
git add autoloads/card_pool.gd tests/test_card_pool.gd
git commit -m "feat(cardpool): perk_heal 改受伤条件卡(hp_below:0.9),去满血废牌陷阱"
```

---

## Task 5: 空池兜底卡（防软锁）

**Files:**
- Modify: `autoloads/card_pool.gd`（`FALLBACK_CARD` 常量、`_fallback_card()`、`_apply_fallback_token()`、`_register_perk_effects()` 注册、`pick()` 末尾注入）
- Test: `tests/test_card_pool.gd`

**Interfaces:**
- Consumes: `player.reroll_tokens`。
- Produces: `_fallback_card() -> Dictionary`；`pick()` 在结果为空时注入兜底卡 `fallback_token`，应用后 `reroll_tokens += 1`。

> 背景：Task 4 给 perk_heal 加了条件后，满血 + 全部其它卡耗尽/封顶的极端态可能让 `pick()` 返回空 → 暂停无法 resume（C3"空池永不软锁"）。用"+1 重抽券"兜底：永不浪费，故不构成废牌/稀释。

- [ ] **Step 1: 写失败测试**（追加末尾）

```gdscript
# ── Phase0 单元2：空池兜底 ─────────────────────────────────────────────────
func test_fallback_card_grants_reroll_token() -> void:
	var before := _player.reroll_tokens
	CardPool.apply(CardPool._fallback_card(), _player)
	assert_int(_player.reroll_tokens).is_equal(before + 1)

func test_pick_never_empty_via_fallback() -> void:
	CardPool.reset_run()
	# 把所有运行时卡 banish 掉 → 随机池与就绪进化全清空 → 触发兜底
	for card in CardPool._runtime_cards:
		CardPool.banish(String(card["id"]))
	_player.hp = _player.max_hp
	var cards := CardPool.pick(_player, 3)
	assert_int(cards.size()).is_equal(1)
	assert_str(cards[0]["id"]).is_equal("fallback_token")
	CardPool.reset_run()  # 清理：别污染其它用例
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_card_pool.gd`
Expected: FAIL —— `_fallback_card` 不存在；空池时 `pick()` 返回 0 张。

- [ ] **Step 3: 实现**

(a) 在 `RARITY_WEIGHTS` 常量附近加：
```gdscript
# 空池兜底卡：仅当其余池为空时由 pick() 注入，保证永不返回空(防暂停无法 resume，C3)。
# 用「+1 重抽券」——永不浪费(可存)，故不构成废牌/稀释(P5)。
const FALLBACK_CARD := { "id": "fallback_token", "name": "重抽券", "desc": "+1 重抽券", "type": "perk" }

func _fallback_card() -> Dictionary:
	return FALLBACK_CARD.duplicate(true)
```
(b) `_register_perk_effects()` 末尾加注册：
```gdscript
	effect_registry["fallback_token"] = _apply_fallback_token
```
(c) 在 `_apply_perk_heal()` 附近加效果回调：
```gdscript
func _apply_fallback_token(player: Player) -> void:
	player.reroll_tokens += 1
```
(d) `pick()` 的 `return result` **之前**插入：
```gdscript
	# 空池兜底：极端态下随机池与就绪进化均空 → 注入兜底券，防软锁(C3)。
	if result.is_empty():
		result.append(_fallback_card())
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_card_pool.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```
git add autoloads/card_pool.gd tests/test_card_pool.gd
git commit -m "feat(cardpool): 空池注入+1券兜底,防 perk_heal 门控后软锁"
```

---

## Task 6: Skip —— 放弃整轮换 +1 券

**Files:**
- Modify: `scenes/ui/level_up_ui.gd`（`_skip_btn` 变量、`_build_footer()` 加按钮、`skip_reward()`、`_on_skip()`）
- Test: `tests/test_level_up_ui.gd`（**新建**）

**Interfaces:**
- Consumes: `player.reroll_tokens`、`_gm.resume_game()`。
- Produces: `level_up_ui.skip_reward(player: Player) -> void`（`reroll_tokens += 1`）；Skip 按钮 → `_on_skip()` → 给券 + resume。

- [ ] **Step 1: 写失败测试**（新建 `tests/test_level_up_ui.gd`）

```gdscript
# tests/test_level_up_ui.gd
extends GdUnitTestSuite

const LevelUpUiScript := preload("res://scenes/ui/level_up_ui.gd")

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

# 仅实例化脚本、不加入场景树 → _ready 不触发(避开 GameManager 自动加载与 @onready 节点依赖)。
# 被测方法只读写 player，无需场景。
func _make_ui() -> Object:
	return auto_free(LevelUpUiScript.new())

func test_skip_reward_grants_one_token() -> void:
	var ui := _make_ui()
	var before: int = _player.reroll_tokens
	ui.skip_reward(_player)
	assert_int(_player.reroll_tokens).is_equal(before + 1)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_level_up_ui.gd`
Expected: FAIL —— `Invalid call. Nonexistent function 'skip_reward'`。

- [ ] **Step 3: 实现**（改 `scenes/ui/level_up_ui.gd`）

(a) 变量区（`_token_label` 旁）加：
```gdscript
var _skip_btn: Button = null
```
(b) `_build_footer()` 末尾（`hint` 之前或之后）加 Skip 按钮：
```gdscript
	_skip_btn = Button.new()
	_skip_btn.text = "跳过 (+1 券)"
	_skip_btn.pressed.connect(_on_skip)
	_footer.add_child(_skip_btn)
```
(c) 加方法（放在 `_on_reroll` 附近）：
```gdscript
# Skip：放弃整轮三选一，换小额回报(+1 重抽券，永不浪费)。
# 回报 < 一张普通卡期望，故是"这轮没好牌"的逃生口，而非常态最优(spec 单元3)。
func skip_reward(player: Player) -> void:
	player.reroll_tokens += 1

func _on_skip() -> void:
	if _player == null:
		return
	skip_reward(_player)
	visible = false
	_gm.resume_game()
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_level_up_ui.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```
git add scenes/ui/level_up_ui.gd tests/test_level_up_ui.gd
git commit -m "feat(ui): 选卡加 Skip(放弃整轮换+1券),不再被迫选废牌"
```

---

## Task 7: 每轮 1 次免费 reroll

**Files:**
- Modify: `scenes/ui/level_up_ui.gd`（`_free_rerolls_left` 变量、`consume_reroll()`、改 `_on_reroll()`/`_on_level_up()`/`_update_footer()`）
- Test: `tests/test_level_up_ui.gd`

**Interfaces:**
- Consumes: `player.reroll_tokens`。
- Produces: `level_up_ui.consume_reroll() -> bool`（先耗免费次数、再耗券；都没则 false）；每次 `_on_level_up` 重置 `_free_rerolls_left = 1`。

- [ ] **Step 1: 写失败测试**（追加到 `tests/test_level_up_ui.gd`）

```gdscript
func test_consume_reroll_uses_free_first() -> void:
	var ui := _make_ui()
	ui._player = _player
	ui._free_rerolls_left = 1
	_player.reroll_tokens = 0
	assert_bool(ui.consume_reroll()).is_true()    # 用免费
	assert_int(_player.reroll_tokens).is_equal(0)  # 未扣券
	assert_bool(ui.consume_reroll()).is_false()    # 免费用尽且无券

func test_consume_reroll_spends_token_after_free() -> void:
	var ui := _make_ui()
	ui._player = _player
	ui._free_rerolls_left = 0
	_player.reroll_tokens = 2
	assert_bool(ui.consume_reroll()).is_true()
	assert_int(_player.reroll_tokens).is_equal(1)  # 扣 1 券
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -a res://tests/test_level_up_ui.gd`
Expected: FAIL —— `Nonexistent function 'consume_reroll'`。

- [ ] **Step 3: 实现**（改 `scenes/ui/level_up_ui.gd`）

(a) 变量区加：
```gdscript
const FREE_REROLLS_PER_DRAFT := 1
var _free_rerolls_left: int = 0
```
(b) `_on_level_up()` 里、`_update_footer()` 调用**之前**加：
```gdscript
	_free_rerolls_left = FREE_REROLLS_PER_DRAFT
```
(c) 加 `consume_reroll()`：
```gdscript
# 重抽计费：每轮 1 次免费(社区共识:免费首抽是控池地基)，用尽后耗券。返回是否允许本次重抽。
func consume_reroll() -> bool:
	if _free_rerolls_left > 0:
		_free_rerolls_left -= 1
		return true
	if _player != null and _player.reroll_tokens > 0:
		_player.reroll_tokens -= 1
		return true
	return false
```
(d) 把 `_on_reroll()` 整体替换为：
```gdscript
func _on_reroll() -> void:
	if _player == null:
		return
	if not consume_reroll():
		return
	_current_cards = CardPool.pick(_player)
	_build_cards(_current_cards)
	_update_footer()
```
(e) 把 `_update_footer()` 整体替换为（反映免费次数 + 正确启用按钮）：
```gdscript
func _update_footer() -> void:
	if _player == null:
		return
	var tokens: int = _player.reroll_tokens
	if _free_rerolls_left > 0:
		_token_label.text = "重抽券 ×%d (免费 ×%d)" % [tokens, _free_rerolls_left]
	else:
		_token_label.text = "重抽券 ×%d" % tokens
	_reroll_btn.disabled = _free_rerolls_left <= 0 and tokens <= 0
```

- [ ] **Step 4: 跑测试确认通过**

Run: `… -a res://tests/test_level_up_ui.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```
git add scenes/ui/level_up_ui.gd tests/test_level_up_ui.gd
git commit -m "feat(ui): 每轮 1 次免费 reroll,让控池工具用得起"
```

---

## 最终验证

- [ ] **Step 1: 全量套件绿 + 核对用例数**

Run:
```
& "C:\Dev\GAME\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "D:\Workspace\GAME\game_0_vsl" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```
Expected: 全绿，且用例总数 = Task 0 基线 + **14**（Task1:3 + Task2:3 + Task3:1 + Task4:2 + Task5:2 + Task6:1 + Task7:2；`test_pick_always_includes_perks` 是改动非新增）。**若总数不升反降 → 有套件解析错误被静默截断，先修再继续。**

- [ ] **Step 2: bot 遥测确定性回归（C5）**

跑一遍 bot A/B 基线（同 W4 流程，`--fixed-fps 60`），确认确定性投放未漂移种子复现。若项目有现成 RunHarness 基线脚本则复用；无则手动跑两次同种子，比对聚合行一致。
> 进化投放是确定性的（字典序），理论上不破复现；此步是兜底确认。

- [ ] **Step 3: 人工烟雾（可选但推荐）**

编辑器内开一局，验证：① 武器满级 + 对应 perk ×3 后，选卡界面**必然**出现高亮进化卡且描述写明门控；② 满血时不再出现"紧急治疗"；③ Skip 按钮可用、点击 +1 券并继续；④ 每轮首次 reroll 不扣券。

---

## Spec 覆盖自检（计划作者已核）

| spec §4 单元 | 对应任务 | 覆盖 |
|---|---|---|
| 单元1 进化可达性（确定性投放 + 透明化） | Task 1+2+3 | ✅ |
| 单元1 视觉锚（✦就绪高亮） | 无需新代码 | ✅ 进化现仅就绪时出现，既有 `legendary` 边框 + "✦ 进化" 标签 + 1.12 放大即是就绪信号 |
| 单元2 perk_heal 去陷阱 | Task 4 | ✅ |
| 单元2 空池兜底重构 | Task 5 | ✅ |
| 单元3 Skip | Task 6 | ✅ |
| 单元4 免费 reroll | Task 7 | ✅ |
| 单元4 券收入提频（spawner 调参） | **有意延后** | spec 标"留作 Phase 0 末数据决策"；免费 reroll 已让工具可用，先不动 spawner（YAGNI），实测仍紧再调 |
| 退出判据 5 项 | 最终验证 | ✅ |

---

## 执行方式（下个会话选一）

**1. Subagent-Driven（推荐）** —— 每任务派新 subagent，任务间复审，迭代快。需 `superpowers:subagent-driven-development`。

**2. Inline Execution** —— 本会话内批量执行，带检查点。需 `superpowers:executing-plans`。
