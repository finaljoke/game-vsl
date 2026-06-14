# scenes/main/main.gd
extends Node

const KNIFE_SCENE = preload("res://scenes/weapons/knife/knife_weapon.tscn")

func _ready() -> void:
	var gm = get_node("/root/GameManager")
	var player := $YSort/Player as Player
	player.leveled_up.connect(func(_lvl: int): gm.trigger_level_up())
	player.died.connect(gm.game_over)
	player.add_weapon(KNIFE_SCENE)
	CardPool.register_weapon(player, "knife")
