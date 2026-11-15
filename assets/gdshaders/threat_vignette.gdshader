shader_type canvas_item;

// red screen edges while a chaser is hunting you. strength 0..1 = how close it is.
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(0.9, 0.05, 0.02, 1.0);
uniform float max_alpha = 0.55;
uniform float pulse_rate = 5.0;

void fragment() {
	vec2 c = UV - 0.5;
	c.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x; // aspect fix
	float r = length(c);
	// edge creeps further in the closer it gets
	float inner = mix(0.62, 0.32, strength);
	float edge = smoothstep(inner, inner + 0.35, r);
	float pulse = 0.85 + 0.15 * sin(TIME * pulse_rate * (0.5 + strength));
	COLOR = vec4(color.rgb, edge * strength * pulse * max_alpha);
}
