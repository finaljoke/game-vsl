# tests/test_level_up_ui.gd
extends GdUnitTestSuite

const LevelUpUiScript := preload("res://scenes/ui/level_up_ui.gd")

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

# 仅实例化脚本、不加入场景树 → _ready 不触发(避开 GameManager 自动加载与 @onready 节点依赖)。
# 被测方法只读写 player，无需场景。
func _make_ui() -> Object:
	return auto_free(LevelUpUiScript.new())

func test_skip_reward_grants_one_token() -> void:
	var ui := _make_ui()
	var before: int = _player.reroll_tokens
	ui.skip_reward(_player)
	assert_int(_player.reroll_tokens).is_equal(before + 1)
