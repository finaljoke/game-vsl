shader_type canvas_item;
render_mode blend_add;
// 电:逐行随机水平抖动 + 加色发光(噼啪)。
uniform float jitter = 0.03;
uniform float speed = 30.0;

float rand(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float row = floor(UV.y * 20.0);
	uv.x += (rand(row + floor(TIME * speed)) - 0.5) * jitter;
	COLOR = texture(TEXTURE, uv) * COLOR;
}
