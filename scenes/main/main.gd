# scenes/main/main.gd
extends Node

func _ready() -> void:
	# CardPool 是 autoload，跨场景重载存活 → 每局开始清掉上局的 ban 状态
	CardPool.reset_run()
	var gm = get_node("/root/GameManager")
	var player := $YSort/Player as Player
	var arena := get_tree().get_first_node_in_group("arena")
	# 把玩家与相机锚到 arena.config，未来换 ArenaConfig 不需要再动这里
	player.global_position = arena.config.player_spawn
	$PhantomCamera2D.position = arena.config.player_spawn
	player.leveled_up.connect(func(_lvl: int): gm.trigger_level_up())
	player.died.connect(gm.game_over)
	# 初始飞刀：走标准 grant 路径，owned_weapons 自动登记
	player.grant_weapon(WeaponDB.get_data("knife"))
