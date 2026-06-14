# autoloads/card_pool.gd
# 子系统 1 阶段：仍保留 CARDS 数组与 match 派发，只把武器获取/升级转到 Player.grant_weapon /
# level_up_weapon，让武器数据走 WeaponDB。子系统 2 会进一步把 match 拆成 effect_registry。
extends Node

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

func pick(player: Player, count: int = 3) -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for card in CARDS:
		if not _check_condition(card["condition"], player):
			continue
		# perk 封顶：达到 max_stacks 后从池中剔除
		if card.has("max_stacks"):
			if player.perk_stacks.get(card["id"], 0) >= card["max_stacks"]:
				continue
		available.append(card)
	available.shuffle()
	return available.slice(0, min(count, available.size()))

func apply(card: Dictionary, player: Player) -> void:
	# 追踪 perk 叠加次数
	if card.get("type", "") == "perk":
		player.perk_stacks[card["id"]] = player.perk_stacks.get(card["id"], 0) + 1

	match card["id"]:
		"knife":
			player.grant_weapon(WeaponDB.get_data("knife"))
		"orb":
			player.grant_weapon(WeaponDB.get_data("orb"))
		"explosion":
			player.grant_weapon(WeaponDB.get_data("explosion"))
		"knife_2", "knife_3":
			player.level_up_weapon("knife")
		"orb_2", "orb_3":
			player.level_up_weapon("orb")
		"explosion_2", "explosion_3":
			player.level_up_weapon("explosion")
		"perk_speed":
			player.speed_mult *= 1.15
		"perk_hp":
			player.max_hp += 20.0
			player.hp = min(player.hp + 20.0, player.max_hp)
		"perk_attack":
			player.attack_speed_mult *= 1.15
		"perk_xp":
			player.xp_mult *= 1.25
		"perk_damage":
			player.damage_mult *= 1.15
		"perk_heal":
			player.hp = minf(player.hp + 30.0, player.max_hp)

func _check_condition(condition: String, player: Player) -> bool:
	if condition == "":
		return true
	if condition.begins_with("no:"):
		var weapon_id := condition.substr(3)
		return not player.has_weapon(weapon_id)
	if condition.begins_with("upgrade:"):
		var parts := condition.split(":")  # ["upgrade", "knife", "1"]
		return player.get_weapon_level(parts[1]) == int(parts[2])
	return false
