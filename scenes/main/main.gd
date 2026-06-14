# scenes/main/main.gd
extends Node

const KNIFE_SCENE = preload("res://scenes/weapons/knife/knife_weapon.tscn")

func _ready() -> void:
	var player := $YSort/Player as Player
	player.leveled_up.connect(func(_lvl: int): GameManager.trigger_level_up())
	player.died.connect(GameManager.game_over)
	player.add_weapon(KNIFE_SCENE)
