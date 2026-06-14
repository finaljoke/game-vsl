# autoloads/game_manager.gd
extends Node

enum State { PLAYING, LEVEL_UP, DEAD }

signal level_up_triggered
signal game_over_triggered

var current_state: State = State.PLAYING
var elapsed_time: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if current_state == State.PLAYING:
		elapsed_time += delta

func trigger_level_up() -> void:
	if current_state != State.PLAYING:
		return
	current_state = State.LEVEL_UP
	get_tree().paused = true
	level_up_triggered.emit()

func resume_game() -> void:
	current_state = State.PLAYING
	get_tree().paused = false

func game_over() -> void:
	if current_state == State.DEAD:
		return
	current_state = State.DEAD
	game_over_triggered.emit()

func restart() -> void:
	elapsed_time = 0.0
	current_state = State.PLAYING
	get_tree().paused = false
	get_tree().reload_current_scene()
