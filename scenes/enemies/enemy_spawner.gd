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

# 敌人原型：hp/spd/con 为在时间缩放基础值上的倍率；after = 解锁所需存活秒数；
# behavior = 行为树类型（chase/ranged/bomber，由 enemy.gd 经 EnemyBT.build 装配）
const ARCHETYPES: Array[Dictionary] = [
	{ "id": "normal", "hp": 1.0,  "spd": 1.0,  "con": 1.0, "tint": Color(1.0, 0.2, 0.2),   "scale": 0.30, "weight": 3, "after": 0.0,   "behavior": "chase"  },
	{ "id": "swarm",  "hp": 0.45, "spd": 1.45, "con": 0.5, "tint": Color(1.0, 0.75, 0.15), "scale": 0.22, "weight": 3, "after": 0.0,   "behavior": "chase"  },
	{ "id": "ranged", "hp": 0.7,  "spd": 0.85, "con": 1.0, "tint": Color(0.4, 1.0, 0.9),   "scale": 0.28, "weight": 2, "after": 60.0,  "behavior": "ranged" },
	{ "id": "bomber", "hp": 0.6,  "spd": 1.2,  "con": 0.0, "tint": Color(1.0, 0.95, 0.4),  "scale": 0.30, "weight": 2, "after": 90.0,  "behavior": "bomber" },
	{ "id": "brute",  "hp": 3.5,  "spd": 0.6,  "con": 2.0, "tint": Color(0.65, 0.2, 0.85), "scale": 0.46, "weight": 2, "after": 120.0, "behavior": "chase"  },
]

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
	var arch := _pick_archetype()
	var base_hp := 20.0 * (1.0 + minutes * 0.25)
	var base_spd := clampf(80.0 * (1.0 + minutes * 0.15), 80.0, 210.0)  # 上限提至 210，后期逼近玩家速度 200，削弱纯风筝
	var enemy := ENEMY_SCENE.instantiate()
	enemy.MAX_HP = base_hp * arch["hp"]
	enemy.hp    = enemy.MAX_HP
	enemy.SPEED = clampf(base_spd * arch["spd"], 50.0, 280.0)
	enemy.CONTACT_DAMAGE = 8.0 * arch["con"]
	enemy.tint = arch["tint"]
	enemy.body_scale = arch["scale"]
	enemy.behavior = arch["behavior"]
	_ysort.add_child(enemy)
	enemy.global_position = _random_edge_pos()
	enemy.died.connect(_on_enemy_died)

# 纯函数：返回当前已解锁（after <= elapsed）的原型子集，便于单测
func _eligible_archetypes(elapsed: float) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for a in ARCHETYPES:
		if elapsed >= a["after"]:
			pool.append(a)
	return pool

func _pick_archetype() -> Dictionary:
	var pool := _eligible_archetypes(_elapsed_time)
	var total := 0
	for a in pool:
		total += int(a["weight"])
	var r := randi() % total
	for a in pool:
		r -= int(a["weight"])
		if r < 0:
			return a
	return pool[0]

func _on_enemy_died(pos: Vector2) -> void:
	var gem := XP_GEM_SCENE.instantiate()
	var minutes := _elapsed_time / 60.0
	gem.value = 10.0 * (1.0 + minutes * 0.25)  # 与敌人 HP 同步成长，防止升级断档
	_ysort.add_child(gem)
	gem.global_position = pos

func _random_edge_pos() -> Vector2:
	match randi() % 4:
		0: return Vector2(randf_range(SPAWN_MARGIN, ARENA_W - SPAWN_MARGIN), SPAWN_MARGIN)
		1: return Vector2(randf_range(SPAWN_MARGIN, ARENA_W - SPAWN_MARGIN), ARENA_H - SPAWN_MARGIN)
		2: return Vector2(SPAWN_MARGIN, randf_range(SPAWN_MARGIN, ARENA_H - SPAWN_MARGIN))
		_: return Vector2(ARENA_W - SPAWN_MARGIN, randf_range(SPAWN_MARGIN, ARENA_H - SPAWN_MARGIN))
