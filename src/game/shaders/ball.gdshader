shader_type canvas_item;
// Ball as a lit, rotating 3D sphere (port + upgrade of the Skia BALL_SKSL in render.ts).
// The quad spans the ball's bounding square; UV -> p in [-1,1]^2. c0/c1/c2 are the columns-as-rows
// of the engine's 3x3 rotation matrix R exactly like the Skia uniforms: c0=(R0,R3,R6) c1=(R1,R4,R7) c2=(R2,R5,R8).
uniform vec3 c0 = vec3(1.0, 0.0, 0.0);
uniform vec3 c1 = vec3(0.0, 1.0, 0.0);
uniform vec3 c2 = vec3(0.0, 0.0, 1.0);
uniform float aa = 0.04;           // edge feather in normalized radius
uniform float hdr = 1.0;           // >1 on high quality: specular feeds the 2D glow
uniform vec3 rim_col = vec3(0.35, 0.6, 1.0);
uniform float lflip = 1.0;         // -1 when the view is rotated 180° (keeps the light top-left on screen)

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	if (d > 1.0) discard;
	float z = sqrt(max(0.0, 1.0 - d * d));
	vec3 n = vec3(p.x, p.y, z);
	vec3 q = vec3(dot(c0, n), dot(c1, n), dot(c2, n));
	vec2 uv = q.xy;
	if (q.z < 0.0) uv.x = -uv.x;
	vec4 c = texture(TEXTURE, uv * 0.93 * 0.5 + 0.5);
	vec3 L = normalize(vec3(-0.42 * lflip, -0.55 * lflip, 0.72));
	float dif = 0.62 + 0.5 * max(dot(n, L), 0.0);
	vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
	float spec = pow(max(dot(n, H), 0.0), 36.0) * 0.55;
	float spec2 = pow(max(dot(n, H), 0.0), 220.0) * 0.6;   // tight hot-spot
	float rim = pow(1.0 - z, 2.5);
	// ambient occlusion toward the lower-right limb (contact side of the shadow)
	float ao = 1.0 - 0.18 * smoothstep(0.2, 1.0, dot(p * lflip, normalize(vec2(0.5, 0.7))));
	vec3 col = c.rgb * dif * ao * (1.0 - 0.45 * rim) + vec3(spec + spec2) * hdr + rim_col * rim * 0.18;
	float a = smoothstep(1.0, 1.0 - aa, d);
	COLOR = vec4(col, a);
}
