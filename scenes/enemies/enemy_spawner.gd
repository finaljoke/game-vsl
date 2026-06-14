# scenes/enemies/enemy_spawner.gd
extends Node

const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")
const XP_GEM_SCENE = preload("res://scenes/collectibles/xp_gem.tscn")

const INITIAL_INTERVAL: float = 1.5
const SCALE_INTERVAL: float = 20.0
const SCALE_FACTOR: float = 0.85
const MIN_INTERVAL: float = 0.3
const MAX_ENEMIES: int = 200
const ARENA_W: float = 1280.0
const ARENA_H: float = 720.0
const SPAWN_MARGIN: float = 20.0

var _spawn_timer: float = 0.0
var _scale_timer: float = 0.0
var _spawn_interval: float = INITIAL_INTERVAL
var _elapsed_time: float = 0.0
var _ysort: Node = null
@onready var _gm = get_node("/root/GameManager")

func _ready() -> void:
	_ysort = get_tree().get_first_node_in_group("ysort")

func _process(delta: float) -> void:
	if _gm.current_state != _gm.State.PLAYING:
		return
	_elapsed_time += delta
	_spawn_timer += delta
	_scale_timer += delta
	if _scale_timer >= SCALE_INTERVAL:
		_scale_timer = 0.0
		_spawn_interval = max(_spawn_interval * SCALE_FACTOR, MIN_INTERVAL)
	if _spawn_timer >= _spawn_interval:
		_spawn_timer = 0.0
		_try_spawn()

func _try_spawn() -> void:
	if get_tree().get_nodes_in_group("enemies").size() >= MAX_ENEMIES:
		return
	var minutes := _elapsed_time / 60.0
	var enemy := ENEMY_SCENE.instantiate()
	enemy.MAX_HP = 20.0 * (1.0 + minutes * 0.25)
	enemy.hp    = enemy.MAX_HP
	enemy.SPEED = clampf(80.0 * (1.0 + minutes * 0.15), 80.0, 160.0)
	_ysort.add_child(enemy)
	enemy.global_position = _random_edge_pos()
	enemy.died.connect(_on_enemy_died)

func _on_enemy_died(pos: Vector2) -> void:
	var gem := XP_GEM_SCENE.instantiate()
	_ysort.add_child(gem)
	gem.global_position = pos

func _random_edge_pos() -> Vector2:
	match randi() % 4:
		0: return Vector2(randf_range(SPAWN_MARGIN, ARENA_W - SPAWN_MARGIN), SPAWN_MARGIN)
		1: return Vector2(randf_range(SPAWN_MARGIN, ARENA_W - SPAWN_MARGIN), ARENA_H - SPAWN_MARGIN)
		2: return Vector2(SPAWN_MARGIN, randf_range(SPAWN_MARGIN, ARENA_H - SPAWN_MARGIN))
		_: return Vector2(ARENA_W - SPAWN_MARGIN, randf_range(SPAWN_MARGIN, ARENA_H - SPAWN_MARGIN))
