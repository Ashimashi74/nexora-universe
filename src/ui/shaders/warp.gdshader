// radial nebula glow for the intro
shader_type canvas_item;
uniform vec2 center = vec2(0.5, 0.44);
uniform vec2 aspect = vec2(1.0, 1.78);
uniform vec4 col : source_color = vec4(0.235, 0.157, 0.627, 1.0);
uniform float strength = 0.2;
void fragment() {
	float d = length((UV - center) * aspect);
	COLOR = vec4(col.rgb, clamp(strength * (1.0 - d / 1.25), 0.0, 1.0));
}
