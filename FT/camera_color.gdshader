shader_type canvas_item;
// Camera preview: YCbCr (separate planes from CameraTexture) -> RGB, square "cover" crop, rotation, digital zoom.
uniform sampler2D tex_y : filter_linear;
uniform sampler2D tex_cbcr : filter_linear;
uniform bool is_rgb = false;
uniform float rot_quarters = 0.0;  // 0..3 clockwise quarter turns applied to the raw image
uniform float img_aspect = 1.7778; // displayed (rotated) width / height
uniform float zoom = 1.0;
uniform bool mirror = false;
uniform float rgb_gain = 1.0;
uniform vec2 rect_size = vec2(300.0, 300.0);
uniform float corner = 20.0;

float sdf(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	float mask = clamp(0.5 - sdf((UV - 0.5) * rect_size, rect_size * 0.5, corner), 0.0, 1.0);
	vec2 p = UV - vec2(0.5);
	p /= max(zoom, 1.0);
	if (img_aspect >= 1.0) {
		p.x /= img_aspect;
	} else {
		p.y *= img_aspect;
	}
	if (mirror) {
		p.x = -p.x;
	}
	// rotate sample position back into raw sensor space
	int q = int(mod(rot_quarters + 0.5, 4.0));
	vec2 r = p;
	if (q == 1) {
		r = vec2(p.y, -p.x);
	} else if (q == 2) {
		r = vec2(-p.x, -p.y);
	} else if (q == 3) {
		r = vec2(-p.y, p.x);
	}
	vec2 uv = r + vec2(0.5);
	if (is_rgb) {
		COLOR = vec4(texture(tex_y, uv).rgb * rgb_gain, mask);
	} else {
		float y = texture(tex_y, uv).r;
		vec2 c = texture(tex_cbcr, uv).rg - vec2(0.5);
		vec3 rgb = vec3(y + 1.402 * c.y, y - 0.344136 * c.x - 0.714136 * c.y, y + 1.772 * c.x);
		COLOR = vec4(clamp(rgb, 0.0, 1.0), mask);
	}
}
