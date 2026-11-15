shader_type spatial;
render_mode unshaded;

// game clock that stops while paused (set by Main), unlike TIME
global uniform float game_time;

// scrolling chevrons along -Z of the mesh, for speed strips and pads
uniform vec4 color_a : source_color = vec4(0.05, 0.9, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.02, 0.08, 0.12, 1.0);
uniform float energy = 2.5;
uniform float repeats = 4.0;
uniform float scroll_speed = 1.5;

void fragment() {
	vec2 uv = UV;
	// tips point toward -Z (the push direction) and scroll that way
	float v = fract(uv.y * repeats - abs(uv.x - 0.5) * 1.2 + game_time * scroll_speed);
	float chevron = step(0.55, v);
	ALBEDO = mix(color_b.rgb, color_a.rgb * energy, chevron);
}
