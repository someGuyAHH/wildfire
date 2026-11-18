// shared noise helpers: #include "res://assets/gdshaders/include/noise.gdshaderinc"

// pseudo-random 0..1 per lattice point
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// smooth 0..1 value noise, one feature per unit
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// value noise that repeats every `period` units along x (period a whole number): for noise around
// a circle, where x is the angle. plain value_noise there leaves a seam where atan() wraps
float value_noise_wrap(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, period);
	float x1 = mod(i.x + 1.0, period);
	return mix(mix(hash(vec2(x0, i.y)), hash(vec2(x1, i.y)), u.x),
			   mix(hash(vec2(x0, i.y + 1.0)), hash(vec2(x1, i.y + 1.0)), u.x), u.y);
}
