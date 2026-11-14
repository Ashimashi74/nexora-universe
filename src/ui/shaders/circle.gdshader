// circular mask (avatars / photos)
shader_type canvas_item;
uniform float feather = 0.02;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = length(UV - vec2(0.5));
	c.a *= 1.0 - smoothstep(0.5 - feather, 0.5, d);
	COLOR = c * COLOR;
}
