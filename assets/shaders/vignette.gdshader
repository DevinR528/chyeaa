shader_type canvas_item;
render_mode unshaded;

// All in the viewport's base-resolution space (what get_canvas_transform() maps
// to), not physical window pixels, which differ under stretch, DPI, or fullscreen.
uniform vec2 center_px = vec2(420.0, 252.0);
uniform float inner_px = 88.0;
uniform float outer_px = 208.0;
uniform float darkness : hint_range(0.0, 1.0) = 0.45;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	float veil = smoothstep(inner_px, outer_px, distance(local_px, center_px));
	COLOR = vec4(0.0, 0.0, 0.0, veil * darkness);
}
