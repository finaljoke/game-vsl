# scenes/main/main.gd
extends Node

func _ready() -> void:
	var gm = get_node("/root/GameManager")
	var player := $YSort/Player as Player
	player.leveled_up.connect(func(_lvl: int): gm.trigger_level_up())
	player.died.connect(gm.game_over)
	# 初始飞刀：走标准 grant 路径，owned_weapons 自动登记
	player.grant_weapon(WeaponDB.get_data("knife"))
