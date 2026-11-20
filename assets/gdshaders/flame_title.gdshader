shader_type canvas_item;

// A title made of fire (FlameTitle): the letters filled with flame colours (white-gold at the
// bottom, ember, red at the top, a slow flicker rising through them) and flat flame tongues rising
// off their tops, tearing loose as they climb. TEXTURE is the title drawn white into a SubViewport
// with headroom above it. Real time (TIME), so it burns on in the pause menu.

uniform vec4 core : source_color = vec4(1.0, 0.93, 0.62, 1.0);  // white-gold, the hottest
uniform vec4 gold : source_color = vec4(1.0, 0.761, 0.227, 1.0);
uniform vec4 ember : source_color = vec4(1.0, 0.416, 0.102, 1.0);
uniform vec4 red : source_color = vec4(0.761, 0.149, 0.059, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.078, 0.067, 0.059, 0.85);
// how far above the letters the flames reach, as a fraction of the texture's height (FlameTitle sets it)
uniform float reach = 0.3;
uniform vec2 shadow_px = vec2(4.0, 4.0);
// a thin dark edge round the letters, so they read against their own flames (px)
uniform float outline_px = 3.0;
uniform float speed = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// heat 0..1 to the fire's colours (soft steps between them)
vec3 fire(float h) {
	vec3 c = mix(red.rgb, ember.rgb, smoothstep(0.18, 0.34, h));
	c = mix(c, gold.rgb, smoothstep(0.5, 0.64, h));
	return mix(c, core.rgb, smoothstep(0.8, 0.92, h));
}

void fragment() {
	float aspect = TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x; // width / height
	vec2 q = UV * vec2(aspect, 1.0); // in heights, so the noise isn't stretched
	float t = TIME * speed;
	float a = texture(TEXTURE, UV).a;
	// how far down the nearest letter is (0..1 of reach; 1: none in reach), along a swaying line
	float sway = (vnoise(vec2(q.x * 2.5, q.y * 3.0 - t * 1.2)) - 0.5) * 0.12;
	float d = 1.0;
	for (int i = 1; i <= 24; i++) {
		float k = float(i) / 24.0;
		if (texture(TEXTURE, UV + vec2(sway * k / aspect, k * reach)).a > 0.5) { d = k; break; }
	}
	if (d < 1.0) {
		float lo = d - 1.0 / 24.0;
		for (int j = 0; j < 4; j++) {
			float mid = (lo + d) * 0.5;
			if (texture(TEXTURE, UV + vec2(sway * mid / aspect, mid * reach)).a > 0.5) d = mid; else lo = mid;
		}
	}
	// flames: tongues of their own height, torn by noise that climbs (bits break off and rise)
	float tongue = 0.35 + 0.65 * (vnoise(vec2(q.x * 6.0, t * 1.4)) * 0.6 + vnoise(vec2(q.x * 15.0, t * 2.6)) * 0.4);
	float rise = vnoise(vec2(q.x * 9.0, q.y * 6.0 + t * 2.4)) * 0.6 + vnoise(vec2(q.x * 20.0, q.y * 13.0 + t * 3.6)) * 0.4;
	float f = 1.0 - d / tongue + (rise - 0.5) * 0.7 * smoothstep(0.0, 0.6, d);
	float flame = smoothstep(0.0, max(fwidth(f), 0.002), f);
	vec3 flame_col = fire(clamp(f * 0.75 + 0.05, 0.0, 0.7)); // red edge, ember, gold at the root
	// the letters: hot at the bottom, cooler at the top, with heat rising through them
	float ly = clamp((UV.y - reach) / (1.0 - reach), 0.0, 1.0);
	float heat = 0.32 + ly * 0.7 + (vnoise(vec2(q.x * 5.0, q.y * 7.0 + t * 1.8)) - 0.5) * 0.3;
	vec3 letter_col = fire(heat);
	// shadow under it all, then flames, then letters
	float sh = texture(TEXTURE, UV - shadow_px * TEXTURE_PIXEL_SIZE).a * shadow_color.a;
	vec4 c = vec4(shadow_color.rgb, sh);
	c = mix(c, vec4(flame_col, 1.0), flame);
	float edge = 0.0; // the letters grown by outline_px: a dark ring under them
	for (int k = 0; k < 8; k++) {
		float ang = float(k) * 0.785398;
		edge = max(edge, texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * outline_px * TEXTURE_PIXEL_SIZE).a);
	}
	c = mix(c, vec4(shadow_color.rgb, 1.0), edge * 0.92);
	c = mix(c, vec4(letter_col, 1.0), a);
	COLOR = c;
}
