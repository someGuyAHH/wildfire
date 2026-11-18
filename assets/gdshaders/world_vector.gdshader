shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// the art-pass world material: flat vector-style surfaces (crisp joints, chamfered blocks,
// inlays) lit like a modern game. reads a packed pattern map from tools/texgen/patterns.py:
//   R height (0 = joint, ramps over the bevel, 1 = face), G per-block tone, B accent (inlay/crack)
// projected along the surface's dominant world axis (no uvs needed: the maps are generated boxes).
// joints and accents are thresholded with fwidth, so their edges stay sharp at any distance.

// game clock that stops while paused (set by Main), unlike TIME
global uniform float game_time;

uniform sampler2D pattern : filter_linear_mipmap_anisotropic, repeat_enable;
// metres of world one pattern tile covers
uniform float tile_size = 4.0;
uniform vec4 base_color : source_color = vec4(0.4, 0.36, 0.34, 1.0);
uniform vec4 joint_color : source_color = vec4(0.08, 0.06, 0.06, 1.0);
// how far each block's own tone strays from base_color (0 = all alike)
uniform float tone_range : hint_range(0.0, 1.0) = 0.25;
// height under this is joint
uniform float joint_level : hint_range(0.0, 1.0) = 0.1;
// how strongly the bevels bend the lighting
uniform float bevel_strength = 2.5;
// faces pick up a touch of light on their bevel's upper rim (the vector "highlight stroke")
uniform float rim_light : hint_range(0.0, 1.0) = 0.25;
uniform vec4 accent_color : source_color = vec4(1.0, 0.45, 0.1, 0.0); // alpha = how much it shows
uniform float accent_emission = 0.0;
// accents breathe (embers in cracks): 0 = steady
uniform float accent_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_face : hint_range(0.0, 1.0) = 0.8;
uniform float roughness_joint : hint_range(0.0, 1.0) = 0.95;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
// where the pattern's texel step is measured for the bevel normal (in pattern texels)
uniform float normal_step = 1.5;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_nrm);
	// dominant-axis projection: tops/bottoms use xz, walls use the horizontal axis + up
	vec2 uv;
	vec3 tu;
	vec3 tv;
	if (n.y > max(n.x, n.z)) {
		uv = world_pos.xz;
		tu = vec3(1.0, 0.0, 0.0);
		tv = vec3(0.0, 0.0, 1.0);
	} else if (n.x > n.z) {
		uv = vec2(world_pos.z, -world_pos.y);
		tu = vec3(0.0, 0.0, 1.0);
		tv = vec3(0.0, -1.0, 0.0);
	} else {
		uv = vec2(world_pos.x, -world_pos.y);
		tu = vec3(1.0, 0.0, 0.0);
		tv = vec3(0.0, -1.0, 0.0);
	}
	uv /= tile_size;
	vec4 t = texture(pattern, uv);
	float h = t.r;

	// bevel normal from the height's slope (central differences in pattern space)
	vec2 px = normal_step / vec2(textureSize(pattern, 0));
	float hx = texture(pattern, uv + vec2(px.x, 0.0)).r - texture(pattern, uv - vec2(px.x, 0.0)).r;
	float hy = texture(pattern, uv + vec2(0.0, px.y)).r - texture(pattern, uv - vec2(0.0, px.y)).r;
	vec3 wn = normalize(world_nrm - bevel_strength * (hx * tu + hy * tv));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// crisp joint line: threshold the height with an anti-aliasing width from screen derivatives
	float w = fwidth(h) * 0.75 + 0.002;
	float joint = 1.0 - smoothstep(joint_level - w, joint_level + w, h);
	vec3 face = base_color.rgb * (1.0 + (t.g - 0.5) * 2.0 * tone_range);
	// the bevel's top rim (sloped and facing up the projection) catches a highlight stroke
	float slope = clamp(length(vec2(hx, hy)) * 6.0, 0.0, 1.0);
	face += base_color.rgb * rim_light * slope * step(joint_level, h) * clamp(-hy * 8.0 + 0.3, 0.0, 1.0);
	vec3 col = mix(face, joint_color.rgb, joint);

	float aw = fwidth(t.b) * 0.75 + 0.002;
	float accent = smoothstep(0.5 - aw, 0.5 + aw, t.b) * accent_color.a;
	col = mix(col, accent_color.rgb, accent);
	float breathe = 1.0 + accent_pulse * (sin(game_time * 1.7 + world_pos.x * 0.3 + world_pos.z * 0.2) * 0.5 - 0.1);
	EMISSION = accent_color.rgb * accent * accent_emission * breathe;

	ALBEDO = col;
	ROUGHNESS = mix(roughness_face, roughness_joint, joint);
	METALLIC = metallic_value * (1.0 - joint);
}
