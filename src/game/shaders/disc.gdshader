shader_type canvas_item;
// Disc art: anti-aliased round mask over a full-bleed team sprite (render.ts clips the logo to a circle).
// Vertex colour carries the per-draw tint (dark overlay for the side not on turn).
varying vec4 vcol;
void vertex() { vcol = COLOR; }
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float w = max(fwidth(d) * 1.25, 0.004);
	float m = 1.0 - smoothstep(0.985 - w, 0.985, d);
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb * vcol.rgb, c.a * m * vcol.a);
}
