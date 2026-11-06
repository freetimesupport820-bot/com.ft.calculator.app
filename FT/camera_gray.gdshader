shader_type canvas_item;
// Same crop/zoom geometry as the preview, but outputs luminance only (used for QR decoding).
uniform sampler2D tex_y : filter_linear;
uniform bool is_rgb = false;
uniform float rot_quarters = 0.0;
uniform float img_aspect = 1.7778;
uniform float zoom = 1.0;

void fragment() {
	vec2 p = UV - vec2(0.5);
	p /= max(zoom, 1.0);
	if (img_aspect >= 1.0) {
		p.x /= img_aspect;
	} else {
		p.y *= img_aspect;
	}
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
	vec4 s = texture(tex_y, uv);
	float l = is_rgb ? dot(s.rgb, vec3(0.299, 0.587, 0.114)) : s.r;
	COLOR = vec4(vec3(l), 1.0);
}
