shader_type canvas_item;
// The prototype's desaturate pass followed by its fog pass, in one shader.
// The prototype's plate uv has its origin at the bottom-left, so `plate` flips UV.y.

uniform float desaturate_amount : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D fog_noise : filter_linear, repeat_enable;
uniform float fog_density : hint_range(0.0, 1.0) = 0.0;
// Noise tiles per plate.
uniform float fog_scale = 1.0;
// `fog_horizon` biases the grain toward the top of the plate; the ramp starts at
// plate height `fog_floor` (0 is the bottom). A horizon of 0 is even across the plate.
uniform float fog_floor : hint_range(0.0, 1.0) = 0.0;
uniform float fog_horizon : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 color = COLOR;
	float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
	color.rgb = mix(color.rgb, vec3(luminance), desaturate_amount);

	vec2 plate = vec2(UV.x, 1.0 - UV.y);
	float n = texture(fog_noise, plate * fog_scale).r;
	float above = smoothstep(min(fog_floor, 0.999), 1.0, plate.y);
	float h = mix(1.0, above, fog_horizon);
	color.rgb = mix(color.rgb, vec3(n), clamp(fog_density * h, 0.0, 1.0));
	COLOR = color;
}
