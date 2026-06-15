# scenes/ui/hud.gd
extends CanvasLayer

@onready var hp_bar: ProgressBar = $HPBar
@onready var xp_bar: ProgressBar = $XPBar
@onready var timer_label: Label = $TimerLabel
@onready var level_label: Label = $LevelLabel
@onready var _gm = get_node("/root/GameManager")

var _player: Player = null
var _kills: int = 0
var _kill_label: Label = null

func _ready() -> void:
	add_to_group("hud")
	_player = get_tree().get_first_node_in_group("player") as Player
	GameFeel.boss_incoming.connect(_show_boss_warning)
	# 击杀数：代码内建一个 Label(免改 .tscn)，监听 enemy_died 累加，给"积累感"+第二目标。
	_kill_label = Label.new()
	_kill_label.add_theme_font_size_override("font_size", 16)
	_kill_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_kill_label.add_theme_constant_override("outline_size", 4)
	_kill_label.position = Vector2(10.0, 36.0)  # HP 条(10,10~30)正下方
	add_child(_kill_label)
	GameFeel.enemy_died.connect(_on_enemy_killed)

func _on_enemy_killed(_position: Vector2, _enemy: Node2D) -> void:
	_kills += 1

func _process(_delta: float) -> void:
	if _player == null:
		return
	hp_bar.value = (_player.hp / _player.max_hp) * 100.0
	xp_bar.value = _player.get_xp_percent() * 100.0
	level_label.text = "Lv.%d" % _player.level
	var t := int(_gm.elapsed_time)
	timer_label.text = "%02d:%02d" % [t / 60, t % 60]
	if _kill_label != null:
		_kill_label.text = "击杀 %d" % _kills

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
