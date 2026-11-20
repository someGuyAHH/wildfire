shader_type canvas_item;

// shades the live match behind a menu so its text reads: from the left (the title screen's
// column), from the bottom (the match setup's row), or all over (settings, how to play); the
// menu eases between them. Plus darker corners.
uniform float strength = 0.82;
uniform vec4 tint : source_color = vec4(0.03, 0.015, 0.01, 1.0);
uniform float side = 1.0;
uniform float low = 0.0;
uniform float full = 0.0;

void fragment() {
	float left = (1.0 - smoothstep(0.0, 0.62, UV.x)) * strength * side;
	float bottom = smoothstep(0.3, 0.95, UV.y) * 0.9 * low;
	vec2 c = UV - 0.5;
	float corners = smoothstep(0.35, 0.85, length(c * vec2(1.4, 1.0))) * 0.55;
	float a = max(max(left, bottom), full * 0.86) + corners * (1.0 - full) + 0.12;
	COLOR = vec4(tint.rgb, clamp(a, 0.0, 0.95));
}
