extends GdUnitTestSuite
## 武器视觉重做：新导入的 Tiny Dungeon 武器精灵可正常 load(确认拷入 + import 成功)。

func test_weapon_sprites_imported() -> void:
	assert_object(load("res://assets/sprites/kenney/weapons/axe.png")).is_not_null()
	assert_object(load("res://assets/sprites/kenney/weapons/hammer.png")).is_not_null()
