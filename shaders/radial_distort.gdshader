shader_type canvas_item;
// 变幻:屏读径向扭曲,把背景向中心吸入(引力井)。
uniform float strength = 0.1;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 dir = UV - vec2(0.5);
	float d = length(dir);
	vec2 offset = normalize(dir + vec2(0.0001)) * strength * clamp(0.5 - d, 0.0, 0.5);
	vec4 col = texture(screen_tex, SCREEN_UV + offset);
	COLOR = vec4(col.rgb, texture(TEXTURE, UV).a);
}
