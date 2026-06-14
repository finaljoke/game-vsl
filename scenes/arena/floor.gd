# scenes/arena/floor.gd
# 自绘随机地砖背景：按竞技场尺寸网格逐格画加权随机地砖。
# arena.gd 在 _apply_config() 里调 setup(size, spawn) → queue_redraw；尺寸随 ArenaConfig，
# 故换地图（新 arena .tres）零改动。用固定 seed 的 RNG，保证布局每局稳定、不闪烁。
# 不画石/骨/桶等点缀物——任何 3D 感独立小物件都容易被误读为可拾物或敌人，
# 让真实体（玩家/敌人/宝石）在场上最干净跳出。
extends Node2D

const TILE_PX: int = 16
const TILE_SCALE: int = 3
const CELL: int = TILE_PX * TILE_SCALE  # 48px/格

# 地砖：plain 占多数（权重 3），speckled 偶发（权重 1）→ 自然破单调
const FLOOR_TILES: Array[Texture2D] = [
	preload("res://assets/sprites/kenney/tiles/floor_a.png"),
	preload("res://assets/sprites/kenney/tiles/floor_b.png"),
	preload("res://assets/sprites/kenney/tiles/floor_c.png"),
	preload("res://assets/sprites/kenney/tiles/floor_d.png"),
	preload("res://assets/sprites/kenney/tiles/floor_e.png"),
]
const FLOOR_WEIGHTS: Array[int] = [3, 3, 3, 1, 1]

const LAYOUT_SEED: int = 0x5EED        # 固定布局种子
# 地砖整体压暗/去饱和一点，让玩家与敌人更跳出
const FLOOR_TINT: Color = Color(0.82, 0.8, 0.83, 1.0)

var _size: Vector2 = Vector2(1280, 720)
var _spawn: Vector2 = Vector2(640, 360)

func setup(size: Vector2, spawn: Vector2) -> void:
	_size = size
	_spawn = spawn
	queue_redraw()

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = LAYOUT_SEED
	var cols := int(ceil(_size.x / CELL))
	var rows := int(ceil(_size.y / CELL))
	var weight_total := 0
	for w in FLOOR_WEIGHTS:
		weight_total += w
	var cell_size := Vector2(CELL, CELL)
	for r in rows:
		for c in cols:
			var pos := Vector2(c * CELL, r * CELL)
			draw_texture_rect(_pick_floor(rng, weight_total), Rect2(pos, cell_size), false, FLOOR_TINT)

func _pick_floor(rng: RandomNumberGenerator, weight_total: int) -> Texture2D:
	var roll := rng.randi_range(0, weight_total - 1)
	var acc := 0
	for i in FLOOR_WEIGHTS.size():
		acc += FLOOR_WEIGHTS[i]
		if roll < acc:
			return FLOOR_TILES[i]
	return FLOOR_TILES[0]
