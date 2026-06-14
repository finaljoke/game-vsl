# scenes/ui/hud.gd
extends CanvasLayer

@onready var hp_bar: ProgressBar = $HPBar
@onready var xp_bar: ProgressBar = $XPBar
@onready var timer_label: Label = $TimerLabel
@onready var level_label: Label = $LevelLabel
@onready var _gm = get_node("/root/GameManager")

var _player: Player = null

func _ready() -> void:
	add_to_group("hud")
	_player = get_tree().get_first_node_in_group("player") as Player
	GameFeel.boss_incoming.connect(_show_boss_warning)

func _process(_delta: float) -> void:
	if _player == null:
		return
	hp_bar.value = (_player.hp / _player.max_hp) * 100.0
	xp_bar.value = _player.get_xp_percent() * 100.0
	level_label.text = "Lv.%d" % _player.level
	var t := int(_gm.elapsed_time)
	timer_label.text = "%02d:%02d" % [t / 60, t % 60]

# Spawner 在 boss 登场前 BOSS_WARNING_LEAD 秒触发，3 秒后自销毁。
func _show_boss_warning() -> void:
	var label := Label.new()
	label.text = "⚠ BOSS 来袭"
	label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", 48)
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position = Vector2(-180.0, 60.0)  # 抵消 label 自身宽度近似居中
	label.size = Vector2(360.0, 64.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	var blink := create_tween().bind_node(label).set_loops(5)
	blink.tween_property(label, "modulate:a", 0.3, 0.3)
	blink.tween_property(label, "modulate:a", 1.0, 0.3)
	blink.finished.connect(func() -> void:
		if is_instance_valid(label):
			label.queue_free())
