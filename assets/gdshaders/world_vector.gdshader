shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// the art-pass world material: flat vector-style surfaces (crisp joints, chamfered blocks,
// inlays) lit like a modern game. reads a packed pattern map from tools/texgen/patterns.py:
//   R height (0 = joint, ramps over the bevel, 1 = face), G per-block tone, B accent (inlay/crack)
// projected along the surface's dominant world axis (no uvs needed: the maps are generated boxes).
// joints and accents are thresholded with fwidth, so their edges stay sharp at any distance.

// game clock that stops while paused (set by Main), unlike TIME
global uniform float game_time;

#include "res://assets/gdshaders/include/noise.gdshaderinc"

uniform sampler2D pattern : filter_linear_mipmap_anisotropic, repeat_enable;
// the height's slope, baked by patterns.py (<name>_slope.png): 0.5 + slope / 3 in R (along u), G (along v)
uniform sampler2D slope_map : filter_linear_mipmap_anisotropic, repeat_enable;
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
// how strongly the sun glints off it (0.5: Godot's default; matte stone wants less)
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;
uniform vec4 accent_color : source_color = vec4(1.0, 0.45, 0.1, 0.0); // alpha = how much it shows
uniform float accent_emission = 0.0;
// accents breathe (embers in cracks): 0 = steady
uniform float accent_pulse : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_face : hint_range(0.0, 1.0) = 0.8;
uniform float roughness_joint : hint_range(0.0, 1.0) = 0.95;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
// breaking the repeat: every block gets its own tone and shine in every tile copy (0 = the
// pattern's own tones only), and big soft patches of grime drift over everything
uniform float block_variation : hint_range(0.0, 1.0) = 0.0;
uniform float rough_variation : hint_range(0.0, 1.0) = 0.0;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.0;
// how much darker (and rougher) broken stone is: chipped corners, pits, cracks (the pattern's
// surfaces at 0.3-0.55 height, under the faces). 0: drawn like the face
uniform float broken_shade : hint_range(0.0, 1.0) = 0.0;
// metres across one grime patch
uniform float grime_scale = 9.0;
// what grime turns a face toward (alpha = how far at full grime): dark dirt, or moss
uniform vec4 grime_color : source_color = vec4(0.0, 0.0, 0.0, 0.45);

// weathering seen on old stone (the Pont du Gard): rain streaks down walls, drawn as crisp
// flat shapes (vector, not soft grime): how dark, metres across one, metres long
uniform float streaks : hint_range(0.0, 1.0) = 0.0;
uniform float streak_width = 1.2;
uniform float streak_length = 8.0;
// up-facing faces bleached paler by the sun (alpha = how much)
uniform vec4 top_tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);

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

	// bevel normal from the height's slope (baked: one sample instead of four)
	vec2 sl = (texture(slope_map, uv).rg - 0.5) * 3.0;
	float hx = sl.x;
	float hy = sl.y;
	vec3 wn = normalize(world_nrm - bevel_strength * (hx * tu + hy * tv));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// crisp joint line: threshold the height with an anti-aliasing width from screen derivatives
	float w = fwidth(h) * 0.75 + 0.002;
	float joint = 1.0 - smoothstep(joint_level - w, joint_level + w, h);
	// which block this is, in which copy of the tile (A < 0.5: it started in the tile to the left)
	vec2 cell = floor(uv) - vec2(step(t.a, 0.5), 0.0);
	float id = hash(cell * 7.13 + vec2(t.g * 97.0, t.g * 31.0));
	float id2 = hash(cell * 3.71 + vec2(t.g * 53.0, 11.0));
	float tone = mix(t.g, id, block_variation);
	vec2 wp = uv * tile_size;
	float grime = value_noise(wp / grime_scale) * 0.65 + value_noise(wp / (grime_scale * 0.31) + 17.0) * 0.35;
	grime = smoothstep(0.45, 0.85, grime) * grime_strength;
	vec3 face = base_color.rgb * (1.0 + (tone - 0.5) * 2.0 * tone_range);
	face = mix(face, grime_color.rgb, grime * grime_color.a);
	// the bevel's top rim (sloped and facing up the projection) catches a highlight stroke
	float slope = clamp(length(vec2(hx, hy)) * 6.0, 0.0, 1.0);
	face += base_color.rgb * rim_light * slope * step(joint_level, h) * clamp(-hy * 8.0 + 0.3, 0.0, 1.0);
	if (streaks > 0.0) {
		float wall = 1.0 - smoothstep(0.3, 0.6, n.y);
		float along = n.x > n.z ? world_pos.z : world_pos.x;
		float sv = value_noise(vec2(along / streak_width, world_pos.y / streak_length)) * 0.7
				+ value_noise(vec2(along / streak_width * 0.37 + 5.0, world_pos.y / streak_length * 2.3)) * 0.3;
		float sw = fwidth(sv) + 0.002;
		face *= 1.0 - smoothstep(0.62 - sw, 0.62 + sw, sv) * streaks * wall;
	}
	face = mix(face, face * top_tint.rgb * 1.3, top_tint.a * smoothstep(0.55, 0.9, world_nrm.y));
	float broken = (1.0 - smoothstep(0.52, 0.66, h)) * broken_shade;
	face *= 1.0 - broken;
	vec3 col = mix(face, joint_color.rgb, joint);

	float aw = fwidth(t.b) * 0.75 + 0.002;
	float accent = smoothstep(0.5 - aw, 0.5 + aw, t.b) * accent_color.a;
	col = mix(col, accent_color.rgb, accent);
	float breathe = 1.0 + accent_pulse * (sin(game_time * 1.7 + world_pos.x * 0.3 + world_pos.z * 0.2) * 0.5 - 0.1);
	EMISSION = accent_color.rgb * accent * accent_emission * breathe;

	ALBEDO = col;
	float rough = clamp(roughness_face + (id2 - 0.5) * rough_variation + grime * 0.4 + broken * 0.5, 0.0, 1.0);
	// specular anti-aliasing: where the normal turns fast from one pixel to the next (bevels,
	// cracks, pits drawn by the slope map) the surface counts as rougher, so those thin strips
	// can't flash the sun's highlight as the camera moves (Kaplanyan & Hoffman)
	vec3 dn = fwidth(wn);
	float r = mix(rough, roughness_joint, joint);
	ROUGHNESS = sqrt(min(r * r + min(dot(dn, dn) * 2.0, 0.6), 1.0));
	SPECULAR = specular_amount;
	METALLIC = metallic_value * (1.0 - joint);
}
