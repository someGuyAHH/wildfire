shader_type canvas_item;

// screen burns away to black (progress 0 -> 1) with a glowing ember edge, then burns back in
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float edge_width = 0.07;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float n = value_noise(UV * vec2(9.0, 5.0)) * 0.65 + value_noise(UV * 23.0) * 0.35;
	n = n * 0.8 + (1.0 - UV.y) * 0.2; // burns from the bottom up, roughly
	float t = progress * (1.0 + edge_width * 2.0) - edge_width;
	float d = n - t;
	float black = 1.0 - step(0.0, d);
	float edge = (1.0 - smoothstep(0.0, edge_width, d)) * step(0.0, d) * step(0.001, progress);
	vec3 col = mix(vec3(0.0), edge_color.rgb * 2.0, edge);
	COLOR = vec4(col, clamp(black + edge, 0.0, 1.0));
}
