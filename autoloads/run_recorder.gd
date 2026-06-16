# autoloads/run_recorder.gd
# 纯序列化单元。RunHarness 调 begin() 启动;之后每 interval 把 DebugMetrics.snapshot() 差分成一行
# tick CSV,并订阅离散事件写 event JSONL;终局 RunHarness 调 finalize() 写 summary.json 并关文件。
# 不启用(begin 未调用)时不开任何文件、信号处理器全部 no-op。
extends Node

# tick CSV 列顺序(与 format_row 入参顺序严格对应)。
const TICK_COLUMNS: Array = [
	"t", "level", "kills_total", "kills_ps", "dmg_dealt_ps", "dmg_taken_ps",
	"hp", "hp_pct", "danger_ps", "enemies_alive", "enemies_near", "healed_ps", "time_scale",
]
# 只把"显著"受击写进 event log。接触伤害每物理帧 emit 一次 player_hit(~60/s,每次极小),
# 若全写会让 events 膨胀到十万行;阈值过滤后只留弹道/爆炸等爆发威胁(定位"因"的有用标记)。
# 接触 trickle 的总量仍由 tick CSV 的 dmg_taken_ps 曲线完整反映,不丢信息。
const PLAYER_HIT_LOG_MIN: float = 5.0

var _recording: bool = false
var _base_path: String = ""
var _csv: FileAccess = null
var _events: FileAccess = null
var _interval: float = 1.0
var _elapsed: float = 0.0          # 游戏秒(仅 PLAYING 累加)
var _since_tick: float = 0.0
var _prev: Dictionary = {}         # 上 tick 的 snapshot(差分算 /s)
var _prev_t: float = 0.0
var _config: Dictionary = {}
var _build: Array = []             # 选卡序列(picked id),写进 summary.build
var _hp_pct_sum: float = 0.0       # hp_pct 累加(算 summary.hp_pct_avg)
var _hp_pct_n: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 订阅自身能独立采的事件(其余由 RunHarness 主动喂)。未 recording 时处理器 no-op。
	GameFeel.player_hit.connect(_on_player_hit)
	GameFeel.boss_incoming.connect(_on_boss_incoming)

# ── 纯静态(单测) ───────────────────────────────────────────────────────────
static func tick_header() -> String:
	return ",".join(TICK_COLUMNS)

static func format_row(values: Array) -> String:
	var parts: Array = []
	for v in values:
		parts.append(str(v))
	return ",".join(parts)

# 相对名补 res:// 前缀;已带 res://|user:// 的保持。
static func resolve_base_path(out: String) -> String:
	if out.begins_with("res://") or out.begins_with("user://"):
		return out
	return "res://" + out

# ── 生命周期(RunHarness 调用) ───────────────────────────────────────────────
func begin(out: String, interval: float, config: Dictionary) -> void:
	# 重入守卫:已在记录时再次 begin 会覆写 _csv/_events 句柄而不关闭旧的 → 缓冲丢失/句柄泄漏。
	# 管线本只调一次,这里兜底防 footgun;要重开请先 finalize()。
	if _recording:
		push_warning("RunRecorder.begin() 在记录中被再次调用 — 已忽略;请先 finalize()。")
		return
	_base_path = resolve_base_path(out)
	_interval = interval
	_config = config
	_ensure_dir(_base_path)
	_csv = FileAccess.open(_base_path + ".tick.csv", FileAccess.WRITE)
	if _csv != null:
		_csv.store_line(tick_header())
	_events = FileAccess.open(_base_path + ".events.jsonl", FileAccess.WRITE)
	_prev = DebugMetrics.snapshot()
	_prev_t = 0.0
	_elapsed = 0.0
	_since_tick = 0.0
	_recording = true

func _ensure_dir(base_path: String) -> void:
	var abs := ProjectSettings.globalize_path(base_path)
	var dir := abs.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)

func _process(delta: float) -> void:
	if not _recording or not _is_playing():
		return
	_elapsed += delta
	_since_tick += delta
	if _since_tick >= _interval:
		_write_tick()
		_since_tick = 0.0

func _write_tick() -> void:
	var s := DebugMetrics.snapshot()
	var dt := maxf(_elapsed - _prev_t, 0.001)
	var kills_ps := (float(s["kills_total"]) - float(_prev["kills_total"])) / dt
	var dmg_dealt_ps := (float(s["dmg_dealt_total"]) - float(_prev["dmg_dealt_total"])) / dt
	var dmg_taken_ps := (float(s["dmg_taken_total"]) - float(_prev["dmg_taken_total"])) / dt
	var healed_ps := (float(s["healed_total"]) - float(_prev["healed_total"])) / dt
	var danger_ps := (float(s["danger_total"]) - float(_prev["danger_total"])) / dt
	var row := format_row([
		"%.1f" % _elapsed,
		int(s["level"]),
		int(s["kills_total"]),
		"%.2f" % kills_ps,
		"%.2f" % dmg_dealt_ps,
		"%.2f" % dmg_taken_ps,
		"%.1f" % float(s["hp"]),
		"%.3f" % float(s["hp_pct"]),
		"%.3f" % danger_ps,
		int(s["enemies_alive"]),
		int(s["enemies_near"]),
		"%.2f" % healed_ps,
		"%.2f" % Engine.time_scale,
	])
	if _csv != null:
		_csv.store_line(row)
	_hp_pct_sum += float(s["hp_pct"])
	_hp_pct_n += 1
	_prev = s
	_prev_t = _elapsed

# ── 事件(部分自订阅,部分 RunHarness 主动喂) ────────────────────────────────
func log_levelup(level: int, picked_id: String, offered_ids: Array) -> void:
	_build.append(picked_id)
	_write_event({"type": "level_up", "level": level, "picked": picked_id, "offered": offered_ids})

func _on_player_hit(amount: float) -> void:
	if not _recording or amount < PLAYER_HIT_LOG_MIN:
		return   # 接触 trickle(每帧极小)不写,只留显著爆发威胁;总量靠 CSV dmg_taken_ps
	_write_event({"type": "player_hit", "amount": amount,
			"hp_after": DebugMetrics.get_hp(), "enemies_near": DebugMetrics.get_enemies_near()})

func _on_boss_incoming() -> void:
	if not _recording:
		return
	_write_event({"type": "boss_incoming"})

func _write_event(data: Dictionary) -> void:
	if _events == null:
		return
	data["t"] = snappedf(_elapsed, 0.1)
	_events.store_line(JSON.stringify(data))

# 终局:写 summary.json,关文件,停止记录。outcome ∈ {victory, death, timeout}。
func finalize(outcome: String) -> void:
	if not _recording:
		return
	_write_event({"type": outcome, "level": DebugMetrics.get_level()})
	var summary := {
		"outcome": outcome,
		"survived_s": snappedf(_elapsed, 0.1),
		"final_level": DebugMetrics.get_level(),
		"kills": DebugMetrics.get_kills_total(),
		"dmg_dealt_total": snappedf(DebugMetrics.get_dmg_dealt_total(), 0.1),
		"dmg_taken_total": snappedf(DebugMetrics.get_dmg_taken_total(), 0.1),
		"hp_pct_avg": snappedf(_hp_pct_sum / maxi(_hp_pct_n, 1), 0.001),
		"hp_pct_min": snappedf(DebugMetrics.get_hp_pct_min(), 0.001),
		"danger_total_s": snappedf(DebugMetrics.get_danger_total(), 0.1),
		"build": _build,
		"seed": _config.get("seed", 0),
		"config": _config,
	}
	var f := FileAccess.open(_base_path + ".summary.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(summary, "\t"))
		f.close()
	if _csv != null:
		_csv.close()
		_csv = null
	if _events != null:
		_events.close()
		_events = null
	_recording = false

func _is_playing() -> bool:
	return GameManager.current_state == GameManager.State.PLAYING
