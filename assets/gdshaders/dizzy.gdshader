shader_type canvas_item;

// game clock that stops while paused (set by Main), unlike TIME
global uniform float game_time;

// dizziness overlay: wobbly uv warp + rgb split + sickly tint + vignette, all scaled by strength.
// the hud hides the rect when strength is 0 so it costs nothing normally.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float wave_amount = 0.006;
uniform float aberration = 0.012;
uniform vec4 tint : source_color = vec4(0.75, 1.0, 0.7, 1.0);
uniform float tint_mix = 0.25;
uniform float vignette = 0.45;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float t = game_time;
	vec2 wave = vec2(sin(uv.y * 9.0 + t * 2.3), cos(uv.x * 7.0 + t * 1.9)) * wave_amount * strength;
	vec2 split = c * aberration * strength * (0.6 + 0.4 * sin(t * 3.1));
	vec3 col;
	col.r = texture(screen_tex, uv + wave + split).r;
	col.g = texture(screen_tex, uv + wave).g;
	col.b = texture(screen_tex, uv + wave - split).b;
	col = mix(col, col * tint.rgb, tint_mix * strength);
	col *= 1.0 - smoothstep(0.3, 0.8, length(c)) * vignette * strength;
	COLOR = vec4(col, 1.0);
}
