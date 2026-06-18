shader_type canvas_item;
// 召唤:对 alpha 做十字膨胀,差值染成幽光描边。窄 width 保轮廓可读。
uniform vec4 glow_color : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform float width = 2.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * width;
	float a = tex.a;
	a = max(a, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	a = max(a, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	float outline = clamp(a - tex.a, 0.0, 1.0);
	COLOR = tex + glow_color * outline;
}
