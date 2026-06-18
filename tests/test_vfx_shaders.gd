extends GdUnitTestSuite

func _uniform_names(path: String) -> Array:
	var sh := load(path) as Shader
	if sh == null:
		return []
	var names: Array = []
	for u in sh.get_shader_uniform_list():
		names.append(u["name"])
	return names

func test_fire_shader_loads_with_uniforms() -> void:
	assert_object(load("res://shaders/fire_distort.gdshader")).is_not_null()
	assert_array(_uniform_names("res://shaders/fire_distort.gdshader")).contains(["speed", "tint"])

func test_ice_shader_loads_with_uniforms() -> void:
	assert_array(_uniform_names("res://shaders/ice_edge.gdshader")).contains(["edge_color", "rim"])

func test_electric_shader_loads_with_uniforms() -> void:
	assert_array(_uniform_names("res://shaders/electric_jitter.gdshader")).contains(["jitter", "speed"])

func test_summon_shader_loads_with_uniforms() -> void:
	assert_array(_uniform_names("res://shaders/summon_glow.gdshader")).contains(["glow_color", "width"])

func test_distort_shader_loads_with_uniforms() -> void:
	assert_array(_uniform_names("res://shaders/radial_distort.gdshader")).contains(["strength"])

func test_make_shader_material_returns_shader_material() -> void:
	var m: ShaderMaterial = Vfx.make_shader_material(&"fire")
	assert_bool(m is ShaderMaterial).is_true()
	assert_object(m.shader).is_not_null()

func test_shared_material_is_cached() -> void:
	assert_object(Vfx.make_shader_material(&"ice")).is_same(Vfx.make_shader_material(&"ice"))

func test_unique_material_is_distinct() -> void:
	assert_object(Vfx.make_shader_material(&"ice", true)).is_not_same(Vfx.make_shader_material(&"ice", true))

func test_unknown_shader_returns_null() -> void:
	assert_object(Vfx.make_shader_material(&"nope")).is_null()

func test_freeze_indicator_uses_ice_shader() -> void:
	var n := Vfx.make_status_indicator(&"freeze")
	assert_bool(n is Sprite2D).is_true()
	assert_bool((n as Sprite2D).material is ShaderMaterial).is_true()
	n.free()
