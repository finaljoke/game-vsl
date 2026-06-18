shader_type canvas_item;
// 火:UV 噪声扰动制造热浪 + 暖色乘法。安全用于序列帧(不强制加色,不过曝)。
uniform float speed = 1.0;
uniform float strength = 0.04;
uniform vec4 tint : source_color = vec4(1.0, 0.6, 0.2, 1.0);

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	uv.y += sin(uv.x * 12.0 + t * 6.0) * strength;
	uv.x += cos(uv.y * 10.0 + t * 5.0) * strength;
	vec4 tex = texture(TEXTURE, uv);
	COLOR = tex * tint * COLOR;
}
