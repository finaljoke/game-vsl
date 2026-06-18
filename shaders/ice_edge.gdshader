shader_type canvas_item;
// 冰:从中心向外的白边(冰晶轮廓),保留原 alpha。
uniform vec4 edge_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float rim = 1.5;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float d = clamp(distance(UV, vec2(0.5)) * 2.0, 0.0, 1.0);
	float e = pow(d, rim);
	vec3 col = mix(tex.rgb, edge_color.rgb, e);
	COLOR = vec4(col, tex.a);
}
