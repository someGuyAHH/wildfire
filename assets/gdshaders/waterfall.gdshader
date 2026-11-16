shader_type spatial;
render_mode cull_disabled;

// flowing water ribbon (Jungle falls). UV.x = metres across, UV.y = metres downstream;
// COLOR.r = foam (lip and splash), COLOR.g = edge fade.
uniform vec4 water : source_color = vec4(0.32, 0.58, 0.68, 0.6);
uniform vec4 foam : source_color = vec4(0.88, 0.95, 1.0, 0.9);
uniform float flow_speed = 7.0;
uniform float streak_gap = 3.0;

varying vec2 shade;

void vertex() {
	shade = COLOR.rg;
}

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	float col = floor(UV.x * 2.5);
	float ph = hash(col);
	float s = fract((UV.y - TIME * flow_speed * (0.75 + 0.5 * ph)) / streak_gap + ph);
	float streak = smoothstep(0.0, 0.1, s) * (1.0 - smoothstep(0.25, 0.55, s));
	streak *= 1.0 - smoothstep(0.3, 1.0, abs(fract(UV.x * 2.5) - 0.5) * 2.0);
	float f = clamp(shade.r + streak * 0.55, 0.0, 1.0);
	ALBEDO = mix(water.rgb, foam.rgb, f);
	ALPHA = mix(water.a, foam.a, f) * shade.g * smoothstep(0.0, 5.0, UV.y);
	ROUGHNESS = 0.12;
}
