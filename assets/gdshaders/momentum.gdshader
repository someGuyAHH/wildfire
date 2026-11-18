shader_type canvas_item;

// game clock that stops while paused (set by Main), unlike TIME
global uniform float game_time;

// momentum overlay, on above 20 m/s (= fast enough to body-slam someone):
// cool blue edges, radial zoom blur toward the rim, a slight rgb split, and crackling cyan
// flames flowing outward around the rim. everything scales with speed (0..1).
// the hud hides the rect when speed is 0, so it's free when you're slow.
// overdrive (0..1, above 30 m/s) turns it electric: violet flames and crackling arcs on the rim.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float speed : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.15, 0.45, 1.0, 1.0);
uniform vec4 flame_tint : source_color = vec4(0.45, 0.95, 1.0, 1.0);
uniform float blur_strength = 0.045;
uniform int blur_samples = 6;
uniform float flame_strength = 1.5;
uniform float overdrive : hint_range(0.0, 1.0) = 0.0;
uniform vec4 over_tint : source_color = vec4(0.5, 0.15, 1.0, 1.0);
uniform vec4 over_flame_tint : source_color = vec4(0.85, 0.5, 1.0, 1.0);

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

	vec3 tint_c = mix(tint.rgb, over_tint.rgb, overdrive);
	vec3 flame_c = mix(flame_tint.rgb, over_flame_tint.rgb, overdrive);

	// cool vignette
	float vig = smoothstep(0.32, 0.85, r);
	col = mix(col, col * 0.55 + tint_c * 0.45, vig * speed * 0.6);

	// flames: two layers of noise bands sliding outward around the rim, flickering
	// angle as 0..1 round the rim; each noise layer wraps a whole number of cells round it, so
	// there's no seam where atan() jumps from +pi to -pi (it used to cut the left half in two)
	float turn = atan(ca.y, ca.x) / 6.2831853 + 0.5;
	float flow = value_noise_wrap(vec2(turn * 44.0, r * 10.0 - game_time * 7.0), 44.0);
	flow = flow * 0.6 + value_noise_wrap(vec2(turn * 119.0 + 3.0, r * 23.0 - game_time * 11.0), 119.0) * 0.4;
	float flames = smoothstep(0.64, 0.86, flow) * smoothstep(0.38, 0.8, r);
	float pulse = 0.75 + 0.25 * sin(game_time * 16.0);
	col += flame_c * flames * speed * pulse * flame_strength;
	col += flame_c * vig * vig * speed * 0.35;

	// overdrive arcs: thin jittering lines around the rim, re-rolled ~20 times a second, gated so
	// only some sectors crackle at once
	if (overdrive > 0.0) {
		float tick = floor(game_time * 20.0);
		float line = value_noise_wrap(vec2(turn * 25.0 + tick * 1.37, r * 9.0 + tick * 0.71), 25.0);
		float arcs = 1.0 - smoothstep(0.0, 0.035, abs(line - 0.5));
		float gate = step(0.55, value_noise_wrap(vec2(turn * 16.0 + tick * 3.1, tick * 0.37), 16.0));
		arcs *= gate * smoothstep(0.42, 0.8, r);
		col += vec3(0.92, 0.86, 1.0) * arcs * overdrive * 1.6;
	}

	COLOR = vec4(col, 1.0);
}
