extends GdUnitTestSuite

# 代表性抽样：每个导入目录至少验一张，确认拷入 + import 成功。
func test_particle_pack_imported() -> void:
	assert_object(load("res://assets/sprites/kenney/particles/pack/circle_03.png")).is_not_null()
	assert_object(load("res://assets/sprites/kenney/particles/pack/twirl_01.png")).is_not_null()
	assert_object(load("res://assets/sprites/kenney/particles/pack/flame_01.png")).is_not_null()
	assert_object(load("res://assets/sprites/kenney/particles/pack/slash_01.png")).is_not_null()

func test_explosion_frames_imported() -> void:
	assert_object(load("res://assets/sprites/kenney/explosions/regularExplosion00.png")).is_not_null()
	assert_object(load("res://assets/sprites/kenney/explosions/sonicExplosion00.png")).is_not_null()
	assert_object(load("res://assets/sprites/kenney/explosions/groundExplosion00.png")).is_not_null()

func test_smoke_and_runes_imported() -> void:
	assert_object(load("res://assets/sprites/kenney/smoke/whitePuff00.png")).is_not_null()
	assert_object(load("res://assets/sprites/kenney/runes/runeBlue_tile_001.png")).is_not_null()
