shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// The art pass's photo-textured structures (Overworld: aqueduct and ruins in honey limestone, rubble
// towers, cliff-rock blocks, painted-metal hubs). A photo set (colour, OpenGL normal, roughness,
// optional metalness) projected along each surface's dominant world axis, like world_vector (the
// map boxes need no uvs), weathered the way the references are (the Pont du Gard: tone that drifts
// over metres, rain streaks down the walls, paler weathered tops, dirt low down, joints only
// hairlines):
//   - anti-tiling: a second read, turned (detile_angle) and shifted, swapped in by a broad noise
//   - macro tone: two noise layers drift the colour between tint_a and tint_b
//   - streaks: long vertical noise darkening walls; tops: a pale dusty cast on up-facing faces
//   - grime low down: darker under grime_height metres above the given base level
//   - joints (optional): a pattern map's joint lines (world_vector's R channel), faintly
// Runs on game_time only through nothing: static.

#include "res://assets/gdshaders/include/noise.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
// tiling noise (assets/images/terrain/macro_noise.png): R, G broad fBm, B finer
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// metres of world one photo tile covers
uniform float tile_size = 3.0;
// the photo's colour is multiplied by these (drifting from a to b over the macro noise)
uniform vec4 tint_a : source_color = vec4(1.0);
uniform vec4 tint_b : source_color = vec4(1.0);
// brightness multiplier on top of the tints (photos are often dark)
uniform float gain = 1.0;
// metres across one patch of tone drift
uniform float macro_scale = 14.0;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform float roughness_bias : hint_range(-1.0, 1.0) = 0.0;
uniform float metallic_scale : hint_range(0.0, 1.0) = 0.0;
// anti-tiling: metres per noise cycle that swaps the two reads (0 = off), and how far the second
// read is turned: any angle for textures without a direction; PI for courses and strata (rubble
// walls, layered rock): turned any other way they'd run askew
uniform float detile_scale = 23.0;
uniform float detile_angle = 2.0944;
// how sharply the two reads swap: soft suits grain and smears, masonry wants a near-hard swap
// (a soft one cross-fades two stone layouts into a ghosted double image)
uniform float detile_sharpness = 5.0;
// rain streaks on walls: strength, metres across one streak, metres long
uniform float streaks : hint_range(0.0, 1.0) = 0.0;
uniform float streak_width = 0.9;
uniform float streak_length = 9.0;
// up-facing faces: paler and dustier
uniform vec4 top_color : source_color = vec4(1.0, 1.0, 1.0, 0.0); // alpha = how much
// dirt low down: darkest at grime_base (world y), gone by grime_base + grime_height
uniform float grime : hint_range(0.0, 1.0) = 0.0;
uniform float grime_base = 0.0;
uniform float grime_height = 3.0;
uniform vec4 grime_color : source_color = vec4(0.25, 0.2, 0.14, 1.0);
// faint joints from a pattern map (world_vector's packed map: R height, 0 in joints)
uniform sampler2D joint_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float joint_tile = 12.0;
uniform float joints : hint_range(0.0, 1.0) = 0.0;
uniform vec4 joint_color : source_color = vec4(0.3, 0.25, 0.18, 1.0);

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(world_nrm);
	vec2 p; // metres in the projection plane
	vec3 tu;
	vec3 tv;
	if (an.y > max(an.x, an.z)) {
		p = world_pos.xz;
		tu = vec3(1.0, 0.0, 0.0);
		tv = vec3(0.0, 0.0, 1.0);
	} else if (an.x > an.z) {
		p = vec2(world_pos.z, -world_pos.y);
		tu = vec3(0.0, 0.0, 1.0);
		tv = vec3(0.0, -1.0, 0.0);
	} else {
		p = vec2(world_pos.x, -world_pos.y);
		tu = vec3(1.0, 0.0, 0.0);
		tv = vec3(0.0, -1.0, 0.0);
	}
	vec2 uv = p / tile_size;

	// anti-tiling: read twice (the second turned ~120 degrees and shifted), swap by a broad noise
	float dt = detile_scale > 0.0 ? clamp((texture(noise_tex, p / detile_scale).r - 0.5) * detile_sharpness + 0.5, 0.0, 1.0) : 0.0;
	mat2 ROT = mat2(vec2(cos(detile_angle), sin(detile_angle)), vec2(-sin(detile_angle), cos(detile_angle)));
	vec2 uv2 = ROT * uv + vec2(0.37, 0.71);
	vec4 col = texture(albedo_tex, uv);
	vec3 nt = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	float rough = texture(rough_tex, uv).r;
	float metal = texture(metal_tex, uv).r;
	if (dt > 0.001) {
		vec3 nt2 = texture(normal_tex, uv2).rgb * 2.0 - 1.0;
		nt2.xy = transpose(ROT) * nt2.xy;
		col = mix(col, texture(albedo_tex, uv2), dt);
		nt = mix(nt, nt2, dt);
		rough = mix(rough, texture(rough_tex, uv2).r, dt);
		metal = mix(metal, texture(metal_tex, uv2).r, dt);
	}

	// tone drift over metres
	vec2 wp = vec2(world_pos.x + world_pos.y * 0.7, world_pos.z - world_pos.y * 0.4);
	float m1 = texture(noise_tex, wp / macro_scale * 0.25).g;
	float m2 = texture(noise_tex, wp / macro_scale * 0.9 + 0.3).b;
	vec3 tint = mix(tint_a.rgb, tint_b.rgb, smoothstep(0.25, 0.75, m1 * 0.75 + m2 * 0.25));
	vec3 c = col.rgb * tint * gain;

	float up = smoothstep(0.55, 0.9, world_nrm.y);
	float wall = 1.0 - smoothstep(0.3, 0.6, an.y);
	// rain streaks: noise stretched down the wall, broken up along its length
	if (streaks > 0.0) {
		float along = an.x > an.z ? world_pos.z : world_pos.x;
		float s1 = texture(noise_tex, vec2(along / streak_width * 0.25, world_pos.y / streak_length * 0.25)).b;
		float s2 = texture(noise_tex, vec2(along / streak_width * 0.11 + 0.5, world_pos.y / streak_length * 0.6)).r;
		float streak = smoothstep(0.5, 0.85, s1) * smoothstep(0.3, 0.7, s2);
		c *= 1.0 - streak * streaks * wall * 0.45;
		rough = min(1.0, rough + streak * streaks * wall * 0.15);
	}
	c = mix(c, c * top_color.rgb * 1.5, up * top_color.a);
	if (grime > 0.0) {
		float g = 1.0 - smoothstep(0.0, grime_height, world_pos.y - grime_base);
		g *= 0.6 + 0.4 * texture(noise_tex, wp * 0.15).b;
		c = mix(c, c * grime_color.rgb * 2.0, g * grime);
	}
	if (joints > 0.0) {
		float h = texture(joint_map, p / joint_tile).r;
		float w = fwidth(h) * 0.75 + 0.02;
		float j = 1.0 - smoothstep(0.1 - w, 0.1 + w, h);
		c = mix(c, c * joint_color.rgb * 1.6, j * joints);
	}

	ALBEDO = c;
	ROUGHNESS = clamp(rough + roughness_bias, 0.0, 1.0);
	METALLIC = metal * metallic_scale;
	// normal map in the projection's frame: image +y (OpenGL green) is -tv
	nt.xy *= normal_strength;
	vec3 wn = normalize(world_nrm * max(nt.z, 0.05) + tu * nt.x - tv * nt.y);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
