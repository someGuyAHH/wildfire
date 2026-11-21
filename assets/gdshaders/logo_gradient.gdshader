shader_type canvas_item;
// A vertical gradient over text: `top` at the label's top edge to `bottom` at its bottom edge.
uniform vec4 top : source_color = vec4(1.0, 0.35, 0.08, 1.0);
uniform vec4 bottom : source_color = vec4(1.0, 0.76, 0.23, 1.0);
uniform float height = 200.0;
varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	float t = clamp(local_y / height, 0.0, 1.0);
	COLOR.rgb = mix(top.rgb, bottom.rgb, t);
}
