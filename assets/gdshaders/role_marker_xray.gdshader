shader_type spatial;
// Same as role_marker, drawn over walls (the Torch). Unshaded and last in the opaque pass.
render_mode depth_test_disabled, unshaded;
instance uniform vec3 tint : source_color = vec3(1.0);
instance uniform float glow = 0.0;
uniform float glow_boost = 0.25; // how much the Torch's glow brightens it

void fragment() {
	ALBEDO = tint * (1.0 + glow * glow_boost);
}
