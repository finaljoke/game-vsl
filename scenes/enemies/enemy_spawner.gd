# scenes/enemies/enemy_spawner.gd
extends Node

const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")
const XP_GEM_SCENE = preload("res://scenes/collectibles/xp_gem.tscn")
const SpawnDirectorScript = preload("res://scenes/enemies/spawn_director.gd")

const INITIAL_INTERVAL: float = 1.5
const SCALE_INTERVAL: float = 20.0
const SCALE_FACTOR: float = 0.85
const MIN_INTERVAL: float = 0.3
const BOSS_WARNING_LEAD: float = 3.0  # 在 boss after 之前 N 秒发 GameFeel.boss_incoming，让 HUD 弹预警

# 三幕结构：切换点对齐幕间小 Boss(3:00 / 6:30)。难度乘区只作用于 HP 与 XP 掉落
# (XP 与 HP 同步成长防升级断档)，不动速度——速度有独立曲线，且后期跑位由闪避(P1-D)兜底。
const ACT2_START: float = 180.0  # 3:00
const ACT3_START: float = 390.0  # 6:30

# 敌人原型：hp/spd/con 为在时间缩放基础值上的倍率；after = 解锁所需存活秒数；
# behavior = 行为树类型（chase/ranged/bomber，由 enemy.gd 经 EnemyBT.build 装配）
# after = 解锁所需存活秒数。解锁铺满全程(每 60~90s 进一个新类型)，让"新东西"贯穿整局，
# 而非前 2 分钟塞满、后 8 分钟原地踏步。类型解锁之间的空档由 SpawnDirector 节拍事件填充。
# split = 死亡时分裂出的小怪数量(0=不分裂)；charger 走专属 charger 行为树(预警冲刺)。
const ARCHETYPES: Array[Dictionary] = [
	{ "id": "normal",   "hp": 1.0,  "spd": 1.0,  "con": 1.0, "tint": Color(1.0, 0.2, 0.2),   "scale": 0.30, "weight": 3, "after": 0.0,   "behavior": "chase",   "texture": preload("res://assets/sprites/kenney/characters/enemy_demon.png")    },
	{ "id": "swarm",    "hp": 0.45, "spd": 1.45, "con": 0.5, "tint": Color(1.0, 0.75, 0.15), "scale": 0.22, "weight": 3, "after": 0.0,   "behavior": "chase",   "texture": preload("res://assets/sprites/kenney/characters/enemy_spider.png")   },
	{ "id": "ranged",   "hp": 0.7,  "spd": 0.85, "con": 1.0, "tint": Color(0.4, 1.0, 0.9),   "scale": 0.28, "weight": 2, "after": 60.0,  "behavior": "ranged",  "texture": preload("res://assets/sprites/kenney/characters/enemy_ghost.png")    },
	{ "id": "bomber",   "hp": 0.6,  "spd": 1.2,  "con": 0.0, "tint": Color(1.0, 0.95, 0.4),  "scale": 0.30, "weight": 2, "after": 120.0, "behavior": "bomber",  "texture": preload("res://assets/sprites/kenney/characters/enemy_imp.png")      },
	# Charger：预警停顿后高速突进，制造可躲避的爆发威胁(配合 P1 闪避)
	{ "id": "charger",  "hp": 1.3,  "spd": 1.0,  "con": 1.6, "tint": Color(1.0, 0.45, 0.1),  "scale": 0.34, "weight": 2, "after": 180.0, "behavior": "charger", "texture": preload("res://assets/sprites/kenney/characters/enemy_imp.png")      },
	{ "id": "brute",    "hp": 3.5,  "spd": 0.6,  "con": 2.0, "tint": Color(0.65, 0.2, 0.85), "scale": 0.46, "weight": 2, "after": 240.0, "behavior": "chase",   "texture": preload("res://assets/sprites/kenney/characters/enemy_werewolf.png") },
	# Splitter：死亡裂成 2 只小怪(死亡钩子，offspring 从自身时缩属性派生)
	{ "id": "splitter", "hp": 1.4,  "spd": 0.95, "con": 1.0, "tint": Color(0.35, 0.9, 0.4),  "scale": 0.40, "weight": 2, "after": 330.0, "behavior": "chase",   "split": 2, "texture": preload("res://assets/sprites/kenney/characters/enemy_spider.png")   },
	# Boss：脚本化登场(见 BOSS_EVENTS)，不进随机出怪池 → after 设哨兵值(>WIN_TIME)。此条目仅作 Boss 三围/外观来源。
	{ "id": "boss",     "hp": 12.0, "spd": 0.7,  "con": 2.5, "tint": Color(0.9, 0.1, 0.1),   "scale": 0.65, "weight": 1, "after": 9999.0, "behavior": "boss",    "texture": preload("res://assets/sprites/kenney/characters/enemy_werewolf.png") },
]

# 脚本化 Boss 时间表：固定时间点登场(不走随机池)。每个登场前 BOSS_WARNING_LEAD 秒预警。
# kind="mini" 击杀 → 立即升级选卡；kind="final" 击杀 → 直接通关(扛到 WIN_TIME 兜底)。
const BOSS_EVENTS: Array[Dictionary] = [
	{ "time": 180.0, "kind": "mini" },   # 3:00 第一幕间小 Boss
	{ "time": 390.0, "kind": "mini" },   # 6:30 第二幕间小 Boss
	{ "time": 540.0, "kind": "final" },  # 9:00 终局 Boss(决战)
]

var _spawn_timer: float = 0.0
var _scale_timer: float = 0.0
var _spawn_interval: float = INITIAL_INTERVAL
var _elapsed_time: float = 0.0
var _ysort: Node = null
var _arena: Node = null  # 持有 .config: ArenaConfig
var _boss_alive: bool = false           # 并发锁：同一时刻只允许一只 boss 存活
var _bosses_spawned: int = 0            # 已登场的脚本化 Boss 数(指向 BOSS_EVENTS 下一项)
var _boss_warned: int = 0               # 已预警的脚本化 Boss 数
var _director = SpawnDirectorScript.new()  # 节拍层：在 trickle 之上叠爆发/喘息事件
var _music_path: String = ""            # 当前 BGM 已解析路径，路径变化才重放(去抖；多幕共用一首不重启)
@onready var _gm = get_node("/root/GameManager")

func _ready() -> void:
	_ysort = get_tree().get_first_node_in_group("ysort")
	_arena = get_tree().get_first_node_in_group("arena")

func _process(delta: float) -> void:
	if _gm.current_state != _gm.State.PLAYING:
		return
	_elapsed_time += delta
	_spawn_timer += delta
	_scale_timer += delta
	if _scale_timer >= SCALE_INTERVAL:
		_scale_timer = 0.0
		_spawn_interval = max(_spawn_interval * SCALE_FACTOR, MIN_INTERVAL)
	_update_boss_schedule()
	_update_music()
	# 节拍层：到点则触发一个爆发/喘息事件，叠在 trickle 之上形成锯齿强度曲线。
	if _director.is_due(_elapsed_time):
		_run_event(_director.advance(_elapsed_time))
	if _spawn_timer >= _spawn_interval:
		_spawn_timer = 0.0
		_try_spawn()

# 脚本化 Boss 调度：到 (time - LEAD) 发预警；到 time 生成对应 kind 的 Boss。
func _update_boss_schedule() -> void:
	if _boss_warned < BOSS_EVENTS.size():
		var w_evt: Dictionary = BOSS_EVENTS[_boss_warned]
		if _elapsed_time >= float(w_evt["time"]) - BOSS_WARNING_LEAD:
			_boss_warned += 1
			GameFeel.boss_incoming.emit()
	if _bosses_spawned < BOSS_EVENTS.size():
		var s_evt: Dictionary = BOSS_EVENTS[_bosses_spawned]
		if _elapsed_time >= float(s_evt["time"]):
			_bosses_spawned += 1
			_spawn_boss(String(s_evt["kind"]))

# 生成一只脚本化 Boss。final 更肉(作为可击杀的通关目标)；按 kind 接不同死亡奖励。
func _spawn_boss(kind: String) -> void:
	var arch := _archetype_by_id("boss").duplicate()
	if kind == "final":
		arch["hp"] = float(arch["hp"]) * 2.5
		arch["scale"] = float(arch["scale"]) * 1.25
	var boss := _spawn_one(arch, _random_edge_pos())
	if boss == null:
		return
	if kind == "final":
		boss.died.connect(_on_final_boss_died)
	else:
		boss.died.connect(_on_mini_boss_died)

func _on_mini_boss_died(_pos: Vector2) -> void:
	_grant_reroll_tokens(2)   # 掉重抽券，在升级选卡里可重抽/ban
	_gm.trigger_level_up()    # 幕间小 Boss 击杀 → 立即升级选卡

func _on_final_boss_died(_pos: Vector2) -> void:
	_gm.trigger_victory()     # 终局 Boss 击杀 → 直接通关

func _grant_reroll_tokens(n: int) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p != null and "reroll_tokens" in p:
		p.reroll_tokens += n

func _try_spawn() -> void:
	if _enemy_count() >= _max_enemies(_elapsed_time):
		return
	# trickle 只刷普通怪；Boss 走 BOSS_EVENTS 脚本化登场。
	_spawn_one(_pick_eligible_nonboss(), _random_edge_pos())

# 按原型在 pos 实例化一只敌人并注入时缩属性。trickle 与节拍事件共用，stat 逻辑只此一处。
func _spawn_one(arch: Dictionary, pos: Vector2) -> Enemy:
	var minutes := _elapsed_time / 60.0
	var base_hp := _scaled_base_hp(_elapsed_time)  # 线性曲线 ×幕乘区，后半程超线性递增
	var base_spd := clampf(80.0 * (1.0 + minutes * 0.15), 80.0, 210.0)  # 上限提至 210，后期逼近玩家速度 200，削弱纯风筝
	var enemy := ENEMY_SCENE.instantiate()
	enemy.MAX_HP = base_hp * arch["hp"]
	enemy.hp    = enemy.MAX_HP
	enemy.SPEED = clampf(base_spd * arch["spd"], 50.0, 280.0)
	enemy.CONTACT_DAMAGE = 8.0 * arch["con"]
	enemy.tint = arch["tint"]
	enemy.body_scale = arch["scale"]
	enemy.sprite_texture = arch["texture"]
	enemy.behavior = arch["behavior"]
	enemy.split_count = int(arch.get("split", 0))
	_ysort.add_child(enemy)
	enemy.global_position = pos
	enemy.died.connect(_on_enemy_died)
	if arch["id"] == "boss":
		_boss_alive = true
		enemy.died.connect(_on_boss_died)
	return enemy as Enemy

func _on_boss_died(_pos: Vector2) -> void:
	_boss_alive = false

func _enemy_count() -> int:
	return get_tree().get_nodes_in_group("enemies").size()

# 同屏敌人上限按幕递增，配合节拍爆发让后期真正更密。
func _max_enemies(elapsed: float) -> int:
	match _current_act(elapsed):
		1: return 120
		2: return 200
		_: return 300

# ── 节拍事件执行（mechanism；policy 在 spawn_director.gd）─────────────────────

func _run_event(ev: Dictionary) -> void:
	var type: String = ev.get("type", "")
	match type:
		"swarm_rush": _event_swarm_rush()
		"pincer":     _event_pincer()
		"elite_pack": _event_elite_pack()
		"breather":   pass  # 张弛：本拍不额外刷怪，让密度回落
	if type != "breather":
		print("[director] %s @ %ds (enemies=%d)" % [type, int(_elapsed_time), _enemy_count()])

# 单边潮水：一条边爆发一波 swarm。
func _event_swarm_rush() -> void:
	var n := 8 + _current_act(_elapsed_time) * 4
	var swarm := _archetype_by_id("swarm")
	var s: Vector2 = _arena.config.size
	var m: float = _arena.config.spawn_margin
	var edge := randi() % 4
	for _i in range(n):
		if _enemy_count() >= _max_enemies(_elapsed_time):
			break
		_spawn_one(swarm, _pos_on_edge(edge, randf(), s, m))

# 包夹：在玩家四周环形生成一圈(保持距离，不糊脸)。
func _event_pincer() -> void:
	var n := 6 + _current_act(_elapsed_time) * 3
	var center := _player_pos()
	for i in range(n):
		if _enemy_count() >= _max_enemies(_elapsed_time):
			break
		var ang := TAU * float(i) / float(n)
		var pos := _clamp_to_arena(center + Vector2(cos(ang), sin(ang)) * 260.0)
		_spawn_one(_pick_eligible_nonboss(), pos)

# 精英小队：少量被强化(更肉更大更疼)的已解锁原型。
func _event_elite_pack() -> void:
	var n := 2 + _current_act(_elapsed_time)
	for _i in range(n):
		if _enemy_count() >= _max_enemies(_elapsed_time):
			break
		var elite := _pick_eligible_nonboss().duplicate()
		elite["hp"] = float(elite["hp"]) * 2.5
		elite["scale"] = float(elite["scale"]) * 1.3
		elite["con"] = float(elite["con"]) * 1.3
		_spawn_one(elite, _random_edge_pos())

# ── 幕结构与难度乘区（纯函数，便于单测）─────────────────────────────────────

# 当前处于第几幕：Act1 [0,180) / Act2 [180,390) / Act3 [390,∞)
func _current_act(elapsed: float) -> int:
	if elapsed < ACT2_START:
		return 1
	if elapsed < ACT3_START:
		return 2
	return 3

# 按幕的 HP/威胁乘区，叠在线性时间曲线之上，使后半程难度真正递增。
func _difficulty_mult(elapsed: float) -> float:
	match _current_act(elapsed):
		1: return 1.0
		2: return 1.4
		_: return 2.0

# 线性时间因子 ×幕乘区，HP 与 XP 共用，保持二者同步成长。
func _time_scale(elapsed: float) -> float:
	return (1.0 + (elapsed / 60.0) * 0.25) * _difficulty_mult(elapsed)

# 当前时刻 normal 原型的基准 HP（各原型再乘自身 hp 倍率）。
func _scaled_base_hp(elapsed: float) -> float:
	return 20.0 * _time_scale(elapsed)

# 当前时刻击杀掉落的 XP 值，与 base_hp 同步成长防升级断档。
func _scaled_xp_value(elapsed: float) -> float:
	return 10.0 * _time_scale(elapsed)

# 纯函数：返回当前已解锁（after <= elapsed）的原型子集，便于单测
func _eligible_archetypes(elapsed: float) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for a in ARCHETYPES:
		if elapsed >= a["after"]:
			pool.append(a)
	return pool

func _on_enemy_died(pos: Vector2) -> void:
	var gem := XP_GEM_SCENE.instantiate()
	gem.value = _scaled_xp_value(_elapsed_time)  # 与敌人 HP(含幕乘区)同步成长，防止升级断档
	_ysort.add_child(gem)
	gem.global_position = pos

func _random_edge_pos() -> Vector2:
	var s: Vector2 = _arena.config.size
	var m: float = _arena.config.spawn_margin
	match randi() % 4:
		0: return Vector2(randf_range(m, s.x - m), m)
		1: return Vector2(randf_range(m, s.x - m), s.y - m)
		2: return Vector2(m, randf_range(m, s.y - m))
		_: return Vector2(s.x - m, randf_range(m, s.y - m))

# 沿指定边(0上/1下/2左/3右)按参数 t∈[0,1] 取一点。swarm_rush 让整波从同一边涌入。
func _pos_on_edge(edge: int, t: float, s: Vector2, m: float) -> Vector2:
	match edge:
		0: return Vector2(lerpf(m, s.x - m, t), m)
		1: return Vector2(lerpf(m, s.x - m, t), s.y - m)
		2: return Vector2(m, lerpf(m, s.y - m, t))
		_: return Vector2(s.x - m, lerpf(m, s.y - m, t))

func _player_pos() -> Vector2:
	var p := get_tree().get_first_node_in_group("player")
	if p != null and is_instance_valid(p):
		return p.global_position
	return _arena.config.size * 0.5

func _clamp_to_arena(pos: Vector2) -> Vector2:
	var s: Vector2 = _arena.config.size
	var m: float = _arena.config.spawn_margin
	return Vector2(clampf(pos.x, m, s.x - m), clampf(pos.y, m, s.y - m))

func _archetype_by_id(id: String) -> Dictionary:
	for a in ARCHETYPES:
		if a["id"] == id:
			return a
	return ARCHETYPES[0]

# ── BGM：按幕切歌，Boss 存活期间切 Boss 曲。素材缺失时静默跳过(不崩)──────────

# 纯映射：当前该放哪首。boss_alive 优先级最高(决战氛围)。
func _music_track_for(elapsed: float, boss_alive: bool) -> String:
	if boss_alive:
		return "boss"
	return "act%d" % _current_act(elapsed)

func _update_music() -> void:
	# 按解析后的路径去抖：路径没变就不重放(act 切幕共用同一首时不会重启)。
	var path := _resolve_music(_music_track_for(_elapsed_time, _boss_alive))
	if path == _music_path:
		return
	_music_path = path
	if path != "":
		_play_music_path(path)

# 解析轨道文件：先精确匹配 <track>.{ogg,mp3,wav}；act* 找不到时回退到通用 game 轨
# (素材少时多幕共用一首)。文件缺失返回 "" → 调用方静默跳过。
func _resolve_music(track: String) -> String:
	var names := [track]
	if track.begins_with("act"):
		names.append("game")
	for n in names:
		for ext in [".ogg", ".mp3", ".wav"]:
			var p := "res://assets/audio/music/%s%s" % [n, ext]
			if ResourceLoader.exists(p):
				return p
	return ""

const MUSIC_DB: float = -10.0  # BGM 整体压低，避免盖过打击/反馈音(config 级，可调)

func _play_music_path(path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	if "loop" in stream:
		stream.loop = true
	SoundManager.play_music_at_volume(stream, MUSIC_DB, 1.0)  # -10dB + 1s 交叉淡入

# 已解锁原型中按权重抽一个非 boss(节拍事件用，boss 只走 trickle)。
func _pick_eligible_nonboss() -> Dictionary:
	var pool: Array[Dictionary] = []
	for a in _eligible_archetypes(_elapsed_time):
		if a["id"] != "boss":
			pool.append(a)
	if pool.is_empty():
		return _archetype_by_id("normal")
	var total := 0
	for a in pool:
		total += int(a["weight"])
	var r := randi() % total
	for a in pool:
		r -= int(a["weight"])
		if r < 0:
			return a
	return pool[0]
