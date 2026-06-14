# scenes/ui/level_up_ui.gd
extends CanvasLayer

@onready var card_container: HBoxContainer = $BG/Panel/CardContainer
@onready var _gm = get_node("/root/GameManager")

const COLORS := {
	"weapon": Color(0x4a9effff),
	"upgrade": Color(0xf5a623ff),
	"perk": Color(0x50fa7bff),
}
const TYPE_LABELS := {
	"weapon": "新武器",
	"upgrade": "★ 强化",
	"perk": "属性",
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_gm.level_up_triggered.connect(_on_level_up)

func _on_level_up() -> void:
	visible = true
	var player := get_tree().get_first_node_in_group("player") as Player
	_build_cards(CardPool.pick(player))

func _build_cards(cards: Array) -> void:
	for child in card_container.get_children():
		child.queue_free()
	for card in cards:
		card_container.add_child(_make_card(card))

func _make_card(card: Dictionary) -> Control:
	var color: Color = COLORS[card["type"]]

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(160, 180)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0x16213eff)
	style.set_border_width_all(1)
	style.border_color = color
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(0, 3)
	bar.color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bar)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 8)
	vbox.add_child(margin)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 4)
	margin.add_child(content)

	var type_lbl := Label.new()
	type_lbl.text = TYPE_LABELS[card["type"]]
	type_lbl.add_theme_color_override("font_color", color)
	type_lbl.add_theme_font_size_override("font_size", 10)
	type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(type_lbl)

	var name_lbl := Label.new()
	name_lbl.text = card["name"]
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = card["desc"]
	desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(desc_lbl)

	if card["type"] == "upgrade":
		panel.scale = Vector2(1.04, 1.04)

	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_on_card_picked(card)
	)

	return panel

func _on_card_picked(card: Dictionary) -> void:
	visible = false
	var player := get_tree().get_first_node_in_group("player") as Player
	CardPool.apply(card, player)
	GameFeel.item_selected.emit()
	_gm.resume_game()
