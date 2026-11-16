shader_type canvas_item;

// game clock that stops while paused (set by Main), unlike TIME
global uniform float game_time;

// momentum overlay, on above 20 m/s (= fast enough to body-slam someone):
// cool blue edges, radial zoom blur toward the rim, a slight rgb split, and crackling cyan
// flames flowing outward around the rim. everything scales with speed (0..1).
// the hud hides the rect when speed is 0, so it's free when you're slow.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float speed : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.15, 0.45, 1.0, 1.0);
uniform vec4 flame_tint : source_color = vec4(0.45, 0.95, 1.0, 1.0);
uniform float blur_strength = 0.045;
uniform int blur_samples = 6;
uniform float flame_strength = 1.5;

#include "res://assets/gdshaders/include/noise.gdshaderinc"

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	vec2 ca = c;
	ca.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x; // aspect-correct for round shapes
	float r = length(ca);
	float edge = smoothstep(0.22, 0.75, r);

	// radial zoom blur, only toward the edges so the crosshair area stays sharp
	float amount = blur_strength * speed * edge;
	vec3 col = vec3(0.0);
	int n = max(blur_samples, 1);
	for (int i = 0; i < n; i++) {
		float t = float(i) / float(max(n - 1, 1));
		col += texture(screen_tex, uv - c * amount * t).rgb;
	}
	col /= float(n);

	// slight rgb split toward the edges
	vec2 off = c * 0.01 * speed * edge;
	col.r = mix(col.r, texture(screen_tex, uv + off).r, 0.7);
	col.b = mix(col.b, texture(screen_tex, uv - off).b, 0.7);

	// cool vignette
	float vig = smoothstep(0.32, 0.85, r);
	col = mix(col, col * 0.55 + tint.rgb * 0.45, vig * speed * 0.6);

	// flames: two layers of noise bands sliding outward around the rim, flickering
	float ang = atan(ca.y, ca.x);
	float flow = value_noise(vec2(ang * 7.0, r * 10.0 - game_time * 7.0));
	flow = flow * 0.6 + value_noise(vec2(ang * 19.0 + 3.0, r * 23.0 - game_time * 11.0)) * 0.4;
	float flames = smoothstep(0.64, 0.86, flow) * smoothstep(0.38, 0.8, r);
	float pulse = 0.75 + 0.25 * sin(game_time * 16.0);
	col += flame_tint.rgb * flames * speed * pulse * flame_strength;
	col += flame_tint.rgb * vig * vig * speed * 0.35;

	COLOR = vec4(col, 1.0);
}
