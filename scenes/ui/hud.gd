# scenes/ui/hud.gd
extends CanvasLayer

@onready var hp_bar: ProgressBar = $HPBar
@onready var xp_bar: ProgressBar = $XPBar
@onready var timer_label: Label = $TimerLabel
@onready var level_label: Label = $LevelLabel

var _player: Player = null

func _ready() -> void:
	add_to_group("hud")
	_player = get_tree().get_first_node_in_group("player") as Player

func _process(_delta: float) -> void:
	if _player == null:
		return
	hp_bar.value = (_player.hp / _player.max_hp) * 100.0
	xp_bar.value = _player.get_xp_percent() * 100.0
	level_label.text = "Lv.%d" % _player.level
	var t := int(GameManager.elapsed_time)
	timer_label.text = "%02d:%02d" % [t / 60, t % 60]
