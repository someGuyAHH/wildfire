shader_type canvas_item;

// Freeze: frost closing in on the screen. Two layers:
//  - a blue mist thickening toward the edges (its inner edge broken up by baked noise), and
//  - fine ice crystals (snowflake stars, frost feathers off the edges) drawn into a baked texture,
//    tools/texgen/frost.py: R is how bright the crystal line is, G WHEN it forms (0..254, 255 never),
//    B the mist's noise. A pixel of crystal shows once `strength` has passed its time, so as strength
//    rises the crystals sprout at the edges and branch inward the way they were grown, freshly formed
//    ice glinting a moment. No pulsing: the HUD eases `strength` in and out smoothly.
// Drafted in numpy first (tools' stills) to match the owner's reference (a frosted pane, but blue).

uniform sampler2D frost : filter_linear, repeat_disable;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 deep : source_color = vec3(0.1, 0.35, 0.95);   // the mist's inner, deeper blue
uniform vec3 mist : source_color = vec3(0.5, 0.76, 1.0);    // ...paling to this at the edge
uniform vec3 ice : source_color = vec3(0.86, 0.96, 1.0);    // the crystals
uniform float mist_alpha = 0.55;
uniform float mist_reach = 0.38;  // how far in the mist reaches at full strength (screen heights)

void fragment() {
	if (strength <= 0.001) discard;
	vec3 f = texture(frost, UV).rgb;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x; // width / height
	float e = min(min(UV.x, 1.0 - UV.x) * aspect, min(UV.y, 1.0 - UV.y)); // in from the nearest edge
	// mist
	float reach = max(strength * mist_reach * (0.6 + 0.8 * f.b), 0.0001);
	float hz = 1.0 - smoothstep(0.0, reach, e);
	vec3 col = mix(deep, mist, hz);
	float a = hz * mist_alpha * sqrt(strength);
	// crystals: shown once their time has come, glinting as they form
	float t = f.g * (255.0 / 254.0);
	float shown = clamp((strength - t) / 0.03, 0.0, 1.0);
	float fresh = clamp(1.0 - (strength - t) / 0.08, 0.0, 1.0) * shown;
	float cr = clamp(f.r * shown * (1.0 + 0.6 * fresh), 0.0, 1.0);
	col = mix(col, ice, cr);
	a = max(a, cr * 0.95);
	COLOR = vec4(col, a);
}
