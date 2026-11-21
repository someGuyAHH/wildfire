shader_type spatial;
// Role marker: a flat-shaded solid colour (opaque, so TAA has nothing to smear). Colour and glow are
// per instance, so every marker shares this one material. The depth-tested variant.
instance uniform vec3 tint : source_color = vec3(1.0);
instance uniform float glow = 0.0;
uniform float self_light = 0.3;

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.7;
	EMISSION = tint * (self_light + glow);
}
