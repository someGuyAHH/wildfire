shader_type canvas_item;

// game clock that stops while paused (set by Main), unlike TIME
global uniform float game_time;

// radial streaks toward the screen edges, driven by player speed
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.55);
uniform float line_count = 110.0;
uniform float inner_radius = 0.32;
uniform float flicker_rate = 16.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x; // aspect fix
	float r = length(uv);
	float a = atan(uv.y, uv.x) / 6.2831853 + 0.5;
	float rnd = hash(floor(a * line_count) + floor(game_time * flicker_rate) * 13.7);
	float across = abs(fract(a * line_count) - 0.5) * 2.0;
	float line = smoothstep(0.4, 0.0, across) * step(0.74, rnd);
	float radial = smoothstep(inner_radius, inner_radius + 0.4, r);
	COLOR = vec4(line_color.rgb, line_color.a * line * radial * intensity);
}
