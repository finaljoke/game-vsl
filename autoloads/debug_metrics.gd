# autoloads/debug_metrics.gd
# 平衡观测仪表(可移除)。订阅 GameFeel 信号,维护「进攻轴 + 威胁轴」两套累计值,
# 每 LOG_INTERVAL 秒打印一行聚合;并对外暴露 getters/snapshot(供 RunRecorder 落盘)
# 及 Performance 自定义监视器(编辑器 Debugger→Monitors 实时看图)。本身不改任何数值。
#
# 移除方式:删本文件 + 去掉 project.godot [autoload] 里的 DebugMetrics 行即可。
extends Node

const ENABLED: bool = true          # 关闭即惰性(不订阅、不打印)
const LOG_INTERVAL: float = 5.0     # 聚合打印周期(秒,按游戏内 PLAYING 时间)
const SHOW_OVERLAY: bool = false    # 额外在屏幕左上角显示实时面板
const DANGER_THRESHOLD: float = 0.25  # hp_pct 低于此判定"危险"
const NEAR_RADIUS: float = 140.0    # enemies_near 统计半径(px)

# ── 进攻轴累计 ──────────────────────────────────────────────────────────────
var _kills_total: int = 0
var _dmg_dealt_total: float = 0.0
var _healed_total: float = 0.0
var _levelups_total: int = 0
var _level: int = 1
# ── 威胁轴累计 ──────────────────────────────────────────────────────────────
var _dmg_taken_total: float = 0.0
var _danger_total: float = 0.0      # hp_pct<阈值 的累计游戏秒
var _hp: float = 0.0
var _hp_pct: float = 1.0
var _hp_pct_min: float = 1.0
# ── 窗口(每 interval 重置,仅给控制台行) ─────────────────────────────────────
var _kills_window: int = 0
var _healed_window: float = 0.0
var _dmg_taken_window: float = 0.0
# ── 计时(仅 PLAYING 态累加,避免选卡暂停污染速率) ────────────────────────────
var _elapsed: float = 0.0
var _since_log: float = 0.0
var _last_levelup_t: float = 0.0

var _player_node: Player = null
var _overlay: Label = null

func _ready() -> void:
	if not ENABLED:
		set_process(false)
		return
	# 选卡时 get_tree().paused=true;用 ALWAYS 让仪表自身不被暂停(再靠状态门控速率)。
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameFeel.enemy_hit.connect(_on_enemy_hit)
	GameFeel.enemy_died.connect(_on_enemy_died)
	GameFeel.player_hit.connect(_on_player_hit)
	GameFeel.player_leveled_up.connect(_on_player_leveled_up)
	GameFeel.player_healed.connect(_on_player_healed)
	_register_monitors()
	if SHOW_OVERLAY:
		_setup_overlay()
	print("[DebugMetrics] ON — 每 %.0fs 聚合一次(进攻+威胁两轴)" % LOG_INTERVAL)

# 清零所有累计(供测试/重开)。
func reset_metrics() -> void:
	_kills_total = 0
	_dmg_dealt_total = 0.0
	_healed_total = 0.0
	_levelups_total = 0
	_level = 1
	_dmg_taken_total = 0.0
	_danger_total = 0.0
	_hp = 0.0
	_hp_pct = 1.0
	_hp_pct_min = 1.0
	_kills_window = 0
	_healed_window = 0.0
	_dmg_taken_window = 0.0
	_elapsed = 0.0
	_since_log = 0.0
	_last_levelup_t = 0.0

# ── 信号处理 ────────────────────────────────────────────────────────────────
# channel 形参带默认值：DIRECT/DOT 都累计(DoT 伤害继续计入遥测)，且让既有 3 参直调测试不破。
func _on_enemy_hit(amount: float, _position: Vector2 = Vector2.ZERO, _enemy: Node2D = null, _channel: int = 0) -> void:
	_dmg_dealt_total += amount

func _on_enemy_died(_position: Vector2, _enemy: Node2D) -> void:
	_kills_total += 1
	_kills_window += 1

func _on_player_hit(amount: float) -> void:
	_dmg_taken_total += amount
	_dmg_taken_window += amount

func _on_player_healed(amount: float) -> void:
	_healed_total += amount
	_healed_window += amount

func _on_player_leveled_up(level: int) -> void:
	_levelups_total += 1
	_level = level
	var gap := _elapsed - _last_levelup_t
	_last_levelup_t = _elapsed
	print("[DebugMetrics] 升级 → Lv%d  距上次 %.1fs (t=%.0fs)" % [level, gap, _elapsed])

# ── 每帧:轮询 HP + 累计危险/最低血(仅 PLAYING) ────────────────────────────
func _process(delta: float) -> void:
	if not _is_playing():
		return
	_elapsed += delta
	_since_log += delta
	var p := _get_player()
	if p != null:
		_sample_hp(p.hp, p.max_hp, delta)
	if _since_log >= LOG_INTERVAL:
		_log_aggregate()
		_since_log = 0.0
		_kills_window = 0
		_healed_window = 0.0
		_dmg_taken_window = 0.0
	if _overlay != null:
		_overlay.text = _overlay_text()

# HP 采样(纯逻辑,便于单测):更新当前血量/百分比,累计危险时长与最低血。
func _sample_hp(hp: float, max_hp: float, delta: float) -> void:
	_hp = hp
	_hp_pct = (hp / max_hp) if max_hp > 0.0 else 0.0
	if _hp_pct < _hp_pct_min:
		_hp_pct_min = _hp_pct
	if _hp_pct < DANGER_THRESHOLD:
		_danger_total += delta

# ── getters / snapshot(供 RunRecorder) ─────────────────────────────────────
func get_kills_total() -> int: return _kills_total
func get_dmg_dealt_total() -> float: return _dmg_dealt_total
func get_dmg_taken_total() -> float: return _dmg_taken_total
func get_healed_total() -> float: return _healed_total
func get_danger_total() -> float: return _danger_total
func get_hp() -> float: return _hp
func get_hp_pct() -> float: return _hp_pct
func get_hp_pct_min() -> float: return _hp_pct_min
func get_level() -> int: return _level
func get_elapsed() -> float: return _elapsed

func get_enemies_alive() -> int:
	return get_tree().get_nodes_in_group("enemies").size()

func get_enemies_near() -> int:
	var p := _get_player()
	if p == null:
		return 0
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D and p.global_position.distance_to(e.global_position) <= NEAR_RADIUS:
			n += 1
	return n

func snapshot() -> Dictionary:
	return {
		"kills_total": _kills_total,
		"dmg_dealt_total": _dmg_dealt_total,
		"dmg_taken_total": _dmg_taken_total,
		"healed_total": _healed_total,
		"danger_total": _danger_total,
		"hp": _hp,
		"hp_pct": _hp_pct,
		"hp_pct_min": _hp_pct_min,
		"level": _level,
		"enemies_alive": get_enemies_alive(),
		"enemies_near": get_enemies_near(),
	}

# ── Performance 自定义监视器(编辑器实时看图;headless 无害) ────────────────────
func _register_monitors() -> void:
	_add_monitor("vsl/kills_total", get_kills_total)
	_add_monitor("vsl/dmg_taken_total", get_dmg_taken_total)
	_add_monitor("vsl/hp_pct", get_hp_pct)
	_add_monitor("vsl/enemies_near", get_enemies_near)

func _add_monitor(id: String, callable: Callable) -> void:
	if not Performance.has_custom_monitor(id):
		Performance.add_custom_monitor(id, callable)

# ── 控制台聚合行(进攻 + 威胁) ───────────────────────────────────────────────
func _log_aggregate() -> void:
	var kps := float(_kills_window) / LOG_INTERVAL
	var dmg_taken_ps := _dmg_taken_window / LOG_INTERVAL
	var heal_ps := _healed_window / LOG_INTERVAL
	var lvl_pm := (float(_levelups_total) / _elapsed * 60.0) if _elapsed > 0.0 else 0.0
	print("[DebugMetrics] t=%5.0fs | 击杀 %.1f/s(累计%d) | 升级 %.2f/min | 受伤 %.1f/s | HP %.0f%%(最低%.0f%%) | 嗜血 %.2f/s | tscale %.2f"
			% [_elapsed, kps, _kills_total, lvl_pm, dmg_taken_ps, _hp_pct * 100.0, _hp_pct_min * 100.0, heal_ps, Engine.time_scale])

func _is_playing() -> bool:
	return GameManager.current_state == GameManager.State.PLAYING

func _get_player() -> Player:
	if _player_node == null or not is_instance_valid(_player_node):
		_player_node = get_tree().get_first_node_in_group("player") as Player
	return _player_node

func _overlay_text() -> String:
	return "t=%.0fs\nkills %d\nhp %.0f%% (min %.0f%%)\ndmg_taken %.0f\nnear %d\ntscale %.2f" % [
			_elapsed, _kills_total, _hp_pct * 100.0, _hp_pct_min * 100.0,
			_dmg_taken_total, get_enemies_near(), Engine.time_scale]

func _setup_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 11
	add_child(canvas)
	_overlay = Label.new()
	_overlay.position = Vector2(8, 8)
	_overlay.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_overlay.add_theme_constant_override("outline_size", 3)
	_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	canvas.add_child(_overlay)
