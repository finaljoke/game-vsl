# scenes/main/main.gd
extends Node

func _ready() -> void:
	var player := $YSort/Player as Player
	player.leveled_up.connect(func(_lvl: int): GameManager.trigger_level_up())
	player.died.connect(GameManager.game_over)
