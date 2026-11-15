shader_type canvas_item;

// darkens the left of the screen (where the menu sits) and the corners, so text reads over the
// live match running behind it
uniform float strength = 0.82;
uniform vec4 tint : source_color = vec4(0.03, 0.015, 0.01, 1.0);

void fragment() {
	float left = 1.0 - smoothstep(0.0, 0.62, UV.x);
	vec2 c = UV - 0.5;
	float corners = smoothstep(0.35, 0.85, length(c * vec2(1.4, 1.0)));
	COLOR = vec4(tint.rgb, clamp(left * strength + corners * 0.55 + 0.12, 0.0, 0.95));
}
