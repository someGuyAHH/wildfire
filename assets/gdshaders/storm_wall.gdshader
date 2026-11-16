shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;

// game clock that stops while paused (set by Main), unlike TIME
global uniform float game_time;

// the hot potato storm: a ring of fire licking upward, densest at the ground, fading out on top
uniform vec4 base_color : source_color = vec4(1.0, 0.32, 0.05, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.82, 0.35, 1.0);
uniform float intensity = 1.6;
uniform float wall_height = 60.0;
uniform float around_tiles = 140.0;

varying float height01;

#include "res://assets/gdshaders/include/noise.gdshaderinc"

void vertex() {
	height01 = VERTEX.y / wall_height + 0.5; // 0 at the ground, 1 at the top
}

void fragment() {
	float h = clamp(height01, 0.0, 1.0);
	float n = value_noise(vec2(UV.x * around_tiles, h * 6.0 - game_time * 1.4)) * 0.6
			+ value_noise(vec2(UV.x * around_tiles * 2.7, h * 15.0 - game_time * 3.1)) * 0.4;
	float flame = smoothstep(0.35, 0.9, n + (0.45 - h));
	float fade = 1.0 - smoothstep(0.15, 0.95, h);
	ALBEDO = mix(base_color.rgb, hot_color.rgb, flame) * intensity;
	ALPHA = clamp((flame * 0.85 + 0.12) * fade, 0.0, 1.0);
}
