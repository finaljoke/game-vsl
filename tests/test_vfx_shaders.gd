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
