shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// tree crowns: twig cards (tools/texgen/foliage.py) cut out by their alpha, both sides lit from
// the crown's outward normals (baked in the model), light showing through from behind, a slow
// sway. Runs on game_time, so it stops while paused.

global uniform float game_time;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;
// light through the leaves from behind
uniform vec4 backlight_color : source_color = vec4(0.3, 0.42, 0.14, 1.0);
// metres of sway at the crown (model space y above the trunk's base scales it in)
uniform float sway = 0.12;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.72;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz; // per tree, so a tree sways as one
	float t = game_time;
	float s = sin(t * 1.1 + wp.x * 0.13 + wp.z * 0.11) * 0.7 + sin(t * 2.3 + wp.x * 0.37) * 0.3;
	VERTEX.xz += vec2(0.8, 0.6) * s * sway * clamp(VERTEX.y / 20.0, 0.0, 1.0);
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb * tint.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	// keep the baked outward normal on back faces too (Godot flips it for double-sided faces):
	// the crown shades as one rounded mass, not card by card
	if (!FRONT_FACING) NORMAL = -NORMAL;
	BACKLIGHT = backlight_color.rgb;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.25;
}
