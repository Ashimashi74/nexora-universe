// Tiled star layer scrolling vertically (parallax), no per-frame script work.
shader_type canvas_item;
uniform vec2 rect_size = vec2(1080.0, 1920.0);
uniform float tile = 1024.0;
uniform float period = 60.0;      // seconds for one tile
uniform float opacity = 0.75;
uniform float twinkle = 0.25;
uniform vec2 drift = vec2(0.0, 0.0); // extra offset (px) for touch/scroll parallax
void fragment() {
	vec2 p = (UV * rect_size + drift) / tile;
	p.y -= TIME / period;
	vec4 s = texture(TEXTURE, fract(p));
	float tw = 1.0 - twinkle + twinkle * sin(TIME * 1.7 + (p.x * 37.0 + p.y * 53.0));
	COLOR = vec4(s.rgb * 1.25, s.a * opacity * tw);
}
