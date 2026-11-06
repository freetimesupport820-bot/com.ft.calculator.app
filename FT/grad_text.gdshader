shader_type canvas_item;
// Gradient-filled text (CSS .gt: linear-gradient(90deg, ac, ac2 55%, ac3) + background-clip:text)
uniform vec4 c0 : source_color = vec4(0.024, 0.714, 0.831, 1.0);
uniform vec4 c1 : source_color = vec4(0.486, 0.227, 0.929, 1.0);
uniform vec4 c2 : source_color = vec4(0.925, 0.282, 0.6, 1.0);
uniform float text_width = 200.0;
varying float vx;

void vertex() {
	vx = VERTEX.x;
}

void fragment() {
	float t = clamp(vx / max(text_width, 1.0), 0.0, 1.0);
	vec4 g = t < 0.55 ? mix(c0, c1, t / 0.55) : mix(c1, c2, (t - 0.55) / 0.45);
	COLOR = vec4(g.rgb, COLOR.a);
}
