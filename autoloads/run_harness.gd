# autoloads/run_harness.gd
# Bot 驱动 + 遥测编排器。无 --bot 命令行参数时完全惰性(active=false),真人游玩零影响。
# 职责:读命令行配置、每物理帧驱动 bot 移动、监听升级自动选卡、设种子/快进、检测终局收尾退出。
#
# 本文件含两个纯静态函数(compute_kite_dir / choose_card),不依赖场景,便于单测。
extends Node

const RunAnalysis := preload("res://tools/run_analysis.gd")   # 纯解析模块,solo_spec 等共用

# ── 可调参数(集中) ────────────────────────────────────────────────────────
const PERCEPTION_RADIUS: float = 220.0   # kite 感知半径(px):此半径内敌人产生斥力
const CENTER_PULL_GAIN: float = 0.004    # kite 避墙:离中心越远拉回越强
const DEFAULT_FAST: float = 3.0          # --fast 缺省(同种子 diff 验确定性后可升降)
const DEFAULT_INTERVAL: float = 1.0      # tick CSV 采样周期(游戏秒)
const NEAR_RADIUS: float = 140.0         # 传给 player.bot 的近敌半径(预留,DebugMetrics 另有同名)
const DODGE_RADIUS: float = 200.0        # 躲弹感知半径(px):此半径内、正接近的弹触发侧移
const W_KITE: float = 1.0                 # _compute_input 合成:避敌权重
const W_DODGE: float = 1.5                # 合成:躲弹权重(占优——正面斥力对快弹无效)

# 选卡优先级表(命名 profile)。matcher: 精确卡 id,或 "type:<type>" 匹配卡型。
# default = 生存优先(先保命再进攻),给 bot 一套稳定可活满全程的 build。以后外置到 data/bot_profiles/。
const DEFAULT_PROFILE: Array = [
	"perk_hp", "synergy_lifesteal", "perk_heal",
	"type:evolution", "type:synergy", "type:upgrade",
	"type:weapon", "type:perk",
]
const PROFILES: Dictionary = {"default": DEFAULT_PROFILE}

# 每把武器进化所需 perk(spec §6.4)。供单武器档堆到 evolve_ready。
# 新武器(maul/frostbite/gravity_well/reanimate)的 id 以 W2/W3a 实际为准;不存在时该项仅未被用到,无害。
const SOLO_PERKS := {
	"knife": "perk_attack", "whip": "perk_attack", "boomerang": "perk_speed",
	"explosion": "perk_damage", "aura": "perk_hp", "lightning": "perk_attack", "orb": "perk_hp",
	"maul": "perk_hp", "frostbite": "perk_attack", "gravity_well": "perk_speed", "reanimate": "perk_hp",
}

const FLOOR_PERK_HP_STACKS: int = 5   # solofloor_ 档开局授予的 perk_hp 层数(+100 max HP 生存垫,纯防御不加击杀)

const MIX_CHASSIS: Array = ["frostbite"]          # 混编生存底盘武器:控制(slow)、低清场,留 headroom 给目标
const MIX_CHASSIS_PERK_HP_STACKS: int = 5         # 底盘防御垫(A/B 两臂同垫,delta 抵消;让 base 脆武器活到进化)

# 单武器优先表:拿武器 → 升级 → (就绪即)进化 → 堆进化 perk → 生存兜底。
# 不含通用 type:weapon,故 bot 不会拿别的武器,保证单武器隔离。
static func solo_profile(weapon_id: String, evo_perk: String) -> Array:
	return [
		weapon_id,
		weapon_id + "_2", weapon_id + "_3",
		"evolve_" + weapon_id,
		evo_perk,
		"synergy_lifesteal", "perk_hp", "perk_heal",
		"type:upgrade", "type:synergy", "type:perk",
	]

# 混编优先表:目标武器优先(满级→进化→进化 perk),其次底盘武器维护,再生存兜底。
# 不含通用 type:weapon → bot 不拿外来武器,保证「底盘 + 目标」纯净。target=="" 即纯底盘(mixbase)。
static func mix_profile(target: String, target_evo_perk: String) -> Array:
	var p: Array = []
	if target != "":
		p.append_array([target, target + "_2", target + "_3", "evolve_" + target, target_evo_perk])
	for w in MIX_CHASSIS:
		p.append_array([w, w + "_2", w + "_3"])
	p.append_array(["synergy_lifesteal", "perk_hp", "perk_heal", "type:upgrade", "type:synergy", "type:perk"])
	return p

# 单武器档名 → 规格(委托纯模块 run_analysis,与分析器共用同一解析,DRY)。
# {"is_solo": bool, "is_floor": bool, "weapon_id": String}。
static func solo_spec(cards_name: String) -> Dictionary:
	return RunAnalysis.solo_spec(cards_name)

static func profile_for(name: String) -> Array:
	var spec := solo_spec(name)
	if spec["is_solo"]:
		var wid: String = spec["weapon_id"]
		return solo_profile(wid, String(SOLO_PERKS.get(wid, "perk_hp")))
	var mspec := RunAnalysis.mix_spec(name)
	if mspec["is_mix"]:
		var t: String = mspec["target"]
		return mix_profile(t, String(SOLO_PERKS.get(t, "perk_hp")))
	return PROFILES.get(name, DEFAULT_PROFILE)

# ── 运行时状态(Task 7 填充驱动逻辑;此处先声明,供其他文件引用) ────────────────
var active: bool = false                 # 是否 bot 模式(无 --bot 时恒 false → 全链路惰性)
var base_time_scale: float = 1.0         # 快进基线;game_feel hitstop 恢复到这里而非写死 1.0

# ── 纯静态决策函数(无场景依赖,单测覆盖) ──────────────────────────────────────

# kite 移动方向:Σ(远离半径内敌人,越近越强) + (拉回竞技场中心,避墙)。归一化;无净向量返回 ZERO。
static func compute_kite_dir(player_pos: Vector2, enemy_positions: Array, arena_center: Vector2, perception_radius: float) -> Vector2:
	var sorted_enemies := enemy_positions.duplicate()
	sorted_enemies.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)
	var repulse := Vector2.ZERO
	for ep in sorted_enemies:
		var to_player: Vector2 = player_pos - ep
		var d := to_player.length()
		if d > perception_radius or d <= 0.001:
			continue
		# 越近权重越大(d→0 时趋近 1,d→radius 时趋近 0)
		repulse += to_player.normalized() * (1.0 - d / perception_radius)
	var center_pull := (arena_center - player_pos) * CENTER_PULL_GAIN
	var dir := repulse + center_pull
	if dir.length() < 0.001:
		return Vector2.ZERO
	return dir.normalized()

# 躲弹方向:对半径内"正朝玩家飞来"的弹,沿垂直其弹道方向把玩家推离弹道线。
# projectiles: Array[{ "pos": Vector2, "vel": Vector2 }]。归一化;无净向量返回 ZERO。
# 求和前按位置 (x→y) 定序(C5:消除 get_nodes_in_group 顺序抖动 × 浮点加法非结合)。
static func compute_dodge_dir(player_pos: Vector2, projectiles: Array, dodge_radius: float) -> Vector2:
	var sorted_proj := projectiles.duplicate()
	sorted_proj.sort_custom(func(a, b):
		var pa: Vector2 = a["pos"]
		var pb: Vector2 = b["pos"]
		return pa.x < pb.x if pa.x != pb.x else pa.y < pb.y
	)
	var steer := Vector2.ZERO
	for pr in sorted_proj:
		var pos: Vector2 = pr["pos"]
		var vel: Vector2 = pr["vel"]
		var to_player := player_pos - pos
		var d := to_player.length()
		if d > dodge_radius or d <= 0.001:
			continue
		if vel.dot(to_player) <= 0.0:
			continue   # 远离或已掠过,不躲
		var vdir := vel.normalized()
		var lateral := to_player - vdir * to_player.dot(vdir)   # 玩家相对弹道线的横向偏移
		var side := lateral
		if side.length() < 0.001:
			side = Vector2(-vdir.y, vdir.x)   # 正中:确定性取一侧垂直
		steer += side.normalized() * (1.0 - d / dodge_radius)
	if steer.length() < 0.001:
		return Vector2.ZERO
	return steer.normalized()

# kite + dodge 加权合成,归一化;两者皆零返回 ZERO。
static func blend_move(kite: Vector2, dodge: Vector2, w_kite: float, w_dodge: float) -> Vector2:
	var v := kite * w_kite + dodge * w_dodge
	if v.length() < 0.001:
		return Vector2.ZERO
	return v.normalized()

# 从 offered 里按 profile 顺序取最高优先命中;无命中取第 0 张兜底(保证一定有解,防暂停卡死)。
static func choose_card(offered: Array, profile: Array) -> Dictionary:
	for matcher in profile:
		for card in offered:
			if _card_matches(card, String(matcher)):
				return card
	return offered[0] if not offered.is_empty() else {}

static func _card_matches(card: Dictionary, matcher: String) -> bool:
	if matcher.begins_with("type:"):
		return String(card.get("type", "")) == matcher.substr(5)
	return String(card.get("id", "")) == matcher

# ── 运行时状态(Task 7) ──────────────────────────────────────────────────────
var _bot_mode: String = "kite"
var _profile: Array = DEFAULT_PROFILE
var _cards_name_val: String = ""         # cfg["cards"] 原始值;solo_ 授武器用
var _out: String = "telemetry/run"
var _maxtime: float = 0.0                # 0 = 不设上限(只靠自然终局)
var _player: Player = null
var _arena_center: Vector2 = Vector2(640, 360)  # 1280×720 中心;_ready 再从 arena 校正
var _finished: bool = false
var _solo_weapon_granted: bool = false

# 命令行解析(纯函数,单测)。无 --bot → active=false。返回配置字典。
static func parse_args(user_args: Array) -> Dictionary:
	var cfg := {
		"active": false, "bot": "kite", "cards": "default",
		"seed": 0, "fast": DEFAULT_FAST, "out": "telemetry/run", "maxtime": 0.0,
	}
	for raw in user_args:
		var a := String(raw)
		if a == "--bot" or a.begins_with("--bot="):
			cfg["active"] = true
			if "=" in a:
				cfg["bot"] = a.split("=")[1]
		elif a.begins_with("--cards="):
			cfg["cards"] = a.split("=")[1]
		elif a.begins_with("--seed="):
			cfg["seed"] = int(a.split("=")[1])
		elif a.begins_with("--fast="):
			cfg["fast"] = float(a.split("=")[1])
		elif a.begins_with("--out="):
			cfg["out"] = a.split("=")[1]
		elif a.begins_with("--maxtime="):
			cfg["maxtime"] = float(a.split("=")[1])
	return cfg

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := parse_args(OS.get_cmdline_user_args())
	active = cfg["active"]
	if not active:
		return   # 真人模式:全惰性
	_bot_mode = cfg["bot"]
	_cards_name_val = cfg["cards"]
	_profile = profile_for(cfg["cards"])
	_out = cfg["out"]
	_maxtime = cfg["maxtime"]
	base_time_scale = cfg["fast"]
	seed(int(cfg["seed"]))                 # 早于任何 randi():首个 randi 在主场景 _ready 之后
	Engine.time_scale = base_time_scale
	GameManager.level_up_triggered.connect(_on_level_up)
	GameManager.victory_triggered.connect(func() -> void: _finish("victory"))
	GameManager.game_over_triggered.connect(func() -> void: _finish("death"))
	RunRecorder.begin(_out, DEFAULT_INTERVAL, {
		"bot": _bot_mode, "cards": cfg["cards"], "fast": base_time_scale,
		"seed": int(cfg["seed"]), "maxtime": _maxtime,
	})
	print("[RunHarness] bot=%s cards=%s seed=%d fast=%.1f out=%s maxtime=%.0f"
			% [_bot_mode, cfg["cards"], int(cfg["seed"]), base_time_scale, _out, _maxtime])

func _physics_process(_delta: float) -> void:
	if not active or _finished:
		return
	if GameManager.current_state != GameManager.State.PLAYING:
		return
	var p := _get_player()
	if p == null:
		return
	if _maxtime > 0.0 and DebugMetrics.get_elapsed() >= _maxtime:
		_finish("timeout")
		return
	if not _solo_weapon_granted:
		_solo_weapon_granted = true
		_grant_initial_loadout(p)
	p.bot_input = _compute_input(p)

func _compute_input(p: Player) -> Vector2:
	if _bot_mode == "still":
		return Vector2.ZERO
	var positions: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D:
			positions.append(e.global_position)
	var projectiles: Array = []
	for b in get_tree().get_nodes_in_group("enemy_projectiles"):
		if b is Node2D:
			projectiles.append({"pos": b.global_position, "vel": b.direction * b.SPEED})
	var kite := compute_kite_dir(p.global_position, positions, _arena_center, PERCEPTION_RADIUS)
	var dodge := compute_dodge_dir(p.global_position, projectiles, DODGE_RADIUS)
	return blend_move(kite, dodge, W_KITE, W_DODGE)

# 升级:唯一一次 pick → 按 profile 选 → apply → 通知 recorder → resume。
func _on_level_up() -> void:
	if _finished:
		return   # 终局帧可能仍有排队的升级信号:已 finalize/quit,不再选卡/翻状态(与 _physics_process/_finish 一致)
	var p := _get_player()
	if p == null:
		return
	var offered: Array = CardPool.pick(p)
	var picked := choose_card(offered, _profile)
	if picked.is_empty():
		GameManager.resume_game()
		return
	var offered_ids: Array = []
	for c in offered:
		offered_ids.append(c.get("id", ""))
	CardPool.apply(picked, p)
	RunRecorder.log_levelup(p.level, String(picked.get("id", "")), offered_ids)
	GameManager.resume_game()

func _finish(outcome: String) -> void:
	if _finished:
		return
	_finished = true
	RunRecorder.finalize(outcome)
	print("[RunHarness] 终局=%s,退出。" % outcome)
	get_tree().quit()

# 开局授予档位 loadout,使 bot 真正评估目标(否则随机卡池常不提供→饿死无解)。
# 按 cards 档名分流:solo_/solofloor_ → _grant_solo;mixbase/mix_ → _grant_mix;其余(默认档)不触发。
# 仅 bot 模式;按 id 授予(无 RNG,确定性)。
func _grant_initial_loadout(p: Player) -> void:
	if p == null:
		return
	var spec := solo_spec(_cards_name_val)
	if spec["is_solo"]:
		_grant_solo(p, spec)
		return
	var mspec := RunAnalysis.mix_spec(_cards_name_val)
	if mspec["is_mix"]:
		_grant_mix(p, mspec)

# 单武器档:授目标武器、移除外来武器、地板档加防御垫。
func _grant_solo(p: Player, spec: Dictionary) -> void:
	var wid: String = spec["weapon_id"]
	if wid == "":
		return
	# solo 隔离:移除所有非目标已持有武器(含 main.gd 默认授予的起手 knife),否则起手 knife 污染
	# build(knife_2/_3 就绪)。.keys() 是快照,迭代中 erase 安全。
	for owned_id in p.owned_weapons.keys():
		if owned_id != wid:
			var node = p.owned_weapons[owned_id].get("node")
			if is_instance_valid(node):
				node.queue_free()
			p.owned_weapons.erase(owned_id)
	if not p.has_weapon(wid):
		CardPool.apply({"id": wid}, p)   # 目标未持有才授予(solo_knife 时 knife 已在,避免重复 grant 泄漏旧节点)
	CardPool.banish_other_weapons(wid)   # 外来武器卡永不再被提供(防 choose_card offered[0] 兜底污染)
	# base 档(报告 §5①内容广度):banish 进化 → bot 永卡 base L3,隔离纯 base 武器清场强度。
	# 与 _grant_mix 底盘永不进化同机制:banished 进化被 ready_evolutions 守卫滤除 → 确定性投放不再占槽。
	if spec.get("is_base", false):
		CardPool.banish("evolve_" + wid)
	# 地板档:额外授纯防御垫(perk_hp 只加 HP 不加击杀 → kpm 仍单武器归属),让弱 solo 武器活到进化。
	if spec["is_floor"]:
		for _i in range(FLOOR_PERK_HP_STACKS):
			CardPool.apply({"id": "perk_hp"}, p)

# 混编档:授「底盘 + 目标」,移除其余武器,授底盘防御垫(A/B 两臂同垫 → delta 抵消)。
func _grant_mix(p: Player, mspec: Dictionary) -> void:
	var target: String = mspec["target"]
	var loadout := MIX_CHASSIS.duplicate()
	if target != "" and not loadout.has(target):
		loadout.append(target)
	for owned_id in p.owned_weapons.keys():
		if not loadout.has(owned_id):
			var node = p.owned_weapons[owned_id].get("node")
			if is_instance_valid(node):
				node.queue_free()
			p.owned_weapons.erase(owned_id)
	for wid in loadout:
		if not p.has_weapon(wid):
			CardPool.apply({"id": wid}, p)
	CardPool.banish_weapons_except(loadout)
	# 底盘永不进化:banish 其进化卡。确定性进化投放取就绪集 weapon-id 字典序第一个(card_pool.pick
	# L200/207),底盘若也就绪且字典序在目标前(实测 frostbite<knife)会永久占槽挡死目标进化——bot 的
	# mix_profile 只认 evolve_<target>,不会消费底盘进化 → 目标永不被投放。banish 底盘进化卡即解(被
	# ready_evolutions 的 _banished 守卫 L196 滤除)。仅 banish 进化,底盘武器本体仍可满级供控制/续航。
	for w in MIX_CHASSIS:
		CardPool.banish("evolve_" + w)
	for _i in range(MIX_CHASSIS_PERK_HP_STACKS):
		CardPool.apply({"id": "perk_hp"}, p)

func _get_player() -> Player:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	return _player
