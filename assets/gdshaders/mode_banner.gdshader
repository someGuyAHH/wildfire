shader_type canvas_item;

// game clock that stops while paused (set by Main), unlike TIME
global uniform float game_time;

// placeholder banners for the mode cards: flat vector shapes, one pattern per mode
//   0 classic: a single flame     1 spread: fire rippling across a grid of dots
//   2 hunted: you, with the swarm's rings closing in     3 hot potato: a shrinking storm + fuse spark
uniform int pattern = 0;
uniform vec4 bg_color : source_color = vec4(0.12, 0.05, 0.03, 1.0);
uniform vec4 main_color : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.9, 0.55, 1.0);
uniform float aspect = 1.6;

float flame(vec2 p, float scale, float t) {
	p /= scale;
	float wob = sin(p.y * 9.0 + t * 5.0) * 0.035 * smoothstep(0.15, -0.4, p.y);
	float w = 0.21 * pow(clamp((p.y + 0.42) / 0.57, 0.0, 1.0), 0.75);
	float body = step(abs(p.x - wob), w) * step(-0.42, p.y) * step(p.y, 0.15);
	float base = step(length(p - vec2(0.0, 0.15)), 0.21);
	return max(body, base);
}

float ring(vec2 p, float r, float w) {
	return 1.0 - smoothstep(w * 0.5, w, abs(length(p) - r));
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float t = game_time;
	// diagonal stripes, slowly drifting
	float stripe = step(0.5, fract((UV.x * aspect + UV.y) * 5.0 - t * 0.15));
	vec3 col = mix(bg_color.rgb, bg_color.rgb * 1.35, stripe * 0.6);
	if (pattern == 0) {
		float outer = flame(p, 1.0, t);
		float inner = flame(p - vec2(0.0, 0.07), 0.55, t * 1.3);
		col = mix(col, main_color.rgb, outer);
		col = mix(col, hot_color.rgb, inner * outer);
	} else if (pattern == 1) {
		vec2 g = UV * vec2(aspect, 1.0) * 7.0;
		vec2 id = floor(g);
		vec2 cell = fract(g) - 0.5;
		float dotm = step(length(cell), 0.28);
		float dist = length(id + 0.5 - vec2(aspect * 3.5, 3.5));
		float wave = mod(t * 2.2, 9.0);
		float lit = step(dist, wave);
		float front = step(wave - 1.2, dist) * lit;
		col = mix(col, mix(bg_color.rgb * 2.2, main_color.rgb, lit), dotm);
		col = mix(col, hot_color.rgb, dotm * front);
	} else if (pattern == 2) {
		for (int i = 0; i < 4; i++) {
			float r = (1.0 - fract(t * 0.3 + float(i) * 0.25)) * 0.75;
			col = mix(col, main_color.rgb, ring(p, r, 0.025) * smoothstep(0.0, 0.15, r));
		}
		float r0 = (1.0 - fract(t * 0.3)) * 0.75;
		for (int k = 0; k < 8; k++) {
			float a = float(k) * 0.7854 + t * 0.4;
			vec2 q = vec2(cos(a), sin(a)) * r0;
			col = mix(col, main_color.rgb * 1.3, step(length(p - q), 0.035));
		}
		col = mix(col, hot_color.rgb, step(length(p), 0.07));
	} else {
		float r = 0.46 - 0.2 * fract(t * 0.12);
		float outside = smoothstep(r, r + 0.01, length(p));
		col = mix(col, mix(col, main_color.rgb * 0.75, 0.6), outside);
		col = mix(col, main_color.rgb, ring(p, r, 0.03));
		col = mix(col, bg_color.rgb * 0.5, step(length(p - vec2(0.0, 0.04)), 0.11));
		float spark = step(length(p - vec2(0.07, -0.1)), 0.035 + 0.015 * sin(t * 20.0));
		col = mix(col, hot_color.rgb, spark);
	}
	COLOR = vec4(col, 1.0);
}
