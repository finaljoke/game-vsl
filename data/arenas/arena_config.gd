# data/arenas/arena_config.gd
# 一张地图的几何配置：尺寸、出生点、生成边距、底色、墙厚度。
# Arena 节点在 _ready() 期间据此重设 BG/Walls；EnemySpawner 据此算边缘出怪点。
class_name ArenaConfig
extends Resource

@export var size: Vector2 = Vector2(1280, 720)
@export var player_spawn: Vector2 = Vector2(640, 360)
@export var spawn_margin: float = 20.0  # 出怪点距边缘的内缩
@export var bg_color: Color = Color(0.12, 0.12, 0.15, 1.0)
@export var wall_thickness: float = 10.0
