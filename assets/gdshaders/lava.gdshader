shader_type spatial;

// lava sea (Inferno): dark crust drifting over a glowing melt, in world space so one big plane
// tiles seamlessly. Cheap: a few sines, no textures.
uniform vec4 melt : source_color = vec4(1.0, 0.42, 0.08, 1.0);
uniform vec4 crust : source_color = vec4(0.12, 0.03, 0.02, 1.0);
uniform float glow = 3.0;
uniform float scale = 0.06;
uniform float flow = 0.25;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float waves(vec2 p, float t) {
	float v = sin(p.x * 1.3 + t) * sin(p.y * 1.1 - t * 0.7);
	v += 0.5 * sin(p.x * 2.7 - p.y * 1.9 + t * 1.3);
	v += 0.25 * sin(p.x * 5.1 + p.y * 4.3 - t * 1.9);
	return v / 1.75;
}

void fragment() {
	vec2 p = world_pos.xz * scale;
	float t = TIME * flow;
	vec2 warp = vec2(waves(p + 3.1, t), waves(p.yx - 1.7, t));
	float v = waves(p + warp * 0.8, t);
	float cracks = smoothstep(0.05, 0.45, abs(v)); // 0 in the glowing seams, 1 on the crust
	ALBEDO = mix(melt.rgb, crust.rgb, cracks);
	EMISSION = melt.rgb * glow * (1.0 - cracks) + melt.rgb * 0.15;
	ROUGHNESS = mix(0.3, 0.95, cracks);
}
