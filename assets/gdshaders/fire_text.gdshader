shader_type canvas_item;

// game clock that stops while paused (set by Main), unlike TIME
global uniform float game_time;

// fire gradient on a Label's letters (fill only, the dark outline stays): deep red at the top,
// white-hot at the bottom, with a soft flicker running across.
uniform float text_height = 140.0;
uniform vec3 top_color : source_color = vec3(1.0, 0.28, 0.05);
uniform vec3 bottom_color : source_color = vec3(1.0, 0.93, 0.6);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float g = clamp(local_pos.y / text_height, 0.0, 1.0);
	float flicker = 0.88 + 0.12 * sin(game_time * 7.0 + local_pos.x * 0.045) * sin(game_time * 3.1 + local_pos.x * 0.02);
	vec3 fire = mix(top_color, bottom_color, g) * flicker;
	float fill = step(0.5, dot(c.rgb, vec3(0.333)));
	c.rgb = mix(c.rgb, fire, fill);
	COLOR = c;
}
