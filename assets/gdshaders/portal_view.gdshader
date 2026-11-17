shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;

// A portal doorway: shows its camera's picture where it lands on screen, so the doorway looks
// straight through to the other side.
uniform sampler2D view : source_color, filter_linear;

void fragment() {
	ALBEDO = texture(view, SCREEN_UV).rgb;
}
