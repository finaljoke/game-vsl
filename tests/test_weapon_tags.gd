# tests/test_weapon_tags.gd
# 锁定 11 基础 + 11 进化武器的元素标签(spec §5 权威映射)。
extends GdUnitTestSuite

const EXPECTED_TAGS := {
	"knife": [&"physical"],
	"whip": [&"physical", &"fire"],
	"boomerang": [&"physical"],
	"maul": [&"physical", &"ice", &"lightning"],
	"orb": [&"physical"],
	"explosion": [&"fire"],
	"aura": [&"fire"],
	"lightning": [&"lightning"],
	"frostbite": [&"ice"],
	"gravity_well": [&"gravity", &"ice"],
	"reanimate": [&"summon"],
	"thousand_edge": [&"physical"],
	"bloody_whip": [&"physical", &"fire"],
	"cyclone": [&"physical"],
	"earthshatter": [&"physical", &"ice", &"lightning"],
	"mega_orb": [&"physical"],
	"nuke": [&"fire"],
	"inferno_aura": [&"fire"],
	"thunderstorm": [&"lightning"],
	"blizzard": [&"ice"],
	"singularity": [&"gravity", &"ice"],
	"horde": [&"summon"],
}

func test_all_weapons_have_expected_tags() -> void:
	for id in EXPECTED_TAGS:
		var data := WeaponDB.get_data(id)
		assert_object(data).override_failure_message("缺武器数据 %s" % id).is_not_null()
		for tag in EXPECTED_TAGS[id]:
			assert_bool(data.tags.has(tag)) \
				.override_failure_message("%s 缺标签 %s" % [id, tag]).is_true()
