shader_type canvas_item;
// Rounded rectangle with CSS-like linear gradient (3 stops). Used for buttons, chips, logo, toast.
uniform vec2 rect_size = vec2(100.0, 40.0);
uniform float radius = 16.0;
uniform vec4 c0 : source_color = vec4(0.024, 0.714, 0.831, 1.0);
uniform vec4 c1 : source_color = vec4(0.486, 0.227, 0.929, 1.0);
uniform vec4 c2 : source_color = vec4(0.925, 0.282, 0.6, 1.0);
uniform float mid = 0.55;
uniform float angle_deg = 135.0;
uniform float gloss = 1.0;
uniform float opacity = 1.0;
uniform float shift = 0.0;

float sdf(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	float d = sdf(p, rect_size * 0.5, radius);
	float a = clamp(0.5 - d, 0.0, 1.0);
	float ang = radians(angle_deg);
	vec2 dir = vec2(sin(ang), -cos(ang));
	float len = abs(rect_size.x * dir.x) + abs(rect_size.y * dir.y);
	float t = clamp(dot(p, dir) / max(len, 1.0) + 0.5 + shift, 0.0, 1.0);
	vec4 col = t < mid ? mix(c0, c1, t / mid) : mix(c1, c2, (t - mid) / (1.0 - mid));
	// top gloss (CSS ::after white 35% -> 0 over upper 55%)
	float gy = UV.y / 0.55;
	col.rgb = mix(col.rgb, vec3(1.0), gloss * 0.35 * clamp(1.0 - gy, 0.0, 1.0));
	COLOR = vec4(col.rgb, col.a * a * opacity);
}
