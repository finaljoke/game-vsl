# scenes/ui/level_up_ui.gd
extends CanvasLayer

@onready var card_container: HBoxContainer = $BG/Panel/CardContainer
@onready var _panel: VBoxContainer = $BG/Panel
@onready var _gm = get_node("/root/GameManager")

const COLORS := {
	"weapon": Color(0x4a9effff),
	"upgrade": Color(0xf5a623ff),
	"perk": Color(0x50fa7bff),
	"evolution": Color(0xbd93f9ff),
	"synergy": Color(0xff79c6ff),
}
const TYPE_LABELS := {
	"weapon": "新武器",
	"upgrade": "★ 强化",
	"perk": "属性",
	"evolution": "✦ 进化",
	"synergy": "◈ 协同",
}
# 稀有度 → 边框颜色/粗细(给"强卡稀有感"的视觉锚)
const RARITY_COLORS := {
	"common": Color(0.72, 0.72, 0.72),
	"uncommon": Color(0.30, 0.80, 1.0),
	"rare": Color(0.75, 0.45, 1.0),
	"legendary": Color(1.0, 0.65, 0.15),
}
const RARITY_BORDER := {"common": 1, "uncommon": 2, "rare": 3, "legendary": 4}

var _player: Player = null
var _current_cards: Array = []
var _footer: HBoxContainer = null
var _reroll_btn: Button = null
var _token_label: Label = null
var _skip_btn: Button = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_gm.level_up_triggered.connect(_on_level_up)
	_gm.game_over_triggered.connect(func() -> void: visible = false)
	_gm.victory_triggered.connect(func() -> void: visible = false)
	_build_footer()

# 重抽/ban 页脚：重抽券>0 时可用(代码内建，免改 .tscn)
func _build_footer() -> void:
	_footer = HBoxContainer.new()
	_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	_footer.add_theme_constant_override("separation", 16)
	_panel.add_child(_footer)

	_reroll_btn = Button.new()
	_reroll_btn.text = "重抽"
	_reroll_btn.pressed.connect(_on_reroll)
	_footer.add_child(_reroll_btn)

	_token_label = Label.new()
	_token_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	_footer.add_child(_token_label)

	_skip_btn = Button.new()
	_skip_btn.text = "跳过 (+1 券)"
	_skip_btn.pressed.connect(_on_skip)
	_footer.add_child(_skip_btn)

	var hint := Label.new()
	hint.text = "(右键卡牌 = 永久 Ban，各消耗 1 券)"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_footer.add_child(hint)

func _on_level_up() -> void:
	# bot 模式:选卡由 RunHarness 单点解决(唯一一次 pick)。UI 早退,避免第二次 pick() 破坏种子复现。
	if RunHarness.active:
		return
	visible = true
	_player = get_tree().get_first_node_in_group("player") as Player
	_current_cards = CardPool.pick(_player)
	_build_cards(_current_cards)
	_update_footer()

func _update_footer() -> void:
	if _player == null:
		return
	var tokens: int = _player.reroll_tokens
	_token_label.text = "重抽券 ×%d" % tokens
	_reroll_btn.disabled = tokens <= 0

func _on_reroll() -> void:
	if _player == null or _player.reroll_tokens <= 0:
		return
	_player.reroll_tokens -= 1
	_current_cards = CardPool.pick(_player)
	_build_cards(_current_cards)
	_update_footer()

# Skip：放弃整轮三选一，换小额回报(+1 重抽券，永不浪费)。
# 回报 < 一张普通卡期望，故是"这轮没好牌"的逃生口，而非常态最优(spec 单元3)。
func skip_reward(player: Player) -> void:
	player.reroll_tokens += 1

func _on_skip() -> void:
	if _player == null:
		return
	skip_reward(_player)
	visible = false
	_gm.resume_game()

func _on_card_banished(card: Dictionary) -> void:
	if _player == null or _player.reroll_tokens <= 0:
		return
	_player.reroll_tokens -= 1
	CardPool.banish(String(card["id"]))
	_current_cards = CardPool.pick(_player)
	_build_cards(_current_cards)
	_update_footer()

func _build_cards(cards: Array) -> void:
	for child in card_container.get_children():
		child.queue_free()
	for card in cards:
		card_container.add_child(_make_card(card))

func _make_card(card: Dictionary) -> Control:
	var color: Color = COLORS[card["type"]]
	var rarity := String(card.get("rarity", "common"))
	var rcolor: Color = RARITY_COLORS.get(rarity, Color(0.72, 0.72, 0.72))

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(160, 180)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0x16213eff)
	# 边框按稀有度上色/加粗，顶部色条仍按卡型 → 一眼区分 强弱 + 类别
	style.set_border_width_all(int(RARITY_BORDER.get(rarity, 1)))
	style.border_color = rcolor
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

	var icon_tex: Texture2D = CardPool.card_icon(card)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.custom_minimum_size = Vector2(0, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(icon)

	var type_lbl := Label.new()
	type_lbl.text = TYPE_LABELS[card["type"]]
	type_lbl.add_theme_color_override("font_color", color)
	type_lbl.add_theme_font_size_override("font_size", 12)
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
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(desc_lbl)

	if card["type"] == "upgrade":
		panel.scale = Vector2(1.08, 1.08)
	elif card["type"] == "evolution":
		panel.scale = Vector2(1.12, 1.12)

	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_on_card_picked(card)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_on_card_banished(card)
	)

	return panel

func _on_card_picked(card: Dictionary) -> void:
	visible = false
	var player := get_tree().get_first_node_in_group("player") as Player
	CardPool.apply(card, player)
	GameFeel.item_selected.emit()
	_gm.resume_game()
