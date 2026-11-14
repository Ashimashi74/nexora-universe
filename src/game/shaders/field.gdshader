shader_type canvas_item;
// Sharp field with soft feathered edges (render.ts staticLayer DstIn gradients: 6% top/bottom, 5% left/right).
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float fy = smoothstep(0.0, 0.06, UV.y) * (1.0 - smoothstep(0.94, 1.0, UV.y));
	float fx = smoothstep(0.0, 0.05, UV.x) * (1.0 - smoothstep(0.95, 1.0, UV.x));
	COLOR = vec4(c.rgb, c.a * fx * fy);
}
