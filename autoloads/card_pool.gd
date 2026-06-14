# autoloads/card_pool.gd
extends Node

const CARDS: Array[Dictionary] = [
	{ "id": "knife",       "name": "飞刀",      "desc": "朝最近敌人射出飞刀",    "type": "weapon",  "condition": "no:knife"      },
	{ "id": "orb",         "name": "护盾球",    "desc": "绕身旋转的能量球",      "type": "weapon",  "condition": "no:orb"        },
	{ "id": "explosion",   "name": "爆炸",      "desc": "随机位置触发范围爆炸",  "type": "weapon",  "condition": "no:explosion"  },
	{ "id": "knife_2",     "name": "飞刀 Lv.2",    "desc": "冷却 1.0s → 0.5s",         "type": "upgrade", "condition": "upgrade:knife"     },
	{ "id": "orb_2",       "name": "护盾球 Lv.2",  "desc": "护盾球数量 2 → 3",          "type": "upgrade", "condition": "upgrade:orb"       },
	{ "id": "explosion_2", "name": "爆炸 Lv.2",    "desc": "冷却 3.0s → 1.5s",         "type": "upgrade", "condition": "upgrade:explosion" },
	{ "id": "perk_speed",  "name": "移速提升",  "desc": "移动速度永久 +15%",     "type": "perk",    "condition": "", "max_stacks": 6 },
	{ "id": "perk_hp",     "name": "生命上限",  "desc": "最大 HP +20，当场补满", "type": "perk",    "condition": "", "max_stacks": 8 },
	{ "id": "perk_attack", "name": "攻速提升",  "desc": "攻击速度永久 +15%",     "type": "perk",    "condition": "", "max_stacks": 6 },
	{ "id": "perk_xp",     "name": "XP 加成",   "desc": "XP 获取量永久 +25%",    "type": "perk",    "condition": "", "max_stacks": 4 },
	{ "id": "perk_damage", "name": "攻击强化",  "desc": "武器伤害永久 +15%",     "type": "perk",    "condition": "", "max_stacks": 8 },
	# 无上限兜底卡：保证卡池不为空，防止空池导致暂停无法 resume
	{ "id": "perk_heal",   "name": "紧急治疗",  "desc": "立刻回复 30 HP",        "type": "perk",    "condition": "" },
]

const KNIFE_SCENE := preload("res://scenes/weapons/knife/knife_weapon.tscn")
const ORB_SCENE := preload("res://scenes/weapons/orb/orb_weapon.tscn")
const ORB_SHIELD_SCENE := preload("res://scenes/weapons/orb/orb_shield.tscn")
const EXPLOSION_SCENE := preload("res://scenes/weapons/explosion/explosion_weapon.tscn")

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
			player.add_weapon(KNIFE_SCENE)
			player.owned_weapons["knife"] = 1
		"orb":
			player.add_weapon(ORB_SCENE)
			player.owned_weapons["orb"] = 1
		"explosion":
			player.add_weapon(EXPLOSION_SCENE)
			player.owned_weapons["explosion"] = 1
		"knife_2":
			for child in player.get_children():
				if child is KnifeWeapon:
					child.cooldown = 0.5
			player.owned_weapons["knife"] = 2
		"orb_2":
			var new_orb := ORB_SHIELD_SCENE.instantiate() as OrbShield
			player.add_child(new_orb)
			new_orb.orbit_index = 2
			new_orb.total_orbs = 3
			for child in player.get_children():
				if child is OrbShield:
					child.total_orbs = 3
			player.owned_weapons["orb"] = 2
		"explosion_2":
			for child in player.get_children():
				if child is ExplosionWeapon:
					child.cooldown = 1.5
			player.owned_weapons["explosion"] = 2
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

func register_weapon(player: Player, weapon_id: String) -> void:
	player.owned_weapons[weapon_id] = 1

func _check_condition(condition: String, player: Player) -> bool:
	if condition == "":
		return true
	if condition.begins_with("no:"):
		var weapon_id := condition.substr(3)
		return not player.owned_weapons.has(weapon_id)
	if condition.begins_with("upgrade:"):
		var weapon_id := condition.substr(8)
		var lvl: int = player.owned_weapons.get(weapon_id, 0)
		return lvl >= 1 and lvl < 2
	return false
