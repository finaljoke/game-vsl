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
	{ "id": "knife",       "name": "长弓",      "desc": "瞄准最近敌射出穿透箭，远距暴击", "type": "weapon",  "condition": "no:knife"      },
	{ "id": "orb",         "name": "缚灵",      "desc": "环绕自身的守卫灵，接触伤害",   "type": "weapon",  "condition": "no:orb"        },
	{ "id": "explosion",   "name": "火球",      "desc": "投向最密集敌群的范围爆炸 + 地火",  "type": "weapon",  "condition": "no:explosion"  },
	{ "id": "knife_2",     "name": "长弓 Lv.2",    "desc": "冷却 0.9s → 0.7s，穿透↑",   "type": "upgrade", "condition": "upgrade:knife:1"     },
	{ "id": "orb_2",       "name": "缚灵 Lv.2",  "desc": "灵体数量 2 → 3",            "type": "upgrade", "condition": "upgrade:orb:1"       },
	{ "id": "explosion_2", "name": "火球 Lv.2",    "desc": "冷却 2.6s → 1.6s，地火↑",  "type": "upgrade", "condition": "upgrade:explosion:1" },
	{ "id": "knife_3",     "name": "长弓 Lv.3",    "desc": "冷却 0.7s → 0.5s，穿透 +1",  "type": "upgrade", "condition": "upgrade:knife:2"     },
	{ "id": "orb_3",       "name": "缚灵 Lv.3",  "desc": "灵体数量 3 → 4",            "type": "upgrade", "condition": "upgrade:orb:2"       },
	{ "id": "explosion_3", "name": "火球 Lv.3",    "desc": "冷却 1.6s → 1.0s，地火↑",  "type": "upgrade", "condition": "upgrade:explosion:2" },
	# 新武器(E1)：机制与飞刀/护盾球/爆炸错开
	{ "id": "lightning",   "name": "连锁闪电",     "desc": "向最近敌劈雷并连锁，附感电硬直", "type": "weapon",  "condition": "no:lightning"  },
	{ "id": "whip",        "name": "斩",           "desc": "朝移动方向快速弧劈，高频近身",  "type": "weapon",  "condition": "no:whip"       },
	{ "id": "boomerang",   "name": "回旋斧",       "desc": "抛出后折返，去回各结算穿透",  "type": "weapon",  "condition": "no:boomerang"  },
	{ "id": "aura",        "name": "烈焰护体",     "desc": "贴身燃烧光环，持续灼烧",      "type": "weapon",  "condition": "no:aura"       },
	{ "id": "lightning_2", "name": "连锁闪电 Lv.2", "desc": "连锁数 3 → 4，冷却↓",       "type": "upgrade", "condition": "upgrade:lightning:1" },
	{ "id": "lightning_3", "name": "连锁闪电 Lv.3", "desc": "连锁数 4 → 5，冷却↓",       "type": "upgrade", "condition": "upgrade:lightning:2" },
	{ "id": "whip_2",      "name": "斩 Lv.2",      "desc": "弧更宽，冷却↓",             "type": "upgrade", "condition": "upgrade:whip:1"      },
	{ "id": "whip_3",      "name": "斩 Lv.3",      "desc": "弧更宽，冷却↓",             "type": "upgrade", "condition": "upgrade:whip:2"      },
	{ "id": "boomerang_2", "name": "回旋斧 Lv.2",  "desc": "穿透 +1，射程↑",            "type": "upgrade", "condition": "upgrade:boomerang:1" },
	{ "id": "boomerang_3", "name": "回旋斧 Lv.3",  "desc": "穿透 +1，射程↑",            "type": "upgrade", "condition": "upgrade:boomerang:2" },
	{ "id": "aura_2",      "name": "烈焰护体 Lv.2", "desc": "范围 +20，灼烧↑",          "type": "upgrade", "condition": "upgrade:aura:1"      },
	{ "id": "aura_3",      "name": "烈焰护体 Lv.3", "desc": "范围 +20，灼烧↑",          "type": "upgrade", "condition": "upgrade:aura:2"      },
	# W2 新增武器
	{ "id": "maul",        "name": "碎",           "desc": "慢速大范围砸击，强击退+硬直",   "type": "weapon",  "condition": "no:maul"       },
	{ "id": "maul_2",      "name": "碎 Lv.2",      "desc": "范围/击退/硬直↑，冷却↓",        "type": "upgrade", "condition": "upgrade:maul:1"     },
	{ "id": "maul_3",      "name": "碎 Lv.3",      "desc": "范围/击退/硬直↑，冷却↓",        "type": "upgrade", "condition": "upgrade:maul:2"     },
	{ "id": "frostbite",   "name": "霜噬",         "desc": "冰爆减速，再命中则冻结",       "type": "weapon",  "condition": "no:frostbite"  },
	{ "id": "frostbite_2", "name": "霜噬 Lv.2",    "desc": "范围/减速/冻结↑，冷却↓",        "type": "upgrade", "condition": "upgrade:frostbite:1" },
	{ "id": "frostbite_3", "name": "霜噬 Lv.3",    "desc": "范围/减速/冻结↑，冷却↓",        "type": "upgrade", "condition": "upgrade:frostbite:2" },
	{ "id": "gravity_well",   "name": "引力井",     "desc": "漩涡拉拽聚怪 + 轻伤，放大 AoE", "type": "weapon",  "condition": "no:gravity_well"  },
	{ "id": "gravity_well_2", "name": "引力井 Lv.2", "desc": "范围/拉力/轻伤↑，冷却↓",       "type": "upgrade", "condition": "upgrade:gravity_well:1" },
	{ "id": "gravity_well_3", "name": "引力井 Lv.3", "desc": "范围/拉力/轻伤↑，冷却↓",       "type": "upgrade", "condition": "upgrade:gravity_well:2" },
	# W3a 新增武器
	{ "id": "reanimate",   "name": "亡者召唤",     "desc": "召唤自主骷髅随从，独立索敌近战",  "type": "weapon",  "condition": "no:reanimate"  },
	{ "id": "reanimate_2", "name": "亡者召唤 Lv.2", "desc": "随从上限 +1，存活↑",            "type": "upgrade", "condition": "upgrade:reanimate:1" },
	{ "id": "reanimate_3", "name": "亡者召唤 Lv.3", "desc": "随从上限 +1，伤害/存活↑",        "type": "upgrade", "condition": "upgrade:reanimate:2" },
	# 质变卡(E3)：非数值协同，rarity 默认 rare(_assign_default_rarities)
	{ "id": "synergy_pierce",    "name": "贯穿强化", "desc": "所有投射类武器穿透 +1", "type": "synergy", "condition": "has_any:knife,boomerang,thousand_edge,cyclone", "max_stacks": 3 },
	{ "id": "synergy_multishot", "name": "多重投射", "desc": "飞刀类额外多发 1 枚",   "type": "synergy", "condition": "has_any:knife,thousand_edge", "max_stacks": 2 },
	{ "id": "synergy_magnet",    "name": "磁化",     "desc": "XP 拾取范围 ×1.5",      "type": "synergy", "condition": "", "max_stacks": 3 },
	{ "id": "synergy_lifesteal", "name": "嗜血",     "desc": "每次击杀回 0.5 HP",      "type": "synergy", "condition": "", "max_stacks": 4 },
	{ "id": "perk_speed",  "name": "移速提升",  "desc": "移动速度永久 +15%",     "type": "perk",    "condition": "", "max_stacks": 8 },
	{ "id": "perk_hp",     "name": "生命上限",  "desc": "最大 HP +20，当场补满", "type": "perk",    "condition": "", "max_stacks": 10 },
	{ "id": "perk_attack", "name": "攻速提升",  "desc": "攻击速度永久 +15%",     "type": "perk",    "condition": "", "max_stacks": 8 },
	{ "id": "perk_xp",     "name": "XP 加成",   "desc": "XP 获取量永久 +25%",    "type": "perk",    "condition": "", "max_stacks": 6 },
	{ "id": "perk_damage", "name": "攻击强化",  "desc": "武器伤害永久 +15%",     "type": "perk",    "condition": "", "max_stacks": 8 },
	# perk_heal 改受伤条件卡(hp_below:0.9)：满血时不进池，消灭"满血回血"废牌陷阱
	{ "id": "perk_heal",   "name": "紧急治疗",  "desc": "立刻回复 30 HP",        "type": "perk",    "condition": "hp_below:0.9" },
]

# 稀有度抽取权重：值越大越常见。强卡(进化/质变)更稀有。
const RARITY_WEIGHTS := {"common": 100, "uncommon": 50, "rare": 20, "legendary": 6}

# 空池兜底卡：仅当其余池为空时由 pick() 注入，保证永不返回空(防暂停无法 resume，C3)。
# 用「+1 重抽券」——永不浪费(可存)，故不构成废牌/稀释(P5)。
const FALLBACK_CARD := { "id": "fallback_token", "name": "重抽券", "desc": "+1 重抽券", "type": "perk" }

# 静态 CARDS + 运行时注入的进化卡。pick() 只读它。
var _runtime_cards: Array[Dictionary] = []
# id → Callable(player)。每个 Callable 已绑定该卡所需参数。
var effect_registry: Dictionary = {}
# 本局被 ban 掉的卡 id 集合(reset_run 清空)。pick() 跳过。
var _banished: Dictionary = {}

func _ready() -> void:
	_runtime_cards = CARDS.duplicate(true)  # 深拷贝：后续给每张卡补 rarity 不污染 const
	_register_weapon_effects()
	_register_perk_effects()
	_register_evolution_cards()
	_register_synergy_effects()
	_assign_default_rarities()

# 给未显式标注 rarity 的卡按类型补默认稀有度。
func _assign_default_rarities() -> void:
	for card in _runtime_cards:
		if not card.has("rarity"):
			card["rarity"] = _default_rarity_for(String(card.get("type", "")))

func _default_rarity_for(type: String) -> String:
	match type:
		"weapon":    return "uncommon"
		"evolution": return "legendary"
		"synergy":   return "rare"
		_:           return "common"  # perk / upgrade

# 抽取权重(纯映射，便于单测)。
func rarity_weight(card: Dictionary) -> int:
	return int(RARITY_WEIGHTS.get(String(card.get("rarity", "common")), 100))

# 永久把某卡移出本局卡池(消耗重抽券，由 UI 调用)。
func banish(id: String) -> void:
	_banished[id] = true

# 每局开始重置本局 ban 状态(CardPool 是 autoload 跨场景重载存活)。
func reset_run() -> void:
	_banished.clear()

# 静态武器与升级卡（依赖 WeaponDB 提供数据，但 CARDS 数组里的 id/condition 是手写的）
func _register_weapon_effects() -> void:
	for id in ["knife", "orb", "explosion", "lightning", "whip", "boomerang", "aura", "maul", "frostbite", "gravity_well", "reanimate"]:
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
	effect_registry["fallback_token"] = _apply_fallback_token

# 质变卡(E3)：改玩家 modifier，由武器/拾取在运行时读取
func _register_synergy_effects() -> void:
	effect_registry["synergy_pierce"]    = _apply_synergy_pierce
	effect_registry["synergy_multishot"] = _apply_synergy_multishot
	effect_registry["synergy_magnet"]    = _apply_synergy_magnet
	effect_registry["synergy_lifesteal"] = _apply_synergy_lifesteal

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
	# 空池兜底：极端态下随机池与就绪进化均空 → 注入兜底券，防软锁(C3)。
	if result.is_empty():
		result.append(_fallback_card())
	return result

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
	# perk 与 synergy 都按 id 累计层数(供 pick() 的 max_stacks 封顶)
	var t: String = card.get("type", "")
	if t == "perk" or t == "synergy":
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

# 空池兜底券：仅当 pick() 其余池全空时注入并应用，+1 重抽券永不浪费(防软锁，C3)。
func _fallback_card() -> Dictionary:
	return FALLBACK_CARD.duplicate(true)

func _apply_fallback_token(player: Player) -> void:
	player.reroll_tokens += 1

# 质变效果(E3)
func _apply_synergy_pierce(player: Player) -> void:
	player.global_pierce += 1

func _apply_synergy_multishot(player: Player) -> void:
	player.extra_projectiles += 1

func _apply_synergy_magnet(player: Player) -> void:
	player.pickup_range_mult *= 1.5

func _apply_synergy_lifesteal(player: Player) -> void:
	player.lifesteal += 0.5

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
	if condition.begins_with("hp_below:"):
		var frac := float(condition.substr(9))
		return player.hp < player.max_hp * frac
	# 质变卡门控(E3)：has:<id> 持有该武器；has_any:<id,id,...> 持有任一
	if condition.begins_with("has_any:"):
		for w in condition.substr(8).split(","):
			if player.has_weapon(w.strip_edges()):
				return true
		return false
	if condition.begins_with("has:"):
		return player.has_weapon(condition.substr(4))
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
