// Rounded rect with a 3-stop gradient, glossy top, border and soft outer glow.
// The ColorRect is expanded by `pad` px on every side so the glow has room.
shader_type canvas_item;
render_mode blend_mix;

uniform vec2 size = vec2(100.0, 100.0);   // full ColorRect size in px
uniform float pad = 0.0;                  // glow margin in px
uniform float radius = 40.0;
uniform vec4 c0 : source_color = vec4(0.31, 0.89, 1.0, 1.0);
uniform vec4 c1 : source_color = vec4(0.36, 0.55, 1.0, 1.0);
uniform vec4 c2 : source_color = vec4(0.64, 0.36, 1.0, 1.0);
uniform float angle = 0.6;                // gradient direction (0 = left->right)
uniform float gloss = 0.32;
uniform float border = 3.0;
uniform vec4 border_col : source_color = vec4(1.0, 1.0, 1.0, 0.35);
uniform vec4 glow_col = vec4(0.3, 0.9, 1.0, 0.0); // may be HDR (>1)
uniform float glow_size = 24.0;
uniform float shine = -1.0;               // 0..1 sweep position (<0 = off)
uniform float alpha = 1.0;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * size;
	vec2 inner = size - vec2(pad * 2.0);
	vec2 c = size * 0.5;
	float r = min(radius, min(inner.x, inner.y) * 0.5);
	float d = sd_round_box(px - c, inner * 0.5, r);
	float aa = max(fwidth(d), 0.6);
	float body = 1.0 - smoothstep(-aa, aa, d);
	vec2 uv = (px - vec2(pad)) / max(inner, vec2(1.0));
	vec2 dir = vec2(cos(angle), sin(angle));
	float t = clamp(dot(uv - 0.5, dir) / (abs(dir.x) * 0.5 + abs(dir.y) * 0.5) * 0.5 + 0.5, 0.0, 1.0);
	vec4 col = t < 0.5 ? mix(c0, c1, t * 2.0) : mix(c1, c2, (t - 0.5) * 2.0);
	// gloss on the top half
	float g = gloss * (1.0 - smoothstep(0.0, 0.55, uv.y));
	col.rgb = mix(col.rgb, vec3(1.0), g);
	// shine sweep (diagonal band)
	if (shine >= 0.0) {
		float x = uv.x + uv.y * 0.35 - (shine * 1.8 - 0.4);
		col.rgb += vec3(0.35) * (1.0 - smoothstep(0.0, 0.07, abs(x)));
	}
	// border
	float bmask = (1.0 - smoothstep(-aa, aa, d)) * smoothstep(-border - aa, -border + aa, d);
	col.rgb = mix(col.rgb, border_col.rgb, bmask * border_col.a);
	vec4 o = vec4(col.rgb, col.a * body);
	// outer glow
	if (glow_col.a > 0.0 && d > 0.0) {
		float gl = exp(-d / max(glow_size * 0.45, 1.0)) * glow_col.a;
		o = vec4(glow_col.rgb, gl);
	}
	o.a *= alpha;
	COLOR = o;
}
