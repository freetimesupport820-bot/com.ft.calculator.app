shader_type canvas_item;
// Scanner viewfinder: dim outside the inset rounded frame (box-shadow 999px), white border and cyan glow.
uniform vec2 rect_size = vec2(300.0, 300.0);
uniform float inset = 0.18;
uniform float radius = 22.0;
uniform float border = 3.0;
uniform vec4 glow_color : source_color = vec4(0.133, 0.827, 0.933, 1.0);
uniform float dim = 0.5;
uniform float outer_radius = 20.0;

float sdf(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	vec2 half_in = rect_size * (0.5 - inset);
	float d = sdf(p, half_in, radius);
	float outer = sdf(p, rect_size * 0.5, outer_radius);
	float clip = clamp(0.5 - outer, 0.0, 1.0);
	float outside = clamp(d * 1.0 + 0.5, 0.0, 1.0);
	float ring = clamp(1.0 - abs(d + border * 0.5) / (border * 0.5 + 0.5), 0.0, 1.0);
	float glow = exp(-max(d, 0.0) / 10.0) * 0.55 * step(0.0, d);
	vec3 col = vec3(0.012, 0.024, 0.082);
	float a = outside * dim;
	vec3 outc = mix(col, glow_color.rgb, glow);
	a = max(a, glow * 0.6);
	vec3 rgb = mix(outc, vec3(1.0), ring);
	a = max(a, ring * 0.92);
	COLOR = vec4(rgb, a * clip);
}
