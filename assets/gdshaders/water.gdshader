shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// Jungle river and pools. Colour by the real depth of water under each pixel (from the depth
// buffer): clear teal in the shallows, dark green-blue in the middle; foam where it meets the
// bank; ripples drifting downstream (UV.y = metres downstream, UV.x = metres across); more
// opaque at grazing angles, like water. The meshes are wider than the channels: the terrain
// cuts their edges into the shoreline. Runs on game_time (stops while paused).

global uniform float game_time;

#include "res://assets/gdshaders/include/noise.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 shallow : source_color = vec4(0.24, 0.52, 0.48, 1.0);
uniform vec4 deep : source_color = vec4(0.04, 0.17, 0.19, 1.0);
uniform vec4 foam_color : source_color = vec4(0.86, 0.94, 0.92, 1.0);
// metres of water before it's fully the deep colour
uniform float depth_scale = 2.2;
// alpha in the shallowest and deepest water
uniform float clear_alpha = 0.3;
uniform float deep_alpha = 0.93;
// foam along the banks: how deep it reaches (m) and how broken up it is
uniform float foam_depth = 0.45;
uniform float foam_noise = 0.6;
// downstream speed of the ripples (m/s; ~0 for a pool) and their strength
uniform float flow_speed = 1.3;
uniform float ripple = 0.42;

float waves(vec2 p) {
	vec2 flow = vec2(0.0, game_time * flow_speed);
	// broad swells only: a finer layer read as spots under the sun's highlight
	return value_noise(p * 0.22 - flow * 0.22 + vec2(game_time * 0.04, 0.0))
			+ 0.45 * value_noise(p * vec2(0.62, 0.45) - flow * 0.4 + 7.3);
}

void fragment() {
	// ripple normal: finite differences of the drifting waves, in tangent space
	float e = 0.12;
	float h0 = waves(UV);
	float hx = waves(UV + vec2(e, 0.0));
	float hy = waves(UV + vec2(0.0, e));
	NORMAL_MAP = normalize(vec3((h0 - hx) / e * ripple, (h0 - hy) / e * ripple, 1.0)) * 0.5 + 0.5;

	// how much water lies behind this pixel: the scene's depth minus the surface's
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	behind.xyz /= behind.w;
	float water = max(VERTEX.z - behind.z, 0.0); // view space looks down -z
	float t = clamp(water / depth_scale, 0.0, 1.0);

	vec3 col = mix(shallow.rgb, deep.rgb, sqrt(t));
	float alpha = mix(clear_alpha, deep_alpha, sqrt(t));
	// foam: a band along the bank, broken up by the drifting waves
	float foam = 1.0 - smoothstep(0.0, foam_depth, water + (h0 - 0.8) * foam_noise * foam_depth);
	col = mix(col, foam_color.rgb, foam * 0.85);
	alpha = max(alpha, foam * 0.9);
	// grazing angles reflect more (and hide what's under)
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	alpha = mix(alpha, 1.0, fres * 0.65);

	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = mix(0.04, 0.5, foam);
	SPECULAR = 0.6;
}
