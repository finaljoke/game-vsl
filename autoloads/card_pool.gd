# autoloads/card_pool.gd
# 卡池 + 效果注册表。
#
# CARDS 是静态基础卡定义；进化卡在 _ready() 期间从 WeaponDB.all_evolvable() 动态注入到 _runtime_cards。
# 每张卡的副作用通过 effect_registry: { id -> Callable(player) } 派发，
# 加新卡型只需注册一个 Callable（典型场景：新武器只动 .tres，CardPool 零改动）。
extends Node

signal weapon_leveled(id: String, new_level: int)
signal weapon_evolved(old_id: String, new_id: String)

const CARDS: Array[Dictionary] = [
	{ "id": "knife",       "name": "飞刀",      "desc": "朝最近敌人射出飞刀",    "type": "weapon",  "condition": "no:knife"      },
	{ "id": "orb",         "name": "护盾球",    "desc": "绕身旋转的能量球",      "type": "weapon",  "condition": "no:orb"        },
	{ "id": "explosion",   "name": "爆炸",      "desc": "随机位置触发范围爆炸",  "type": "weapon",  "condition": "no:explosion"  },
	{ "id": "knife_2",     "name": "飞刀 Lv.2",    "desc": "冷却 1.0s → 0.5s",         "type": "upgrade", "condition": "upgrade:knife:1"     },
	{ "id": "orb_2",       "name": "护盾球 Lv.2",  "desc": "护盾球数量 2 → 3",          "type": "upgrade", "condition": "upgrade:orb:1"       },
	{ "id": "explosion_2", "name": "爆炸 Lv.2",    "desc": "冷却 3.0s → 1.5s",         "type": "upgrade", "condition": "upgrade:explosion:1" },
	{ "id": "knife_3",     "name": "飞刀 Lv.3",    "desc": "冷却 0.5s → 0.3s，穿透 +2",  "type": "upgrade", "condition": "upgrade:knife:2"     },
	{ "id": "orb_3",       "name": "护盾球 Lv.3",  "desc": "护盾球数量 3 → 4",          "type": "upgrade", "condition": "upgrade:orb:2"       },
	{ "id": "explosion_3", "name": "爆炸 Lv.3",    "desc": "冷却 1.5s → 1.0s",         "type": "upgrade", "condition": "upgrade:explosion:2" },
	{ "id": "perk_speed",  "name": "移速提升",  "desc": "移动速度永久 +15%",     "type": "perk",    "condition": "", "max_stacks": 8 },
	{ "id": "perk_hp",     "name": "生命上限",  "desc": "最大 HP +20，当场补满", "type": "perk",    "condition": "", "max_stacks": 10 },
	{ "id": "perk_attack", "name": "攻速提升",  "desc": "攻击速度永久 +15%",     "type": "perk",    "condition": "", "max_stacks": 8 },
	{ "id": "perk_xp",     "name": "XP 加成",   "desc": "XP 获取量永久 +25%",    "type": "perk",    "condition": "", "max_stacks": 6 },
	{ "id": "perk_damage", "name": "攻击强化",  "desc": "武器伤害永久 +15%",     "type": "perk",    "condition": "", "max_stacks": 8 },
	# 无上限兜底卡：保证卡池不为空，防止空池导致暂停无法 resume
	{ "id": "perk_heal",   "name": "紧急治疗",  "desc": "立刻回复 30 HP",        "type": "perk",    "condition": "" },
]

# 静态 CARDS + 运行时注入的进化卡。pick() 只读它。
var _runtime_cards: Array[Dictionary] = []
# id → Callable(player)。每个 Callable 已绑定该卡所需参数。
var effect_registry: Dictionary = {}

func _ready() -> void:
	_runtime_cards = CARDS.duplicate()
	_register_weapon_effects()
	_register_perk_effects()
	_register_evolution_cards()

# 静态武器与升级卡（依赖 WeaponDB 提供数据，但 CARDS 数组里的 id/condition 是手写的）
func _register_weapon_effects() -> void:
	for id in ["knife", "orb", "explosion"]:
		effect_registry[id] = _grant_weapon.bind(id)
		effect_registry["%s_2" % id] = _level_up_weapon.bind(id)
		effect_registry["%s_3" % id] = _level_up_weapon.bind(id)

func _register_perk_effects() -> void:
	effect_registry["perk_speed"]  = _apply_perk_mult.bind("speed_mult", 1.15)
	effect_registry["perk_attack"] = _apply_perk_mult.bind("attack_speed_mult", 1.15)
	effect_registry["perk_xp"]     = _apply_perk_mult.bind("xp_mult", 1.25)
	effect_registry["perk_damage"] = _apply_perk_mult.bind("damage_mult", 1.15)
	effect_registry["perk_hp"]     = _apply_perk_hp
	effect_registry["perk_heal"]   = _apply_perk_heal

# 从 WeaponDB 扫描带 evolution.evolved_id 的武器，自动注入进化卡。
# 进化 evolved 形态 .tres 可缺失（占位通路）；_evolve_weapon 会回退用 source 数据。
func _register_evolution_cards() -> void:
	for d in WeaponDB.all_evolvable():
		var data: WeaponData = d
		var weapon_id: String = data.id
		var evo_id: String = "evolve_" + weapon_id
		var card: Dictionary = {
			"id": evo_id,
			"name": "%s 进化" % data.display_name,
			"desc": "解锁 %s 的终极形态" % data.display_name,
			"type": "evolution",
			"condition": "evolve_ready:" + weapon_id,
		}
		_runtime_cards.append(card)
		effect_registry[evo_id] = _evolve_weapon.bind(weapon_id)

func pick(player: Player, count: int = 3) -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for card in _runtime_cards:
		if not _check_condition(card["condition"], player):
			continue
		# perk 封顶：达到 max_stacks 后从池中剔除
		if card.has("max_stacks"):
			if player.perk_stacks.get(card["id"], 0) >= card["max_stacks"]:
				continue
		available.append(card)
	available.shuffle()
	return available.slice(0, min(count, available.size()))

# 卡片图标：从卡关联的武器 WeaponData.icon 取（数据驱动；perk 卡无图标返回 null）。
func card_icon(card: Dictionary) -> Texture2D:
	var weapon_id := _weapon_id_of(card)
	if weapon_id == "":
		return null
	var data := WeaponDB.get_data(weapon_id)
	return data.icon if data != null else null

# 由卡 id/type 反推所属武器 id：weapon=本体，upgrade=去尾级数(knife_2→knife)，evolution=去 evolve_ 前缀。
func _weapon_id_of(card: Dictionary) -> String:
	var id: String = card["id"]
	match card.get("type", ""):
		"weapon":    return id
		"upgrade":   return id.rsplit("_", true, 1)[0]
		"evolution": return id.trim_prefix("evolve_")
	return ""

func apply(card: Dictionary, player: Player) -> void:
	if card.get("type", "") == "perk":
		player.perk_stacks[card["id"]] = player.perk_stacks.get(card["id"], 0) + 1
	var fn: Callable = effect_registry.get(card["id"], Callable())
	if not fn.is_valid():
		push_error("CardPool.apply: no effect for %s" % card["id"])
		return
	fn.call(player)

# 效果回调 ──────────────────────────────────────────────────────────────────
# 注意：Callable.bind(args) 在 Godot 4 中是**追加**bound args 到 call args 之后。
# 所以 .bind("speed_mult", 1.15).call(player) 实际是 _apply_perk_mult(player, "speed_mult", 1.15)，
# player 必须是第一参数。

func _grant_weapon(player: Player, weapon_id: String) -> void:
	var data := WeaponDB.get_data(weapon_id)
	if data == null:
		push_error("CardPool._grant_weapon: %s missing in WeaponDB" % weapon_id)
		return
	player.grant_weapon(data)

func _level_up_weapon(player: Player, weapon_id: String) -> void:
	player.level_up_weapon(weapon_id)
	weapon_leveled.emit(weapon_id, player.get_weapon_level(weapon_id))

func _apply_perk_mult(player: Player, stat: String, factor: float) -> void:
	player.set(stat, player.get(stat) * factor)

func _apply_perk_hp(player: Player) -> void:
	player.max_hp += 20.0
	player.hp = min(player.hp + 20.0, player.max_hp)

func _apply_perk_heal(player: Player) -> void:
	player.hp = minf(player.hp + 30.0, player.max_hp)

func _evolve_weapon(player: Player, source_id: String) -> void:
	var source_data := WeaponDB.get_data(source_id)
	if source_data == null or not source_data.evolution.has("evolved_id"):
		push_error("CardPool._evolve_weapon: %s has no evolution" % source_id)
		return
	var evolved_id := String(source_data.evolution["evolved_id"])
	var evolved_data := WeaponDB.get_data(evolved_id)
	# 占位：进化目标 .tres 缺失则用 source 数据（视觉无变化但通路打通）
	if evolved_data == null:
		evolved_data = source_data
	player.replace_weapon(source_id, evolved_data)
	weapon_evolved.emit(source_id, evolved_id)

# 条件 DSL ──────────────────────────────────────────────────────────────────

func _check_condition(condition: String, player: Player) -> bool:
	if condition == "":
		return true
	if condition.begins_with("no:"):
		var wid := condition.substr(3)
		if player.has_weapon(wid):
			return false
		# 源武器已进化(replace_weapon 抹掉了源 id) → 别把基础武器卡放回池
		var data := WeaponDB.get_data(wid)
		if data != null and data.evolution.has("evolved_id") \
				and player.has_weapon(String(data.evolution["evolved_id"])):
			return false
		return true
	if condition.begins_with("upgrade:"):
		var parts := condition.split(":")  # ["upgrade", "knife", "1"]
		return player.get_weapon_level(parts[1]) == int(parts[2])
	if condition.begins_with("evolve_ready:"):
		return _is_evolve_ready(player, condition.substr(13))
	return false

# 进化解锁：武器到 max_level 且关联 perk 累积到阈值。
# 阈值优先取 evolution.requires_perk_stacks（每个进化可独立放宽），缺省回退到 perk 的 max_stacks。
func _is_evolve_ready(player: Player, weapon_id: String) -> bool:
	if not player.has_weapon(weapon_id):
		return false
	var data := WeaponDB.get_data(weapon_id)
	if data == null or not data.evolution.has("evolved_id"):
		return false
	if player.get_weapon_level(weapon_id) < data.max_level:
		return false
	if not data.evolution.has("requires_perk"):
		return false
	var perk_id := String(data.evolution["requires_perk"])
	var threshold := int(data.evolution.get("requires_perk_stacks", _perk_max_stacks(perk_id)))
	if threshold <= 0:
		return false
	return player.perk_stacks.get(perk_id, 0) >= threshold

func _perk_max_stacks(perk_id: String) -> int:
	for c in CARDS:
		if c["id"] == perk_id:
			return c.get("max_stacks", 0)
	return 0
