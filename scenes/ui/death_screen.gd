# scenes/ui/death_screen.gd
extends CanvasLayer

@onready var time_label: Label = $BG/Panel/TimeLabel
@onready var level_label: Label = $BG/Panel/LevelLabel
@onready var restart_btn: Button = $BG/Panel/RestartButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	GameManager.game_over_triggered.connect(_on_game_over)
	restart_btn.pressed.connect(GameManager.restart)

func _on_game_over() -> void:
	visible = true
	var player := get_tree().get_first_node_in_group("player") as Player
	level_label.text = "达到等级：%d" % player.level
	var t := int(GameManager.elapsed_time)
	time_label.text = "存活时长：%02d:%02d" % [t / 60, t % 60]
