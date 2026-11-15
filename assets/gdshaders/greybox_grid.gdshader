shader_type spatial;

// world-space triplanar grid: 1 m minor lines, 10 m major lines. reads speed really well.
uniform vec4 base_color : source_color = vec4(0.45, 0.46, 0.5, 1.0);
uniform vec4 line_color : source_color = vec4(0.12, 0.12, 0.14, 1.0);
uniform float minor_cell = 1.0;
uniform float major_cell = 10.0;
uniform float minor_width = 0.015;
uniform float major_width = 0.05;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid(vec2 p, float cell, float w) {
	vec2 g = abs(fract(p / cell + 0.5) - 0.5) * cell;
	float d = min(g.x, g.y);
	float aa = fwidth(d);
	return 1.0 - smoothstep(w - aa, w + aa, d);
}

void fragment() {
	vec3 n = abs(world_nrm);
	vec2 p = n.y > max(n.x, n.z) ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
	float l = max(grid(p, minor_cell, minor_width) * 0.35, grid(p, major_cell, major_width));
	ALBEDO = mix(base_color.rgb, line_color.rgb, l);
	ROUGHNESS = roughness_value;
}
