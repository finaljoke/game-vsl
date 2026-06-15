# autoloads/game_manager.gd
extends Node

enum State { PLAYING, LEVEL_UP, DEAD }

const WIN_TIME: float = 600.0  # 10 分钟生存即胜利

signal level_up_triggered
signal game_over_triggered
signal victory_triggered

var current_state: State = State.PLAYING
var elapsed_time: float = 0.0
var _pending_level_ups: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if current_state == State.PLAYING:
		elapsed_time += delta
		if elapsed_time >= WIN_TIME:
			_win()

func trigger_level_up() -> void:
	_pending_level_ups += 1
	if current_state == State.PLAYING:
		_start_level_up()

func _start_level_up() -> void:
	if _pending_level_ups <= 0:
		return
	current_state = State.LEVEL_UP
	get_tree().paused = true
	level_up_triggered.emit()

func resume_game() -> void:
	_pending_level_ups = max(0, _pending_level_ups - 1)
	current_state = State.PLAYING
	if _pending_level_ups > 0:
		_start_level_up()
	else:
		get_tree().paused = false

func game_over() -> void:
	if current_state == State.DEAD:
		return
	current_state = State.DEAD
	_pending_level_ups = 0
	get_tree().paused = true
	game_over_triggered.emit()

# 供 spawner 在终局 Boss 被击杀时调用 → 直接通关(不必等 WIN_TIME)。
func trigger_victory() -> void:
	_win()

func _win() -> void:
	if current_state == State.DEAD:
		return
	current_state = State.DEAD
	_pending_level_ups = 0
	get_tree().paused = true
	victory_triggered.emit()

func restart() -> void:
	elapsed_time = 0.0
	current_state = State.PLAYING
	_pending_level_ups = 0
	get_tree().paused = false
	get_tree().reload_current_scene()
