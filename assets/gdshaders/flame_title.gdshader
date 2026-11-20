shader_type canvas_item;

// A title's letters burning (FlameTitle): flat bands of flame lick up off the tops of the letters,
// vector style (three hard-edged colours, no smooth gradient). TEXTURE is the title drawn white
// into a SubViewport with headroom above it; flames are the letters below each pixel, smeared up
// and torn into tongues by scrolling noise. Real time (TIME), so they burn on in the pause menu.

uniform vec4 letter_color : source_color = vec4(0.953, 0.925, 0.886, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.078, 0.067, 0.059, 0.85);
uniform vec4 band_low : source_color = vec4(0.761, 0.149, 0.059, 1.0);  // deep red, the outer edge
uniform vec4 band_mid : source_color = vec4(1.0, 0.416, 0.102, 1.0);    // ember
uniform vec4 band_high : source_color = vec4(1.0, 0.761, 0.227, 1.0);   // gold, hugging the letters
// how far above the letters the flames reach, as a fraction of the texture's height
uniform float reach = 0.3;
// hard shadow under the letters, in pixels
uniform vec2 shadow_px = vec2(4.0, 4.0);
uniform float speed = 1.4;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float band(float f, float edge) {
	float w = max(fwidth(f), 0.002);
	return smoothstep(edge - w, edge + w, f);
}

void fragment() {
	float aspect = TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x; // width / height
	vec2 q = UV * vec2(aspect, 1.0); // in heights, so the noise isn't stretched
	float t = TIME * speed;
	// sway: the higher up, the further the flame leans (looked up a bent line below this pixel)
	float sway = (vnoise(vec2(q.x * 2.5, q.y * 3.0 - t * 1.2)) - 0.5) * 0.16;
	// how far down the nearest letter is (0..1 of reach; 1: none in reach)
	float d = 1.0;
	for (int i = 1; i <= 24; i++) {
		float k = float(i) / 24.0;
		if (texture(TEXTURE, UV + vec2(sway * k / aspect, k * reach)).a > 0.5) { d = k; break; }
	}
	if (d < 1.0) { // narrow it down between the last miss and the hit (smooth band edges)
		float lo = d - 1.0 / 24.0;
		for (int j = 0; j < 4; j++) {
			float mid = (lo + d) * 0.5;
			if (texture(TEXTURE, UV + vec2(sway * mid / aspect, mid * reach)).a > 0.5) d = mid; else lo = mid;
		}
	}
	// pointed tongues, each its own height and flickering; the bands nest inside (gold, ember, red)
	float wob = vnoise(vec2(q.x * 3.0, t * 0.9)) * 1.5;
	float tips = 1.0 - abs(fract(q.x * 6.5 + wob) * 2.0 - 1.0);
	float flick = vnoise(vec2(q.x * 7.0, t * 1.8)) * 0.7 + vnoise(vec2(q.x * 19.0, t * 3.1)) * 0.3;
	float tongue = 0.3 + 0.7 * mix(tips, flick, 0.45);
	float f = 1.0 - d / tongue;
	vec4 c = vec4(band_low.rgb, band(f, 0.0));
	c.rgb = mix(c.rgb, band_mid.rgb, band(f, 0.3));
	c.rgb = mix(c.rgb, band_high.rgb, band(f, 0.62));
	// a hard shadow under the letters, then the letters on top
	float sh = texture(TEXTURE, UV - shadow_px * TEXTURE_PIXEL_SIZE).a * shadow_color.a;
	c = vec4(mix(c.rgb, shadow_color.rgb, sh), max(c.a, sh));
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(mix(c.rgb, letter_color.rgb, a), max(c.a, a));
}
