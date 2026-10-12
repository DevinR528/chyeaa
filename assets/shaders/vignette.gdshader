shader_type canvas_item;
render_mode unshaded;

uniform vec2 center_px = vec2(420.0, 252.0);
uniform float inner_px = 88.0;
uniform float outer_px = 208.0;
uniform float darkness : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec2 pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	float veil = smoothstep(inner_px, outer_px, distance(pixel, center_px));
	COLOR = vec4(0.0, 0.0, 0.0, veil * darkness);
}
