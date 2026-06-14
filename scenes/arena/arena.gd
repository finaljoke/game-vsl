# scenes/arena/arena.gd
# 按 ArenaConfig 把 BG/4 面墙摆好。加 "arena" 组让 spawner/main 通过组取 config。
extends Node2D

const DEFAULT_CONFIG = preload("res://data/arenas/default.tres")

@export var config: ArenaConfig

@onready var _bg: Node2D = $Background  # 挂了 floor.gd，自绘地砖网格
@onready var _wall_top: StaticBody2D = $WallTop
@onready var _wall_bottom: StaticBody2D = $WallBottom
@onready var _wall_left: StaticBody2D = $WallLeft
@onready var _wall_right: StaticBody2D = $WallRight

func _ready() -> void:
	add_to_group("arena")
	if config == null:
		config = DEFAULT_CONFIG
	_apply_config()

func _apply_config() -> void:
	var w := config.size.x
	var h := config.size.y
	var t := config.wall_thickness
	# 背景：floor.gd 按 ArenaConfig.size 自绘地砖网格；player_spawn 保留参数以兼容旧签名
	_bg.setup(config.size, config.player_spawn)
	# 4 面墙紧贴竞技场外缘，shape 是 .tscn 里的 sub_resource（单实例，原地改）
	_set_wall(_wall_top,    Vector2(w * 0.5, -t * 0.5),     Vector2(w, t))
	_set_wall(_wall_bottom, Vector2(w * 0.5, h + t * 0.5),  Vector2(w, t))
	_set_wall(_wall_left,   Vector2(-t * 0.5, h * 0.5),     Vector2(t, h))
	_set_wall(_wall_right,  Vector2(w + t * 0.5, h * 0.5),  Vector2(t, h))

func _set_wall(wall: StaticBody2D, pos: Vector2, size: Vector2) -> void:
	wall.position = pos
	var shape: RectangleShape2D = wall.get_node("CollisionShape2D").shape
	shape.size = size
