# scenes/ui/level_up_ui.gd
extends CanvasLayer

const WEAPON_REGISTRY: Array[Dictionary] = [
	{
		"id": "knife",
		"name": "飞刀",
		"desc": "朝最近敌人射出飞刀",
		"scene": "res://scenes/weapons/knife/knife_weapon.tscn"
	},
	{
		"id": "orb",
		"name": "护盾球",
		"desc": "绕身旋转的能量球",
		"scene": "res://scenes/weapons/orb/orb_weapon.tscn"
	},
	{
		"id": "explosion",
		"name": "爆炸",
		"desc": "随机位置触发范围爆炸",
		"scene": "res://scenes/weapons/explosion/explosion_weapon.tscn"
	}
]

@onready var card_container: HBoxContainer = $BG/Panel/CardContainer
@onready var _gm = get_node("/root/GameManager")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_gm.level_up_triggered.connect(_on_level_up)

func _on_level_up() -> void:
	visible = true
	_build_cards()

func _build_cards() -> void:
	for child in card_container.get_children():
		child.queue_free()
	for data in WEAPON_REGISTRY:
		var btn := Button.new()
		btn.text = "%s\n%s" % [data["name"], data["desc"]]
		btn.custom_minimum_size = Vector2(160, 100)
		btn.pressed.connect(_on_weapon_picked.bind(data["scene"]))
		card_container.add_child(btn)

func _on_weapon_picked(scene_path: String) -> void:
	visible = false
	GameFeel.item_selected.emit()
	var player := get_tree().get_first_node_in_group("player") as Player
	player.add_weapon(load(scene_path))
	_gm.resume_game()
